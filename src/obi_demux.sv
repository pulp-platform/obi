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

module obi_demux #(
  parameter obi_pkg::obi_cfg_t ObiCfg      = obi_pkg::ObiDefaultConfig,
  parameter type               obi_req_t   = logic,
  parameter type               obi_rsp_t   = logic,
  parameter int unsigned       NumMstPorts = 32'd0,
  parameter int unsigned       NumMaxTrans = 32'd0,
  parameter type               select_t    = logic [$clog2(NumMstPorts)-1:0]
) (
  input  logic                       clk_i,
  input  logic                       rst_ni,

  input  select_t                    slv_port_select_i,
  input  obi_req_t                   slv_port_req_i,
  output obi_rsp_t                   slv_port_rsp_o,

  output obi_req_t [NumMstPorts-1:0] mst_ports_req_o,
  input  obi_rsp_t [NumMstPorts-1:0] mst_ports_rsp_i
);

  if (ObiCfg.Integrity) begin
    $fatal(1, "unimplemented");
  end

  // stall requests to ensure in-order behavior (could be handled differently with rready)
  localparam CounterWidth = cf_math_pkg::idx_width(NumMaxTrans);

  logic cnt_up, cnt_down, overflow;
  logic [CounterWidth-1:0] in_flight;
  logic slv_port_rready;

  select_t select_d, select_q;

  always_comb begin
    select_d = select_q;
    cnt_up = 1'b0;
    for (int i = 0; i < NumMstPorts; i++) begin
      mst_ports_req_o[i].req = 1'b0;
      mst_ports_req_o[i].a   = '0;
    end

    if (!overflow) begin
      if (slv_port_select_i == select_q || in_flight == '0 || (in_flight == 1 && cnt_down)) begin
        mst_ports_req_o[slv_port_select_i].req = slv_port_req_i.req;
        mst_ports_req_o[slv_port_select_i].a = slv_port_req_i.a;
      end
    end

    if (mst_ports_req_o[slv_port_select_i].req && mst_ports_rsp_i[slv_port_select_i].gnt) begin
      select_d = slv_port_select_i;
      cnt_up = 1'b1;
    end
  end

  assign slv_port_rsp_o.gnt    = mst_ports_rsp_i[slv_port_select_i].gnt;
  assign slv_port_rsp_o.r      = mst_ports_rsp_i[select_q].r;
  assign slv_port_rsp_o.rvalid = mst_ports_rsp_i[select_q].rvalid;

  if (ObiCfg.UseRReady) begin
    assign slv_port_rready = slv_port_req_i.rready;
    for (genvar i = 0; i < NumMstPorts; i++) begin
      assign mst_ports_req_o[i].rready = slv_port_req_i.rready;
    end
  end else begin
    assign slv_port_rready = 1'b1;
  end

  assign cnt_down = mst_ports_rsp_i[select_q].rvalid && slv_port_rready;

  delta_counter #(
    .WIDTH           ( CounterWidth ),
    .STICKY_OVERFLOW ( 1'b0         )
  ) i_counter (
    .clk_i,
    .rst_ni,

    .clear_i   ( 1'b0      ),
    .en_i      ( cnt_up ^ cnt_down ),
    .load_i    ( 1'b0      ),
    .down_i    ( cnt_down ),
    .delta_i   ( {{CounterWidth-1{1'b0}}, 1'b1} ),
    .d_i       ( '0        ),
    .q_o       ( in_flight ),
    .overflow_o( overflow  )
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_select
    if(!rst_ni) begin
      select_q <= '0;
    end else begin
      select_q <= select_d;
    end
  end

endmodule
