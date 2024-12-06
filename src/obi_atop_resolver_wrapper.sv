// Copyright 2024 Mosaic SoC Ltd. All rights reserved.
// Authors: Luca Rufer, luca@mosaic-soc.com

`include "obi/typedef.svh"

/// A wrapper to the OBI atomic operation resolver that allows the resolver to be bypassed.
module obi_atop_resolver_wrapper
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
  parameter bit                RegisterAmo               = 1'b0,
  /// Resolver atomic operations. When 1, resolve ATOPs, when 0, block atomics and respond with err.
  parameter bit                Resolve                   = 1'b1
) (
  input logic clk_i,
  input logic rst_ni,
  input logic testmode_i,

  input  sbr_port_obi_req_t sbr_port_req_i,
  output sbr_port_obi_rsp_t sbr_port_rsp_o,

  output mgr_port_obi_req_t mgr_port_req_o,
  input  mgr_port_obi_rsp_t mgr_port_rsp_i
);

  if (Resolve) begin : gen_resolve

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
      .sbr_port_req_i,
      .sbr_port_rsp_o,
      .mgr_port_req_o,
      .mgr_port_rsp_i
    );

  end else begin : gen_block

    localparam int unsigned MaxTrans = 32'd3;
    localparam int unsigned TransCounterBitWidth = $clog2(MaxTrans);

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

    logic [TransCounterBitWidth-1:0] trans_counter_d, trans_counter_q;
    logic [SbrPortObiCfg.IdWidth-1:0] err_id_d, err_id_q;
    logic atop_detected_d, atop_detected_q;

    logic mgr_port_req_rready, sbr_port_req_rready;

    always_comb begin : proc_bypass
      // Request feed-through
      mgr_port_req_o.a.addr       = sbr_port_req_i.a.addr;
      mgr_port_req_o.a.we         = sbr_port_req_i.a.we;
      mgr_port_req_o.a.be         = sbr_port_req_i.a.be;
      mgr_port_req_o.a.wdata      = sbr_port_req_i.a.wdata;
      mgr_port_req_o.a.aid        = sbr_port_req_i.a.aid;
      mgr_port_req_o.a.a_optional = a_optional;

      // Request Handshake signals
      if (atop_detected_q | (trans_counter_q == MaxTrans)) begin
        mgr_port_req_o.req = 1'b0;
        sbr_port_rsp_o.gnt = 1'b0;
      end else begin
        mgr_port_req_o.req = sbr_port_req_i.req & ~sbr_port_req_i.a.a_optional.atop[5];
        sbr_port_rsp_o.gnt = mgr_port_rsp_i.gnt;
      end

      // Check for atomics in a request
      atop_detected_d = atop_detected_q;
      err_id_d        = err_id_q;
      if (sbr_port_req_i.req & sbr_port_req_i.a.a_optional.atop[5] & ~atop_detected_q) begin
        sbr_port_rsp_o.gnt = 1'b1;
        atop_detected_d    = 1'b1;
        err_id_d           = mgr_port_req_o.a.aid;
      end

      // Response
      sbr_port_rsp_o.r.rdata      = mgr_port_rsp_i.r.rdata;
      sbr_port_rsp_o.r.rid        = mgr_port_rsp_i.r.rid;
      sbr_port_rsp_o.r.err        = mgr_port_rsp_i.r.err;
      sbr_port_rsp_o.r.r_optional = '0;
      if (SbrPortObiCfg.OptionalCfg.RUserWidth && MgrPortObiCfg.OptionalCfg.RUserWidth) begin
        sbr_port_rsp_o.r.r_optional.ruser = mgr_port_rsp_i.r.r_optional.ruser;
      end
      sbr_port_rsp_o.r.r_optional.exokay = '0;

      mgr_port_req_rready                = sbr_port_req_rready;
      sbr_port_rsp_o.rvalid              = mgr_port_rsp_i.rvalid;

      // Overwrite response with ATOP err
      if (atop_detected_q & trans_counter_q == 0) begin
        sbr_port_rsp_o.r.rdata      = '0;
        sbr_port_rsp_o.r.rid        = err_id_q;
        sbr_port_rsp_o.r.err        = 1'b1;
        sbr_port_rsp_o.r.r_optional = '0;

        mgr_port_req_rready         = 1'b0;
        sbr_port_rsp_o.rvalid       = 1'b1;

        // Reset atop_detected on subordinate port handshake
        if (sbr_port_req_rready & sbr_port_rsp_o.rvalid) begin
          atop_detected_d = 1'b0;
        end
      end

      // Counter for outstanding transactions to be completed in-order
      trans_counter_d = trans_counter_q;
      if (mgr_port_req_o.req & mgr_port_rsp_i.gnt) begin
        trans_counter_d++;
      end
      if (mgr_port_rsp_i.rvalid & mgr_port_req_rready) begin
        trans_counter_d--;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        trans_counter_q <= '0;
        atop_detected_q <= '0;
        err_id_q        <= '0;
      end else begin
        trans_counter_q <= trans_counter_d;
        atop_detected_q <= atop_detected_d;
        err_id_q        <= err_id_d;
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

  end

endmodule
