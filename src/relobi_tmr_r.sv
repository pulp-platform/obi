// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_tmr_r #(
  parameter obi_pkg::obi_cfg_t ObiCfg       = obi_pkg::ObiDefaultConfig,
  parameter type               obi_r_chan_t = logic,
  parameter type               r_optional_t = logic
) (
  input  obi_r_chan_t [2:0] three_r_i,
  output obi_r_chan_t       voted_r_o 
);

  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.DataWidth+hsiao_ecc_pkg::min_ecc(ObiCfg.DataWidth))
  ) i_r_data (
    .a_i        (three_r_i[0].rdata),
    .b_i        (three_r_i[1].rdata),
    .c_i        (three_r_i[2].rdata),
    .majority_o (voted_r_o.rdata),
    .error_o    (),
    .error_cba_o()
  );
  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.IdWidth)
  ) i_r_id (
    .a_i        (three_r_i[0].rid),
    .b_i        (three_r_i[1].rid),
    .c_i        (three_r_i[2].rid),
    .majority_o (voted_r_o.rid),
    .error_o    (),
    .error_cba_o()
  );
  TMR_voter i_r_err (
    .a_i        (three_r_i[0].err),
    .b_i        (three_r_i[1].err),
    .c_i        (three_r_i[2].err),
    .majority_o (voted_r_o.err)
  );

  if (ObiCfg.OptionalCfg.RUserWidth) begin : gen_ruser
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.RUserWidth)
    ) i_r_id (
      .a_i        (three_r_i[0].r_optional.user),
      .b_i        (three_r_i[1].r_optional.user),
      .c_i        (three_r_i[2].r_optional.user),
      .majority_o (voted_r_o.r_optional.user),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.RChkWidth) begin : gen_rchk
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.RChkWidth)
    ) i_r_id (
      .a_i        (three_r_i[0].r_optional.rchk),
      .b_i        (three_r_i[1].r_optional.rchk),
      .c_i        (three_r_i[2].r_optional.rchk),
      .majority_o (voted_r_o.r_optional.rchk),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.UseAtop) begin : gen_exokay
    TMR_voter i_r_err (
      .a_i        (three_r_i[0].r_optional.exokay),
      .b_i        (three_r_i[1].r_optional.exokay),
      .c_i        (three_r_i[2].r_optional.exokay),
      .majority_o (voted_r_o.r_optional.exokay)
    );
  end
  if (!ObiCfg.OptionalCfg.RUserWidth &&
      !ObiCfg.OptionalCfg.RChkWidth &&
      !ObiCfg.OptionalCfg.UseAtop ) begin : gen_optional_tie
    assign voted_r_o.r_optional = '0;
  end

  bitwise_TMR_voter #(
    .DataWidth(hsiao_ecc_pkg::min_ecc(ObiCfg.IdWidth+1+$bits(r_optional_t)))
  ) i_r_id (
    .a_i        (three_r_i[0].other_ecc),
    .b_i        (three_r_i[1].other_ecc),
    .c_i        (three_r_i[2].other_ecc),
    .majority_o (voted_r_o.other_ecc),
    .error_o    (),
    .error_cba_o()
  );


endmodule
