// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

/// An encoder for reliable OBI
module relobi_decoder import hsiao_ecc_pkg::*; #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg = obi_pkg::ObiDefaultConfig,

  parameter type relobi_req_t           = logic,
  parameter type relobi_rsp_t           = logic,
  parameter type obi_req_t              = logic,
  parameter type obi_rsp_t              = logic,
  parameter type a_optional_t           = logic,
  parameter type r_optional_t           = logic
) (
  input  relobi_req_t rel_req_i,
  output relobi_rsp_t rel_rsp_o,

  output obi_req_t    req_o,
  input  obi_rsp_t    rsp_i

  // TODO: error output!!!
);

  TMR_voter_detect i_req_valid_vote (
    .a_i        (rel_req_i.req[0]),
    .b_i        (rel_req_i.req[1]),
    .c_i        (rel_req_i.req[2]),
    .majority_o (req_o.req),
    .error_cba_o()
  );

  assign rel_rsp_o.gnt = {3{rsp_i.gnt}};

  if (Cfg.UseRReady) begin : gen_rready_vote
    TMR_voter_detect i_rsp_ready_vote (
      .a_i        (rel_req_i.rready[0]),
      .b_i        (rel_req_i.rready[1]),
      .c_i        (rel_req_i.rready[2]),
      .majority_o (req_o.rready),
      .error_cba_o()
    );
  end

  assign rel_rsp_o.rvalid = {3{rsp_i.rvalid}};

  hsiao_ecc_dec #(
    .DataWidth ( Cfg.AddrWidth )
  ) i_addr_dec (
    .in        ( rel_req_i.a.addr ),
    .out       ( req_o.a.addr     ),
    .syndrome_o(),
    .err_o     ()
  );

  hsiao_ecc_dec #(
    .DataWidth ( Cfg.DataWidth )
  ) i_wdata_dec (
    .in        ( rel_req_i.a.wdata ),
    .out       ( req_o.a.wdata     ),
    .syndrome_o(),
    .err_o     ()
  );

  relobi_a_other_decoder #(
    .Cfg          (Cfg),
    .a_optional_t (a_optional_t)
  ) i_a_remaining_dec (
    .we_i        (rel_req_i.a.we),
    .be_i        (rel_req_i.a.be),
    .aid_i       (rel_req_i.a.aid),
    .a_optional_i(rel_req_i.a.a_optional),
    .other_ecc_i (rel_req_i.a.other_ecc),
    .we_o        (req_o.a.we),
    .be_o        (req_o.a.be),
    .aid_o       (req_o.a.aid),
    .a_optional_o(req_o.a.a_optional )
  );

  hsiao_ecc_enc #(
    .DataWidth ( Cfg.DataWidth )
  ) i_rdata_enc (
    .in ( rsp_i.r.rdata ),
    .out( rel_rsp_o.r.rdata )
  );

  relobi_r_other_encoder #(
    .Cfg          (Cfg),
    .r_optional_t (r_optional_t)
  ) i_r_remaining_enc (
    .err_i       (rsp_i.r.err),
    .rid_i       (rsp_i.r.rid),
    .r_optional_i(rsp_i.r.r_optional),
    .other_ecc_o (rel_rsp_o.r.other_ecc)
  );

  assign rel_rsp_o.r.err = rsp_i.r.err;
  assign rel_rsp_o.r.rid = rsp_i.r.rid;
  assign rel_rsp_o.r.r_optional = rsp_i.r.r_optional;
endmodule
