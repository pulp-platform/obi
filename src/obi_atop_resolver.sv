// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Samuel Riedel <sriedel@iis.ee.ethz.ch>
// Author: Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Handles atomics. Hence, it needs to be instantiated in front of a memory region over which the
/// bus has exclusive access.
module obi_atop_resolver
  import obi_pkg::*;
#(
    /// The configuration of the subordinate ports (input ports).
    parameter obi_pkg::obi_cfg_t SbrPortObiCfg             = obi_pkg::ObiDefaultConfig,
    /// The configuration of the manager port (output port).
    parameter obi_pkg::obi_cfg_t MgrPortObiCfg             = SbrPortObiCfg,
    /// The request struct for the subordinate port (input ports).
    parameter type               sbr_port_obi_req_t        = logic,
    /// The response struct for the subordinate port (input ports).
    parameter type               sbr_port_obi_rsp_t        = logic,
    /// The request struct for the manager port (output port).
    parameter type               mgr_port_obi_req_t        = sbr_port_obi_req_t,
    /// The response struct for the manager ports (output ports).
    parameter type               mgr_port_obi_rsp_t        = sbr_port_obi_rsp_t,
    ///
    parameter type               mgr_port_obi_a_optional_t = logic,
    parameter type               mgr_port_obi_r_optional_t = logic,
    /// Enable LR & SC AMOS
    parameter bit                LrScEnable                = 1,
    /// Cut path between request and response at the cost of increased AMO latency
    /// Note: if RegisterAmo is 0, the ATOP resolver is not OBI protocol compliant
    parameter bit                RegisterAmo               = 1'b1,
    // Word width of the widest RISC-V processor that can issue requests to this module.
    // 32 for RV32; 64 for RV64, where both 32-bit (.W suffix) and 64-bit (.D suffix) AMOs are
    // supported if `aw_strb` is set correctly.
    parameter int unsigned       RiscvWordWidth            = 32,
    /// Number of outstanding transactions. Only relevant if downstream interface is cut
    parameter int unsigned       NumTxns                   = 2
) (
    input logic clk_i,
    input logic rst_ni,
    input logic testmode_i,

    input  sbr_port_obi_req_t sbr_port_req_i,
    output sbr_port_obi_rsp_t sbr_port_rsp_o,

    output mgr_port_obi_req_t mgr_port_req_o,
    input  mgr_port_obi_rsp_t mgr_port_rsp_i
);

  if (!SbrPortObiCfg.OptionalCfg.UseAtop) $fatal(1, "Atomics require atop to be enabled");
  if (MgrPortObiCfg.OptionalCfg.UseAtop)
    $fatal(1, "Filter requires atop to be disabled on manager port");
  if (SbrPortObiCfg.Integrity || MgrPortObiCfg.Integrity) $error("Integrity not supported");

  logic meta_valid, meta_ready;
  logic rdata_valid, rdata_ready;

  // read signal before register
  logic [SbrPortObiCfg.DataWidth-1:0] out_rdata;

  logic pop_resp;

  typedef enum logic [1:0] {
    Idle,
    WaitAMOLoad,
    WriteBackAMO
  } amo_state_e;

  amo_state_e state_q, state_d;

  logic sc, exokay;

  logic                                    load_amo;
  logic                                    save_amo_result;
  logic                                    amo_ignore_rsp_d, amo_ignore_rsp_q;
  obi_atop_e                               amo_op_d, amo_op_q;
  logic                                    rsp_happening;
  logic                                    amo_available, amo_last_outstanding;
  logic      [SbrPortObiCfg.AddrWidth-1:0] addr_q;

  logic      [  SbrPortObiCfg.IdWidth-1:0] aid_q;

  localparam int unsigned AxiAluRatio = SbrPortObiCfg.DataWidth / RiscvWordWidth;
  logic [AxiAluRatio-1:0][RiscvWordWidth-1:0] amo_operand_a;
  logic [AxiAluRatio-1:0][RiscvWordWidth-1:0] amo_operand_a_q;
  logic [AxiAluRatio-1:0][RiscvWordWidth-1:0] amo_operand_b_q;
  logic [$clog2(SbrPortObiCfg.DataWidth/8)-$clog2(RiscvWordWidth/8)-1:0]
      amo_operand_addr, amo_operand_addr_q;
  logic [AxiAluRatio-1:0][RiscvWordWidth-1:0] amo_result, amo_result_q;

  // Selection of the RiscvWordWidth word within the wide atomic request.
  logic [SbrPortObiCfg.DataWidth/8-1:0] be_q;
  logic [$clog2(SbrPortObiCfg.DataWidth/8)-1:0] lz_cnt;
  assign amo_operand_addr = lz_cnt >> $clog2(RiscvWordWidth / 8);

  lzc #(
      .WIDTH(SbrPortObiCfg.DataWidth / 8),
      .MODE (1'b0)
  ) i_count_addr (
      .in_i   (be_q),
      .cnt_o  (lz_cnt),
      .empty_o(  /*Unused*/)
  );

  typedef struct packed {
    logic [SbrPortObiCfg.IdWidth-1:0] aid;
    logic                             exokay;
    logic                             sc;
  } meta_buffer_t;

  meta_buffer_t meta_buf_fifo_in, meta_buf_fifo_out;

  assign meta_buf_fifo_in = '{
    aid:        sbr_port_req_i.a.aid,
    exokay:     exokay,
    sc:         sc
  };

  // Store the metadata at handshake
  stream_fifo #(
      .T            (meta_buffer_t),
      .DEPTH        (NumTxns),
      .FALL_THROUGH (1'b0)
  ) i_metadata_register (
      .clk_i,
      .rst_ni,
      .flush_i    ('0),
      .testmode_i ('0),
      .usage_o    (),
      .valid_i    (sbr_port_req_i.req && sbr_port_rsp_o.gnt),
      .ready_o    (meta_ready),
      .data_i     (meta_buf_fifo_in),
      .valid_o    (meta_valid),
      .ready_i    (pop_resp),
      .data_o     (meta_buf_fifo_out)
  );

  // Store response if it's not accepted immediately
  logic rdata_full, rdata_empty;

  assign rdata_ready = !rdata_full;
  assign rdata_valid = !rdata_empty;

  typedef struct packed {
    logic [SbrPortObiCfg.DataWidth-1:0] data;
    logic                               err;
    mgr_port_obi_r_optional_t           optional;
  } out_buffer_t;
  out_buffer_t out_buf_fifo_in, out_buf_fifo_out;

  always_comb begin
    out_rdata = mgr_port_rsp_i.r.rdata;

    // For an SC, set the rdata value according to the RISCV-spec
    if (LrScEnable && meta_buf_fifo_out.sc) begin
      out_rdata = meta_buf_fifo_out.exokay ? '0 : $unsigned(1);
    end
  end

  assign out_buf_fifo_in = '{
          data: out_rdata,
          err: mgr_port_rsp_i.r.err,
          optional: mgr_port_rsp_i.r.r_optional
      };

  assign sbr_port_rsp_o.r.rdata = out_buf_fifo_out.data;
  assign sbr_port_rsp_o.r.rid = meta_buf_fifo_out.aid;
  assign sbr_port_rsp_o.r.err = out_buf_fifo_out.err;
  assign sbr_port_rsp_o.r.r_optional.exokay = meta_buf_fifo_out.exokay;
  if (SbrPortObiCfg.OptionalCfg.RUserWidth) begin : gen_ruser
    if (MgrPortObiCfg.OptionalCfg.RUserWidth) begin : gen_ruser_assign
      always_comb begin
        sbr_port_rsp_o.r.r_optional.ruser = '0;
        sbr_port_rsp_o.r.r_optional.ruser = out_buf_fifo_out.optional.ruser;
      end
    end else begin : gen_no_ruser
      assign sbr_port_rsp_o.r.r_optional.ruser = '0;
    end
  end

  fifo_v3 #(
      .FALL_THROUGH(1'b1),
      .dtype       (out_buffer_t),
      .DEPTH       (2)
  ) i_rdata_fifo (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .flush_i(1'b0),
      .full_o (rdata_full),
      .empty_o(rdata_empty),
      .usage_o( ),
      .data_i (out_buf_fifo_in),
      .push_i (~amo_ignore_rsp_q & rsp_happening),
      .data_o (out_buf_fifo_out),
      .pop_i  (pop_resp)
  );

  // Ready to output data if both meta and read data
  // are available (the read data will always be last)
  assign sbr_port_rsp_o.rvalid = meta_valid & rdata_valid;
  // Only pop the data from the registers once both registers are ready
  if (SbrPortObiCfg.UseRReady) begin : gen_pop_rready
    assign pop_resp = sbr_port_rsp_o.rvalid & sbr_port_req_i.rready;
  end else begin : gen_pop_norready
    assign pop_resp = sbr_port_rsp_o.rvalid;
  end

  // ----------------
  // LR/SC
  // ----------------

  if (LrScEnable) begin : gen_lrsc
    // unique requester identifier, does not necessarily match core_id
    logic [SbrPortObiCfg.IdWidth-1:0] unique_requester_id;

    typedef struct packed {
      /// Is the reservation valid.
      logic                               valid;
      /// On which address is the reservation placed.
      /// This address is aligned to the memory size
      /// implying that the reservation happen on a set size
      /// equal to the word width of the memory (32 or 64 bit).
      logic [SbrPortObiCfg.AddrWidth-1:0] addr;
      /// Which requester made this reservation. Important to
      /// track the reservations from different requesters and
      /// to prevent any live-locking.
      logic [SbrPortObiCfg.IdWidth-1:0]   requester;
    } reservation_t;
    reservation_t reservation_d, reservation_q;

    `FF(reservation_q, reservation_d, 1'b0, clk_i, rst_ni);

    always_comb begin
      unique_requester_id = sbr_port_req_i.a.aid;

      reservation_d = reservation_q;
      exokay = 1'b0;
      sc = 1'b0;
      // new valid transaction
      if (sbr_port_req_i.req && sbr_port_rsp_o.gnt) begin

        // Any LR (even if the reservation fails) will return exokay if reservations are supported.
        if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == ATOPLR) begin
          exokay = 1'b1;
        end

        // An SC can only pair with the most recent LR in program order.
        // Place a reservation on the address if there isn't already a valid reservation.
        // We prevent a live-lock by don't throwing away the reservation of a hart unless
        // it makes a new reservation in program order or issues any SC.
        if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == ATOPLR &&
            (!reservation_q.valid || reservation_q.requester == unique_requester_id)) begin
          reservation_d.valid = 1'b1;
          reservation_d.addr = sbr_port_req_i.a.addr;
          reservation_d.requester = unique_requester_id;
        end

        // An SC may succeed only if no store from another hart (or other device) to
        // the reservation set can be observed to have occurred between
        // the LR and the SC, and if there is no other SC between the
        // LR and itself in program order.

        // check whether another requester has made a write attempt
        if ((unique_requester_id != reservation_q.requester) &&
            (sbr_port_req_i.a.addr == reservation_q.addr) &&
            (!((obi_atop_e'(sbr_port_req_i.a.a_optional.atop) inside {ATOPLR, ATOPSC}) ||
               !sbr_port_req_i.a.a_optional.atop[5]) || sbr_port_req_i.a.we)) begin
          reservation_d.valid = 1'b0;
        end

        // An SC from the same hart clears any pending reservation.
        if (reservation_q.valid && obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == ATOPSC
            && reservation_q.requester == unique_requester_id) begin
          reservation_d.valid = 1'b0;
          // An SC success shall be signaled via exokay only if:
          // - the target sending the response supports exclusive accesses,
          // - the related reservation is still valid, and
          // - the reservation set contains the bytes being written.
          if (reservation_q.addr == sbr_port_req_i.a.addr) begin
            exokay = 1'b1;
          end
        end

        if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == ATOPSC) begin
          sc = 1'b1;
        end

      end
    end  // always_comb
  end else begin : gen_disable_lrsc
    assign exokay = 1'b0;
    assign sc = 1'b0;
  end

  // ----------------
  // Atomics
  // ----------------

  mgr_port_obi_a_optional_t a_optional;
  if (MgrPortObiCfg.OptionalCfg.AUserWidth) begin : gen_auser
    if (SbrPortObiCfg.OptionalCfg.AUserWidth) begin : gen_auser_assign
      always_comb begin
        a_optional.auser = '0;
        a_optional.auser = sbr_port_req_i.a.a_optional.auser;
      end
    end else begin : gen_no_auser
      assign a_optional.auser = '0;
    end
  end
  if (MgrPortObiCfg.OptionalCfg.WUserWidth) begin : gen_wuser
    if (SbrPortObiCfg.OptionalCfg.WUserWidth) begin : gen_wuser_assign
      always_comb begin
        a_optional.wuser = '0;
        a_optional.wuser = sbr_port_req_i.a.a_optional.wuser;
      end
    end else begin : gen_no_wuser
      assign a_optional.wuser = '0;
    end
  end
  if (MgrPortObiCfg.OptionalCfg.UseProt) begin : gen_prot
    if (SbrPortObiCfg.OptionalCfg.UseProt) begin : gen_prot_assign
      assign a_optional.prot = sbr_port_req_i.a.a_optional.prot;
    end else begin : gen_no_prot
      assign a_optional.prot = obi_pkg::DefaultProt;
    end
  end
  if (MgrPortObiCfg.OptionalCfg.UseMemtype) begin : gen_memtype
    if (SbrPortObiCfg.OptionalCfg.UseMemtype) begin : gen_memtype_assign
      assign a_optional.memtype = sbr_port_req_i.a.a_optional.memtype;
    end else begin : gen_no_memtype
      assign a_optional.memtype = obi_pkg::DefaultMemtype;
    end
  end
  if (MgrPortObiCfg.OptionalCfg.MidWidth) begin : gen_mid
    if (SbrPortObiCfg.OptionalCfg.MidWidth) begin : gen_mid_assign
      always_comb begin
        a_optional.mid = '0;
        a_optional.mid = sbr_port_req_i.a.a_optional.mid;
      end
    end else begin : gen_no_mid
      assign a_optional.mid = '0;
    end
  end
  if (MgrPortObiCfg.OptionalCfg.UseDbg) begin : gen_dbg
    if (SbrPortObiCfg.OptionalCfg.UseDbg) begin : gen_dbg_assign
      assign a_optional.dbg = sbr_port_req_i.a.a_optional.dbg;
    end else begin : gen_no_dbg
      assign a_optional.dbg = '0;
    end
  end

  if (!MgrPortObiCfg.OptionalCfg.AUserWidth &&
      !MgrPortObiCfg.OptionalCfg.WUserWidth &&
      !MgrPortObiCfg.OptionalCfg.UseProt &&
      !MgrPortObiCfg.OptionalCfg.UseMemtype &&
      !MgrPortObiCfg.OptionalCfg.MidWidth &&
      !MgrPortObiCfg.OptionalCfg.UseDbg) begin : gen_no_optional
    assign a_optional = '0;
  end

  if (MgrPortObiCfg.UseRReady) begin : gen_rsp_happening
    assign mgr_port_req_o.rready = rdata_ready;
    assign rsp_happening = mgr_port_rsp_i.rvalid & mgr_port_req_o.rready;
  end else begin : gen_rsp_norready
    assign rsp_happening = mgr_port_rsp_i.rvalid;
  end

  always_comb begin
    // feed-through
    sbr_port_rsp_o.gnt = rdata_ready & mgr_port_rsp_i.gnt & amo_available & meta_ready;
    mgr_port_req_o.req = sbr_port_req_i.req & rdata_ready & amo_available;
    mgr_port_req_o.a.addr = sbr_port_req_i.a.addr;
    mgr_port_req_o.a.we = sbr_port_req_i.a.we;
    mgr_port_req_o.a.wdata = sbr_port_req_i.a.wdata;
    mgr_port_req_o.a.be = sbr_port_req_i.a.be;
    mgr_port_req_o.a.aid = sbr_port_req_i.a.aid;
    mgr_port_req_o.a.a_optional = a_optional;

    if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) inside {AMOSWAP, AMOADD, AMOXOR, AMOAND,
                                                              AMOOR, AMOMIN, AMOMAX, AMOMINU,
                                                              AMOMAXU}) begin
      // For AMO read first, then modify and write later
      mgr_port_req_o.a.we = 1'b0;
    end else if (obi_atop_e'(sbr_port_req_i.a.a_optional.atop) == ATOPSC) begin
      // For a Store-Conditional, only write if the exclusive access was okay.
      // Otherwise, perform a dummy read to keep the access order consistent
      mgr_port_req_o.a.we = exokay;
    end

    state_d = state_q;
    amo_op_d = amo_op_q;
    amo_ignore_rsp_d = amo_ignore_rsp_q & ~rsp_happening;

    load_amo = 1'b0;
    save_amo_result = 1'b0;

    unique case (state_q)
      Idle: begin
        if (sbr_port_req_i.req &
            sbr_port_rsp_o.gnt &
            !((obi_atop_e'(sbr_port_req_i.a.a_optional.atop) inside {ATOPLR, ATOPSC}) ||
              !sbr_port_req_i.a.a_optional.atop[5])) begin
          load_amo = 1'b1;
          amo_op_d = obi_atop_e'(sbr_port_req_i.a.a_optional.atop);
          state_d  = WaitAMOLoad;
        end
      end
      WaitAMOLoad: begin
        // Do not allow any new requests until all outstanding (normal) loads and the AMO load have
        // completed
        sbr_port_rsp_o.gnt = 1'b0;
        mgr_port_req_o.req = 1'b0;
        if (amo_last_outstanding && rsp_happening) begin
          save_amo_result = 1'b1;
          amo_op_d = obi_atop_e'(ATOPNONE);
          state_d = WriteBackAMO;
          if (!RegisterAmo) begin
            // Forward AMO result
            mgr_port_req_o.req     = 1'b1;
            mgr_port_req_o.a.we    = 1'b1;
            mgr_port_req_o.a.addr  = addr_q;
            mgr_port_req_o.a.aid   = aid_q;
            mgr_port_req_o.a.wdata = amo_result;
            mgr_port_req_o.a.be    = {RiscvWordWidth/8{1'b1}} <<
            (amo_operand_addr * RiscvWordWidth/8);
            if (mgr_port_rsp_i.gnt && mgr_port_rsp_i.gnt) begin
              // Do not forward the write response to the subordinate port
              amo_ignore_rsp_d = 1'b1;
              state_d = Idle;
            end
          end
        end
      end
      WriteBackAMO: begin
        // The manager port is busy with the write-back; do not grant any new requests
        sbr_port_rsp_o.gnt = 1'b0;
        // Commit AMO
        mgr_port_req_o.req     = 1'b1;
        mgr_port_req_o.a.we    = 1'b1;
        mgr_port_req_o.a.addr  = addr_q;
        mgr_port_req_o.a.aid   = aid_q;
        mgr_port_req_o.a.wdata = amo_result_q;
        mgr_port_req_o.a.be    = {RiscvWordWidth/8{1'b1}} <<
        (amo_operand_addr_q * RiscvWordWidth/8);
        if (mgr_port_req_o.req && mgr_port_rsp_i.gnt) begin
          // Do not forward the write response to the subordinate port
          amo_ignore_rsp_d = 1'b1;
          state_d = Idle;
        end
      end
      default:;
    endcase
  end

  `FFLNR(amo_result_q, amo_result, save_amo_result, clk_i)
  `FFLNR(amo_operand_addr_q, amo_operand_addr, save_amo_result, clk_i)

  credit_counter #(
    .NumCredits     (NumTxns)
  ) i_credit_counter (
    .clk_i,
    .rst_ni,
    .credit_o     (),
    .credit_give_i(rsp_happening),
    .credit_take_i(mgr_port_req_o.req & mgr_port_rsp_i.gnt),
    .credit_init_i('0),
    .credit_left_o(amo_available),
    .credit_crit_o(amo_last_outstanding),
    .credit_full_o()
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q          <= Idle;
      amo_ignore_rsp_q <= 1'b0;
      amo_op_q         <= obi_atop_e'('0);
      addr_q           <= '0;
      be_q             <= '0;
      amo_operand_b_q  <= '0;
      aid_q            <= '0;
    end else begin
      state_q <= state_d;
      amo_op_q <= amo_op_d;
      amo_ignore_rsp_q <= amo_ignore_rsp_d;
      if (load_amo) begin
        addr_q          <= sbr_port_req_i.a.addr;
        be_q            <= sbr_port_req_i.a.be;
        aid_q           <= sbr_port_req_i.a.aid;
        amo_operand_b_q <= sbr_port_req_i.a.wdata;
      end
    end
  end

  // ----------------
  // AMO ALU
  // ----------------
  logic [RiscvWordWidth+1:0] adder_sum;
  logic [RiscvWordWidth:0] adder_operand_a, adder_operand_b;

  `FFL(amo_operand_a_q, mgr_port_rsp_i.r.rdata, rsp_happening, '0, clk_i, rst_ni)
  assign amo_operand_a = rsp_happening ? mgr_port_rsp_i.r.rdata : amo_operand_a_q;
  assign adder_sum = adder_operand_a + adder_operand_b;

  /* verilator lint_off WIDTH */
  always_comb begin : amo_alu

    adder_operand_a = $signed(amo_operand_a[amo_operand_addr]);
    adder_operand_b = $signed(amo_operand_b_q[amo_operand_addr]);

    amo_result = amo_operand_b_q;

    unique case (amo_op_q)
      // the default is to output operand_b
      AMOSWAP: ;
      AMOADD: amo_result[amo_operand_addr] = adder_sum[RiscvWordWidth-1:0];
      AMOAND:
      amo_result[amo_operand_addr] = amo_operand_a[amo_operand_addr] &
      amo_operand_b_q[amo_operand_addr];
      AMOOR:
      amo_result[amo_operand_addr] = amo_operand_a[amo_operand_addr] |
      amo_operand_b_q[amo_operand_addr];
      AMOXOR:
      amo_result[amo_operand_addr] = amo_operand_a[amo_operand_addr] ^
      amo_operand_b_q[amo_operand_addr];
      AMOMAX: begin
        adder_operand_b = -$signed(amo_operand_b_q[amo_operand_addr]);
        amo_result[amo_operand_addr] = adder_sum[RiscvWordWidth] ?
        amo_operand_b_q[amo_operand_addr] : amo_operand_a[amo_operand_addr];
      end
      AMOMIN: begin
        adder_operand_b = -$signed(amo_operand_b_q[amo_operand_addr]);
        amo_result[amo_operand_addr] = adder_sum[RiscvWordWidth] ?
        amo_operand_a[amo_operand_addr] : amo_operand_b_q[amo_operand_addr];
      end
      AMOMAXU: begin
        adder_operand_a = $unsigned(amo_operand_a[amo_operand_addr]);
        adder_operand_b = -$unsigned(amo_operand_b_q[amo_operand_addr]);
        amo_result[amo_operand_addr] = adder_sum[RiscvWordWidth] ?
        amo_operand_b_q[amo_operand_addr] : amo_operand_a[amo_operand_addr];
      end
      AMOMINU: begin
        adder_operand_a = $unsigned(amo_operand_a[amo_operand_addr]);
        adder_operand_b = -$unsigned(amo_operand_b_q[amo_operand_addr]);
        amo_result[amo_operand_addr] = adder_sum[RiscvWordWidth] ?
        amo_operand_a[amo_operand_addr] : amo_operand_b_q[amo_operand_addr];
      end
      default: amo_result = '0;
    endcase
  end

  // pragma translate_off
  // Check for unsupported parameters
  if (RiscvWordWidth != 32) begin : gen_datawidth_err
    $error($sformatf({"Module currently only supports RiscvWordWidth = 32 (Currently %0d)."
    }, RiscvWordWidth));
  end

`ifndef VERILATOR
  assert_rdata_full :
  assert property (@(posedge clk_i) disable iff (~rst_ni) (sbr_port_rsp_o.gnt |-> !rdata_full))
  else $fatal(1, "Trying to push new data although the i_rdata_register is not ready.");
`endif
  // pragma translate_on

endmodule

`include "obi/typedef.svh"
`include "obi/assign.svh"

module obi_atop_resolver_intf
  import obi_pkg::*;
#(
    /// The configuration of the subordinate ports (input ports).
    parameter obi_pkg::obi_cfg_t SbrPortObiCfg = obi_pkg::ObiDefaultConfig,
    /// The configuration of the manager port (output port).
    parameter obi_pkg::obi_cfg_t MgrPortObiCfg = SbrPortObiCfg,
    /// Enable LR & SC AMOS
    parameter bit                LrScEnable    = 1,
    /// Cut path between request and response at the cost of increased AMO latency
    parameter bit                RegisterAmo   = 1'b1
) (
    input logic clk_i,
    input logic rst_ni,
    input logic testmode_i,

    OBI_BUS.Subordinate sbr_port,

    OBI_BUS.Manager mgr_port
);

  `OBI_TYPEDEF_ALL(sbr_port_obi, SbrPortObiCfg)
  `OBI_TYPEDEF_ALL(mgr_port_obi, MgrPortObiCfg)

  sbr_port_obi_req_t sbr_port_req;
  sbr_port_obi_rsp_t sbr_port_rsp;

  mgr_port_obi_req_t mgr_port_req;
  mgr_port_obi_rsp_t mgr_port_rsp;

  `OBI_ASSIGN_TO_REQ(sbr_port_req, sbr_port, SbrPortObiCfg)
  `OBI_ASSIGN_FROM_RSP(sbr_port, sbr_port_rsp, SbrPortObiCfg)

  `OBI_ASSIGN_FROM_REQ(mgr_port, mgr_port_req, MgrPortObiCfg)
  `OBI_ASSIGN_TO_RSP(mgr_port_rsp, mgr_port, MgrPortObiCfg)

  obi_atop_resolver #(
      .SbrPortObiCfg            (SbrPortObiCfg),
      .MgrPortObiCfg            (MgrPortObiCfg),
      .sbr_port_obi_req_t       (sbr_port_obi_req_t),
      .sbr_port_obi_rsp_t       (sbr_port_obi_rsp_t),
      .mgr_port_obi_req_t       (mgr_port_obi_req_t),
      .mgr_port_obi_rsp_t       (mgr_port_obi_rsp_t),
      .mgr_port_obi_a_optional_t(mgr_port_obi_a_optional_t),
      .mgr_port_obi_r_optional_t(mgr_port_obi_r_optional_t),
      .LrScEnable               (LrScEnable),
      .RegisterAmo              (RegisterAmo)
  ) i_obi_atop_resolver (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .sbr_port_req_i(sbr_port_req),
      .sbr_port_rsp_o(sbr_port_rsp),
      .mgr_port_req_o(mgr_port_req),
      .mgr_port_rsp_i(mgr_port_rsp)
  );

endmodule
