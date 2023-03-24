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

module obi_mux #(
  parameter obi_pkg::obi_cfg_t SlvPortObiCfg      = obi_pkg::ObiDefaultConfig,
  parameter obi_pkg::obi_cfg_t MstPortObiCfg      = SlvPortObiCfg,
  parameter type               slv_port_obi_req_t = logic,
  parameter type               slv_port_a_chan_t  = logic,
  parameter type               slv_port_obi_rsp_t = logic,
  parameter type               mst_port_obi_req_t = slv_port_obi_req_t,
  parameter type               mst_port_obi_rsp_t = slv_port_obi_rsp_t,
  parameter int unsigned       NumSlvPorts        = 32'd0,
  parameter int unsigned       NumMaxTrans        = 32'd0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  input  slv_port_obi_req_t [NumSlvPorts-1:0] slv_ports_obi_req_i,
  output slv_port_obi_rsp_t [NumSlvPorts-1:0] slv_ports_obi_rsp_o,

  output mst_port_obi_req_t                   mst_port_obi_req_o,
  input  mst_port_obi_rsp_t                   mst_port_obi_rsp_i
);
  if (NumSlvPorts <= 1) begin
    $fatal(1, "unimplemented");
  end

  localparam RequiredExtraIdWidth = $clog2(NumSlvPorts);

  logic [NumSlvPorts-1:0] slv_ports_req, slv_ports_gnt;
  slv_port_a_chan_t [NumSlvPorts-1:0] slv_ports_a;
  for (genvar i = 0; i < NumSlvPorts; i++) begin
    assign slv_ports_req[i] = slv_ports_obi_req_i[i].req;
    assign slv_ports_a[i] = slv_ports_obi_req_i[i].a;
    assign slv_ports_obi_rsp_o[i].gnt = slv_ports_gnt[i];
  end

  slv_port_a_chan_t mst_port_a_in_slv;
  logic [RequiredExtraIdWidth-1:0] selected_id, response_id;
  logic mst_port_req, fifo_full, fifo_pop;

  rr_arb_tree #(
    .NumIn     ( NumSlvPorts ),
    .DataType  ( slv_port_a_chan_t ),
    .AxiVldRdy ( 1'b1 ),
    .LockIn    ( 1'b1 )
  ) i_rr_arb (
    .clk_i,
    .rst_ni,

    .flush_i ( 1'b0 ),
    .rr_i    ( '0 ),

    .req_i   ( slv_ports_req ),
    .gnt_o   ( slv_ports_gnt ),
    .data_i  ( slv_ports_a   ),

    .req_o   ( mst_port_req ),
    .gnt_i   ( mst_port_obi_rsp_i.gnt && ~fifo_full ),
    .data_o  ( mst_port_a_in_slv ),

    .idx_o   ( selected_id )
  );

  assign mst_port_obi_req_o.req = mst_port_req && ~fifo_full;

  if (MstPortObiCfg.IdWidth > 0 && (MstPortObiCfg.IdWidth >= SlvPortObiCfg.IdWidth + RequiredExtraIdWidth)) begin
    $fatal(1, "unimplemented");

    // assign mst_port_obi_req_o.a.addr = mst_port_a_in_slv.addr;
    // assign mst_port_obi_req_o.a.we = mst_port_a_in_slv.we;
    // assign mst_port_obi_req_o.a.be = mst_port_a_in_slv.be;
    // assign mst_port_obi_req_o.a.wdata = mst_port_a_in_slv.wdata;
    // if (MstPortObiCfg.AUserWidth) begin
    //   assign mst_port_obi_req_o.a.optional.auser = mst_port_a_in_slv.optional.auser;
    // end
    // if (MstPortObiCfg.WUserWidth) begin
    //   assign mst_port_obi_req_o.a.optional.wuser = mst_port_a_in_slv.optional.wuser;
    // end

    // assign mst_port_obi_req_o.a.optional = 
  end else begin
    assign mst_port_obi_req_o.a = mst_port_a_in_slv;
  end

  fifo_v3 #(
    .FALL_THROUGH( 1'b0                 ),
    .DATA_WIDTH  ( RequiredExtraIdWidth ),
    .DEPTH       ( NumMaxTrans          )
  ) i_fifo (
    .clk_i,
    .rst_ni,
    .flush_i   ('0),
    .testmode_i,

    .full_o    ( fifo_full                                        ),
    .empty_o   (),
    .usage_o   (),
    .data_i    ( selected_id                                      ),
    .push_i    ( mst_port_obi_req_o.req && mst_port_obi_rsp_i.gnt ),

    .data_o    ( response_id                                      ),
    .pop_i     ( fifo_pop                                         )
  );

  if (ObiCfg.UseRReady) begin
    assign mst_port_obi_req_o.rready = slv_port_obi_req_i[response_id].rready;
  end
  always_comb begin
    for (genvar i = 0; i < NumMstPorts; i++) begin
      slv_ports_obi_rsp_o[i].r = '0;
      slv_ports_obi_rsp_o[i].rvalid = '0;
    end
    slv_ports_obi_rsp_o[response_id].r = mst_port_obi_rsp_i.r;
    slv_ports_obi_rsp_o[response_id].rvalid = mst_port_obi_rsp_i.rvalid;
  end

  if (ObiCfg.UseRReady) begin
    assign fifo_pop = mst_port_obi_rsp_i.rvalid && mst_port_obi_req_o.rready;
  end else begin
    assign fifo_pop = mst_port_obi_rsp_i.rvalid;
  end

endmodule
