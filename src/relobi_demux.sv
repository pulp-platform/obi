// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_demux #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The request struct for all ports.
  parameter type               obi_req_t   = logic,
  /// The response struct for all ports.
  parameter type               obi_rsp_t   = logic,
  /// The r_chan struct for all ports.
  parameter type               obi_r_chan_t = logic,
  /// The number of manager ports.
  parameter int unsigned       NumMgrPorts = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans = 32'd0,
  /// Use TMR for select signal
  parameter bit                TmrSelect   = 1'b1,
  /// The type of the port select signal.
  parameter type               select_t    = logic [$clog2(NumMgrPorts)-1:0],
  parameter int unsigned       SelWidth    = TmrSelect ? 3 : 1
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  select_t  [   SelWidth-1:0] sbr_port_select_i,
  input  obi_req_t                   sbr_port_req_i,
  output obi_rsp_t                   sbr_port_rsp_o,

  output obi_req_t [NumMgrPorts-1:0] mgr_ports_req_o,
  input  obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp_i
);

  if (ObiCfg.Integrity) begin : gen_integrity_err
    $fatal(1, "unimplemented");
  end

  // stall requests to ensure in-order behavior (could be handled differently with rready)
  localparam int unsigned CounterWidth = cf_math_pkg::idx_width(NumMaxTrans);

  // Internals TMR'd

  logic [2:0] cnt_up, cnt_down, overflow;
  logic [2:0][CounterWidth-1:0] in_flight;
  logic [2:0] sbr_port_gnt;
  logic [2:0] sbr_port_rready;

  select_t [2:0] select_d, select_d_voted, select_q, select_i_tmr;

  logic [NumMgrPorts-1:0][2:0] mgr_ports_req;

  for (genvar i = 0; i < 3; i++) begin : gen_tmr
    assign select_i_tmr[i] = TmrSelect ? sbr_port_select_i[i] : sbr_port_select_i[0];

    always_comb begin : proc_req
      select_d[i] = select_q[i];
      cnt_up[i] = 1'b0;
      for (int j = 0; j < NumMgrPorts; j++) begin
        mgr_ports_req[j][i] = 1'b0;
      end
      sbr_port_gnt[i] = 1'b0;

      if (!overflow[i]) begin
        if (select_i_tmr[i] == select_q[i] || in_flight[i] == '0 || (in_flight[i] == 1 && cnt_down[i])) begin
          mgr_ports_req[select_i_tmr[i]][i] = sbr_port_req_i.req[i];
          sbr_port_gnt[i]                   = mgr_ports_rsp_i[select_i_tmr[i]].gnt[i];
        end
      end

      if (mgr_ports_req[select_i_tmr[i]][i] && mgr_ports_rsp_i[select_i_tmr[i]].gnt[i]) begin
        select_d[i] = select_i_tmr[i];
        cnt_up[i] = 1'b1;
      end
    end
  end

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mgr_req
    assign mgr_ports_req_o[i].req = mgr_ports_req[i];
    assign mgr_ports_req_o[i].a   = sbr_port_req_i.a;
  end

  assign sbr_port_rsp_o.gnt    = sbr_port_gnt;

  relobi_tmr_r #(
    .ObiCfg      (ObiCfg),
    .obi_r_chan_t(obi_r_chan_t)
  ) i_r_vote (
    .three_r_i({mgr_ports_rsp_i[select_q[2]].r,
                mgr_ports_rsp_i[select_q[1]].r,
                mgr_ports_rsp_i[select_q[0]].r}),
    .voted_r_o(sbr_port_rsp_o.r)
  );

  for (genvar i = 0; i < 3; i++) begin : gen_rvalid
    // Could be voted, but with only one error source (either select_q or rvalid) should suffice
    assign sbr_port_rsp_o.rvalid[i] = mgr_ports_rsp_i[select_q[i]].rvalid[i];
  end

  if (ObiCfg.UseRReady) begin : gen_rready
    assign sbr_port_rready = sbr_port_req_i.rready;
    for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_rready
      assign mgr_ports_req_o[i].rready = sbr_port_req_i.rready;
    end
  end else begin : gen_no_rready
    assign sbr_port_rready = 3'b111;
  end

  logic [2:0][CounterWidth:0] counter_q, counter_d_voted, counter_d;

  for (genvar i = 0; i < 3; i++) begin : gen_counter
    // Could be voted, but with only one error source (either select_q or rvalid) should suffice
    assign cnt_down[i] = mgr_ports_rsp_i[select_q[i]].rvalid[i] && sbr_port_rready[i];

    assign overflow[i] = counter_q[CounterWidth];
    assign in_flight[i] = counter_q[CounterWidth-1:0];

    always_comb begin
      counter_d[i] = counter_q[i];

      if (cnt_up & ~cnt_down) begin
        counter_d[i] = counter_q[i] + {{CounterWidth-1{1'b0}}, 1'b1};
      end else if (cnt_down & ~cnt_up) begin
        coutner_d[i] = counter_q[i] - {{CounterWidth-1{1'b0}}, 1'b1};
      end
    end
  end

  for (genvar i = 0; i < 3; i++) begin : gen_tmr_state
    bitwise_TMR_voter #(
      .DataWidth( $clog2(NumMgrPorts) )
    ) i_select_vote (
      .a_i        (select_d[0]),
      .b_i        (select_d[1]),
      .c_i        (select_d[2]),
      .majority_o (select_d_voted[i]),
      .error_o    (),
      .error_cba_o()
    );
    bitwise_TMR_voter #(
      .DataWidth( CounterWidth+1 )
    ) i_select_vote (
      .a_i        (counter_d[0]),
      .b_i        (counter_d[1]),
      .c_i        (counter_d[2]),
      .majority_o (counter_d_voted[i]),
      .error_o    (),
      .error_cba_o()
    );
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_select
    if(!rst_ni) begin
      counter_q <= '0;
      select_q <= '0;
    end else begin
      counter_q <= counter_d_voted;
      select_q <= select_d_voted;
    end
  end

endmodule
