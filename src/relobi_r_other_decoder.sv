// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Diyou Shen <dishen@iis.ee.ethz.ch>

module relobi_r_other_decoder #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg           = obi_pkg::ObiDefaultConfig,

  parameter type               r_optional_t  = logic,
  parameter int unsigned       OtherEccWidth = relobi_pkg::relobi_r_other_ecc_width(Cfg)
) (
  input  logic                       err_i,
  input  logic [Cfg.IdWidth    -1:0] rid_i,
  input  r_optional_t                r_optional_i,
  input  logic [  OtherEccWidth-1:0] other_ecc_i,

  output logic                       err_o,
  output logic [Cfg.IdWidth    -1:0] rid_o,
  output r_optional_t                r_optional_o

  // TODO: error
);

  localparam int unsigned ROtherWidth = relobi_pkg::relobi_r_other_width(Cfg);
  // localparam int unsigned EssentialWidth = 1 + Cfg.IdWidth;
  // error bit is not implemented
  localparam int unsigned EssentialWidth = Cfg.IdWidth;

  localparam int unsigned ExokayBit  = ROtherWidth - EssentialWidth;
  localparam int unsigned RUserBit   = Cfg.OptionalCfg.UseAtop ? ExokayBit - 1 : ExokayBit;
  localparam int unsigned RChkBit    = (Cfg.OptionalCfg.RUserWidth > 0) ? RUserBit - Cfg.OptionalCfg.RUserWidth : RUserBit;

  logic [ROtherWidth-1:0] postdec;
  logic [ROtherWidth-1:0] predec;

  assign predec[ROtherWidth-1-:EssentialWidth] = rid_i;
  assign rid_o = postdec[ROtherWidth-1-:EssentialWidth];
  assign err_o = err_i;

  if (Cfg.OptionalCfg.UseAtop) begin
    assign predec[ExokayBit-1-:1] = r_optional_i.exokay;
    assign r_optional_o.exokay = postdec[ExokayBit-1-:1];
  end else begin
    assign r_optional_o.exokay = '0;
  end

  if (Cfg.OptionalCfg.RUserWidth > 0) begin
    assign predec[RUserBit-1-:Cfg.OptionalCfg.RUserWidth] = r_optional_i.ruser;
    assign r_optional_o.ruser = postdec[RUserBit-1-:Cfg.OptionalCfg.RUserWidth];
  end else begin
    assign r_optional_o.ruser = '0;
  end

  if (Cfg.OptionalCfg.RChkWidth > 0) begin
    assign predec[RChkBit-1-:Cfg.OptionalCfg.RChkWidth] = r_optional_i.rchk;
    assign r_optional_o.rchk = postdec[RChkBit-1-:Cfg.OptionalCfg.RChkWidth];
  end else begin
    assign r_optional_o.rchk = '0;
  end

  hsiao_ecc_dec #(
    .DataWidth (ROtherWidth)
  ) i_r_remaining_dec (
    .in        ( {other_ecc_i, predec} ),
    .out       ( postdec ),
    .syndrome_o(),
    .err_o     ()
  );

endmodule
