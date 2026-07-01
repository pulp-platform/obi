// Copyright 2026 Mosaic SoC Ltd.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"
`include "obi/assign.svh"

module tb_obi_atop_filter;
  import obi_pkg::*;

  localparam int unsigned MaxTimeout  = 10000;

  localparam int unsigned AddrWidth   = 32;
  localparam int unsigned DataWidth   = 32;
  localparam int unsigned IdWidth     = 3;
  localparam int unsigned AUserWidth  = 4;
  localparam int unsigned WUserWidth  = 2;
  localparam int unsigned RUserWidth  = 3;
  localparam int unsigned MaxTrans    = 4;

  localparam time CyclTime = 10ns;
  localparam time ApplTime =  2ns;
  localparam time TestTime =  8ns;

  localparam int unsigned NumTests = 1000;

  localparam obi_pkg::obi_cfg_t SbrConfig = '{
    UseRReady:   1'b1,
    CombGnt:     1'b0,
    AddrWidth:   AddrWidth,
    DataWidth:   DataWidth,
    IdWidth:     IdWidth,
    Integrity:   1'b0,
    BeFull:      1'b1,
    OptionalCfg: '{
      UseAtop:    1'b1,
      UseMemtype: 1'b1,
      UseProt:    1'b1,
      UseDbg:     1'b1,
      AUserWidth: AUserWidth,
      WUserWidth: WUserWidth,
      RUserWidth: RUserWidth,
      MidWidth:   1,
      AChkWidth:  1,
      RChkWidth:  1
    }
  };

  // Manager Port: Inherit from Subordinate port
  localparam obi_pkg::obi_cfg_t MgrConfig = SbrConfig;

  `OBI_TYPEDEF_ALL(sbr, SbrConfig)
  `OBI_TYPEDEF_ALL(mgr, MgrConfig)

  typedef obi_test::obi_rand_manager #(
    .ObiCfg           ( SbrConfig        ),
    .obi_a_optional_t ( sbr_a_optional_t ),
    .obi_r_optional_t ( sbr_r_optional_t ),
    .TA               ( ApplTime         ),
    .TT               ( TestTime         ),
    .MinAddr          ( 32'h0000_0000    ),
    .MaxAddr          ( 32'h0001_3000    ),
    .AMinWaitCycles   ( 0                ),
    .AMaxWaitCycles   ( 5                ),
    .RMinWaitCycles   ( 0                ),
    .RMaxWaitCycles   ( 10               )
  ) rand_manager_t;

  typedef obi_test::obi_rand_subordinate #(
    .ObiCfg           ( MgrConfig        ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t ),
    .RandResp         ( 1'b1             ),
    .TA               ( ApplTime         ),
    .TT               ( TestTime         ),
    .AMinWaitCycles   ( 0                ),
    .AMaxWaitCycles   ( 5                ),
    .RMinWaitCycles   ( 0                ),
    .RMaxWaitCycles   ( 10               )
  ) rand_subordinate_t;

  logic clk, rst_n;
  logic end_of_sim;
  int unsigned num_errors = 0;
  int unsigned num_mgr_req_hs = 0;
  int unsigned num_mgr_rsp_hs = 0;
  int unsigned num_sbr_req_hs = 0;
  int unsigned num_sbr_rsp_hs = 0;

  mgr_a_chan_t mgr_req_queue[$];
  mgr_a_chan_t non_atop_req_queue[$];
  mgr_r_chan_t sbr_rsp_queue[$];

  OBI_BUS_DV #(
    .OBI_CFG          ( SbrConfig        ),
    .obi_a_optional_t ( sbr_a_optional_t ),
    .obi_r_optional_t ( sbr_r_optional_t )
  ) sbr_bus_dv (
    .clk_i  ( clk   ),
    .rst_ni ( rst_n )
  );
  OBI_BUS #(
    .OBI_CFG          ( SbrConfig        ),
    .obi_a_optional_t ( sbr_a_optional_t ),
    .obi_r_optional_t ( sbr_r_optional_t )
  ) sbr_bus ();

  OBI_BUS #(
    .OBI_CFG          ( MgrConfig        ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t )
  ) mgr_bus ();
  OBI_BUS_DV #(
    .OBI_CFG          ( MgrConfig        ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t )
  ) mgr_bus_dv (
    .clk_i  ( clk   ),
    .rst_ni ( rst_n )
  );

  rand_manager_t    obi_rand_manager;
  rand_subordinate_t obi_rand_subordinate;

  initial begin
    obi_rand_manager = new(sbr_bus_dv, "MGR");
    end_of_sim <= 1'b0;
    obi_rand_manager.reset();
  end

  initial begin
    obi_rand_subordinate = new(mgr_bus_dv, "SUB");
    obi_rand_subordinate.reset();
    obi_rand_subordinate.run();
  end

  `OBI_ASSIGN(sbr_bus, sbr_bus_dv, SbrConfig, SbrConfig)
  `OBI_ASSIGN(mgr_bus_dv, mgr_bus, MgrConfig, MgrConfig)

  clk_rst_gen #(
    .ClkPeriod    ( CyclTime ),
    .RstClkCycles ( 5        )
  ) i_clk_gen (
    .clk_o  ( clk   ),
    .rst_no ( rst_n )
  );

  obi_atop_filter_intf #(
    .SbrPortObiCfg ( SbrConfig ),
    .MgrPortObiCfg ( MgrConfig ),
    .MaxTrans      ( MaxTrans  )
  ) i_atop_filter (
    .clk_i      ( clk     ),
    .rst_ni     ( rst_n   ),
    .testmode_i ( '0      ),
    .sbr_port   ( sbr_bus ),
    .mgr_port   ( mgr_bus )
  );

  /*====================================================================
  =                                Main                                =
  ====================================================================*/

  initial begin
    wait (rst_n);
    @(posedge clk);

    obi_rand_manager.run(NumTests);

    end_of_sim <= 1'b1;
  end

  initial begin
    wait (rst_n);
    forever begin
      @(posedge clk);
      if (mgr_bus.req & mgr_bus.gnt) num_mgr_req_hs++;
      if (mgr_bus.rvalid & mgr_bus.rready) num_mgr_rsp_hs++;
      if (sbr_bus.req & sbr_bus.gnt) num_sbr_req_hs++;
      if (sbr_bus.rvalid & sbr_bus.rready) num_sbr_rsp_hs++;
    end
  end

  /*====================================================================
  =                              Checker                               =
  ====================================================================*/

  initial begin
    wait (rst_n);
    forever begin
      @(posedge clk);

      // sbr_bus req hs: capture all requests from the upstream manager
      if (sbr_bus.req && sbr_bus.gnt) begin : push_mgr_req
        automatic mgr_a_chan_t req;
        req.addr       = sbr_bus.addr;
        req.we         = sbr_bus.we;
        req.be         = sbr_bus.be;
        req.wdata      = sbr_bus.wdata;
        req.aid        = sbr_bus.aid;
        req.a_optional = sbr_bus.a_optional;
        mgr_req_queue.push_back(req);
        if (req.a_optional.atop == '0) begin
          non_atop_req_queue.push_back(req);
        end
      end

      // mgr_bus rsp: push downstream subordinate response for later sbr_bus check
      if (mgr_bus.rvalid && mgr_bus.rready) begin : push_sbr_rsp
        automatic mgr_r_chan_t rsp;
        rsp.rdata      = mgr_bus.rdata;
        rsp.rid        = mgr_bus.rid;
        rsp.err        = mgr_bus.err;
        rsp.r_optional = mgr_bus.r_optional;
        sbr_rsp_queue.push_back(rsp);
      end

      // mgr_bus req hs: verify filter correctly forwards non-ATOP request
      if (mgr_bus.req && mgr_bus.gnt) begin : check_fwd_req
        automatic mgr_a_chan_t ref_req;
        if (non_atop_req_queue.size() == 0) begin
          $error("[t=%0t] mgr_bus req handshake but non_atop_req_queue is empty!", $time);
          num_errors++;
        end else begin
          ref_req = non_atop_req_queue.pop_front();
          if (!(ref_req.addr       ==? mgr_bus.addr      ) ||
              !(ref_req.we         ==? mgr_bus.we        ) ||
              !(ref_req.be         ==? mgr_bus.be        ) ||
              !(ref_req.wdata      ==? mgr_bus.wdata     ) ||
              !(ref_req.aid        ==? mgr_bus.aid       ) ||
              !(ref_req.a_optional ==? mgr_bus.a_optional)) begin
            $error("[t=%0t] Forwarded request mismatch on mgr_bus!", $time);
            num_errors++;
          end
        end
      end

      // sbr_bus rsp: verify response sent back to the upstream manager
      if (sbr_bus.rvalid & sbr_bus.rready) begin : check_mgr_rsp
        if (mgr_req_queue.size() == 0) begin
          $error("[t=%0t] mgr_req_queue empty on sbr_bus rsp!", $time);
          num_errors++;
        end else begin
          automatic mgr_a_chan_t req;
          req = mgr_req_queue.pop_front();
          if (req.aid !== sbr_bus.rid) begin
            $error("[t=%0t] ID mismatch on rsp: aid=%0d rid=%0d",
                   $time, req.aid, sbr_bus.rid);
            num_errors++;
          end
          if (req.a_optional.atop != '0) begin
            // ATOP was blocked; filter generated error response
            if (sbr_bus.err !== 1'b1) begin
              $error("[t=%0t] Expected err=1 on ATOP error rsp!", $time);
              num_errors++;
            end
          end else begin
            // Non-ATOP forwarded path: compare against captured downstream response
            automatic mgr_r_chan_t fwd_rsp;
            if (sbr_rsp_queue.size() == 0) begin
              $error("[t=%0t] sbr_rsp_queue empty on non-atomic rsp!", $time);
              num_errors++;
            end else begin
              fwd_rsp = sbr_rsp_queue.pop_front();
              if (!(fwd_rsp.rdata      ==? sbr_bus.rdata     ) ||
                  !(fwd_rsp.rid        ==? sbr_bus.rid       ) ||
                  !(fwd_rsp.err        ==? sbr_bus.err       ) ||
                  !(fwd_rsp.r_optional ==? sbr_bus.r_optional)) begin
                $error("[t=%0t] Forwarded response mismatch on sbr_bus!", $time);
                num_errors++;
              end
            end
          end
        end
      end
    end
  end

  /*====================================================================
  =                               Timeout                              =
  ====================================================================*/

  initial begin
    automatic int unsigned timeout   = 0;
    automatic logic [1:0]  handshake = 2'b00;

    @(posedge clk);
    wait (rst_n);

    fork
      while (timeout < MaxTimeout) begin
        handshake = {mgr_bus.req, mgr_bus.gnt};
        @(posedge clk);
        if (handshake != {mgr_bus.req, mgr_bus.gnt}) begin
          timeout = 0;
        end else begin
          timeout += 1;
        end
      end
      wait (end_of_sim);
    join_any

    if (end_of_sim && num_errors == 0) begin
      $display("SUCCESS");
    end else if (end_of_sim) begin
      if (num_errors > 0) begin
        $fatal(1, "Encountered %d errors.", num_errors);
      end else begin
        $display("All tests passed.");
      end
    end else begin
      $fatal(1, "TIMEOUT");
    end

    $stop;
  end

endmodule
