// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "obi/assign.svh"
`include "redundancy_cells/voters.svh"

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
  input  mgr_port_obi_rsp_t                   mgr_port_rsp_i,

  output logic [1:0]                          fault_o
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

  logic [8:0][1:0] hsiao_faults;
  logic [8:0][1:0] hsiao_faults_gated;
  logic [1:0][8:0] hsiao_faults_transpose;
  logic [4:0] voter_faults;
  for (genvar i = 0; i < 9; i++) begin : gen_hsiao_faults_transpose
    for (genvar j = 0; j < 2; j++) begin : gen_hsiao_faults_transpose_inner
      assign hsiao_faults_transpose[j][i] = hsiao_faults_gated[i][j];
    end
  end
  assign fault_o[0] = |voter_faults | |hsiao_faults_transpose[0];
  assign fault_o[1] = |hsiao_faults_transpose[1];

  logic [NumSbrPorts-1:0][2:0] sbr_ports_req, sbr_ports_gnt;
  sbr_port_a_chan_t [NumSbrPorts-1:0] sbr_ports_a;

  sbr_port_a_chan_t       mgr_port_a_in_sbr;
  mgr_port_a_chan_t [2:0] mgr_port_a_tmr;
  logic [2:0][RequiredExtraIdWidth-1:0] selected_id, response_id;
  logic [2:0] mgr_port_req, fifo_full, fifo_pop;

  logic [2:0] rr_arb_mgr_port_gnt;

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_assign
    assign sbr_ports_req[i] = sbr_ports_req_i[i].req;
    assign sbr_ports_a[i] = sbr_ports_req_i[i].a;
    assign sbr_ports_rsp_o[i].gnt = sbr_ports_gnt[i];
  end

  assign mgr_port_req_o.req = mgr_port_req & ~fifo_full;

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

    .idx_o   ( selected_id         ),

    .fault_o ( voter_faults[0] )
  );

  for (genvar i = 0; i < 3; i++) begin : gen_tmr_aid
    if (MgrPortObiCfg.IdWidth == SbrPortObiCfg.IdWidth) begin : gen_aid_identical
      always_comb begin
        `OBI_SET_A_STRUCT(mgr_port_a_tmr[i], mgr_port_a_in_sbr)
        mgr_port_a_tmr[i].other_ecc = mgr_port_a_in_sbr.other_ecc;
      end
      assign hsiao_faults[i] = '0;
      assign hsiao_faults_gated[i] = '0;
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
        .we_i        (mgr_port_a_in_sbr.we),
        .be_i        (mgr_port_a_in_sbr.be),
        .aid_i       (mgr_port_a_in_sbr.aid),
        .a_optional_i(mgr_port_a_in_sbr.a_optional),
        .other_ecc_i (mgr_port_a_in_sbr.other_ecc),
        .we_o        (we),
        .be_o        (be),
        .aid_o       (sbr_aid),
        .a_optional_o(a_optional),

        .fault_o (hsiao_faults[i])
      );
      assign hsiao_faults_gated[i] = mgr_port_req[i] ? hsiao_faults[i] : '0;
      if (MgrPortObiCfg.IdWidth >= SbrPortObiCfg.IdWidth +
                                   RequiredExtraIdWidth   ) begin : gen_aid_extend
        always_comb begin
          mgr_aid = '0;
          mgr_aid[SbrPortObiCfg.IdWidth + RequiredExtraIdWidth-1:0] = {selected_id[i], sbr_aid};
        end
      end else begin : gen_aid_noextend
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
        .other_ecc_o (other_ecc)
      );

      assign mgr_port_a_tmr[i].addr       = mgr_port_a_in_sbr.addr;
      assign mgr_port_a_tmr[i].wdata      = mgr_port_a_in_sbr.wdata;
      assign mgr_port_a_tmr[i].we         = we;
      assign mgr_port_a_tmr[i].be         = be;
      assign mgr_port_a_tmr[i].aid        = mgr_aid;
      assign mgr_port_a_tmr[i].a_optional = a_optional;
      assign mgr_port_a_tmr[i].other_ecc  = other_ecc;

    end
  end

  `VOTE31F(mgr_port_a_tmr, mgr_port_req_o.a, voter_faults[1])

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
        .r_optional_o(),
        .fault_o (hsiao_faults[3+i])
      );
      assign hsiao_faults_gated[3+i] = mgr_port_rsp_i.rvalid[i] ? hsiao_faults[3+i] : '0;

      assign {response_id[i], rsp_rid[i]} =
        mgr_port_rsp_i.r.rid[SbrPortObiCfg.IdWidth + RequiredExtraIdWidth-1:0];
      assign fifo_full[i] = 1'b0;
    end

    assign voter_faults[3:2] = '0;

  end else begin : gen_no_id_assign
    logic [2:0][RequiredExtraIdWidth + hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth)-1:0]
      selected_id_tmr_three;
    logic [RequiredExtraIdWidth + hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth)-1:0]
      selected_id_tmr, response_id_encoded;

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
        .err_o     (hsiao_faults[3+i])
      );
      assign hsiao_faults_gated[3+i] = fifo_pop[i] ? hsiao_faults[3+i] : '0;
    end

    `VOTE31F(selected_id_tmr_three, selected_id_tmr, voter_faults[2])

    rel_fifo #(
      .FallThrough( 1'b0                 ),
      .DataWidth  ( RequiredExtraIdWidth + hsiao_ecc_pkg::min_ecc(RequiredExtraIdWidth) ),
      .Depth      ( NumMaxTrans          ),
      .TmrStatus  ( 1'b1                 ),
      .DataHasEcc ( 1'b1                 ),
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
      .pop_i     ( fifo_pop                                ),

      .fault_o (voter_faults[3])
    );

  end

  if (MgrPortObiCfg.UseRReady) begin : gen_rready_connect
    for (genvar i = 0; i < 3; i++) begin : gen_rready_connect_tmr
      assign mgr_port_req_o.rready[i] = sbr_ports_req_i[response_id[i]].rready[i];
    end
  end
  logic [NumSbrPorts-1:0][2:0] sbr_rsp_rvalid;
  sbr_port_r_chan_t [NumSbrPorts-1:0] sbr_rsp_r;
  if (MgrPortObiCfg.IdWidth == SbrPortObiCfg.IdWidth) begin : gen_rid_identical
    always_comb begin : proc_sbr_rsp
      for (int i = 0; i < NumSbrPorts; i++) begin
        // Always assign r struct to avoid triplication overhead
        `OBI_SET_R_STRUCT(sbr_rsp_r[i], mgr_port_rsp_i.r);
        sbr_rsp_r[i].other_ecc = mgr_port_rsp_i.r.other_ecc;
        sbr_rsp_rvalid[i] = '0;
      end
      for (int i = 0; i < 3; i++) begin
        sbr_rsp_rvalid[response_id[i]][i] = mgr_port_rsp_i.rvalid[i];
      end
    end
    assign hsiao_faults[8:6] = '0;
    assign hsiao_faults_gated[8:6] = '0;
    assign voter_faults[4] = '0;
  end else begin : gen_rid_decrease
    logic [2:0][MgrPortObiCfg.IdWidth-1:0] mgr_rid_tmr;
    sbr_port_r_chan_t [2:0] sbr_r_tmr;
    sbr_port_r_chan_t sbr_r;

    for (genvar i = 0; i < 3; i++) begin : gen_tmr_rid
      relobi_r_other_decoder #(
        .Cfg          (MgrPortObiCfg),
        .r_optional_t (r_optional_t)
      ) i_r_other_decode (
        .rid_i       (mgr_port_rsp_i.r.rid),
        .err_i       (mgr_port_rsp_i.r.err),
        .r_optional_i(mgr_port_rsp_i.r.r_optional),
        .other_ecc_i (mgr_port_rsp_i.r.other_ecc),
        .rid_o       (mgr_rid_tmr[i]),
        .err_o       (sbr_r_tmr[i].err),
        .r_optional_o(sbr_r_tmr[i].r_optional),
        .fault_o (hsiao_faults[6+i])
      );
      assign sbr_r_tmr[i].rid = mgr_rid_tmr[i][SbrPortObiCfg.IdWidth-1:0];
      relobi_r_other_encoder #(
        .Cfg          (SbrPortObiCfg),
        .r_optional_t (r_optional_t)
      ) i_r_other_encode (
        .rid_i       (sbr_r_tmr[i].rid),
        .err_i       (sbr_r_tmr[i].err),
        .r_optional_i(sbr_r_tmr[i].r_optional),
        .other_ecc_o (sbr_r_tmr[i].other_ecc)
      );
      assign sbr_r_tmr[i].rdata = mgr_port_rsp_i.r.rdata;
    end
    assign hsiao_faults_gated[8:6] = fifo_pop[0] ? hsiao_faults[8:6] : '0;
    always_comb begin
      sbr_rsp_rvalid = '0;
      for (int i = 0; i < 3; i++) begin
        sbr_rsp_rvalid[response_id[i]][i] = mgr_port_rsp_i.rvalid[i];
      end
    end
    relobi_tmr_r #(
      .ObiCfg (SbrPortObiCfg),
      .obi_r_chan_t (sbr_port_r_chan_t),
      .r_optional_t (r_optional_t)
    ) tmr_r_vote (
      .three_r_i(sbr_r_tmr),
      .voted_r_o(sbr_r),
      .fault_o (voter_faults[4])
    );
    for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_sbr_r_assign
      assign sbr_rsp_r[i].rdata = sbr_r.rdata;
      assign sbr_rsp_r[i].rid = sbr_r.rid;
      assign sbr_rsp_r[i].err = sbr_r.err;
      assign sbr_rsp_r[i].r_optional = sbr_r.r_optional;
      assign sbr_rsp_r[i].other_ecc = sbr_r.other_ecc;
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
