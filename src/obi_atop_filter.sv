// Copyright 2026 Mosaic SoC Ltd.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"
`include "common_cells/assertions.svh"

/// Filter atomic operations (ATOPs) in a protocol-compliant manner.
///
/// This module filters atomic operations (ATOPs), i.e., write transactions that have a non-zero
/// `a.atop` value, from its `sbr` to its `mgr` port. This module guarantees that:
///
/// 1) `a.atop` is always `obi_pkg::ATOPNONE` on the `mgr` port;
///
/// 2) Transactions with non-zero `a.atop` on the `sbr` port are handled in conformance with the
///    OBI standard by replying to such transactions with `{err, exokay} = 2’b10`.
///
/// ## Intended usage
/// This module is intended to be placed between managers that may issue ATOPs and subordinates that
/// do not support ATOPs. That way, this module ensures that the OBI protocol remains in a defined
/// state on systems with mixed ATOP capabilities.
///
/// This module does not support OBI integrity.
module obi_atop_filter
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
  /// The optional field structs.
  parameter type               mgr_port_obi_a_optional_t = logic,
  parameter type               sbr_port_obi_r_optional_t = logic,
  /// Maximum number of transactions in-flight
  parameter int unsigned       MaxTrans = 32'd2
) (
  input logic clk_i,
  input logic rst_ni,
  input logic testmode_i,

  input  sbr_port_obi_req_t sbr_port_req_i,
  output sbr_port_obi_rsp_t sbr_port_rsp_o,

  output mgr_port_obi_req_t mgr_port_req_o,
  input  mgr_port_obi_rsp_t mgr_port_rsp_i
);

  localparam int unsigned TransCounterBitWidth = (MaxTrans == 1) ? 2 : $clog2(MaxTrans+1);

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
  if (MgrPortObiCfg.OptionalCfg.UseAtop) begin : gen_atop
    // Atop not forwarded from Sbr port.
    assign a_optional.atop = obi_pkg::DefaultAtop;
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
  if (MgrPortObiCfg.OptionalCfg.AChkWidth) begin : gen_achk
    if (SbrPortObiCfg.OptionalCfg.AChkWidth) begin : gen_achk_assign
      assign a_optional.achk = sbr_port_req_i.a.a_optional.achk;
    end else begin : gen_no_achk
      assign a_optional.achk = '0;
    end
  end

  if (!MgrPortObiCfg.OptionalCfg.AUserWidth &&
    !MgrPortObiCfg.OptionalCfg.WUserWidth &&
    !MgrPortObiCfg.OptionalCfg.UseAtop &&
    !MgrPortObiCfg.OptionalCfg.UseProt &&
    !MgrPortObiCfg.OptionalCfg.UseMemtype &&
    !MgrPortObiCfg.OptionalCfg.MidWidth &&
    !MgrPortObiCfg.OptionalCfg.UseDbg &&
    !MgrPortObiCfg.OptionalCfg.AChkWidth) begin : gen_no_optional
    assign a_optional = '0;
  end

  sbr_port_obi_r_optional_t r_optional;

  if (SbrPortObiCfg.OptionalCfg.RUserWidth) begin : gen_ruser
    if (MgrPortObiCfg.OptionalCfg.RUserWidth) begin : gen_ruser_assign
      assign r_optional.ruser = mgr_port_rsp_i.r.r_optional.ruser;
    end else begin : gen_no_ruser
      assign r_optional.ruser = '0;
    end
  end

  assign r_optional.exokay = '0;

  logic [TransCounterBitWidth-1:0] trans_counter_d, trans_counter_q;
  logic atop_req_pending_d, atop_req_pending_q;
  logic atop_detected_d, atop_detected_q;
  logic [SbrPortObiCfg.IdWidth-1:0] err_id_d, err_id_q;

  logic mgr_port_req_rready, sbr_port_req_rready;
  logic is_atop;
  logic inject_atop_err_resp;

  assign is_atop = sbr_port_req_i.a.a_optional.atop[5];

  assign inject_atop_err_resp = atop_detected_q & (trans_counter_q == 0);

  always_comb begin : proc_req_rsp
    // State
    atop_req_pending_d = 1'b0;

    // Request feed-through
    mgr_port_req_o.a.addr       = sbr_port_req_i.a.addr;
    mgr_port_req_o.a.we         = sbr_port_req_i.a.we;
    mgr_port_req_o.a.be         = sbr_port_req_i.a.be;
    mgr_port_req_o.a.wdata      = sbr_port_req_i.a.wdata;
    mgr_port_req_o.a.aid        = sbr_port_req_i.a.aid;
    mgr_port_req_o.a.a_optional = a_optional;

    // By default, forward the signals request handshake signals
    mgr_port_req_o.req = sbr_port_req_i.req;
    sbr_port_rsp_o.gnt = mgr_port_rsp_i.gnt;

    // Request Handshake signals
    if (atop_detected_q | (trans_counter_q == MaxTrans)) begin
      // Atomic OP detected or Counter full. Don't grant any new requests
      mgr_port_req_o.req = 1'b0;
      sbr_port_rsp_o.gnt = 1'b0;
    end else begin
      // Prevent forwarding atop requests
      if (sbr_port_req_i.req & is_atop) begin
        mgr_port_req_o.req = 1'b0;
      end

      if (SbrPortObiCfg.CombGnt) begin
        // If CombGnt is allowed, atop requests can be granted right away because they are handled
        // locally.
        if (sbr_port_req_i.req & is_atop) begin
          sbr_port_rsp_o.gnt = 1'b1;
        end
      end else begin
        // If CombGnt is not allowed, atop requests cannot be granted by this module right away, as
        // this would create an illegal dependency.
        // If the request is not granted in the same cycle, set a flag and grant it in the next
        // cycle.
        if (sbr_port_req_i.req & is_atop & !sbr_port_rsp_o.gnt & !atop_req_pending_q) begin
          atop_req_pending_d = 1'b1;
        end
        if (atop_req_pending_q) begin
          sbr_port_rsp_o.gnt = 1'b1;
        end
      end
    end

    // Response
    sbr_port_rsp_o.r.rdata      = mgr_port_rsp_i.r.rdata;
    sbr_port_rsp_o.r.rid        = mgr_port_rsp_i.r.rid;
    sbr_port_rsp_o.r.err        = mgr_port_rsp_i.r.err;
    sbr_port_rsp_o.r.r_optional = r_optional;

    mgr_port_req_rready   = sbr_port_req_rready;
    sbr_port_rsp_o.rvalid = mgr_port_rsp_i.rvalid;

    // Inject atop error response
    if (inject_atop_err_resp) begin
      sbr_port_rsp_o.r.rdata      = '0;
      sbr_port_rsp_o.r.rid        = err_id_q;
      sbr_port_rsp_o.r.err        = 1'b1;
      sbr_port_rsp_o.r.r_optional = '0;

      sbr_port_rsp_o.rvalid       = 1'b1;
      mgr_port_req_rready         = 1'b0;
    end
  end

  always_comb begin : proc_atop_state
    atop_detected_d    = atop_detected_q;
    err_id_d           = err_id_q;

    // Save the request id on an atop request
    if (sbr_port_req_i.req & sbr_port_rsp_o.gnt & is_atop & !atop_detected_q) begin
      atop_detected_d = 1'b1;
      err_id_d        = sbr_port_req_i.a.aid;
    end

    // Clear atop detected when the injected error response is accepted
    if (sbr_port_rsp_o.rvalid & sbr_port_req_rready & inject_atop_err_resp) begin
      atop_detected_d = 1'b0;
    end
  end

  always_comb begin : proc_counter
    // Counter for outstanding transactions to be completed in-order
    trans_counter_d = trans_counter_q;
    if (mgr_port_rsp_i.rvalid & mgr_port_req_rready) begin
      trans_counter_d--;
    end
    if (mgr_port_req_o.req & mgr_port_rsp_i.gnt) begin
      trans_counter_d++;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      trans_counter_q    <= '0;
      atop_req_pending_q <= '0;
      atop_detected_q    <= '0;
      err_id_q           <= '0;
    end else begin
      trans_counter_q    <= trans_counter_d;
      atop_req_pending_q <= atop_req_pending_d;
      atop_detected_q    <= atop_detected_d;
      err_id_q           <= err_id_d;
    end
  end

  if (MgrPortObiCfg.UseRReady) begin : gen_mgr_rready
    assign mgr_port_req_o.rready = mgr_port_req_rready;
  end

  if (SbrPortObiCfg.UseRReady) begin : gen_sbr_rready
    assign sbr_port_req_rready = sbr_port_req_i.rready;
  end else begin
    assign sbr_port_req_rready = 1'b1;
  end

`ifndef OBI_ASSERTS_OFF
  `ASSERT_INIT(sbr_atop_enabled, SbrPortObiCfg.OptionalCfg.UseAtop,
      "obi_atop_filter: SbrPortObiCfg requires UseAtop.")
  `ASSERT_INIT(integrity_unsupported, !SbrPortObiCfg.Integrity && !MgrPortObiCfg.Integrity,
      "obi_atop_filter: Integrity not supported")
  `ASSERT_INIT(max_trans_nonzero, MaxTrans >= 1,
      "obi_atop_filter: MaxTrans must be >= 1")
  `ASSERT_INIT(equal_addr_width, $bits(sbr_port_req_i.a.addr) == $bits(mgr_port_req_o.a.addr),
      "obi_atop_filter: Address width mismatch between sbr and mgr ports!")
  `ASSERT_INIT(equal_data_width, $bits(sbr_port_req_i.a.wdata) == $bits(mgr_port_req_o.a.wdata),
      "obi_atop_filter: Data width mismatch between sbr and mgr ports!")
  `ASSERT_INIT(equal_id_width, $bits(sbr_port_req_i.a.aid) == $bits(mgr_port_req_o.a.aid),
      "obi_atop_filter: ID width mismatch between sbr and mgr ports")
  if (MgrPortObiCfg.OptionalCfg.UseAtop) begin : gen_assert_mgr_atop_none
    `ASSERT(mgr_atop_is_none,
        mgr_port_req_o.req |-> (mgr_port_req_o.a.a_optional.atop == obi_pkg::ATOPNONE),
        clk_i, !rst_ni, "obi_atop_filter: manager port atop is not ATOPNONE!")
    `ASSERT(mgr_exokay_is_zero,
        mgr_port_rsp_i.rvalid |-> !mgr_port_rsp_i.r.r_optional.exokay,
        clk_i, !rst_ni, "obi_atop_filter: manager port exokay is not zero!")
  end
  `ASSERT(sbr_exokay_is_zero,
      sbr_port_rsp_o.rvalid |-> !sbr_port_rsp_o.r.r_optional.exokay,
      clk_i, !rst_ni, "obi_atop_filter: sbr port exokay is not zero!")
  `ASSERT(counter_no_underflow,
      (trans_counter_q == '0) |-> !(mgr_port_rsp_i.rvalid & mgr_port_req_rready),
      clk_i, !rst_ni, "obi_atop_filter: transaction counter underflow!")
  `ASSERT(counter_no_overflow,
      (trans_counter_q == MaxTrans) |->
          !(mgr_port_req_o.req & mgr_port_rsp_i.gnt) | (mgr_port_rsp_i.rvalid & mgr_port_req_rready),
      clk_i, !rst_ni, "obi_atop_filter: transaction counter overflow!")
`endif

endmodule

module obi_atop_filter_intf
  import obi_pkg::*;
#(
  /// The configuration of the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg = obi_pkg::ObiDefaultConfig,
  /// The configuration of the manager port (output port).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg = SbrPortObiCfg,
  /// Maximum number of transactions in-flight
  parameter int unsigned       MaxTrans       = 32'd2
) (
  input logic clk_i,
  input logic rst_ni,
  input logic testmode_i,

  OBI_BUS.Subordinate sbr_port,
  OBI_BUS.Manager     mgr_port
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

  obi_atop_filter #(
      .SbrPortObiCfg            (SbrPortObiCfg),
      .MgrPortObiCfg            (MgrPortObiCfg),
      .sbr_port_obi_req_t       (sbr_port_obi_req_t),
      .sbr_port_obi_rsp_t       (sbr_port_obi_rsp_t),
      .mgr_port_obi_req_t       (mgr_port_obi_req_t),
      .mgr_port_obi_rsp_t       (mgr_port_obi_rsp_t),
      .mgr_port_obi_a_optional_t(mgr_port_obi_a_optional_t),
      .sbr_port_obi_r_optional_t(sbr_port_obi_r_optional_t),
      .MaxTrans                 (MaxTrans)
  ) i_obi_atop_filter (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .sbr_port_req_i(sbr_port_req),
      .sbr_port_rsp_o(sbr_port_rsp),
      .mgr_port_req_o(mgr_port_req),
      .mgr_port_rsp_i(mgr_port_rsp)
  );

endmodule
