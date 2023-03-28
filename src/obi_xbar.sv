// Copyright 2023 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

/// An OBI crossbar interconnect.
module obi_xbar #(
  /// The OBI configuration for the slave ports (input ports).
  parameter obi_pkg::obi_cfg_t SlvPortObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The OBI configuration for the master ports (ouput ports).
  parameter obi_pkg::obi_cfg_t MstPortObiCfg      = SlvPortObiCfg,
  /// The request struct for the slave ports (input ports).
  parameter type               slv_port_obi_req_t = logic,
  /// The A channel struct for the slave ports (input ports).
  parameter type               slv_port_a_chan_t  = logic,
  /// The response struct for the slave ports (input ports).
  parameter type               slv_port_obi_rsp_t = logic,
  /// The R channel struct for the slave ports (input ports).
  parameter type               slv_port_r_chan_t  = logic,
  /// The request struct for the master ports (output ports).
  parameter type               mst_port_obi_req_t = slv_port_obi_req_t,
  /// The response struct for the master ports (output ports).
  parameter type               mst_port_obi_rsp_t = slv_port_obi_rsp_t,
  /// The number of slave ports (input ports).
  parameter int unsigned       NumSlvPorts        = 32'd0,
  /// The number of master ports (output ports).
  parameter int unsigned       NumMstPorts        = 32'd0,
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

  input  slv_port_obi_req_t [NumSlvPorts-1:0] slv_ports_obi_req_i,
  output slv_port_obi_rsp_t [NumSlvPorts-1:0] slv_ports_obi_rsp_o,

  output mst_port_obi_req_t [NumMstPorts-1:0] mst_ports_obi_req_o,
  input  mst_port_obi_rsp_t [NumMstPorts-1:0] mst_ports_obi_rsp_i,

  input  addr_map_rule_t [NumAddrRules-1:0]   addr_map_i,
  input  logic [NumSlvPorts-1:0]              en_default_idx_i,
  input  logic [NumSlvPorts-1:0][$clog2(NumMstPorts)-1:0] default_idx_i
);

  logic [NumSlvPorts-1:0][$clog2(NumMstPorts)-1:0] slv_port_select;

  // Signals from the demuxes
  slv_port_obi_req_t [NumSlvPorts-1:0][NumMstPorts-1:0] slv_reqs;
  slv_port_obi_rsp_t [NumSlvPorts-1:0][NumMstPorts-1:0] slv_rsps;

  // Signals to the muxes
  slv_port_obi_req_t [NumMstPorts-1:0][NumSlvPorts-1:0] mst_reqs;
  slv_port_obi_rsp_t [NumMstPorts-1:0][NumSlvPorts-1:0] mst_rsps;

  for (genvar i = 0; i < NumSlvPorts; i++) begin : gen_demux
    addr_decode #(
      .NoIndices ( NumMstPorts                         ),
      .NoRules   ( NumAddrRules                        ),
      .addr_t    ( logic [MstPortObiCfg.AddrWidth-1:0] ),
      .rule_t    ( addr_map_rule_t                     )
    ) i_addr_decode (
      .addr_i          ( slv_ports_obi_req_i[i].a.addr ),
      .addr_map_i      ( addr_map_i                  ),
      .idx_o           ( slv_port_select[i]          ),
      .dec_valid_o     (),
      .dec_error_o     (),
      .en_default_idx_i( en_default_idx_i[i]         ),
      .default_idx_i   ( default_idx_i[i]            )
    );

    obi_demux #(
      .ObiCfg      ( SlvPortObiCfg      ),
      .obi_req_t   ( slv_port_obi_req_t ),
      .obi_rsp_t   ( slv_port_obi_rsp_t ),
      .NumMstPorts ( NumMstPorts        ),
      .NumMaxTrans ( NumMaxTrans        )
    ) i_demux (
      .clk_i,
      .rst_ni,
      .slv_port_select_i ( slv_port_select[i]     ),
      .slv_port_req_i    ( slv_ports_obi_req_i[i] ),
      .slv_port_rsp_o    ( slv_ports_obi_rsp_o[i] ),
      .mst_ports_req_o   ( slv_reqs[i]            ),
      .mst_ports_rsp_i   ( slv_rsps[i]            )
    );
  end

  for (genvar i = 0; i < NumSlvPorts; i++) begin : gen_interco_slv
    for (genvar j = 0; j < NumMstPorts; j++) begin : gen_interco_mst
      assign mst_reqs[j][i] = slv_reqs[i][j];
      assign slv_rsps[i][j] = mst_rsps[j][i];
    end
  end

  for (genvar i = 0; i < NumMstPorts; i++) begin : gen_mux
    obi_mux #(
      .SlvPortObiCfg      ( SlvPortObiCfg      ),
      .MstPortObiCfg      ( MstPortObiCfg      ),
      .slv_port_obi_req_t ( slv_port_obi_req_t ),
      .slv_port_a_chan_t  ( slv_port_a_chan_t  ),
      .slv_port_obi_rsp_t ( slv_port_obi_rsp_t ),
      .slv_port_r_chan_t  ( slv_port_r_chan_t  ),
      .mst_port_obi_req_t ( mst_port_obi_req_t ),
      .mst_port_obi_rsp_t ( mst_port_obi_rsp_t ),
      .NumSlvPorts        ( NumSlvPorts        ),
      .NumMaxTrans        ( NumMaxTrans        )
    ) i_mux (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .slv_ports_obi_req_i ( mst_reqs[i]            ),
      .slv_ports_obi_rsp_o ( mst_rsps[i]            ),
      .mst_port_obi_req_o  ( mst_ports_obi_req_o[i] ),
      .mst_port_obi_rsp_i  ( mst_ports_obi_rsp_i[i] )
    );
  end

endmodule
