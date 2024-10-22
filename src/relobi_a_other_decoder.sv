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
  localparam int unsigned OptWidth = AOtherWidth - EssentialWidth;

  logic [AOtherWidth-1:0] postdec;
  logic [AOtherWidth-1:0] predec;

  logic error;
  logic [31:0] remaining_width;

  always_comb begin : used_opt_comb
    // Determine which field needs to be protected
    // If a field is not used, we don't need to add ECC to it
    predec = '0;
    predec[AOtherWidth-1-:EssentialWidth] = {we_i, be_i, aid_i};
    {we_o, be_o, aid_o} = postdec[AOtherWidth-1-:EssentialWidth];
    error = 1'b0;
    a_optional_o = '0;

    remaining_width = AOtherWidth - EssentialWidth;

    if (Cfg.OptionalCfg.UseAtop) begin
      predec[remaining_width-1-:6] = a_optional_i.atop;
      a_optional_o.atop = postdec[remaining_width-1-:6];
      remaining_width -= 6;
    end else begin
      a_optional_o.atop = '0;
    end

    if (Cfg.OptionalCfg.UseMemtype) begin
      predec[remaining_width-1-:2] = a_optional_i.memtype;
      a_optional_o.memtype = postdec[remaining_width-1-:2];
      remaining_width -= 2;
    end else begin
      a_optional_o.memtype = '0;
    end

    if (Cfg.OptionalCfg.UseProt) begin
      predec[remaining_width-1-:3] = a_optional_i.prot;
      a_optional_o.prot = postdec[remaining_width-1-:3];
      remaining_width -= 3;
    end else begin
      a_optional_o.prot = '0;
    end

    if (Cfg.OptionalCfg.UseDbg) begin
      predec[remaining_width-1-:1] = a_optional_i.dbg;
      a_optional_o.dbg = postdec[remaining_width-1-:1];
      remaining_width -= 1;
    end else begin
      a_optional_o.dbg = '0;
    end

    if (Cfg.OptionalCfg.AUserWidth > 0) begin
      predec[remaining_width-1-:Cfg.OptionalCfg.AUserWidth] = a_optional_i.auser;
      a_optional_o.auser = postdec[remaining_width-1-:Cfg.OptionalCfg.AUserWidth];
      remaining_width -= Cfg.OptionalCfg.AUserWidth;
    end else begin
      a_optional_o.auser = '0;
    end

    if (Cfg.OptionalCfg.WUserWidth > 0) begin
      predec[remaining_width-1-:Cfg.OptionalCfg.WUserWidth] = a_optional_i.wuser;
      a_optional_o.wuser = postdec[remaining_width-1-:Cfg.OptionalCfg.WUserWidth];
      remaining_width -= Cfg.OptionalCfg.WUserWidth;
    end else begin
      a_optional_o.wuser = '0;
    end

    if (Cfg.OptionalCfg.MidWidth > 0) begin
      predec[remaining_width-1-:Cfg.OptionalCfg.MidWidth] = a_optional_i.mid;
      a_optional_o.mid = postdec[remaining_width-1-:Cfg.OptionalCfg.MidWidth];
      remaining_width -= Cfg.OptionalCfg.MidWidth;
    end else begin
      a_optional_o.mid = '0;
    end

    if (Cfg.OptionalCfg.AChkWidth > 0) begin
      predec[remaining_width-1-:Cfg.OptionalCfg.AChkWidth] = a_optional_i.achk;
      a_optional_o.achk = postdec[remaining_width-1-:Cfg.OptionalCfg.AChkWidth];
      remaining_width -= Cfg.OptionalCfg.AChkWidth;
    end else begin
      a_optional_o.achk = '0;
    end

    // if error is not 0, means we have some used field not assigned correctly
    // debug use only
    if (remaining_width != 0)
      error = 1'b1;
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
