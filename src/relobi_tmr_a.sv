// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_tmr_a #(
  parameter obi_pkg::obi_cfg_t ObiCfg       = obi_pkg::ObiDefaultConfig,
  parameter type               obi_a_chan_t = logic,
  parameter type               a_optional_t = logic
) (
  input  obi_a_chan_t [2:0] three_a_i,
  output obi_a_chan_t       voted_a_o 
);

  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.AddrWidth+hsiao_ecc_pkg::min_ecc(ObiCfg.AddrWidth))
  ) i_r_data (
    .a_i        (three_a_i[0].addr),
    .b_i        (three_a_i[1].addr),
    .c_i        (three_a_i[2].addr),
    .majority_o (voted_a_o.addr),
    .error_o    (),
    .error_cba_o()
  );
  TMR_voter i_r_we (
    .a_i        (three_a_i[0].we),
    .b_i        (three_a_i[1].we),
    .c_i        (three_a_i[2].we),
    .majority_o (voted_a_o.we)
  );
  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.DataWidth/8)
  ) i_r_data (
    .a_i        (three_a_i[0].be),
    .b_i        (three_a_i[1].be),
    .c_i        (three_a_i[2].be),
    .majority_o (voted_a_o.be),
    .error_o    (),
    .error_cba_o()
  );
  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.DataWidth+hsiao_ecc_pkg::min_ecc(ObiCfg.DataWidth))
  ) i_r_data (
    .a_i        (three_a_i[0].wdata),
    .b_i        (three_a_i[1].wdata),
    .c_i        (three_a_i[2].wdata),
    .majority_o (voted_a_o.wdata),
    .error_o    (),
    .error_cba_o()
  );
  bitwise_TMR_voter #(
    .DataWidth(ObiCfg.IdWidth)
  ) i_r_id (
    .a_i        (three_a_i[0].aid),
    .b_i        (three_a_i[1].aid),
    .c_i        (three_a_i[2].aid),
    .majority_o (voted_a_o.aid),
    .error_o    (),
    .error_cba_o()
  );
  TMR_voter i_r_err (
    .a_i        (three_r_i[0].err),
    .b_i        (three_r_i[1].err),
    .c_i        (three_r_i[2].err),
    .majority_o (voted_r_o.err)
  );

  if (ObiCfg.OptionalCfg.AUserWidth) begin : gen_auser
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.RUserWidth)
    ) i_r_id (
      .a_i        (three_a_i[0].a_optional.auser),
      .b_i        (three_a_i[1].a_optional.auser),
      .c_i        (three_a_i[2].a_optional.auser),
      .majority_o (voted_a_o.a_optional.auser),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.WUserWidth) begin : gen_wuser
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.RUserWidth)
    ) i_r_id (
      .a_i        (three_a_i[0].a_optional.wuser),
      .b_i        (three_a_i[1].a_optional.wuser),
      .c_i        (three_a_i[2].a_optional.wuser),
      .majority_o (voted_a_o.a_optional.wuser),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.UseAtop) begin : gen_atop
    bitwise_TMR_voter #(
      .DataWidth(6)
    ) i_r_err (
      .a_i        (three_a_i[0].a_optional.atop),
      .b_i        (three_a_i[1].a_optional.atop),
      .c_i        (three_a_i[2].a_optional.atop),
      .majority_o (voted_a_o.a_optional.atop),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.UseMemtype) begin : gen_memtype
    bitwise_TMR_voter #(
      .DataWidth(2)
    ) i_r_err (
      .a_i        (three_a_i[0].a_optional.memtype),
      .b_i        (three_a_i[1].a_optional.memtype),
      .c_i        (three_a_i[2].a_optional.memtype),
      .majority_o (voted_a_o.a_optional.memtype),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.MidWidth) begin : gen_mid
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.MidWidth)
    ) i_r_err (
      .a_i        (three_a_i[0].a_optional.mid),
      .b_i        (three_a_i[1].a_optional.mid),
      .c_i        (three_a_i[2].a_optional.mid),
      .majority_o (voted_a_o.a_optional.mid),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.UseProt) begin : gen_prot
    bitwise_TMR_voter #(
      .DataWidth(3)
    ) i_r_err (
      .a_i        (three_a_i[0].a_optional.prot),
      .b_i        (three_a_i[1].a_optional.prot),
      .c_i        (three_a_i[2].a_optional.prot),
      .majority_o (voted_a_o.a_optional.prot),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (ObiCfg.OptionalCfg.UseDbg) begin : gen_dbg
    TMR_voter i_r_err (
      .a_i        (three_a_i[0].a_optional.dbg),
      .b_i        (three_a_i[1].a_optional.dbg),
      .c_i        (three_a_i[2].a_optional.dbg),
      .majority_o (voted_a_o.a_optional.dbg)
    );
  end
  if (ObiCfg.OptionalCfg.AChkWidth) begin : gen_achk
    bitwise_TMR_voter #(
      .DataWidth(ObiCfg.OptionalCfg.AChkWidth)
    ) i_r_id (
      .a_i        (three_a_i[0].a_optional.achk),
      .b_i        (three_a_i[1].a_optional.achk),
      .c_i        (three_a_i[2].a_optional.achk),
      .majority_o (voted_a_o.a_optional.achk),
      .error_o    (),
      .error_cba_o()
    );
  end
  if (!ObiCfg.OptionalCfg.AUserWidth &&
      !ObiCfg.OptionalCfg.WUserWidth &&
      !ObiCfg.OptionalCfg.UseAtop    &&
      !ObiCfg.OptionalCfg.UseMemtype &&
      !ObiCfg.OptionalCfg.MidWidth   &&
      !ObiCfg.OptionalCfg.UseProt    &&
      !ObiCfg.OptionalCfg.UseDbg     &&
      !ObiCfg.OptionalCfg.AChkWidth    ) begin : gen_optional_tie
    assign voted_a_o.a_optional = '0;
  end
  bitwise_TMR_voter #(
    .DataWidth(hsiao_ecc_pkg::min_ecc(1+ObiCfg.DataWidth/8+ObiCfg.IdWidth+$bits(a_optional_t)))
  ) i_r_id (
    .a_i        (three_a_i[0].other_ecc),
    .b_i        (three_a_i[1].other_ecc),
    .c_i        (three_a_i[2].other_ecc),
    .majority_o (voted_a_o.other_ecc),
    .error_o    (),
    .error_cba_o()
  );

endmodule
