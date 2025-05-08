// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "obi/assign.svh"

/// An OBI multiplexer.
module relobi_mux #(
  /// The configuration of the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The configuration of the manager port (output port).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The request struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_req_t = logic,
  /// The A channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_a_chan_t  = logic,
  /// The response struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_rsp_t = logic,
  /// The R channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_r_chan_t  = logic,
  /// The request struct for the manager port (output port).
  parameter type               mgr_port_obi_req_t = sbr_port_obi_req_t,
  /// The response struct for the manager port (output port).
  parameter type               mgr_port_obi_rsp_t = sbr_port_obi_rsp_t,
  /// The A channel struct for the manager port (output port).
  parameter type               mgr_port_a_chan_t  = logic,
  /// The A channel optionals struct for all ports.
  parameter type               a_optional_t = logic,
  /// The R channel optionals struct for all ports.
  parameter type               r_optional_t = logic,
  /// The number of subordinate ports (input ports).
  parameter int unsigned       NumSbrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// Use the extended ID field (aid & rid) to route the response
  parameter bit                UseIdForRouting    = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  input  sbr_port_obi_req_t [NumSbrPorts-1:0] sbr_ports_req_i,
  output sbr_port_obi_rsp_t [NumSbrPorts-1:0] sbr_ports_rsp_o,

  output mgr_port_obi_req_t                   mgr_port_req_o,
  input  mgr_port_obi_rsp_t                   mgr_port_rsp_i
);
  if (NumSbrPorts <= 1) begin : gen_NumSbrPorts_err
    $fatal(1, "unimplemented");
  end
  if (MgrPortObiCfg.IdWidth < SbrPortObiCfg.IdWidth) begin : gen_IdWidthDecreasing_err
    $fatal(1, "relobi_mux: IdWidth not allowed to decrease");
  end
  if (MgrPortObiCfg.UseRReady   != SbrPortObiCfg.UseRReady   ||
      MgrPortObiCfg.CombGnt     != SbrPortObiCfg.CombGnt     ||
      MgrPortObiCfg.AddrWidth   != SbrPortObiCfg.DataWidth   ||
      MgrPortObiCfg.DataWidth   != SbrPortObiCfg.DataWidth   ||
      MgrPortObiCfg.Integrity   != SbrPortObiCfg.Integrity   ||
      MgrPortObiCfg.BeFull      != SbrPortObiCfg.BeFull      ||
      MgrPortObiCfg.OptionalCfg != SbrPortObiCfg.OptionalCfg   ) begin : gen_ConfigDiff_err
    $fatal(1, "relobi_mux: Configuration needs to be identical for mgr & sbr except IdWidth");
  end

  localparam int unsigned RequiredExtraIdWidth = $clog2(NumSbrPorts);

  logic [NumSbrPorts-1:0][2:0] sbr_ports_req, sbr_ports_gnt;
  sbr_port_a_chan_t [NumSbrPorts-1:0] sbr_ports_a;
  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_assign
    assign sbr_ports_req[i] = sbr_ports_req_i[i].req;
    assign sbr_ports_a[i] = sbr_ports_req_i[i].a;
    assign sbr_ports_rsp_o[i].gnt = sbr_ports_gnt[i];
  end

  sbr_port_a_chan_t [2:0] mgr_port_a_in_sbr;
  mgr_port_a_chan_t [2:0] mgr_port_a_tmr;
  logic [2:0][RequiredExtraIdWidth-1:0] selected_id, response_id;
  logic [2:0] mgr_port_req, fifo_full, fifo_pop;

  assign mgr_port_req_o.req = mgr_port_req & ~fifo_full;

  logic [2:0] rr_arb_mgr_port_gnt;

  for (genvar i = 0; i < 3; i++) begin : gen_mgr_port_gnt
    assign rr_arb_mgr_port_gnt[i] = mgr_port_rsp_i.gnt[i] && ~fifo_full[i];
  end

  rel_rr_arb_tree #(
    .NumIn     ( NumSbrPorts       ),
    .DataType  ( sbr_port_a_chan_t ),
    .AxiVldRdy ( 1'b1              ),
    .LockIn    ( 1'b1              ),
    .TmrStatus ( 1'b1              )
  ) i_rr_arb (
    .clk_i,
    .rst_ni,

    .flush_i ( 1'b0 ),
    .rr_i    ( '0 ),

    .req_i   ( sbr_ports_req       ),
    .gnt_o   ( sbr_ports_gnt       ),
    .data_i  ( sbr_ports_a         ),

    .req_o   ( mgr_port_req        ),
    .gnt_i   ( rr_arb_mgr_port_gnt ),
    .data_o  ( mgr_port_a_in_sbr   ),

    .idx_o   ( selected_id         )
  );

  for (genvar i = 0; i < 3; i++) begin : gen_tmr_aid
    if (MgrPortObiCfg.IdWidth == SbrPortObiCfg.IdWidth) begin : gen_aid_identical
      always_comb begin
        `OBI_SET_A_STRUCT(mgr_port_a_tmr[i], mgr_port_a_in_sbr[i])
        mgr_port_a_tmr[i].other_ecc = mgr_port_a_in_sbr[i].other_ecc;
      end
    end else begin : gen_aid_extend
      logic we;
      logic [MgrPortObiCfg.DataWidth/8-1:0] be;
      logic [SbrPortObiCfg.IdWidth-1:0] sbr_aid;
      logic [MgrPortObiCfg.IdWidth-1:0] mgr_aid;
      a_optional_t a_optional;
      logic [relobi_pkg::relobi_a_other_ecc_width(MgrPortObiCfg)-1:0] other_ecc;
      relobi_a_other_decoder #(
        .Cfg          (SbrPortObiCfg),
        .a_optional_t (a_optional_t)
      ) i_other_decode (
        .we_i        (mgr_port_a_in_sbr[i].we),
        .be_i        (mgr_port_a_in_sbr[i].be),
        .aid_i       (mgr_port_a_in_sbr[i].aid),
        .a_optional_i(mgr_port_a_in_sbr[i].a_optional),
        .other_ecc_i (mgr_port_a_in_sbr[i].other_ecc),
        .we_o        (we),
        .be_o        (be),
        .aid_o       (sbr_aid),
        .a_optional_o(a_optional)
      );
      if (MgrPortObiCfg.IdWidth >= SbrPortObiCfg.IdWidth +
                                   RequiredExtraIdWidth   ) begin
        always_comb begin
          mgr_aid = '0;
          mgr_aid[SbrPortObiCfg.IdWidth + RequiredExtraIdWidth-1:0] = {selected_id[i], sbr_aid};
        end
      end else begin
        always_comb begin
          mgr_aid = '0;
          mgr_aid[SbrPortObiCfg.IdWidth-1:0] = sbr_aid;
        end
      end
      relobi_a_other_encoder #(
        .Cfg          (MgrPortObiCfg),
        .a_optional_t (a_optional_t)
      ) i_other_encode (
        .we_i        (we),
        .be_i        (be),
        .aid_i       (mgr_aid),
        .a_optional_i(a_optional),
        .other_ecc_o (other_ecc),
      );

      always_comb begin
        `OBI_SET_A_STRUCT(mgr_port_a_tmr[i], mgr_port_a_in_sbr[i])
        mgr_port_a_tmr[i].we         = we;
        mgr_port_a_tmr[i].be         = be;
        mgr_port_a_tmr[i].aid        = mgr_aid;
        mgr_port_a_tmr[i].a_optional = a_optional;
        mgr_port_a_tmr[i].other_ecc  = other_ecc;
      end

    end
  end

  logic [2:0][SbrPortObiCfg.IdWidth-1:0] rsp_rid;

  if (UseIdForRouting) begin : gen_id_assign
    if (!(MgrPortObiCfg.IdWidth > 0 &&
          (MgrPortObiCfg.IdWidth >= SbrPortObiCfg.IdWidth +
                                    RequiredExtraIdWidth   ))) begin : gen_IdWidth_err
      $fatal(1, "UseIdForRouting requires MgrPort IdWidth to increase with log2(NumSbrPorts)");
    end

    for (genvar i = 0; i < 3; i++) begin : gen_tmr_rid
      relobi_r_other_decoder #(
        .Cfg          (SbrPortObiCfg),
        .r_optional_t (r_optional_t)
      ) i_r_other_decode (
        .rid_i       (mgr_port_rsp_i.r.rid[SbrPortObiCfg.IdWidth-1:0]),
        .err_i       (mgr_port_rsp_i.r.err),
        .r_optional_i(mgr_port_rsp_i.r.r_optional),
        .other_ecc_i (mgr_port_rsp_i.r.other_ecc),
        .rid_o       (rsp_rid[i]),
        .err_o       (),
        .r_optional_o()
      );

      assign {response_id[i], rsp_rid[i]} =
        mgr_port_rsp_i.r.rid[SbrPortObiCfg.IdWidth + RequiredExtraIdWidth-1:0];
      assign fifo_full[i] = 1'b0;
    end

  end else begin : gen_no_id_assign
    logic [2:0][hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth)-1:0] selected_id_tmr_three;
    logic [hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth)-1:0] selected_id_tmr, response_id_encoded;

    for (genvar i = 0; i < 3; i++) begin : gen_extra_id_tmr
      hsiao_ecc_enc #(
        .DataWidth (RequiredExtraIdWidth)
      ) i_ecc (
        .in        (selected_id[i]),
        .out       (selected_id_tmr_three[i])
      );

      hsiao_ecc_dec #(
        .DataWidth (RequiredExtraIdWidth)
      ) i_ecc_dec (
        .in        (response_id_encoded),
        .out       (response_id[i]),
        .syndrome_o(),
        .err_o     () // TODO
      );
    end

    `VOTE31F(selected_id, selected_id_tmr, TODO)

    rel_fifo #(
      .FallThrough( 1'b0                 ),
      .DataWidth  ( hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth) ),
      .Depth      ( NumMaxTrans          ),
      .TmrStatus  ( 1'b1                 ),
      .DataHasECC ( 1'b1                 ),
      .StatusFF   ( 1'b0                 )
    ) i_fifo (
      .clk_i,
      .rst_ni,
      .flush_i   ('0),
      .testmode_i,

      .full_o    ( fifo_full                               ),
      .empty_o   (),
      .usage_o   (),
      .data_i    ( selected_id_tmr                         ),
      .push_i    ( mgr_port_req_o.req & mgr_port_rsp_i.gnt ),
      .data_o    ( response_id_encoded                     ),
      .pop_i     ( fifo_pop                                )
    );

  end

  if (MgrPortObiCfg.UseRReady) begin : gen_rready_connect
    for (genvar i = 0; i < 3; i++) begin : gen_rready_connect_tmr
      assign mgr_port_req_o.rready[i] = sbr_ports_req_i[response_id[i]].rready[i];
    end
  end
  logic [NumSbrPorts-1:0][2:0] sbr_rsp_rvalid;
  sbr_port_r_chan_t [NumSbrPorts-1:0] sbr_rsp_r;
  always_comb begin : proc_sbr_rsp
    for (int i = 0; i < NumSbrPorts; i++) begin
      // Always assign r struct to avoid triplication overhead
      `OBI_SET_R_STRUCT(sbr_rsp_r[i], mgr_port_rsp_i.r);
      sbr_rsp_rvalid[i] = '0;
    end
    for (genvar i = 0; i < 3; i++) begin
      sbr_rsp_rvalid[response_id[i]][i] = mgr_port_rsp_i.rvalid[i];
    end
  end

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_rsp_assign
    assign sbr_ports_rsp_o[i].r = sbr_rsp_r[i];
    assign sbr_ports_rsp_o[i].rvalid = sbr_rsp_rvalid[i];
  end

  if (MgrPortObiCfg.UseRReady) begin : gen_fifo_pop
    assign fifo_pop = mgr_port_rsp_i.rvalid & mgr_port_req_o.rready;
  end else begin : gen_fifo_pop
    assign fifo_pop = mgr_port_rsp_i.rvalid;
  end

endmodule
