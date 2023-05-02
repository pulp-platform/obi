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
  parameter type               select_t    = logic [$clog2(NumMgrPorts)-1:0]
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  select_t                    sbr_port_select_i,
  input  obi_req_t                   sbr_port_req_i,
  output obi_rsp_t                   sbr_port_rsp_o,

  output obi_req_t [NumMgrPorts-1:0] mgr_ports_req_o,
  input  obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp_i
);

  if (ObiCfg.Integrity) begin
    $fatal(1, "unimplemented");
  end

  // stall requests to ensure in-order behavior (could be handled differently with rready)
  localparam CounterWidth = cf_math_pkg::idx_width(NumMaxTrans);

  logic cnt_up, cnt_down, overflow;
  logic [CounterWidth-1:0] in_flight;
  logic sbr_port_rready;

  select_t select_d, select_q;

  always_comb begin : proc_req
    select_d = select_q;
    cnt_up = 1'b0;
    for (int i = 0; i < NumMgrPorts; i++) begin
      mgr_ports_req_o[i].req = 1'b0;
      mgr_ports_req_o[i].a   = '0;
    end

    if (!overflow) begin
      if (sbr_port_select_i == select_q || in_flight == '0 || (in_flight == 1 && cnt_down)) begin
        mgr_ports_req_o[sbr_port_select_i].req = sbr_port_req_i.req;
        mgr_ports_req_o[sbr_port_select_i].a = sbr_port_req_i.a;
      end
    end

    if (mgr_ports_req_o[sbr_port_select_i].req && mgr_ports_rsp_i[sbr_port_select_i].gnt) begin
      select_d = sbr_port_select_i;
      cnt_up = 1'b1;
    end
  end

  assign sbr_port_rsp_o.gnt    = mgr_ports_rsp_i[sbr_port_select_i].gnt;
  assign sbr_port_rsp_o.r      = mgr_ports_rsp_i[select_q].r;
  assign sbr_port_rsp_o.rvalid = mgr_ports_rsp_i[select_q].rvalid;

  if (ObiCfg.UseRReady) begin : gen_rready
    assign sbr_port_rready = sbr_port_req_i.rready;
    for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_rready
      assign mgr_ports_req_o[i].rready = sbr_port_req_i.rready;
    end
  end else begin : gen_no_rready
    assign sbr_port_rready = 1'b1;
  end

  assign cnt_down = mgr_ports_rsp_i[select_q].rvalid && sbr_port_rready;

  delta_counter #(
    .WIDTH           ( CounterWidth ),
    .STICKY_OVERFLOW ( 1'b0         )
  ) i_counter (
    .clk_i,
    .rst_ni,

    .clear_i   ( 1'b0      ),
    .en_i      ( cnt_up ^ cnt_down ),
    .load_i    ( 1'b0      ),
    .down_i    ( cnt_down ),
    .delta_i   ( {{CounterWidth-1{1'b0}}, 1'b1} ),
    .d_i       ( '0        ),
    .q_o       ( in_flight ),
    .overflow_o( overflow  )
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_select
    if(!rst_ni) begin
      select_q <= '0;
    end else begin
      select_q <= select_d;
    end
  end

endmodule
