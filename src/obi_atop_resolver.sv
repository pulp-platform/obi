// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Samuel Riedel <sriedel@iis.ee.ethz.ch>
// Author: Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Handles atomics. Hence, it needs to be instantiated in front of a memory region over which the
/// bus has exclusive access.
module obi_atop_resolver import obi_pkg::*; #(
  /// The configuration of the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The configuration of the manager port (output port).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The request struct for the subordinate port (input ports).
  parameter type               sbr_port_obi_req_t = logic,
  /// The response struct for the subordinate port (input ports).
  parameter type               sbr_port_obi_rsp_t = logic,
  /// The request struct for the manager port (output port).
  parameter type               mgr_port_obi_req_t = sbr_port_obi_req_t,
  /// The response struct for the manager ports (output ports).
  parameter type               mgr_port_obi_rsp_t = sbr_port_obi_rsp_t,
  /// Enable LR & SC AMOS
  parameter bit                LrScEnable         = 1,
  /// Cut path between request and response at the cost of increased AMO latency
  parameter bit                RegisterAmo        = 1'b0
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  sbr_port_obi_req_t sbr_port_req_i,
  output sbr_port_obi_rsp_t sbr_port_rsp_o,

  output mgr_port_obi_req_t mgr_port_req_o,
  input  mgr_port_obi_rsp_t mgr_port_rsp_i
);

  if (!SbrPortObiCfg.OptionalCfg.UseAtop) $error("Atomics require atop to be enabled");
  if (MgrPortObiCfg.OptionalCfg.UseAtop) $error("Filter requires atop to be disabled on manager port");

  logic meta_valid, meta_ready;
  logic rdata_valid, rdata_ready;

  /// read signal before register
  logic [SbrPortObiCfg.DataWidth-1:0] out_rdata;

  logic pop_resp;
  logic last_amo_wb;

  enum logic [1:0] {
      Idle, DoAMO, WriteBackAMO
  } state_q, state_d;

  logic                 load_amo;
  obi_atop_e            amo_op_q;
  logic                 amo_wb;
  logic [SbrPortObiCfg.DataWidth/8-1:0]   be_expand;
  logic [SbrPortObiCfg.AddrWidth-1:0] addr_q;

  logic [31:0] amo_operand_a;
  logic [31:0] amo_operand_a_q;
  logic [31:0] amo_operand_b_q;
  logic [31:0] amo_result, amo_result_q;

  // Store the metadata at handshake
  spill_register #(
    .T     (logic [SbrPortObiCfg.IdWidth-1:0]),
    .Bypass(1'b0      )
  ) i_metadata_register (
    .clk_i,
    .rst_ni,
    .valid_i ( sbr_port_req_i.req && sbr_port_rsp_o.gnt ),
    .ready_o ( meta_ready                               ),
    .data_i  ( sbr_port_req_i.a.aid                     ),
    .valid_o ( meta_valid                               ),
    .ready_i ( pop_resp                                 ),
    .data_o  ( sbr_port_rsp_o.r.rid                     )
  );

  // Store response if it's not accepted immediately
  logic rdata_full, rdata_empty;
  logic rdata_usage;

  // assign rdata_ready = !rdata_full;
  assign rdata_ready = !rdata_usage && !rdata_full;
  assign rdata_valid = !rdata_empty;

  fifo_v3 #(
    .FALL_THROUGH (1'b1     ),
    .DATA_WIDTH   (SbrPortObiCfg.DataWidth),
    .DEPTH        (2        )
  ) i_rdata_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0                    ),
    .testmode_i (1'b0                    ),
    .full_o     (rdata_full              ),// queue is full
    .empty_o    (rdata_empty             ),// queue is empty
    .usage_o    (rdata_usage             ),// fill pointer
    .data_i     (out_rdata               ),// data to push into the queue
    .push_i     (~last_amo_wb && mgr_port_rsp_i.rvalid),// data is valid and can be pushed to the queue
    .data_o     (sbr_port_rsp_o.r.rdata  ),// output data
    .pop_i      (pop_resp && !rdata_empty)
  );

  // localparam int unsigned CoreIdWidth  = idx_width(NumCores);
  // localparam int unsigned IniAddrWidth = idx_width(NumCoresPerTile + NumGroups);

  logic sc_successful_d, sc_successful_q;
  logic sc_q;

  // In case of a SC we must forward SC result from the cycle earlier.
  assign out_rdata = (sc_q && LrScEnable) ? $unsigned(!sc_successful_q) : mgr_port_rsp_i.r.rdata;

  // Ready to output data if both meta and read data
  // are available (the read data will always be last)
  assign sbr_port_rsp_o.rvalid = meta_valid && rdata_valid;
  // Only pop the data from the registers once both registers are ready
  if (SbrPortObiCfg.UseRReady) begin
    assign pop_resp   = sbr_port_rsp_o.rvalid && sbr_port_req_i.rready;
  end else begin
    assign pop_resp   = sbr_port_rsp_o.rvalid;
  end

  // Generate out_gnt one cycle after sending a request to the bank, except an AMO's write-back
  `FFL(last_amo_wb, !amo_wb, mgr_port_req_o.req, 1'b0, clk_i, rst_ni);

  // ----------------
  // LR/SC
  // ----------------

  if (LrScEnable) begin : gen_lrsc
    // unique core identifier, does not necessarily match core_id
    logic [SbrPortObiCfg.IdWidth-1:0] unique_core_id;

    typedef struct packed {
      /// Is the reservation valid.
      logic                 valid;
      /// On which address is the reservation placed.
      /// This address is aligned to the memory size
      /// implying that the reservation happen on a set size
      /// equal to the word width of the memory (32 or 64 bit).
      logic [SbrPortObiCfg.AddrWidth-1:0] addr;
      /// Which core made this reservation. Important to
      /// track the reservations from different cores and
      /// to prevent any live-locking.
      logic [SbrPortObiCfg.IdWidth-1:0] core;
    } reservation_t;
    reservation_t reservation_d, reservation_q;

    `FF(sc_successful_q, sc_successful_d, 1'b0, clk_i, rst_ni);
    `FF(reservation_q, reservation_d, 1'b0, clk_i, rst_ni);
    `FF(sc_q, sbr_port_req_i.req && sbr_port_rsp_o.gnt && (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == AMOSC), 1'b0, clk_i, rst_ni);

    always_comb begin
    //   // {group_id, tile_id, core_id}
    //   // MSB of ini_addr determines if request is coming from local or remote tile
    //   if (in_meta_i.ini_addr[IniAddrWidth-1] == 0) begin
    //     // Request is coming from the local tile
    //     // take group id of TCDM adapter
    //     unique_core_id = {'0, in_meta_i.tile_id, in_meta_i.ini_addr[IniAddrWidth-2:0]};
    //   end else begin
    //     // Request is coming from a remote tile
    //     // take group id from ini_addr
    //     // Ignore first bit of IniAddr to obtain the group address
    //     unique_core_id = {in_meta_i.ini_addr[IniAddrWidth-2:0],
    //                       in_meta_i.tile_id, in_meta_i.core_id};
    //   end

      unique_core_id = sbr_port_req_i.a.aid;

      reservation_d = reservation_q;
      sc_successful_d = 1'b0;
      // new valid transaction
      if (sbr_port_req_i.req && sbr_port_rsp_o.gnt) begin

        // An SC can only pair with the most recent LR in program order.
        // Place a reservation on the address if there isn't already a valid reservation.
        // We prevent a live-lock by don't throwing away the reservation of a hart unless
        // it makes a new reservation in program order or issues any SC.
        if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == AMOLR &&
            (!reservation_q.valid || reservation_q.core == unique_core_id)) begin
          reservation_d.valid = 1'b1;
          reservation_d.addr = sbr_port_req_i.a.addr;
          reservation_d.core = unique_core_id;
        end

        // An SC may succeed only if no store from another hart (or other device) to
        // the reservation set can be observed to have occurred between
        // the LR and the SC, and if there is no other SC between the
        // LR and itself in program order.

        // check whether another core has made a write attempt
        if ((unique_core_id != reservation_q.core) &&
            (sbr_port_req_i.a.addr == reservation_q.addr) &&
            (!((obi_atop_e'(sbr_port_req_i.a.a_optional.atop) inside {AMOLR, AMOSC}) || !sbr_port_req_i.a.a_optional.atop[5]) || sbr_port_req_i.a.we)) begin
          reservation_d.valid = 1'b0;
        end

        // An SC from the same hart clears any pending reservation.
        if (reservation_q.valid && obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == AMOSC
            && reservation_q.core == unique_core_id) begin
          reservation_d.valid = 1'b0;
          sc_successful_d = (reservation_q.addr == sbr_port_req_i.a.addr);
        end
      end
    end // always_comb
  end else begin : disable_lrcs
    assign sc_q = 1'b0;
    assign sc_successful_d = 1'b0;
    assign sc_successful_q = 1'b0;
  end

  // ----------------
  // Atomics
  // ----------------

  always_comb begin
    // feed-through
    sbr_port_rsp_o.gnt     = rdata_ready & mgr_port_rsp_i.gnt;
    mgr_port_req_o.req     = sbr_port_req_i.req & rdata_ready;//sbr_port_rsp_o.gnt;
    mgr_port_req_o.a.addr  = sbr_port_req_i.a.addr;
    mgr_port_req_o.a.we    = sbr_port_req_i.a.we | (sc_successful_d & (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == AMOSC));
    mgr_port_req_o.a.wdata = sbr_port_req_i.a.wdata;
    mgr_port_req_o.a.be    = sbr_port_req_i.a.be;

    state_d     = state_q;
    load_amo    = 1'b0;
    amo_wb      = 1'b0;

    unique case (state_q)
      Idle: begin
        if (sbr_port_req_i.req & sbr_port_rsp_o.gnt & !((obi_atop_e'(sbr_port_req_i.a.a_optional.atop) inside {AMOLR, AMOSC}) || !sbr_port_req_i.a.a_optional.atop[5])) begin
          load_amo = 1'b1;
          state_d = DoAMO;
        end
      end
      // Claim the memory interface
      DoAMO, WriteBackAMO: begin
        sbr_port_rsp_o.gnt  = 1'b0;
        if (mgr_port_rsp_i.gnt) begin
          state_d     = (RegisterAmo && state_q != WriteBackAMO) ?  WriteBackAMO : Idle;
        end
        // Commit AMO
        amo_wb                = 1'b1;
        mgr_port_req_o.req    = 1'b1;
        mgr_port_req_o.a.we   = 1'b1;
        mgr_port_req_o.a.addr = addr_q;
        mgr_port_req_o.a.be   = {SbrPortObiCfg.DataWidth/8{1'b1}};
        // serve from register if we cut the path
        if (RegisterAmo) begin
          mgr_port_req_o.a.wdata = amo_result_q;
        end else begin
          mgr_port_req_o.a.wdata = amo_result;
        end
      end
      default:;
    endcase
  end

  if (RegisterAmo) begin : gen_amo_slice
    `FFLNR(amo_result_q, amo_result, (state_q == DoAMO), clk_i)
  end else begin : gen_amo_slice
    assign amo_result_q = '0;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= Idle;
      amo_op_q        <= obi_atop_e'('0);
      addr_q          <= '0;
      amo_operand_b_q <= '0;
    end else begin
      state_q         <= state_d;
      if (load_amo) begin
        amo_op_q        <= obi_atop_e'(sbr_port_req_i.a.a_optional.atop);
        addr_q          <= sbr_port_req_i.a.addr;
        amo_operand_b_q <= sbr_port_req_i.a.wdata;
      end else begin
        amo_op_q        <= AMONONE;
      end
    end
  end

  // ----------------
  // AMO ALU
  // ----------------
  logic [33:0] adder_sum;
  logic [32:0] adder_operand_a, adder_operand_b;

  `FFL(amo_operand_a_q, mgr_port_rsp_i.r.rdata, mgr_port_rsp_i.rvalid, '0, clk_i, rst_ni)

  assign amo_operand_a = mgr_port_rsp_i.rvalid ? mgr_port_rsp_i.r.rdata : amo_operand_a_q;
  assign adder_sum     = adder_operand_a + adder_operand_b;
  /* verilator lint_off WIDTH */
  always_comb begin : amo_alu

    adder_operand_a = $signed(amo_operand_a);
    adder_operand_b = $signed(amo_operand_b_q);

    amo_result = amo_operand_b_q;

    unique case (amo_op_q)
      // the default is to output operand_b
      AMOSWAP:;
      AMOADD: amo_result = adder_sum[31:0];
      AMOAND: amo_result = amo_operand_a & amo_operand_b_q;
      AMOOR:  amo_result = amo_operand_a | amo_operand_b_q;
      AMOXOR: amo_result = amo_operand_a ^ amo_operand_b_q;
      AMOMAX: begin
        adder_operand_b = -$signed(amo_operand_b_q);
        amo_result = adder_sum[32] ? amo_operand_b_q : amo_operand_a;
      end
      AMOMIN: begin
        adder_operand_b = -$signed(amo_operand_b_q);
        amo_result = adder_sum[32] ? amo_operand_a : amo_operand_b_q;
      end
      AMOMAXU: begin
        adder_operand_a = $unsigned(amo_operand_a);
        adder_operand_b = -$unsigned(amo_operand_b_q);
        amo_result = adder_sum[32] ? amo_operand_b_q : amo_operand_a;
      end
      AMOMINU: begin
        adder_operand_a = $unsigned(amo_operand_a);
        adder_operand_b = -$unsigned(amo_operand_b_q);
        amo_result = adder_sum[32] ? amo_operand_a : amo_operand_b_q;
      end
      default: amo_result = '0;
    endcase
  end

  // pragma translate_off
  // Check for unsupported parameters
  if (SbrPortObiCfg.DataWidth != 32 || MgrPortObiCfg.DataWidth != 32) begin
    $error($sformatf("Module currently only supports DataWidth = 32. DataWidth is currently set to: %0d", DataWidth));
  end

  `ifndef VERILATOR
    assert_rdata_full : assert property(
      @(posedge clk_i) disable iff (~rst_ni) (sbr_port_rsp_o.gnt |-> !rdata_full))
      else $fatal (1, "Trying to push new data although the i_rdata_register is not ready.");
  `endif
  // pragma translate_on

endmodule
