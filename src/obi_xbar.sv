// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

/// An OBI crossbar interconnect.
module obi_xbar #(
  /// The OBI configuration for the subordinate ports (input ports).
  parameter obi_pkg::obi_cfg_t SbrPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The OBI configuration for the manager ports (ouput ports).
  parameter obi_pkg::obi_cfg_t MgrPortObiCfg      = SbrPortObiCfg,
  /// The request struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_req_t = logic,
  /// The A channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_a_chan_t  = logic,
  /// The response struct for the subordinate ports (input ports).
  parameter type               sbr_port_obi_rsp_t = logic,
  /// The R channel struct for the subordinate ports (input ports).
  parameter type               sbr_port_r_chan_t  = logic,
  /// The request struct for the manager ports (output ports).
  parameter type               mgr_port_obi_req_t = sbr_port_obi_req_t,
  /// The response struct for the manager ports (output ports).
  parameter type               mgr_port_obi_rsp_t = sbr_port_obi_rsp_t,
  /// The number of subordinate ports (input ports).
  parameter int unsigned       NumSbrPorts        = 32'd0,
  /// The number of manager ports (output ports).
  parameter int unsigned       NumMgrPorts        = 32'd0,
  /// The maximum number of outstanding transactions.
  parameter int unsigned       NumMaxTrans        = 32'd0,
  /// The number of address rules.
  parameter int unsigned       NumAddrRules       = 32'd0,
  /// The address map rule type.
  parameter type               addr_map_rule_t    = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  input  sbr_port_obi_req_t [NumSbrPorts-1:0] sbr_ports_obi_req_i,
  output sbr_port_obi_rsp_t [NumSbrPorts-1:0] sbr_ports_obi_rsp_o,

  output mgr_port_obi_req_t [NumMgrPorts-1:0] mgr_ports_obi_req_o,
  input  mgr_port_obi_rsp_t [NumMgrPorts-1:0] mgr_ports_obi_rsp_i,

  input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
  input  logic [NumSbrPorts-1:0]              en_default_idx_i,
  input  logic [NumSbrPorts-1:0][$clog2(NumMgrPorts)-1:0] default_idx_i
);

  logic [NumSbrPorts-1:0][$clog2(NumMgrPorts)-1:0] sbr_port_select;

  // Signals from the demuxes
  sbr_port_obi_req_t [NumSbrPorts-1:0][NumMgrPorts-1:0] sbr_reqs;
  sbr_port_obi_rsp_t [NumSbrPorts-1:0][NumMgrPorts-1:0] sbr_rsps;

  // Signals to the muxes
  sbr_port_obi_req_t [NumMgrPorts-1:0][NumSbrPorts-1:0] mgr_reqs;
  sbr_port_obi_rsp_t [NumMgrPorts-1:0][NumSbrPorts-1:0] mgr_rsps;

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_demux
    addr_decode #(
      .NoIndices ( NumMgrPorts                         ),
      .NoRules   ( NumAddrRules                        ),
      .addr_t    ( logic [MgrPortObiCfg.AddrWidth-1:0] ),
      .rule_t    ( addr_map_rule_t                     )
    ) i_addr_decode (
      .addr_i          ( sbr_ports_obi_req_i[i].a.addr ),
      .addr_map_i      ( addr_map_i                  ),
      .idx_o           ( sbr_port_select[i]          ),
      .dec_valid_o     (),
      .dec_error_o     (),
      .en_default_idx_i( en_default_idx_i[i]         ),
      .default_idx_i   ( default_idx_i[i]            )
    );

    obi_demux #(
      .ObiCfg      ( SbrPortObiCfg      ),
      .obi_req_t   ( sbr_port_obi_req_t ),
      .obi_rsp_t   ( sbr_port_obi_rsp_t ),
      .NumMgrPorts ( NumMgrPorts        ),
      .NumMaxTrans ( NumMaxTrans        )
    ) i_demux (
      .clk_i,
      .rst_ni,
      .sbr_port_select_i ( sbr_port_select[i]     ),
      .sbr_port_req_i    ( sbr_ports_obi_req_i[i] ),
      .sbr_port_rsp_o    ( sbr_ports_obi_rsp_o[i] ),
      .mgr_ports_req_o   ( sbr_reqs[i]            ),
      .mgr_ports_rsp_i   ( sbr_rsps[i]            )
    );
  end

  for (genvar i = 0; i < NumSbrPorts; i++) begin : gen_interco_sbr
    for (genvar j = 0; j < NumMgrPorts; j++) begin : gen_interco_mgr
      assign mgr_reqs[j][i] = sbr_reqs[i][j];
      assign sbr_rsps[i][j] = mgr_rsps[j][i];
    end
  end

  for (genvar i = 0; i < NumMgrPorts; i++) begin : gen_mux
    obi_mux #(
      .SbrPortObiCfg      ( SbrPortObiCfg      ),
      .MgrPortObiCfg      ( MgrPortObiCfg      ),
      .sbr_port_obi_req_t ( sbr_port_obi_req_t ),
      .sbr_port_a_chan_t  ( sbr_port_a_chan_t  ),
      .sbr_port_obi_rsp_t ( sbr_port_obi_rsp_t ),
      .sbr_port_r_chan_t  ( sbr_port_r_chan_t  ),
      .mgr_port_obi_req_t ( mgr_port_obi_req_t ),
      .mgr_port_obi_rsp_t ( mgr_port_obi_rsp_t ),
      .NumSbrPorts        ( NumSbrPorts        ),
      .NumMaxTrans        ( NumMaxTrans        )
    ) i_mux (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .sbr_ports_obi_req_i ( mgr_reqs[i]            ),
      .sbr_ports_obi_rsp_o ( mgr_rsps[i]            ),
      .mgr_port_obi_req_o  ( mgr_ports_obi_req_o[i] ),
      .mgr_port_obi_rsp_i  ( mgr_ports_obi_rsp_i[i] )
    );
  end

endmodule
