// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module relobi_a_other_decoder #(
  /// Configuration of the bus
  parameter obi_pkg::obi_cfg_t Cfg           = obi_pkg::ObiDefaultConfig,

  parameter type               a_optional_t  = logic,
  parameter int unsigned       OtherEccWidth = relobi_pkg::relobi_a_other_ecc_width(Cfg)
) (
  input  logic                       we_i,
  input  logic [Cfg.DataWidth/8-1:0] be_i,
  input  logic [Cfg.IdWidth    -1:0] aid_i,
  input  a_optional_t                a_optional_i,
  input  logic [  OtherEccWidth-1:0] other_ecc_i,

  output logic                       we_o,
  output logic [Cfg.DataWidth/8-1:0] be_o,
  output logic [Cfg.IdWidth    -1:0] aid_o,
  output a_optional_t                a_optional_o

  // TODO: error
);

  localparam int unsigned AOtherWidth = relobi_pkg::relobi_a_other_width(Cfg);
  localparam int unsigned EssentialWidth = 1 + Cfg.DataWidth/8 + Cfg.IdWidth;

  localparam int unsigned AtopBit    = AOtherWidth - EssentialWidth;
  localparam int unsigned MemTypeBit = Cfg.OptionalCfg.UseAtop    ? AtopBit - 6    : AtopBit;
  localparam int unsigned ProtBit    = Cfg.OptionalCfg.UseMemtype ? MemTypeBit - 2 : MemTypeBit;
  localparam int unsigned DebugBit   = Cfg.OptionalCfg.UseProt    ? ProtBit - 3    : ProtBit;
  localparam int unsigned AUserBit   = Cfg.OptionalCfg.UseDbg     ? DebugBit - 1   : DebugBit;

  localparam int unsigned WUserBit   = (Cfg.OptionalCfg.AUserWidth > 0) ? AUserBit - Cfg.OptionalCfg.AUserWidth : AUserBit;
  localparam int unsigned MidBit     = (Cfg.OptionalCfg.WUserWidth > 0) ? WUserBit - Cfg.OptionalCfg.WUserWidth : WUserBit;
  localparam int unsigned AChkBit    = (Cfg.OptionalCfg.MidWidth > 0)   ? MidBit - Cfg.OptionalCfg.MidWidth     : MidBit;


  logic [AOtherWidth-1:0] postdec;
  logic [AOtherWidth-1:0] predec;

  // Determine which field needs to be protected
  // If a field is not used, we don't need to add ECC to it
  assign predec[AOtherWidth-1-:EssentialWidth] = {we_i, be_i, aid_i};
  assign {we_o, be_o, aid_o} = postdec[AOtherWidth-1-:EssentialWidth];


  if (Cfg.OptionalCfg.UseAtop) begin
    assign predec[AtopBit-1-:6] = a_optional_i.atop;
    assign a_optional_o.atop = postdec[AtopBit-1-:6];
  end else begin
    assign a_optional_o.atop = '0;
  end

  if (Cfg.OptionalCfg.UseMemtype) begin
    assign predec[MemTypeBit-1-:2] = a_optional_i.memtype;
    assign a_optional_o.memtype = postdec[MemTypeBit-1-:2];
  end else begin
    assign a_optional_o.memtype = '0;
  end

  if (Cfg.OptionalCfg.UseProt) begin
    assign predec[ProtBit-1-:3] = a_optional_i.prot;
    assign a_optional_o.prot = postdec[ProtBit-1-:3];
  end else begin
    assign a_optional_o.prot = '0;
  end

  if (Cfg.OptionalCfg.UseDbg) begin
    assign predec[DebugBit-1-:1] = a_optional_i.dbg;
    assign a_optional_o.dbg = postdec[DebugBit-1-:1];
  end else begin
    assign a_optional_o.dbg = '0;
  end

  if (Cfg.OptionalCfg.AUserWidth > 0) begin
    assign predec[AUserBit-1-:Cfg.OptionalCfg.AUserWidth] = a_optional_i.auser;
    assign a_optional_o.auser = postdec[AUserBit-1-:Cfg.OptionalCfg.AUserWidth];
  end else begin
    assign a_optional_o.auser = '0;
  end

  if (Cfg.OptionalCfg.WUserWidth > 0) begin
    assign predec[WUserBit-1-:Cfg.OptionalCfg.WUserWidth] = a_optional_i.wuser;
    assign a_optional_o.wuser = postdec[WUserBit-1-:Cfg.OptionalCfg.WUserWidth];
  end else begin
    assign a_optional_o.wuser = '0;
  end

  if (Cfg.OptionalCfg.MidWidth > 0) begin
    assign predec[MidBit-1-:Cfg.OptionalCfg.MidWidth] = a_optional_i.mid;
    assign a_optional_o.mid = postdec[MidBit-1-:Cfg.OptionalCfg.MidWidth];
  end else begin
    assign a_optional_o.mid = '0;
  end

  if (Cfg.OptionalCfg.AChkWidth > 0) begin
    assign predec[AChkBit-1-:Cfg.OptionalCfg.AChkWidth] = a_optional_i.achk;
    assign a_optional_o.achk = postdec[AChkBit-1-:Cfg.OptionalCfg.AChkWidth];
  end else begin
    assign a_optional_o.achk = '0;
  end

  hsiao_ecc_dec #(
    .DataWidth (AOtherWidth)
  ) i_a_remaining_dec (
    .in        ( {other_ecc_i, predec} ),
    .out       ( postdec ),
    .syndrome_o(),
    .err_o     ()
  );

endmodule
