// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Diyou Shen <dishen@iis.ee.ethz.ch>

module relobi_r_other_encoder #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg           = obi_pkg::ObiDefaultConfig,

  parameter type               r_optional_t  = logic,
  parameter int unsigned       OtherEccWidth = relobi_pkg::relobi_r_other_ecc_width(Cfg)
) (
  input  logic                       err_i,
  input  logic [Cfg.IdWidth    -1:0] rid_i,
  input  r_optional_t                r_optional_i,

  output logic [  OtherEccWidth-1:0] other_ecc_o
);

  localparam int unsigned ROtherWidth = relobi_pkg::relobi_r_other_width(Cfg);
  // localparam int unsigned EssentialWidth = 1 + Cfg.IdWidth;
  // error bit is not implemented
  localparam int unsigned EssentialWidth = Cfg.IdWidth;

  localparam int unsigned ExokayBit  = ROtherWidth - EssentialWidth;
  localparam int unsigned RUserBit   = Cfg.OptionalCfg.UseAtop ? ExokayBit - 1 : ExokayBit;
  localparam int unsigned RChkBit    = (Cfg.OptionalCfg.RUserWidth > 0) ? RUserBit - Cfg.OptionalCfg.RUserWidth : RUserBit;

  logic [ROtherWidth-1:0] unused;
  logic [ROtherWidth-1:0] preenc;

  assign preenc[ROtherWidth-1-:EssentialWidth] = rid_i;

  if (Cfg.OptionalCfg.UseAtop) begin
    assign preenc[ExokayBit-1-:1] = r_optional_i.exokay;
  end

  if (Cfg.OptionalCfg.RUserWidth > 0) begin
    assign preenc[RUserBit-1-:Cfg.OptionalCfg.RUserWidth] = r_optional_i.ruser;
  end

  if (Cfg.OptionalCfg.RChkWidth > 0) begin
    assign preenc[RChkBit-1-:Cfg.OptionalCfg.RChkWidth] = r_optional_i.rchk;
  end
  
  hsiao_ecc_enc #(
    .DataWidth (ROtherWidth)
  ) i_r_remaining_enc (
    .in        ( preenc ),
    .out       ( {other_ecc_o, unused} )
  );

endmodule
