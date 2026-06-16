// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Authors: Georg Rutishauser, georg@mosaic-soc.com

`include "common_cells/registers.svh"

/// This module isolates an OBI port. When `isolate_i` is low, transactions are routed through from
/// the manager to the subordinate port. When `isolate_i` is high, the module waits for any
/// in-flight transactions to be completed and then stops issuing any transactions to the
/// subordinate. Instead, incoming transactions will be answered by an OBI error subordinate (if
/// TerminateTransaction is 1) or stalled. When the subordinate port is isolated and no more
/// transactions are in flight, the isolated_o output will be asserted, indicating that (e.g.) the
/// module connected to the subordinate port can be clock gated.
module obi_isolate #(
  /// Configuration of the OBI ports - must correspond to obi_req_t and obi_rsp_t!
  parameter obi_pkg::obi_cfg_t ObiCfg               = obi_pkg::ObiDefaultConfig,
  /// Maximum number of in-flight transactions. Must be at least 2.
  parameter int unsigned       NumMaxTrans          = 32'd16,
  /// If 1, incoming transactions in isolated mode will be answered by an OBI Error Subordinate, any read will get the response 'h1501A7ED ("isolated"). Otherwise, incoming transactions will be stalled.
  parameter bit                TerminateTransaction = 1'b1,
  /// OBI request type
  parameter type               obi_req_t            = logic,
  /// OBI response type
  parameter type               obi_rsp_t            = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  logic     testmode_i,
  input  obi_req_t sbr_req_i,
  output obi_rsp_t sbr_rsp_o,
  output obi_req_t mgr_req_o,
  input  obi_rsp_t mgr_rsp_i,
  input  logic     isolate_i,
  output logic     isolated_o
);

  localparam int unsigned PendingCntWidth = $clog2(NumMaxTrans + 1);

  typedef enum logic [1:0] {
    Normal,
    Hold,
    Drain,
    Isolate
  } isolate_state_e;

  typedef logic [PendingCntWidth-1:0] cnt_t;

  isolate_state_e isolate_state_d, isolate_state_q;

  obi_req_t [1:0] demux_obi_reqs;
  obi_rsp_t [1:0] demux_obi_rsps;

  cnt_t           pending_cnt;

  logic cnt_up, cnt_down, cnt_empty;

  `FF(isolate_state_q, isolate_state_d, Normal, clk_i, rst_ni);

  if (TerminateTransaction) begin : gen_iso_err_slv
    obi_demux #(
      .ObiCfg     (ObiCfg),
      .obi_req_t  (obi_req_t),
      .obi_rsp_t  (obi_rsp_t),
      .NumMgrPorts(2),
      .NumMaxTrans(NumMaxTrans)
    ) i_obi_demux (
      .clk_i,
      .rst_ni,
      .sbr_port_select_i(isolated_o),
      .sbr_port_req_i   (sbr_req_i),
      .sbr_port_rsp_o   (sbr_rsp_o),
      .mgr_ports_req_o  (demux_obi_reqs),
      .mgr_ports_rsp_i  (demux_obi_rsps)
    );
    obi_err_sbr #(
      .ObiCfg     (ObiCfg),
      .obi_req_t  (obi_req_t),
      .obi_rsp_t  (obi_rsp_t),
      .NumMaxTrans(1),
      .RspData    ('h1501A7ED)
    ) i_obi_err_sbr (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .obi_req_i(demux_obi_reqs[1]),
      .obi_rsp_o(demux_obi_rsps[1])
    );
  end else begin : gen_iso_stall
    assign demux_obi_reqs[1] = '0;
    assign demux_obi_rsps[1] = '0;
    assign sbr_rsp_o         = demux_obi_rsps[0];
    assign demux_obi_reqs[0] = sbr_req_i;
  end  // else: !if(TerminateTransaction)

  // Count up if a transaction is accepted at the input
  assign cnt_up = demux_obi_reqs[0].req & demux_obi_rsps[0].gnt;

  // Count down if a response is transmitted
  if (ObiCfg.UseRReady) begin : gen_cnt_down_full_hs
    assign cnt_down = demux_obi_rsps[0].rvalid & demux_obi_reqs[0].rready;
  end else begin : gen_cnt_down_rvalid_only
    assign cnt_down = demux_obi_rsps[0].rvalid;
  end
  assign cnt_empty = (pending_cnt == 'd0);

  always_comb begin : isolate_fsm
    isolated_o        = 1'b0;
    isolate_state_d   = isolate_state_q;
    mgr_req_o         = demux_obi_reqs[0];
    demux_obi_rsps[0] = mgr_rsp_i;
    unique case (isolate_state_q)
      Normal: begin
        // if we have NumMaxTrans TX in flight, stall the input interface
        if (pending_cnt >= cnt_t'(NumMaxTrans)) begin
          demux_obi_rsps[0].gnt = 1'b0;
          mgr_req_o.req         = 1'b0;
        end else if (sbr_req_i.req & (~mgr_rsp_i.gnt)) begin
          // if a request comes in at the same time as the isolation request, we wait for it to be
          // filled.
          isolate_state_d = Hold;
        end else if (isolate_i) begin
          isolate_state_d = Drain;
        end
      end
      Hold: begin
        // we assume that the manager adheres to the OBI spec and keeps the request high, so no need to override it.
        if (mgr_rsp_i.gnt) begin
          isolate_state_d = (isolate_i) ? Drain : Normal;
        end
      end
      Drain: begin
        // wait for all pending transactions to complete, then go to isolation state
        demux_obi_rsps[0].gnt = 1'b0;
        mgr_req_o.req         = 1'b0;
        if (~isolate_i) begin // we never emptied the counter and isolate has been deasserted, so go
                              // back to normal
          isolate_state_d = Normal;
        end else if (cnt_empty | ((pending_cnt == cnt_t'('d1)) & cnt_down)) begin
          isolate_state_d = Isolate;
        end
      end
      Isolate: begin
        isolated_o        = 1'b1;
        // cut everything completely
        mgr_req_o         = '0;
        demux_obi_rsps[0] = '0;
        if (~isolate_i) isolate_state_d = Normal;
      end
      default: ;// do nothing
    endcase  // unique case (isolate_state_q)
  end : isolate_fsm

  delta_counter #(
    .WIDTH          (PendingCntWidth),
    .STICKY_OVERFLOW(1'b0)
  ) i_counter (
    .clk_i,
    .rst_ni,
    .clear_i   (1'b0),
    .en_i      (cnt_up ^ cnt_down),
    .load_i    (1'b0),
    .down_i    (cnt_down),
    .delta_i   (cnt_t'('d1)),
    .d_i       ('0),
    .q_o       (pending_cnt),
    .overflow_o()
  );

`ifndef SYNTHESIS
  initial begin
    assume (NumMaxTrans >= 2)
    else $fatal(1, "obi_isolate: NumMaxTrans must be >= 2!");
  end

  default disable iff (!rst_ni); cnt_overflow :
  assert property (@(posedge clk_i) (pending_cnt == '1) |=> (pending_cnt != '0))
  else $fatal(1, "obi_isolate: pending_cnt overflow!");
  cnt_underflow :
  assert property (@(posedge clk_i) (pending_cnt == '0) |=> (pending_cnt != '1))
  else $fatal(1, "obi_isolate: pending_cnt underflow!");
  isolate_cnt0 :
  assert property (@(posedge clk_i) (isolated_o == 1'b1 |-> cnt_empty))
  else $fatal(1, "obi_isolate: pending_cnt not 0 'Isolate' state!");
  drain_no_cnt_up :
  assert property (@(posedge clk_i) (isolate_state_q == Drain |-> !cnt_up));
`endif

endmodule : obi_isolate

`include "obi/typedef.svh"
`include "obi/assign.svh"

/// Interface version of obi_isolate.
module obi_isolate_intf #(
  /// Configuration of the OBI ports - must correspond to obi_req_t and obi_rsp_t!
  parameter obi_pkg::obi_cfg_t ObiCfg               = obi_pkg::ObiDefaultConfig,
  /// Maximum number of in-flight transactions. Must be at least 2.
  parameter int unsigned       NumMaxTrans          = 32'd16,
  /// If 1, incoming transactions in isolated mode will be answered by an OBI Error Subordinate, any read will get the response 'h1501A7ED ("isolated"). Otherwise, incoming transactions will be stalled.
  parameter bit                TerminateTransaction = 1'b1
) (
  input  logic               clk_i,
  input  logic               rst_ni,
  input  logic               testmode_i,
         OBI_BUS.Subordinate sbr_port,
         OBI_BUS.Manager     mgr_port,
  input  logic               isolate_i,
  output logic               isolated_o
);
  `OBI_TYPEDEF_ALL(obi, ObiCfg)

  obi_req_t sbr_port_req;
  obi_rsp_t sbr_port_rsp;

  obi_req_t mgr_port_req;
  obi_rsp_t mgr_port_rsp;

  `OBI_ASSIGN_TO_REQ(sbr_port_req, sbr_port, ObiCfg)
  `OBI_ASSIGN_FROM_RSP(sbr_port, sbr_port_rsp, ObiCfg)

  `OBI_ASSIGN_FROM_REQ(mgr_port, mgr_port_req, ObiCfg)
  `OBI_ASSIGN_TO_RSP(mgr_port_rsp, mgr_port, ObiCfg)

  obi_isolate #(
    .ObiCfg              (ObiCfg),
    .NumMaxTrans         (NumMaxTrans),
    .TerminateTransaction(TerminateTransaction),
    .obi_req_t           (obi_req_t),
    .obi_rsp_t           (obi_rsp_t)
  ) i_obi_isolate (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .sbr_req_i(sbr_port_req),
    .sbr_rsp_o(sbr_port_rsp),
    .mgr_req_o(mgr_port_req),
    .mgr_rsp_i(mgr_port_rsp),
    .isolate_i,
    .isolated_o
  );

endmodule : obi_isolate_intf
