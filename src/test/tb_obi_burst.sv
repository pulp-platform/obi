// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"

module tb_obi_burst;

  localparam int unsigned AddrWidth = 32;
  localparam int unsigned DataWidth = 32;
  localparam int unsigned IdWidth = 2;
  localparam int unsigned BurstLenWidth = 8;
  localparam int unsigned NumXbarSbrPorts = 2;
  localparam int unsigned NumXbarMgrPorts = 2;
  localparam int unsigned NumXbarRules = 2;
  localparam int unsigned NumXbarBursts = 1 << BurstLenWidth;
  localparam time CyclTime = 10ns;

  localparam obi_pkg::obi_cfg_t ObiCfg = '{
    UseRReady: 1'b0,
    CombGnt: 1'b0,
    AddrWidth: AddrWidth,
    DataWidth: DataWidth,
    IdWidth: IdWidth,
    Integrity: 1'b0,
    BeFull: 1'b1,
    OptionalCfg: obi_pkg::ObiMinimalOptionalConfig
  };

  `OBI_TYPEDEF_ALL_BURST(burst_obi, ObiCfg, BurstLenWidth)

  typedef struct packed {
    logic                    uses_burst;
    logic [BurstLenWidth-1:0] blen;
    logic                    bfirst;
    logic                    blast;
  } xbar_req_exp_t;

  logic clk;
  logic rst_n;
  int unsigned num_errors;
  int unsigned xbar_rsp0_exp_count;
  int unsigned xbar_rsp1_exp_count;

  initial begin
    clk = 1'b0;
    forever #(CyclTime / 2) clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  task automatic check(input logic cond, input string msg);
    if (!cond) begin
      num_errors++;
      $error("%t - %s", $time, msg);
    end
  endtask

  task automatic push_xbar_mgr_exp(input int unsigned idx, input xbar_req_exp_t exp);
    if (idx == 0) begin
      xbar_mgr0_exp.push_back(exp);
    end else begin
      xbar_mgr1_exp.push_back(exp);
    end
  endtask

  task automatic push_xbar_rsp_exp(input int unsigned idx);
    if (idx == 0) begin
      xbar_rsp0_exp_count++;
    end else begin
      xbar_rsp1_exp_count++;
    end
  endtask

  task automatic pop_xbar_mgr_exp(input int unsigned idx, output xbar_req_exp_t exp);
    exp = '0;
    if (idx == 0) begin
      check(xbar_mgr0_exp.size() != 0, "unexpected xbar target 0 request");
      if (xbar_mgr0_exp.size() != 0) begin
        exp = xbar_mgr0_exp.pop_front();
      end
    end else begin
      check(xbar_mgr1_exp.size() != 0, "unexpected xbar target 1 request");
      if (xbar_mgr1_exp.size() != 0) begin
        exp = xbar_mgr1_exp.pop_front();
      end
    end
  endtask

  task automatic pop_xbar_rsp_exp(input int unsigned idx);
    if (idx == 0) begin
      check(xbar_rsp0_exp_count != 0, "unexpected xbar source 0 response");
      if (xbar_rsp0_exp_count != 0) begin
        xbar_rsp0_exp_count--;
      end
    end else begin
      check(xbar_rsp1_exp_count != 0, "unexpected xbar source 1 response");
      if (xbar_rsp1_exp_count != 0) begin
        xbar_rsp1_exp_count--;
      end
    end
  endtask

  // Mux source locking.
  burst_obi_req_t [1:0] mux_sbr_req;
  burst_obi_rsp_t [1:0] mux_sbr_rsp;
  burst_obi_req_t       mux_mgr_req;
  burst_obi_rsp_t       mux_mgr_rsp;

  obi_mux #(
    .SbrPortObiCfg      ( ObiCfg                       ),
    .MgrPortObiCfg      ( ObiCfg                       ),
    .sbr_port_obi_req_t ( burst_obi_req_t              ),
    .sbr_port_a_chan_t  ( burst_obi_a_chan_t           ),
    .sbr_port_obi_rsp_t ( burst_obi_rsp_t              ),
    .sbr_port_r_chan_t  ( burst_obi_r_chan_t           ),
    .mgr_port_obi_req_t ( burst_obi_req_t              ),
    .mgr_port_obi_rsp_t ( burst_obi_rsp_t              ),
    .NumSbrPorts        ( 2                            ),
    .NumMaxTrans        ( 8                            ),
    .UseIdForRouting    ( 1'b0                         ),
    .BurstMode          ( obi_pkg::OBI_BURST_BEAT_FRAMED ),
    .BurstLenWidth      ( BurstLenWidth                )
  ) i_mux (
    .clk_i       ( clk          ),
    .rst_ni      ( rst_n        ),
    .testmode_i  ( 1'b0         ),
    .sbr_ports_req_i ( mux_sbr_req ),
    .sbr_ports_rsp_o ( mux_sbr_rsp ),
    .mgr_port_req_o  ( mux_mgr_req ),
    .mgr_port_rsp_i  ( mux_mgr_rsp )
  );

  task automatic drive_mux(
    input logic sbr0_req,
    input logic sbr0_first,
    input logic sbr0_last,
    input logic sbr1_req,
    input logic sbr1_first,
    input logic sbr1_last,
    input logic [IdWidth-1:0] exp_id
  );
    @(negedge clk);
    mux_sbr_req = '0;
    mux_sbr_req[0].req = sbr0_req;
    mux_sbr_req[0].a.aid = 2'd0;
    mux_sbr_req[0].a.a_optional.blen = 8'd2;
    mux_sbr_req[0].a.a_optional.bfirst = sbr0_first;
    mux_sbr_req[0].a.a_optional.blast = sbr0_last;
    mux_sbr_req[1].req = sbr1_req;
    mux_sbr_req[1].a.aid = 2'd1;
    mux_sbr_req[1].a.a_optional.blen = 8'd0;
    mux_sbr_req[1].a.a_optional.bfirst = sbr1_first;
    mux_sbr_req[1].a.a_optional.blast = sbr1_last;
    #1ns;
    check(mux_mgr_req.req, "mux manager request missing");
    check(mux_mgr_req.a.aid == exp_id, "mux did not keep the burst source locked");
    @(posedge clk);
  endtask

  // Demux target locking.
  burst_obi_req_t       demux_sbr_req;
  burst_obi_rsp_t       demux_sbr_rsp;
  burst_obi_req_t [1:0] demux_mgr_req;
  burst_obi_rsp_t [1:0] demux_mgr_rsp;
  logic demux_select;

  obi_demux #(
    .ObiCfg        ( ObiCfg                       ),
    .obi_req_t     ( burst_obi_req_t              ),
    .obi_rsp_t     ( burst_obi_rsp_t              ),
    .NumMgrPorts   ( 2                            ),
    .NumMaxTrans   ( 8                            ),
    .select_t      ( logic                        ),
    .BurstMode     ( obi_pkg::OBI_BURST_BEAT_FRAMED ),
    .BurstLenWidth ( BurstLenWidth                )
  ) i_demux (
    .clk_i       ( clk           ),
    .rst_ni      ( rst_n        ),
    .sbr_port_select_i ( demux_select  ),
    .sbr_port_req_i    ( demux_sbr_req ),
    .sbr_port_rsp_o    ( demux_sbr_rsp ),
    .mgr_ports_req_o   ( demux_mgr_req ),
    .mgr_ports_rsp_i   ( demux_mgr_rsp )
  );

  task automatic drive_demux(
    input logic select,
    input logic bfirst,
    input logic blast,
    input logic exp_mgr0,
    input logic exp_mgr1
  );
    @(negedge clk);
    demux_select = select;
    demux_sbr_req = '0;
    demux_sbr_req.req = 1'b1;
    demux_sbr_req.a.a_optional.blen = 8'd2;
    demux_sbr_req.a.a_optional.bfirst = bfirst;
    demux_sbr_req.a.a_optional.blast = blast;
    #1ns;
    check(demux_mgr_req[0].req == exp_mgr0, "demux manager 0 request mismatch");
    check(demux_mgr_req[1].req == exp_mgr1, "demux manager 1 request mismatch");
    @(posedge clk);
  endtask

  typedef struct packed {
    int unsigned idx;
    logic [AddrWidth-1:0] start_addr;
    logic [AddrWidth:0] end_addr;
  } rule_t;

  localparam rule_t [NumXbarRules-1:0] XbarAddrMap = '{
    '{idx: 32'd1, start_addr: 32'h0000_1000, end_addr: 33'h0000_2000},
    '{idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 33'h0000_1000}
  };

  burst_obi_req_t [NumXbarSbrPorts-1:0] xbar_sbr_req;
  burst_obi_rsp_t [NumXbarSbrPorts-1:0] xbar_sbr_rsp;
  burst_obi_req_t [NumXbarMgrPorts-1:0] xbar_mgr_req;
  burst_obi_rsp_t [NumXbarMgrPorts-1:0] xbar_mgr_rsp;
  logic [NumXbarMgrPorts-1:0] xbar_rsp_valid_q;
  burst_obi_r_chan_t [NumXbarMgrPorts-1:0] xbar_rsp_r_q;
  bit xbar_done [NumXbarSbrPorts];
  xbar_req_exp_t xbar_mgr0_exp[$];
  xbar_req_exp_t xbar_mgr1_exp[$];

  obi_xbar #(
    .SbrPortObiCfg      ( ObiCfg                       ),
    .MgrPortObiCfg      ( ObiCfg                       ),
    .sbr_port_obi_req_t ( burst_obi_req_t              ),
    .sbr_port_a_chan_t  ( burst_obi_a_chan_t           ),
    .sbr_port_obi_rsp_t ( burst_obi_rsp_t              ),
    .sbr_port_r_chan_t  ( burst_obi_r_chan_t           ),
    .mgr_port_obi_req_t ( burst_obi_req_t              ),
    .mgr_port_obi_rsp_t ( burst_obi_rsp_t              ),
    .NumSbrPorts        ( NumXbarSbrPorts              ),
    .NumMgrPorts        ( NumXbarMgrPorts              ),
    .NumMaxTrans        ( 8                            ),
    .NumAddrRules       ( NumXbarRules                 ),
    .addr_map_rule_t    ( rule_t                       ),
    .UseIdForRouting    ( 1'b0                         ),
    .BurstMode          ( obi_pkg::OBI_BURST_BEAT_FRAMED ),
    .BurstLenWidth      ( BurstLenWidth                )
  ) i_xbar (
    .clk_i            ( clk          ),
    .rst_ni           ( rst_n        ),
    .testmode_i       ( 1'b0         ),
    .sbr_ports_req_i  ( xbar_sbr_req ),
    .sbr_ports_rsp_o  ( xbar_sbr_rsp ),
    .mgr_ports_req_o  ( xbar_mgr_req ),
    .mgr_ports_rsp_i  ( xbar_mgr_rsp ),
    .addr_map_i       ( XbarAddrMap  ),
    .en_default_idx_i ( '0           ),
    .default_idx_i    ( '0           )
  );

  for (genvar i = 0; i < NumXbarMgrPorts; i++) begin : gen_xbar_rsp
    assign xbar_mgr_rsp[i].gnt = 1'b1;
    assign xbar_mgr_rsp[i].rvalid = xbar_rsp_valid_q[i];
    assign xbar_mgr_rsp[i].r = xbar_rsp_r_q[i];

    always_ff @(posedge clk or negedge rst_n) begin : proc_xbar_rsp
      if (!rst_n) begin
        xbar_rsp_valid_q[i] <= 1'b0;
        xbar_rsp_r_q[i] <= '0;
      end else begin
        xbar_rsp_valid_q[i] <= xbar_mgr_req[i].req;
        xbar_rsp_r_q[i] <= '0;
        xbar_rsp_r_q[i].rid <= xbar_mgr_req[i].a.aid;
        xbar_rsp_r_q[i].rdata <= 32'hb000_0000 | (32'(i) << 8) | xbar_mgr_req[i].a.aid;
        xbar_rsp_r_q[i].err <= 1'b0;
      end
    end
  end

  for (genvar i = 0; i < NumXbarMgrPorts; i++) begin : gen_xbar_mgr_check
    always_ff @(posedge clk) begin
      automatic xbar_req_exp_t exp;
      if (rst_n && xbar_mgr_req[i].req && xbar_mgr_rsp[i].gnt) begin
        pop_xbar_mgr_exp(i, exp);
        check(xbar_mgr_req[i].a.a_optional.blen === exp.blen,
              $sformatf("xbar target %0d request blen mismatch", i));
        check(xbar_mgr_req[i].a.a_optional.bfirst === exp.bfirst,
              $sformatf("xbar target %0d request bfirst mismatch", i));
        check(xbar_mgr_req[i].a.a_optional.blast === exp.blast,
              $sformatf("xbar target %0d request blast mismatch", i));
        if (!exp.uses_burst) begin
          check(xbar_mgr_req[i].a.a_optional.blen === '0,
                $sformatf("xbar target %0d non-burst blen was set", i));
          check(!xbar_mgr_req[i].a.a_optional.bfirst,
                $sformatf("xbar target %0d non-burst bfirst was set", i));
          check(!xbar_mgr_req[i].a.a_optional.blast,
                $sformatf("xbar target %0d non-burst blast was set", i));
        end
      end
    end
  end

  for (genvar i = 0; i < NumXbarSbrPorts; i++) begin : gen_xbar_rsp_check
    always_ff @(posedge clk) begin
      if (rst_n && xbar_sbr_rsp[i].rvalid) begin
        pop_xbar_rsp_exp(i);
      end
    end
  end

  task automatic send_xbar_beat(
    input int unsigned port,
    input int unsigned target,
    input logic [AddrWidth-1:0] addr,
    input logic [IdWidth-1:0] id,
    input logic [BurstLenWidth-1:0] blen,
    input logic bfirst,
    input logic blast,
    input logic uses_burst
  );
    automatic xbar_req_exp_t exp;

    @(negedge clk);
    xbar_sbr_req[port] = '0;
    xbar_sbr_req[port].req = 1'b1;
    xbar_sbr_req[port].a.addr = addr;
    xbar_sbr_req[port].a.we = 1'b0;
    xbar_sbr_req[port].a.be = '1;
    xbar_sbr_req[port].a.aid = id;
    if (uses_burst) begin
      xbar_sbr_req[port].a.a_optional.blen = blen;
      xbar_sbr_req[port].a.a_optional.bfirst = bfirst;
      xbar_sbr_req[port].a.a_optional.blast = blast;
    end
    #1ns;
    while (!xbar_sbr_rsp[port].gnt) begin
      @(posedge clk);
      #1ns;
    end
    exp = '{uses_burst: uses_burst, blen: uses_burst ? blen : '0,
            bfirst: uses_burst ? bfirst : 1'b0, blast: uses_burst ? blast : 1'b0};
    push_xbar_mgr_exp(target, exp);
    push_xbar_rsp_exp(port);
    @(posedge clk);
    @(negedge clk);
    xbar_sbr_req[port] = '0;
  endtask

  task automatic run_xbar_source(input int unsigned port);
    automatic int unsigned seed = 32'h1ace_0000 + port;
    automatic int unsigned target;
    automatic int unsigned burst_len;
    automatic logic [AddrWidth-1:0] addr;

    xbar_done[port] = 1'b0;
    wait (rst_n);
    repeat (port) @(posedge clk);

    for (int unsigned txn = 0; txn < NumXbarBursts; txn++) begin
      target = $urandom(seed) % NumXbarMgrPorts;
      burst_len = txn + 1;
      if (($urandom(seed) % 5) == 0 && burst_len > 1) begin
        addr = target ? 32'h0000_1ff0 : 32'h0000_0ff0;
      end else begin
        addr = target ? 32'h0000_1000 : 32'h0000_0000;
        addr += 32'($urandom(seed) % 32) << 2;
      end

      for (int unsigned beat = 0; beat < burst_len; beat++) begin
        send_xbar_beat(
          port,
          target,
          addr + (beat * (DataWidth / 8)),
          IdWidth'(port),
          BurstLenWidth'(burst_len - 1),
          beat == 0,
          beat == burst_len - 1,
          1'b1
        );
      end

      if (($urandom(seed) % 4) == 0 || txn[3:0] == port[3:0]) begin
        target = $urandom(seed) % NumXbarMgrPorts;
        addr = target ? 32'h0000_1000 : 32'h0000_0000;
        addr += 32'($urandom(seed) % 32) << 2;
        send_xbar_beat(
          port,
          target,
          addr,
          IdWidth'(port),
          '0,
          1'b0,
          1'b0,
          1'b0
        );
      end

      repeat ($urandom(seed) % 3) @(posedge clk);
    end
    xbar_done[port] = 1'b1;
  endtask

  initial begin
    num_errors = 0;
    mux_sbr_req = '0;
    mux_mgr_rsp = '0;
    demux_sbr_req = '0;
    demux_mgr_rsp = '0;
    xbar_sbr_req = '0;
    xbar_done[0] = 1'b0;
    xbar_done[1] = 1'b0;
    xbar_rsp0_exp_count = 0;
    xbar_rsp1_exp_count = 0;
    demux_select = 1'b0;
    mux_mgr_rsp.gnt = 1'b1;
    demux_mgr_rsp[0].gnt = 1'b1;
    demux_mgr_rsp[1].gnt = 1'b1;

    wait (rst_n);

    // Mux: lock source on first beat and release it on last beat.
    drive_mux(1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'd0);
    drive_mux(1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 2'd0);
    drive_mux(1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 2'd0);
    drive_mux(1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 2'd1);
    @(negedge clk);
    mux_sbr_req = '0;

    // Demux: lock target on first beat and release it on last beat.
    drive_demux(1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
    drive_demux(1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
    drive_demux(1'b1, 1'b0, 1'b1, 1'b1, 1'b0);
    drive_demux(1'b1, 1'b1, 1'b1, 1'b0, 1'b1);
    @(negedge clk);
    demux_sbr_req = '0;

    fork
      run_xbar_source(0);
      run_xbar_source(1);
    join
    repeat (20) @(posedge clk);
    check(xbar_mgr0_exp.size() == 0, "xbar target 0 expected requests remain");
    check(xbar_mgr1_exp.size() == 0, "xbar target 1 expected requests remain");
    check(xbar_rsp0_exp_count == 0, "xbar source 0 expected responses remain");
    check(xbar_rsp1_exp_count == 0, "xbar source 1 expected responses remain");

    repeat (5) @(posedge clk);
    if (num_errors == 0) begin
      $display("tb_obi_burst completed successfully.");
    end else begin
      $fatal(1, "tb_obi_burst failed with %0d errors.", num_errors);
    end
    $stop();
  end

endmodule
