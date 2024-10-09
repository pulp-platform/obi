// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Diyou Shen <dishen@iis.ee.ethz.ch>

`include "obi/typedef.svh"
`include "obi/assign.svh"

/// demux wrapper for relOBI
module relobi_test_intf #(
  /// The OBI configuration for the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The OBI configuration for the manager ports (ouput ports).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The number of subordinate ports (input ports).
  // // only support one since we do not have MUX yet
  // parameter int unsigned       NumSbrPorts        = 32'd1,
  /// The number of manager ports (output ports).
  parameter int unsigned       NumMgrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// The number of address rules.
  parameter int unsigned       NumAddrRules       = 32'd0,
  /// The address map rule type.
  parameter type               addr_map_rule_t    = logic,
  /// If addr select is protected by TMR (not implemented)
  parameter bit                TmrSelect          = 1'b0
) (
  input logic         clk_i,
  input logic         rst_ni,
  input logic         testmode_i,

  OBI_BUS.Subordinate sbr_ports,

  OBI_BUS.Manager     mgr_ports [NumMgrPorts],

  input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
  input  logic                                en_default_idx_i,
  input  logic [$clog2(NumMgrPorts)-1:0]      default_idx_i
);
  //////////////////////
  /// Signal Defines ///
  //////////////////////
  `OBI_TYPEDEF_ALL(sbr_port_obi, SbrPortObiCfg)
  `OBI_TYPEDEF_ALL(mgr_port_obi, MgrPortObiCfg)

  `RELOBI_TYPEDEF_ALL(mgr_relobi, MgrPortObiCfg)
  `RELOBI_TYPEDEF_ALL(sbr_relobi, SbrPortObiCfg)

  sbr_port_obi_req_t sbr_ports_req;
  sbr_port_obi_rsp_t sbr_ports_rsp;

  mgr_port_obi_req_t [NumMgrPorts-1:0] mgr_ports_req;
  mgr_port_obi_rsp_t [NumMgrPorts-1:0] mgr_ports_rsp;

  sbr_relobi_req_t sbr_relobi_req;
  sbr_relobi_rsp_t sbr_relobi_rsp;

  mgr_relobi_req_t [NumMgrPorts-1:0] mgr_relobi_req;
  mgr_relobi_rsp_t [NumMgrPorts-1:0] mgr_relobi_rsp;

  logic [$clog2(NumMgrPorts)-1:0] sbr_port_select;

  //////////////////////////
  /// Singal Assignments ///
  //////////////////////////
  `OBI_ASSIGN_TO_REQ(sbr_ports_req, sbr_ports, SbrPortObiCfg)
  `OBI_ASSIGN_FROM_RSP(sbr_ports, sbr_ports_rsp, SbrPortObiCfg)

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mgr_ports_assign
    `OBI_ASSIGN_FROM_REQ(mgr_ports[i], mgr_ports_req[i], MgrPortObiCfg)
    `OBI_ASSIGN_TO_RSP(mgr_ports_rsp[i], mgr_ports[i], MgrPortObiCfg)
  end

  ///////////////////
  /// Main Blocks ///
  ///////////////////

  // TODO: Change to TMR protected address decoder
  addr_decode #(
    .NoIndices ( NumMgrPorts                         ),
    .NoRules   ( NumAddrRules                        ),
    .addr_t    ( logic [MgrPortObiCfg.AddrWidth-1:0] ),
    .rule_t    ( addr_map_rule_t                     )
  ) i_addr_decode (
    .addr_i          ( sbr_ports_req.a.addr ),
    .addr_map_i      ( addr_map_i             ),
    .idx_o           ( sbr_port_select        ),
    .dec_valid_o     (),
    .dec_error_o     (),
    .en_default_idx_i( en_default_idx_i       ),
    .default_idx_i   ( default_idx_i          )
  );

  // Encode to ECC protected signals (relOBI)
  relobi_encoder #(
    .Cfg          ( SbrPortObiCfg           ),
    .obi_req_t    ( sbr_port_obi_req_t      ),
    .obi_rsp_t    ( sbr_port_obi_rsp_t      ),
    .relobi_req_t ( sbr_relobi_req_t        ),
    .relobi_rsp_t ( sbr_relobi_rsp_t        ),
    .a_optional_t ( sbr_relobi_a_optional_t ),
    .r_optional_t ( sbr_relobi_r_optional_t )
  ) i_encoder (
    .req_i        ( sbr_ports_req           ),
    .rsp_o        ( sbr_ports_rsp           ),

    .rel_req_o    ( sbr_relobi_req          ),
    .rel_rsp_i    ( sbr_relobi_rsp          )
  );

  relobi_demux #(
    .ObiCfg       ( SbrPortObiCfg           ),
    .obi_req_t    ( sbr_relobi_req_t        ),
    .obi_rsp_t    ( sbr_relobi_rsp_t        ),
    .obi_r_chan_t ( sbr_relobi_r_chan_t     ),
    .NumMgrPorts  ( NumMgrPorts             ),
    .NumMaxTrans  ( NumMaxTrans             ),
    .TmrSelect    ( TmrSelect               )
  ) i_demux (
    .clk_i              ( clk_i             ),
    .rst_ni             ( rst_ni            ),

    .sbr_port_select_i  ( sbr_port_select   ),
    .sbr_port_req_i     ( sbr_relobi_req    ),
    .sbr_port_rsp_o     ( sbr_relobi_rsp    ),

    .mgr_ports_req_o    ( mgr_relobi_req    ),
    .mgr_ports_rsp_i    ( mgr_relobi_rsp    )
  );

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_relobi_decoder
    relobi_decoder #(
      .Cfg          ( MgrPortObiCfg           ),
      .relobi_req_t ( mgr_relobi_req_t        ),
      .relobi_rsp_t ( mgr_relobi_rsp_t        ),
      .obi_req_t    ( mgr_port_obi_req_t      ),
      .obi_rsp_t    ( mgr_port_obi_rsp_t      ),
      .a_optional_t ( mgr_relobi_a_optional_t ),
      .r_optional_t ( mgr_relobi_r_optional_t )
    ) i_decoder (
      .rel_req_i    ( mgr_relobi_req[i]       ),
      .rel_rsp_o    ( mgr_relobi_rsp[i]       ),

      .req_o        ( mgr_ports_req[i]        ),
      .rsp_i        ( mgr_ports_rsp[i]        )
    );
  end

  //////////////////
  /// Assertions ///
  //////////////////


endmodule
