// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Samuel Riedel <sriedel@iis.ee.ethz.ch>
// Author: Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "obi/typedef.svh"
`include "obi/assign.svh"

module tb_obi_atop_resolver;
  import obi_pkg::*;

  localparam int unsigned NumManagers = 32'd2;
  localparam int unsigned NumMaxTrans = 32'd8;
  localparam int unsigned AddrWidth = 32;
  localparam int unsigned DataWidth = 32;
  localparam int unsigned MgrIdWidth = 5;
  localparam int unsigned SbrIdWidth = MgrIdWidth+$clog2(NumManagers);
  localparam int unsigned AUserWidth = 4;
  localparam int unsigned WUserWidth = 2;
  localparam int unsigned RUserWidth = 3;

  localparam time CyclTime = 10ns;
  localparam time ApplTime =  2ns;
  localparam time TestTime =  8ns;

  localparam obi_pkg::obi_cfg_t MgrConfig = '{
    UseRReady:      1'b0,
    CombGnt:        1'b0,
    AddrWidth: AddrWidth,
    DataWidth: DataWidth,
    IdWidth:  MgrIdWidth,
    Integrity:      1'b0,
    BeFull:         1'b1,
    OptionalCfg: '{
      UseAtop:          1'b1,
      UseMemtype:       1'b0,
      UseProt:          1'b0,
      UseDbg:           1'b0,
      AUserWidth: AUserWidth,
      WUserWidth: WUserWidth,
      RUserWidth: RUserWidth,
      MidWidth:            0,
      AChkWidth:           0,
      RChkWidth:           0
    }
  };
  `OBI_TYPEDEF_ALL_A_OPTIONAL(mgr_a_optional_t, AUserWidth, WUserWidth, 0, 0)
  `OBI_TYPEDEF_ALL_R_OPTIONAL(mgr_r_optional_t, RUserWidth, 0)
  typedef obi_test::obi_rand_manager #(
    .ObiCfg           ( MgrConfig ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t ),
    .TA ( ApplTime ),
    .TT ( TestTime ),
    .MinAddr (32'h0000_0000),
    .MaxAddr (32'h0001_3000)
  ) rand_manager_t;

  localparam obi_pkg::obi_cfg_t MgrMuxedConfig = '{
    UseRReady:      1'b0,
    CombGnt:        1'b0,
    AddrWidth: AddrWidth,
    DataWidth: DataWidth,
    IdWidth:  SbrIdWidth,
    Integrity:      1'b0,
    BeFull:         1'b1,
    OptionalCfg: '{
      UseAtop:          1'b1,
      UseMemtype:       1'b0,
      UseProt:          1'b0,
      UseDbg:           1'b0,
      AUserWidth: AUserWidth,
      WUserWidth: WUserWidth,
      RUserWidth: RUserWidth,
      MidWidth:            0,
      AChkWidth:           0,
      RChkWidth:           0
    }
  };


  localparam obi_pkg::obi_cfg_t SbrConfig = '{
    UseRReady:      1'b0,
    CombGnt:        1'b0,
    AddrWidth: AddrWidth,
    DataWidth: DataWidth,
    IdWidth:  SbrIdWidth,
    Integrity:      1'b0,
    BeFull:         1'b1,
    OptionalCfg: '{
      UseAtop:          1'b0,
      UseMemtype:       1'b0,
      UseProt:          1'b0,
      UseDbg:           1'b0,
      AUserWidth: AUserWidth,
      WUserWidth: WUserWidth,
      RUserWidth: RUserWidth,
      MidWidth:            0,
      AChkWidth:           0,
      RChkWidth:           0
    }
  };
  `OBI_TYPEDEF_ALL_A_OPTIONAL(sbr_a_optional_t, AUserWidth, WUserWidth, 0, 0)
  `OBI_TYPEDEF_ALL_R_OPTIONAL(sbr_r_optional_t, RUserWidth, 0)

  // typedef obi_test::obi_rand_subordinate #(
  //   .ObiCfg ( SbrConfig ),
  //   .obi_a_optional_t ( sbr_a_optional_t ),
  //   .obi_r_optional_t ( sbr_r_optional_t ),
  //   .TA ( ApplTime ),
  //   .TT ( TestTime )
  // ) rand_subordinate_t;

  logic clk, rst_n;
  logic [NumManagers-1:0] end_of_sim;
  int unsigned num_errors = 0;

  OBI_BUS_DV #(
    .OBI_CFG          ( MgrConfig ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t )
  ) mgr_bus_dv [NumManagers] (
    .clk_i  ( clk   ),
    .rst_ni ( rst_n )
  );
  OBI_BUS #(
    .OBI_CFG          ( MgrConfig ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t )
  ) mgr_bus [NumManagers] ();

  OBI_BUS #(
    .OBI_CFG          ( MgrMuxedConfig ),
    .obi_a_optional_t ( mgr_a_optional_t ),
    .obi_r_optional_t ( mgr_r_optional_t )
  ) mgr_bus_muxed ();

  rand_manager_t obi_rand_managers[NumManagers];

  // TODO: Managers write/read? --> copy from axi_riscv_atomics
  for (genvar i = 0; i < NumManagers; i++) begin : gen_mgr_drivers
    initial begin
      obi_rand_managers[i] = new ( mgr_bus_dv[i], $sformatf("MGR_%0d",i));
      // automatic logic [  MgrConfig.DataWidth-1:0] r_rdata    = '0;
      // automatic logic [    MgrConfig.IdWidth-1:0] r_rid      = '0;
      // automatic mgr_r_optional_t                  r_optional = '0;
      end_of_sim[i] <= 1'b0;
      obi_rand_managers[i].reset();



    //   @(posedge rst_n);
    //   obi_rand_manager.write(32'h0000_1100, 4'hF, 32'hDEAD_BEEF, 2,
    //                          '{auser: '0,
    //                            wuser: '0,
    //                            atop: '0,
    //                            memtype: obi_pkg::memtype_t'('0),
    //                            mid: '0,
    //                            prot: obi_pkg::prot_t'('0),
    //                            dbg: '0,
    //                            achk: '0}, r_rid, r_optional);
    //   obi_rand_manager.read(32'h0000_e100, 2, '{auser: '0,
    //                                             wuser: '0,
    //                                             atop: '0,
    //                                             memtype: obi_pkg::memtype_t'('0),
    //                                             mid: '0,
    //                                             prot: obi_pkg::prot_t'('0),
    //                                             dbg: '0,
    //                                             achk: '0}, r_rdata, r_rid, r_optional);
    //   obi_rand_manager.run(NumRequests);

    end

    `OBI_ASSIGN(mgr_bus[i], mgr_bus_dv[i], MgrConfig, MgrConfig)
  end


  // OBI_BUS_DV #(
  //   .OBI_CFG          ( SbrConfig ),
  //   .obi_a_optional_t ( sbr_a_optional_t ),
  //   .obi_r_optional_t ( sbr_r_optional_t )
  // ) sbr_bus_dv (
  //   .clk_i  ( clk   ),
  //   .rst_ni ( rst_n )
  // );
  OBI_BUS #(
    .OBI_CFG          ( SbrConfig ),
    .obi_a_optional_t ( sbr_a_optional_t ),
    .obi_r_optional_t ( sbr_r_optional_t )
  ) sbr_bus ();

  // `OBI_ASSIGN(sbr_bus_dv, sbr_bus, SbrConfig, SbrConfig)

  OBI_ATOP_MONITOR_BUS #(
    .DataWidth(DataWidth),
    .AddrWidth(AddrWidth),
    .IdWidth  (SbrIdWidth),
    .UserWidth(AUserWidth)
  ) mem_monitor_dv (
    .clk_i (clk)
  );


  clk_rst_gen #(
    .ClkPeriod    ( CyclTime ),
    .RstClkCycles ( 5        )
  ) i_clk_gen (
    .clk_o  ( clk   ),
    .rst_no ( rst_n )
  );

  obi_mux_intf #(
    .SbrPortObiCfg  (MgrConfig),
    .MgrPortObiCfg  (MgrMuxedConfig),
    .NumSbrPorts    (NumManagers),
    .NumMaxTrans    (2),
    .UseIdForRouting(1'b0)
  ) i_obi_mux (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .testmode_i(1'b0),
    .sbr_ports (mgr_bus),
    .mgr_port  (mgr_bus_muxed)
  );

  obi_atop_resolver_intf #(
    .SbrPortObiCfg (MgrMuxedConfig),
    .MgrPortObiCfg (SbrConfig),
    .LrScEnable    (1),
    .RegisterAmo   (1'b0)
  ) i_atop_resolver (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .sbr_port (mgr_bus_muxed),
    .mgr_port (sbr_bus)
  );

  obi_sim_mem_intf #(
    .ObiCfg           (SbrConfig),
    .ClearErrOnAccess (1'b0),
    .WarnUninitialized(1'b0),
    .ApplDelay        (ApplTime),
    .AcqDelay         (TestTime)
  ) i_sim_mem (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .obi_sbr(sbr_bus),
    .mon_valid_o(mem_monitor_dv.valid),
    .mon_we_o   (mem_monitor_dv.we),
    .mon_addr_o (mem_monitor_dv.addr),
    .mon_wdata_o(mem_monitor_dv.data),
    .mon_be_o   (mem_monitor_dv.be),
    .mon_id_o   (mem_monitor_dv.id)
  );

  atop_golden_mem_pkg::atop_golden_mem #(
    .ObiAddrWidth (AddrWidth),
    .ObiDataWidth (DataWidth),
    .ObiIdWidthM  (MgrIdWidth),
    .ObiIdWidthS  (SbrIdWidth),
    .ObiUserWidth (AUserWidth),
    .NumMgrWidth  ($clog2(NumManagers)),
    .ApplDelay    (ApplTime),
    .AcqDelay     (TestTime)
  ) golden_memory = new(mem_monitor_dv);
  assign mem_monitor_dv.user = '0;

  /*====================================================================
  =                                Main                                =
  ====================================================================*/

  initial begin
    wait (rst_n);
    @(posedge clk);


    // Run tests!
    test_all_amos();
    // test_same_address();
    // test_amo_write_consistency();
    // // test_interleaving();
    // test_atomic_counter();
    // random_amo();

    // overtake_r();
    end_of_sim <= '1;
  end

  /*====================================================================
  =                               Timeout                              =
  ====================================================================*/

  initial begin
    // TODO timeout monitoring
  end



  /*====================================================================
  =                         Hand crafted tests                         =
  ====================================================================*/

  task automatic test_all_amos();

    automatic logic [AddrWidth-1:0] address;
    automatic logic [DataWidth-1:0] data_init;
    automatic logic [DataWidth-1:0] data_amo;
    automatic atop_t atop;

    $display("Test all possible amos with a single thread...\n");

    for (int j = 0; j < 9; j++) begin
      // Go through standard AMOs
      if (j == 0) atop = AMOSWAP;
      if (j == 1) atop = AMOADD;
      if (j == 2) atop = AMOXOR;
      if (j == 3) atop = AMOAND;
      if (j == 4) atop = AMOOR;
      if (j == 5) atop = AMOMIN;
      if (j == 6) atop = AMOMAX;
      if (j == 7) atop = AMOMINU;
      if (j == 8) atop = AMOMAXU;

      void'(randomize(address));
      void'(randomize(data_init));
      void'(randomize(data_amo));

      write_amo_read_cycle(0, address, data_init, data_amo, 0, 0, atop);



    end

  endtask



  /*====================================================================
  =                          Helper Functions                          =
  ====================================================================*/

  task automatic write_amo_read_cycle(
    input int unsigned           driver,
    input logic [ AddrWidth-1:0] address,
    input logic [ DataWidth-1:0] data_init,
    input logic [ DataWidth-1:0] data_amo,
    input logic [MgrIdWidth-1:0] id,
    input logic [AUserWidth-1:0] user,
    input atop_t                 atop
  );

    automatic logic [MgrIdWidth-1:0] trans_id = id;
    automatic logic [DataWidth-1:0] rdata;
    automatic logic [DataWidth-1:0] exp_data;
    automatic logic [DataWidth-1:0] act_data;
    automatic logic err;
    automatic logic exokay;
    automatic logic exp_err;
    automatic logic exp_exokay;
    automatic logic [MgrIdWidth-1:0] rid;
      
    automatic mgr_a_optional_t a_optional = '0;
    automatic mgr_r_optional_t r_optional;
    a_optional.atop = '0;
    exokay = r_optional.exokay;

    if (!id) begin
      void'(randomize(trans_id));
    end
    // Preload data
    fork
      obi_rand_managers[driver].write(address, '1, data_init, trans_id, a_optional, rdata, rid, err, r_optional);
      golden_memory.write(address, data_init, '1, trans_id, driver, '0, exp_data, exp_err, exp_exokay);
    join
    if (!id) begin
      void'(randomize(trans_id));
    end
    // Execute AMO
    a_optional.atop = atop;
    fork
      obi_rand_managers[driver].write(address, '1, data_amo, trans_id, a_optional, rdata, rid, err, r_optional);
      golden_memory.write(address, data_amo, '1, trans_id, driver, atop, exp_data, exp_err, exp_exokay);
    join
    exokay = r_optional.exokay;
    assert (err == exp_err && exokay == exp_exokay) else begin
      $warning("Response codes did not match! got: 0x%b, exp: 0x%b", {err, exokay}, {exp_err, exp_exokay});
      num_errors += 1;
    end
    assert (rdata == exp_data) else begin
      $warning("ATOP data did not match! got: 0x%x, exp: 0x%x at addr: 0x%x with op 0x%x", rdata, exp_data, address, atop);
      num_errors += 1;
    end
    if (!id) begin
      void'(randomize(trans_id));
    end
    // Check stored data
    a_optional.atop = '0;
    fork
      obi_rand_managers[driver].read(address, trans_id, a_optional, act_data, rid, err, r_optional);
      golden_memory.read(address, trans_id, driver, '0, exp_data, exp_err, exp_exokay);
    join
    assert(act_data == exp_data) else begin
      $warning("Stored data did not match! got: 0x%x, exp: 0x%x at addr: 0x%x with op 0x%x", act_data, exp_data, address, atop);
      num_errors += 1;
    end

  endtask






  initial begin
    wait(&end_of_sim);
    repeat (1000) @(posedge clk);
    $display("Simulation stopped as all Masters transferred their data. Number of Errors = %u", num_errors);
    $stop();
  end

endmodule


