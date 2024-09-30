// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_encoder #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg = obi_pkg::ObiDefaultConfig,

  parameter relobi_req_t           = logic,
  parameter relobi_rsp_t           = logic,
  parameter obi_req_t              = logic,
  parameter obi_rsp_t              = logic,
  parameter a_optional_t           = logic,
  parameter r_optional_t           = logic
) (
  input  obi_req_t    req_i,
  output obi_rsp_t    rsp_o,

  output relobi_req_t rel_req_o,
  input  relobi_rsp_t rel_rsp_i

  // TODO: error output!!!
);

  assign rel_req_o.req = {3{req_i.req}};

  TMR_voter_detect i_req_gnt_vote (
    .a_i        (rel_rsp_i.gnt[0]),
    .b_i        (rel_rsp_i.gnt[1]),
    .c_i        (rel_rsp_i.gnt[2]),
    .majority_o (rsp_o.gnt),
    .error_cba_o()
  );

  if (Cfg.UseRReady) begin : gen_rready_multiply
    assign rel_req_o.rready = {3{req_i.rready}};
  end

  TMR_voter_detect i_rsp_valid_vote (
    .a_i        (rel_rsp_i.rvalid[0]),
    .b_i        (rel_rsp_i.rvalid[1]),
    .c_i        (rel_rsp_i.rvalid[2]),
    .majority_o (rsp_o.rvalid),
    .error_cba_o()
  );

  hsiao_ecc_enc #(
    .DataWidth ( Cfg.AddrWidth )
  ) i_addr_enc (
    .in ( req_i.a.addr ),
    .out( rel_req_o.a.addr ),
  );

  hsiao_ecc_enc #(
    .DataWidth ( Cfg.DataWidth )
  ) i_wdata_enc (
    .in ( req_i.a.wdata ),
    .out( rel_req_o.a.wdata ),
  );

  relobi_a_other_encoder #(
    .Cfg          (Cfg),
    .a_optional_t (a_optional_t)
  ) i_a_remaining_enc (
    .we_i        (req_i.a.we),
    .be_i        (req_i.a.be),
    .aid_i       (req_i.a.aid),
    .a_optional_i(req_i.a.a_optional),
    .other_ecc_o (rel_req_o.a.other_ecc)
  );
  assign rel_req_o.a.we = req_i.a.we;
  assign rel_req_o.a.be = req_i.a.be;
  assign rel_req_o.a.aid = req_i.a.aid;
  assign rel_req_o.a.a_optional = req_i.a.a_optional;

  hsiao_ecc_dec #(
    .DataWidth ( Cfg.DataWidth )
  ) i_rdata_dec (
    .in        ( rel_rsp_i.r.rdata ),
    .out       ( rsp_o.r.rdata ),
    .syndrome_o(),
    .err_o     ()
  );

  hsiao_ecc_dec #(
    .DataWidth ( Cfg.IdWidth /* rid */ +
                 1           /* err */ +
                 $bits(r_optional_t) /* optional */ )
  ) i_r_remaining_dec (
    .in ( {rel_rsp_i.r.other_ecc,
           rel_rsp_i.r.rid,
           rel_rsp_i.r.err,
           rel_rsp_i.r.r_optional} ),
    .out( {rsp_o.r.rid,
           rsp_o.r.err,
           rsp_o.r.r_optional} ),
    .syndrome_o(),
    .err_o     ()
  );

endmodule
