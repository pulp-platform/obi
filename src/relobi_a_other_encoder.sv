// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_a_other_encoder #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg           = obi_pkg::ObiDefaultConfig,

  parameter type               a_optional_t  = logic,
  parameter int unsigned       OtherEccWidth = relobi_pkg::relobi_a_other_ecc_width(Cfg)
) (
  input  logic                       we_i,
  input  logic [Cfg.DataWidth/8-1:0] be_i,
  input  logic [Cfg.IdWidth    -1:0] aid_i,
  input  a_optional_t                a_optional_i,

  output logic [  OtherEccWidth-1:0] other_ecc_o
);
  
  localparam int unsigned AOtherWidth = relobi_pkg::relobi_a_other_width(Cfg);
  localparam int unsigned EssentialWidth = 1 + Cfg.DataWidth/8 + Cfg.IdWidth;

  logic [AOtherWidth-1:0] unused;
  logic [AOtherWidth-1:0] preenc;

  localparam int unsigned AtopBit    = AOtherWidth - EssentialWidth;
  localparam int unsigned MemTypeBit = Cfg.OptionalCfg.UseAtop    ? AtopBit - 6    : AtopBit;
  localparam int unsigned ProtBit    = Cfg.OptionalCfg.UseMemtype ? MemTypeBit - 2 : MemTypeBit;
  localparam int unsigned DebugBit   = Cfg.OptionalCfg.UseProt    ? ProtBit - 3    : ProtBit;
  localparam int unsigned AUserBit   = Cfg.OptionalCfg.UseDbg     ? DebugBit - 1   : DebugBit;

  localparam int unsigned WUserBit   = (Cfg.OptionalCfg.AUserWidth > 0) ? AUserBit - Cfg.OptionalCfg.AUserWidth : AUserBit;
  localparam int unsigned MidBit     = (Cfg.OptionalCfg.WUserWidth > 0) ? WUserBit - Cfg.OptionalCfg.WUserWidth : WUserBit;
  localparam int unsigned AChkBit    = (Cfg.OptionalCfg.MidWidth > 0)   ? MidBit - Cfg.OptionalCfg.MidWidth     : MidBit;

  // Determine which field needs to be protected
  // If a field is not used, we don't need to add ECC to it
  assign preenc[AOtherWidth-1-:EssentialWidth] = {we_i, be_i, aid_i};

  if (Cfg.OptionalCfg.UseAtop) begin
    assign preenc[AtopBit-1-:6] = a_optional_i.atop;
  end

  if (Cfg.OptionalCfg.UseMemtype) begin
    assign preenc[MemTypeBit-1-:2] = a_optional_i.memtype;
  end

  if (Cfg.OptionalCfg.UseProt) begin
    assign preenc[ProtBit-1-:3] = a_optional_i.prot;
  end

  if (Cfg.OptionalCfg.UseDbg) begin
    assign preenc[DebugBit-1-:1] = a_optional_i.dbg;
  end

  if (Cfg.OptionalCfg.AUserWidth > 0) begin
    assign preenc[AUserBit-1-:Cfg.OptionalCfg.AUserWidth] = a_optional_i.auser;
  end

  if (Cfg.OptionalCfg.WUserWidth > 0) begin
    assign preenc[WUserBit-1-:Cfg.OptionalCfg.WUserWidth] = a_optional_i.wuser;
  end

  if (Cfg.OptionalCfg.MidWidth > 0) begin
    assign preenc[MidBit-1-:Cfg.OptionalCfg.MidWidth] = a_optional_i.mid;
  end

  if (Cfg.OptionalCfg.AChkWidth > 0) begin
    assign preenc[AChkBit-1-:Cfg.OptionalCfg.AChkWidth] = a_optional_i.achk;
  end

  hsiao_ecc_enc #(
    .DataWidth (AOtherWidth)
  ) i_a_remaining_enc (
    .in        ( preenc ),
    .out       ( {other_ecc_o, unused} )
  );

endmodule
