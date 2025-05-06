// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

/// An encoder for reliable OBI
module relobi_decoder import hsiao_ecc_pkg::*; #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg = obi_pkg::ObiDefaultConfig,

  parameter relobi_req_t           = logic,
  parameter relobi_rsp_t           = logic,
  parameter obi_req_t              = logic,
  parameter obi_rsp_t              = logic,
  parameter a_optional_t           = logic,
  parameter r_optional_t           = logic
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
    .a_optional_o(req_o.a.a_optional)
  );

  hsiao_ecc_enc #(
    .DataWidth ( Cfg.DataWidth )
  ) i_rdata_enc (
    .in ( rsp_i.r.rdata ),
    .out( rsp_o.r.rdata )
  );

  hsiao_ecc_enc #(
    .DataWidth ( Cfg.IdWidth /* rid */ +
                 1           /* err */ +
                 $bits(r_optional_t) /* optional */ )
  ) i_r_remaining_enc (
    .in ( {rsp_i.r.rid,
           rsp_i.r.err,
           rsp_i.r.r_optional} ),
    .out( {rel_rsp_o.r.other_ecc,
           rel_rsp_o.r.rid,
           rel_rsp_o.r.err,
           rel_rsp_o.r.r_optional} )
  );

endmodule
