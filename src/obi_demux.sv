// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module obi_demux #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The request struct for all ports.
  parameter type               obi_req_t   = logic,
  /// The response struct for all ports.
  parameter type               obi_rsp_t   = logic,
  /// The number of manager ports.
  parameter int unsigned       NumMgrPorts = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans = 32'd0,
  /// The type of the port select signal.
  parameter type               select_t    = logic [cf_math_pkg::idx_width(NumMgrPorts)-1:0],
  /// The burst extension mode.
  parameter obi_pkg::obi_burst_mode_e BurstMode = obi_pkg::OBI_BURST_NONE,
  /// The width of the beat-framed burst length field.
  parameter int unsigned       BurstLenWidth = 32'd8
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  select_t                    sbr_port_select_i,
  input  obi_req_t                   sbr_port_req_i,
  output obi_rsp_t                   sbr_port_rsp_o,

  output obi_req_t [NumMgrPorts-1:0] mgr_ports_req_o,
  input  obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp_i
);

  if (ObiCfg.Integrity) begin : gen_integrity_err
    $fatal(1, "unimplemented");
  end

  if (BurstMode == obi_pkg::OBI_BURST_BEAT_FRAMED && BurstLenWidth == 0) begin : gen_burst_width_err
    $fatal(1, "beat-framed bursts require BurstLenWidth > 0");
  end

  // stall requests to ensure in-order behavior (could be handled differently with rready)
  localparam int unsigned CounterWidth = cf_math_pkg::idx_width(NumMaxTrans);

  logic cnt_up, cnt_down, overflow;
  logic [CounterWidth-1:0] in_flight;
  logic sbr_port_gnt;
  logic sbr_port_rready;
  logic rsp_phase_stalled;

  select_t select_d, select_q;
  select_t req_select;
  logic req_accepted;

  assign req_accepted = sbr_port_req_i.req && sbr_port_gnt;

  if (BurstMode == obi_pkg::OBI_BURST_BEAT_FRAMED) begin : gen_burst_lock
    logic burst_locked_d, burst_locked_q;
    select_t burst_select_d, burst_select_q;

    assign req_select = burst_locked_q ? burst_select_q : sbr_port_select_i;

    always_comb begin
      burst_locked_d = burst_locked_q;
      burst_select_d = burst_select_q;

      if (req_accepted) begin
        if (!burst_locked_q && sbr_port_req_i.a.a_optional.bfirst &&
            !sbr_port_req_i.a.a_optional.blast) begin
          burst_locked_d = 1'b1;
          burst_select_d = req_select;
        end else if (burst_locked_q && sbr_port_req_i.a.a_optional.blast) begin
          burst_locked_d = 1'b0;
        end
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_burst_lock
      if (!rst_ni) begin
        burst_locked_q <= 1'b0;
        burst_select_q <= '0;
      end else begin
        burst_locked_q <= burst_locked_d;
        burst_select_q <= burst_select_d;
      end
    end
  end else begin : gen_no_burst_lock
    assign req_select = sbr_port_select_i;
  end

  always_comb begin : proc_req
    select_d = select_q;
    cnt_up = 1'b0;
    for (int i = 0; i < NumMgrPorts; i++) begin
      mgr_ports_req_o[i].req = 1'b0;
      mgr_ports_req_o[i].a   = '0;
    end
    sbr_port_gnt = 1'b0;

    if (!overflow) begin
      // R-4.1.1: block source changes while a stalled R phase is active
      if (req_select == select_q || (!rsp_phase_stalled &&
          (in_flight == '0 || (in_flight == 1 && cnt_down)))) begin
        mgr_ports_req_o[req_select].req = sbr_port_req_i.req;
        mgr_ports_req_o[req_select].a   = sbr_port_req_i.a;
        sbr_port_gnt                    = mgr_ports_rsp_i[req_select].gnt;
      end
    end

    if (sbr_port_req_i.req && sbr_port_gnt) begin
      select_d = req_select;
      cnt_up = 1'b1;
    end
  end

  assign sbr_port_rsp_o.gnt    = sbr_port_gnt;
  assign sbr_port_rsp_o.r      = mgr_ports_rsp_i[select_q].r;
  assign sbr_port_rsp_o.rvalid = mgr_ports_rsp_i[select_q].rvalid;

  if (ObiCfg.UseRReady) begin : gen_rready
    assign sbr_port_rready = sbr_port_req_i.rready;
    assign rsp_phase_stalled = sbr_port_rsp_o.rvalid && !sbr_port_rready;

    for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_rready
      assign mgr_ports_req_o[i].rready = sbr_port_req_i.rready;
    end
  end else begin : gen_no_rready
    assign sbr_port_rready = 1'b1;
    assign rsp_phase_stalled = 1'b0;
  end

  // R-6: retire the active response only after its R phase transfer completes
  assign cnt_down = sbr_port_rsp_o.rvalid && sbr_port_rready;

  delta_counter #(
    .WIDTH           ( CounterWidth ),
    .STICKY_OVERFLOW ( 1'b0         )
  ) i_counter (
    .clk_i,
    .rst_ni,

    .clear_i   ( 1'b0                           ),
    .en_i      ( cnt_up ^ cnt_down              ),
    .load_i    ( 1'b0                           ),
    .down_i    ( cnt_down                       ),
    .delta_i   ( {{CounterWidth-1{1'b0}}, 1'b1} ),
    .d_i       ( '0                             ),
    .q_o       ( in_flight                      ),
    .overflow_o( overflow                       )
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_select
    if(!rst_ni) begin
      select_q <= '0;
    end else begin
      select_q <= select_d;
    end
  end

endmodule

`include "obi/typedef.svh"
`include "obi/assign.svh"

module obi_demux_intf #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The number of manager ports.
  parameter int unsigned       NumMgrPorts = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans = 32'd0,
  /// The type of the port select signal.
  parameter type               select_t    = logic [cf_math_pkg::idx_width(NumMgrPorts)-1:0],
  /// The burst extension mode.
  parameter obi_pkg::obi_burst_mode_e BurstMode = obi_pkg::OBI_BURST_NONE,
  /// The width of the beat-framed burst length field.
  parameter int unsigned       BurstLenWidth = 32'd8
) (
  input logic         clk_i,
  input logic         rst_ni,

  input select_t      sbr_port_select_i,
  OBI_BUS.Subordinate sbr_port,

  OBI_BUS.Manager     mgr_ports [NumMgrPorts]
);

  if (BurstMode == obi_pkg::OBI_BURST_BEAT_FRAMED) begin : gen_burst
    `OBI_TYPEDEF_ALL_BURST(obi, ObiCfg, BurstLenWidth)

    obi_req_t sbr_port_req;
    obi_rsp_t sbr_port_rsp;

    obi_req_t [NumMgrPorts-1:0] mgr_ports_req;
    obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp;

    `OBI_ASSIGN_TO_REQ(sbr_port_req, sbr_port, ObiCfg)
    `OBI_ASSIGN_FROM_RSP(sbr_port, sbr_port_rsp, ObiCfg)

    for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mgr_ports_assign
      `OBI_ASSIGN_FROM_REQ(mgr_ports[i], mgr_ports_req[i], ObiCfg)
      `OBI_ASSIGN_TO_RSP(mgr_ports_rsp[i], mgr_ports[i], ObiCfg)
    end

    obi_demux #(
      .ObiCfg        ( ObiCfg        ),
      .obi_req_t     ( obi_req_t     ),
      .obi_rsp_t     ( obi_rsp_t     ),
      .NumMgrPorts   ( NumMgrPorts   ),
      .NumMaxTrans   ( NumMaxTrans   ),
      .select_t      ( select_t      ),
      .BurstMode     ( BurstMode     ),
      .BurstLenWidth ( BurstLenWidth )
    ) i_obi_demux (
      .clk_i,
      .rst_ni,
      .sbr_port_select_i,
      .sbr_port_req_i   ( sbr_port_req  ),
      .sbr_port_rsp_o   ( sbr_port_rsp  ),
      .mgr_ports_req_o  ( mgr_ports_req ),
      .mgr_ports_rsp_i  ( mgr_ports_rsp )
    );
  end else begin : gen_no_burst
    `OBI_TYPEDEF_ALL(obi, ObiCfg)

    obi_req_t sbr_port_req;
    obi_rsp_t sbr_port_rsp;

    obi_req_t [NumMgrPorts-1:0] mgr_ports_req;
    obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp;

    `OBI_ASSIGN_TO_REQ(sbr_port_req, sbr_port, ObiCfg)
    `OBI_ASSIGN_FROM_RSP(sbr_port, sbr_port_rsp, ObiCfg)

    for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mgr_ports_assign
      `OBI_ASSIGN_FROM_REQ(mgr_ports[i], mgr_ports_req[i], ObiCfg)
      `OBI_ASSIGN_TO_RSP(mgr_ports_rsp[i], mgr_ports[i], ObiCfg)
    end

    obi_demux #(
      .ObiCfg        ( ObiCfg        ),
      .obi_req_t     ( obi_req_t     ),
      .obi_rsp_t     ( obi_rsp_t     ),
      .NumMgrPorts   ( NumMgrPorts   ),
      .NumMaxTrans   ( NumMaxTrans   ),
      .select_t      ( select_t      ),
      .BurstMode     ( BurstMode     ),
      .BurstLenWidth ( BurstLenWidth )
    ) i_obi_demux (
      .clk_i,
      .rst_ni,
      .sbr_port_select_i,
      .sbr_port_req_i   ( sbr_port_req  ),
      .sbr_port_rsp_o   ( sbr_port_rsp  ),
      .mgr_ports_req_o  ( mgr_ports_req ),
      .mgr_ports_rsp_i  ( mgr_ports_rsp )
    );
  end

endmodule
