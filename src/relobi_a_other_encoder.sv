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
  localparam int unsigned OptWidth = AOtherWidth - EssentialWidth;

  logic [AOtherWidth-1:0] unused;
  logic [AOtherWidth-1:0] a_opt_used;

  logic error;
  logic [31:0] remaining_width;
  always_comb begin : used_opt_comb
    // Determine which field needs to be protected
    // If a field is not used, we don't need to add ECC to it
    a_opt_used = '0;
    a_opt_used[AOtherWidth-1-:EssentialWidth] = {we_i, be_i, aid_i};
    error = 1'b0;

    remaining_width = AOtherWidth - EssentialWidth;

    if (Cfg.OptionalCfg.UseAtop) begin
      a_opt_used[remaining_width-1-:6] = a_optional_i.atop;
      remaining_width -= 6;
    end

    if (Cfg.OptionalCfg.UseMemtype) begin
      a_opt_used[remaining_width-1-:2] = a_optional_i.memtype;
      remaining_width -= 2;
    end

    if (Cfg.OptionalCfg.UseProt) begin
      a_opt_used[remaining_width-1-:3] = a_optional_i.prot;
      remaining_width -= 3;
    end

    if (Cfg.OptionalCfg.UseDbg) begin
      a_opt_used[remaining_width-1-:1] = a_optional_i.dbg;
      remaining_width -= 1;
    end

    if (Cfg.OptionalCfg.AUserWidth > 0) begin
      a_opt_used[remaining_width-1-:Cfg.OptionalCfg.AUserWidth] = a_optional_i.auser;
      remaining_width -= Cfg.OptionalCfg.AUserWidth;
    end

    if (Cfg.OptionalCfg.WUserWidth > 0) begin
      a_opt_used[remaining_width-1-:Cfg.OptionalCfg.WUserWidth] = a_optional_i.wuser;
      remaining_width -= Cfg.OptionalCfg.WUserWidth;
    end

    if (Cfg.OptionalCfg.MidWidth > 0) begin
      a_opt_used[remaining_width-1-:Cfg.OptionalCfg.MidWidth] = a_optional_i.mid;
      remaining_width -= Cfg.OptionalCfg.MidWidth;
    end

    if (Cfg.OptionalCfg.AChkWidth > 0) begin
      a_opt_used[remaining_width-1-:Cfg.OptionalCfg.AChkWidth] = a_optional_i.achk;
      remaining_width -= Cfg.OptionalCfg.AChkWidth;
    end

    // if error is not 0, means we have some used field not assigned correctly
    // debug use only
    if (remaining_width != 0)
      error = 1'b1;
  end

  hsiao_ecc_enc #(
    .DataWidth (AOtherWidth)
  ) i_a_remaining_enc (
    .in        ( a_opt_used ),
    .out       ( {other_ecc_o, unused} )
  );

endmodule
