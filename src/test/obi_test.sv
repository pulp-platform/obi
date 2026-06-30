// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

package obi_test;
  import obi_pkg::*;

  class obi_driver #(
    parameter obi_cfg_t ObiCfg           = ObiDefaultConfig,
    parameter type      obi_a_optional_t = logic,
    parameter type      obi_r_optional_t = logic,
    parameter time      TA               = 0ns,
    parameter time      TT               = 0ns
  );
    virtual OBI_BUS_DV #(
      .OBI_CFG          ( ObiCfg           ),
      .obi_a_optional_t ( obi_a_optional_t ),
      .obi_r_optional_t ( obi_r_optional_t )
    ) obi;

    function new(
      virtual OBI_BUS_DV #(
        .OBI_CFG          ( ObiCfg           ),
        .obi_a_optional_t ( obi_a_optional_t ),
        .obi_r_optional_t ( obi_r_optional_t )
      ) obi
    );
      this.obi = obi;
    endfunction

    function void reset_manager();
      obi.req        <= '0;
      obi.reqpar     <= '1;
      obi.addr       <= '0;
      obi.we         <= '0;
      obi.be         <= '0;
      obi.wdata      <= '0;
      obi.aid        <= '0;
      obi.a_optional <= '0;
      obi.rready     <= '0;
      obi.rreadypar  <= '1;
    endfunction

    function void reset_subordinate();
      obi.gnt        <= '0;
      obi.gntpar     <= '1;
      obi.rvalid     <= '0;
      obi.rvalidpar  <= '1;
      obi.rdata      <= '0;
      obi.rid        <= '0;
      obi.err        <= '0;
      obi.r_optional <= '0;
    endfunction

    task cycle_start;
      #TT;
    endtask

    task cycle_end;
      @(posedge obi.clk_i);
    endtask

    task send_a (
      input logic [  ObiCfg.AddrWidth-1:0] addr,
      input logic                          we,
      input logic [ObiCfg.DataWidth/8-1:0] be,
      input logic [  ObiCfg.DataWidth-1:0] wdata,
      input logic [    ObiCfg.IdWidth-1:0] aid,
      input obi_a_optional_t               a_optional
    );
      obi.req        <= #TA 1'b1;
      obi.reqpar     <= #TA 1'b0;
      obi.addr       <= #TA addr;
      obi.we         <= #TA we;
      obi.be         <= #TA be;
      obi.wdata      <= #TA wdata;
      obi.aid        <= #TA aid;
      obi.a_optional <= #TA a_optional;
      cycle_start();
      while (obi.gnt != 1'b1) begin cycle_end(); cycle_start(); end
      cycle_end();
      obi.req        <= #TA 1'b0;
      obi.reqpar     <= #TA 1'b1;
      obi.addr       <= #TA '0;
      obi.we         <= #TA '0;
      obi.be         <= #TA '0;
      obi.wdata      <= #TA '0;
      obi.aid        <= #TA '0;
      obi.a_optional <= #TA '0;
    endtask

    task send_r (
      input logic [ObiCfg.DataWidth-1:0] rdata,
      input logic [  ObiCfg.IdWidth-1:0] rid,
      input logic                        err,
      input obi_r_optional_t             r_optional
    );
      obi.rvalid     <= #TA 1'b1;
      obi.rvalidpar  <= #TA 1'b0;
      obi.rdata      <= #TA rdata;
      obi.rid        <= #TA rid;
      obi.err        <= #TA err;
      obi.r_optional <= #TA r_optional;
      cycle_start();
      if (ObiCfg.UseRReady) begin
        while (obi.rready != 1'b1) begin cycle_end(); cycle_start(); end
      end
      cycle_end();
      obi.rvalid     <= #TA 1'b0;
      obi.rvalidpar  <= #TA 1'b1;
      obi.rdata      <= #TA '0;
      obi.rid        <= #TA '0;
      obi.err        <= #TA '0;
      obi.r_optional <= #TA '0;
    endtask

    task recv_a (
      output logic [  ObiCfg.AddrWidth-1:0] addr,
      output logic                          we,
      output logic [ObiCfg.DataWidth/8-1:0] be,
      output logic [  ObiCfg.DataWidth-1:0] wdata,
      output logic [    ObiCfg.IdWidth-1:0] aid,
      output obi_a_optional_t               a_optional
    );
      obi.gnt    <= #TA 1'b1;
      obi.gntpar <= #TA 1'b0;
      cycle_start();
      while (obi.req != 1'b1) begin cycle_end(); cycle_start(); end
      addr       = obi.addr;
      we         = obi.we;
      be         = obi.be;
      wdata      = obi.wdata;
      aid        = obi.aid;
      a_optional = obi.a_optional;
      cycle_end();
      obi.gnt    <= #TA 1'b0;
      obi.gntpar <= #TA 1'b1;
    endtask

    task recv_r (
      output logic [ObiCfg.DataWidth-1:0] rdata,
      output logic [  ObiCfg.IdWidth-1:0] rid,
      output logic                        err,
      output obi_r_optional_t             r_optional
    );
      obi.rready    <= #TA 1'b1;
      obi.rreadypar <= #TA 1'b0;
      cycle_start();
      while (obi.rvalid != 1'b1) begin cycle_end(); cycle_start(); end
      rdata      = obi.rdata;
      rid        = obi.rid;
      err        = obi.err;
      r_optional = obi.r_optional;
      cycle_end();
      if (ObiCfg.UseRReady) begin
        obi.rready    <= #TA 1'b0;
        obi.rreadypar <= #TA 1'b1;
      end
    endtask

  endclass

  class obi_rand_manager #(
    // Obi Parameters
    parameter obi_cfg_t    ObiCfg           = ObiDefaultConfig,
    parameter type         obi_a_optional_t = logic,
    parameter type         obi_r_optional_t = logic,
    // Stimuli Parameters
    parameter time         TA               = 2ns,
    parameter time         TT               = 8ns,
    // Manager Parameters
    parameter int unsigned MinAddr          = 32'h0000_0000,
    parameter int unsigned MaxAddr          = 32'hffff_ffff,
    // Wait Parameters
    parameter int unsigned AMinWaitCycles   = 0,
    parameter int unsigned AMaxWaitCycles   = 100,
    parameter int unsigned RMinWaitCycles   = 0,
    parameter int unsigned RMaxWaitCycles   = 100
  );
    typedef obi_test::obi_driver #(
      .ObiCfg           ( ObiCfg           ),
      .obi_a_optional_t ( obi_a_optional_t ),
      .obi_r_optional_t ( obi_r_optional_t ),
      .TA               ( TA               ),
      .TT               ( TT               )
    ) obi_driver_t;

    typedef logic [ObiCfg.AddrWidth-1:0] addr_t;

    string       name;
    obi_driver_t drv;
    addr_t       a_queue[$];

    // Scoreboard for id usage tracking. Values indicate:
    //  0: Id is not used by any outstanding request,
    //  >0: Id is used by that many non-atomic requests,
    //  -1: Id is used by an atomic request.
    int aid_atop_scoreboard[(1<<ObiCfg.IdWidth)-1:0];
    std::semaphore atop_sb_sem;

    function new(
      virtual OBI_BUS_DV #(
        .OBI_CFG          ( ObiCfg           ),
        .obi_a_optional_t ( obi_a_optional_t ),
        .obi_r_optional_t ( obi_r_optional_t )
      ) obi,
      input string name
    );
      this.drv  = new(obi);
      this.name = name;
      this.aid_atop_scoreboard = '{default: '0};
      this.atop_sb_sem = new(1);
      assert(ObiCfg.AddrWidth != 0) else $fatal(1, "ObiCfg.AddrWidth must be non-zero!");
      assert(ObiCfg.DataWidth != 0) else $fatal(1, "ObiCfg.DataWidth must be non-zero!");
    endfunction

    function void reset();
      drv.reset_manager();
      this.a_queue.delete();
      this.aid_atop_scoreboard = '{default: '0};
    endfunction

    function bit atop_id_available();
      for (int unsigned i = 0; i < 1<<ObiCfg.IdWidth; i++) begin
        if (this.aid_atop_scoreboard[i] == 0) begin
          return 1'b1;
        end
      end
      return 1'b0;
    endfunction

    function bit non_atop_id_available();
      for (int unsigned i = 0; i < 1<<ObiCfg.IdWidth; i++) begin
        if (this.aid_atop_scoreboard[i] >= 0) begin
          return 1'b1;
        end
      end
      return 1'b0;
    endfunction

    task automatic rand_wait(input int unsigned min, input int unsigned max);
      int unsigned rand_success, cycles;
      rand_success = std::randomize(cycles) with {
        cycles >= min;
        cycles <= max;
      };
      assert (rand_success) else $error("Failed to randomize wait cycles!");
      repeat (cycles) @(posedge this.drv.obi.clk_i);
    endtask

    task automatic legalize_id(input obi_a_optional_t a_optional, output logic [ObiCfg.IdWidth-1:0] aid);
      automatic bit is_atop;
      if (ObiCfg.OptionalCfg.UseAtop) begin
        is_atop = (a_optional.atop != obi_pkg::ATOPNONE);
      end else begin
        is_atop = 1'b0;
      end

      // Requirement R-12: An OBI manager shall prevent initiating a transaction if it would
      //  lead to multiple outstanding transactions with the same aid of which at least one
      //  transaction is an atomic transaction.
      forever begin
        this.atop_sb_sem.get();
        if (is_atop) begin
          if (!this.atop_id_available()) begin
            // No legal ID available, wait until one becomes available
            this.atop_sb_sem.put();
            rand_wait(1, 1);
            continue;
          end

          // Get a random available id
          assert(std::randomize(aid) with {
            this.aid_atop_scoreboard[aid] == 0;
          });

          // Mark aid used by atomic
          this.aid_atop_scoreboard[aid] = -1;

        end else begin
          if (!this.non_atop_id_available()) begin
            // No legal ID available, wait until one becomes available
            this.atop_sb_sem.put();
            rand_wait(1, 1);
            continue;
          end

          // Get a random available id
          assert(std::randomize(aid) with {
            this.aid_atop_scoreboard[aid] != -1;
          });

          // Increment usage of aid for non-atomic
          this.aid_atop_scoreboard[aid]++;
        end
        this.atop_sb_sem.put();
        break;
      end
    endtask

    task automatic send_as(input int unsigned n_reqs);
      automatic addr_t                         a_addr;
      automatic logic                          a_we;
      automatic logic [ObiCfg.DataWidth/8-1:0] a_be;
      automatic logic [  ObiCfg.DataWidth-1:0] a_wdata;
      automatic logic [    ObiCfg.IdWidth-1:0] a_aid;
      automatic obi_a_optional_t               a_optional;
      automatic int unsigned be_low, be_width;

      repeat (n_reqs) begin
        rand_wait(AMinWaitCycles, AMaxWaitCycles);

        assert(std::randomize(a_we));
        assert(std::randomize(a_wdata));
        if (ObiCfg.BeFull) begin
          // Requirement R-8: No restrictions on BE
          assert(std::randomize(a_be));
          assert(std::randomize(a_addr) with {
            a_addr >= MinAddr;
            a_addr <= MaxAddr;
          });
        end else begin
          // Requirement R-7:
          //  - At least one of the be bits shall be set to 1.
          //  - The 1’s in be shall be contiguous.
          assert(std::randomize(be_low, be_width) with {
            be_low < ObiCfg.DataWidth/8;
            be_low + be_width <= ObiCfg.DataWidth/8;
            be_width > 0;
          });
          a_be = ((1 << (be_width)) - 1) << be_low;
          // Requirement R-9: If i is the index of the least signification bit in be that is 1,
          //  then the least significant addr bits shall be <= i.
          assert(std::randomize(a_addr) with {
            a_addr >= MinAddr;
            a_addr <= MaxAddr;
            a_addr[$clog2(ObiCfg.DataWidth/8)-1:0] <= be_low;
          });
        end

        a_optional = 'x;
        if (ObiCfg.OptionalCfg.UseAtop) begin
          automatic obi_pkg::atop_t atop;
          // Requirement R-11.3: The transaction associated with a LR.W shall have we = 0;
          //  the other atomic memory transactions (i.e. SC.W, AMO*) shall use we = 1.
          assert(std::randomize(atop) with {
            a_we -> atop dist {
              ATOPSC, AMOSWAP, AMOADD, AMOXOR, AMOAND, AMOOR, AMOMIN,
              AMOMAX, AMOMINU, AMOMAXU, ATOPNONE
            };
            !a_we ->atop dist {
              ATOPLR, ATOPNONE
            };
          });
          a_optional.atop = atop;
          if (a_optional.atop != ATOPNONE) begin
            // Requirement R-11.5: The byte enables be used in an atomic memory transaction shall
            //  indicate a word or double-word transfer as implied by the related *.W or *.D
            //  instruction.
            if (ObiCfg.DataWidth == 32) begin
              a_be = '1;
            end else begin
              assert(std::randomize(be_low, be_width) with {
                be_width == 4 || be_width == 8;
                be_low % be_width == 0;
                be_low + be_width <= ObiCfg.DataWidth/8;
              });
              a_be = ((1 << (be_width)) - 1) << be_low;
            end
            // Requirement R-11.4: The address addr used in an atomic memory transaction shall be
            //  naturally aligned.
            a_addr &= ~(be_width - 1);
          end
        end
        if (ObiCfg.OptionalCfg.UseMemtype) begin
          automatic obi_pkg::memtype_t memtype;
          assert(std::randomize(memtype));
          a_optional.memtype = memtype;
        end
        if (ObiCfg.OptionalCfg.UseProt) begin
          automatic obi_pkg::prot_t prot;
          assert(std::randomize(prot));
          a_optional.prot = prot;
        end
        if (ObiCfg.OptionalCfg.UseDbg) begin
          automatic logic dbg;
          assert(std::randomize(dbg));
          a_optional.dbg = dbg;
        end
        if (ObiCfg.OptionalCfg.MidWidth > 0) begin
          automatic logic [$bits(a_optional.mid)-1:0] a_mid;
          assert(std::randomize(a_mid));
          a_optional.mid = a_mid;
        end
        if (ObiCfg.OptionalCfg.AUserWidth > 0) begin
          automatic logic [$bits(a_optional.auser)-1:0] a_auser;
          assert(std::randomize(a_auser));
          a_optional.auser = a_auser;
        end
        if (ObiCfg.OptionalCfg.WUserWidth > 0) begin
          automatic logic [$bits(a_optional.wuser)-1:0] a_wuser;
          assert(std::randomize(a_wuser));
          a_optional.wuser = a_wuser;
        end
        if (ObiCfg.Integrity && ObiCfg.OptionalCfg.AChkWidth > 0) begin
          automatic logic [$bits(a_optional.achk)-1:0] achk;
          assert(std::randomize(achk));
          a_optional.achk = achk;
        end
        legalize_id(a_optional, a_aid);

        this.a_queue.push_back(a_addr);
        this.drv.send_a(a_addr, a_we, a_be, a_wdata, a_aid, a_optional);
      end
    endtask

    task automatic recv_rs(input int unsigned n_rsps);
      automatic addr_t                       a_addr;
      automatic logic [ObiCfg.DataWidth-1:0] r_rdata;
      automatic logic [  ObiCfg.IdWidth-1:0] r_rid;
      automatic logic                        r_err;
      automatic obi_r_optional_t             r_optional;
      repeat (n_rsps) begin
        wait (this.a_queue.size() > 0);
        a_addr = this.a_queue.pop_front();

        if (ObiCfg.UseRReady) begin
          rand_wait(RMinWaitCycles, RMaxWaitCycles);
        end
        drv.recv_r(r_rdata, r_rid, r_err, r_optional);

        // Update atomics scoreboard
        this.atop_sb_sem.get();
        if (aid_atop_scoreboard[r_rid] > 0) begin
          // Non-atomic response
          aid_atop_scoreboard[r_rid]--;
        end else begin
          // Atomic response
          aid_atop_scoreboard[r_rid] = 0;
        end
        this.atop_sb_sem.put();
      end
    endtask

    task automatic run(int unsigned n_reqs);
      $display("Run for Reqs: %0d", n_reqs);
      fork
        this.send_as(n_reqs);
        this.recv_rs(n_reqs);
      join
    endtask

    task automatic write(
      input  addr_t                         addr,
      input  logic [ObiCfg.DataWidth/8-1:0] be,
      input  logic [  ObiCfg.DataWidth-1:0] wdata,
      input  logic [    ObiCfg.IdWidth-1:0] aid,
      input  obi_a_optional_t               a_optional,
      output logic [  ObiCfg.DataWidth-1:0] r_rdata,
      output logic [    ObiCfg.IdWidth-1:0] r_rid,
      output logic                          r_err,
      output obi_r_optional_t               r_optional
    );
      this.drv.send_a(addr, 1'b1, be, wdata, aid, a_optional);
      this.drv.recv_r(r_rdata, r_rid, r_err, r_optional);
    endtask

    task automatic read(
      input  addr_t                       addr,
      input  logic [  ObiCfg.IdWidth-1:0] aid,
      input  obi_a_optional_t             a_optional,
      output logic [ObiCfg.DataWidth-1:0] r_rdata,
      output logic [  ObiCfg.IdWidth-1:0] r_rid,
      output logic                        r_err,
      output obi_r_optional_t             r_optional
    );
      this.drv.send_a(addr, 1'b0, '1, '0, aid, a_optional);
      this.drv.recv_r(r_rdata, r_rid, r_err, r_optional);
    endtask

  endclass

  class obi_rand_subordinate #(
    // Obi Parameters
    parameter obi_cfg_t    ObiCfg           = ObiDefaultConfig,
    parameter type         obi_a_optional_t = logic,
    parameter type         obi_r_optional_t = logic,
    // Response Settings
    parameter bit          RandResp         = 0,
    // Stimuli Parameters
    parameter time         TA               = 2ns,
    parameter time         TT               = 8ns,
    // Wait Parameters
    parameter int unsigned AMinWaitCycles   = 0,
    parameter int unsigned AMaxWaitCycles   = 100,
    parameter int unsigned RMinWaitCycles   = 0,
    parameter int unsigned RMaxWaitCycles   = 100
  );
    typedef obi_test::obi_driver #(
      .ObiCfg           ( ObiCfg           ),
      .obi_a_optional_t ( obi_a_optional_t ),
      .obi_r_optional_t ( obi_r_optional_t ),
      .TA               ( TA               ),
      .TT               ( TT               )
    ) obi_driver_t;

    typedef logic [ObiCfg.AddrWidth-1:0] addr_t;
    typedef logic [  ObiCfg.IdWidth-1:0] id_t;

    string       name;
    obi_driver_t drv;
    addr_t       a_queue[$];
    id_t         id_queue[$];
    logic        is_excl_queue[$];

    function new(
      virtual OBI_BUS_DV #(
        .OBI_CFG          ( ObiCfg           ),
        .obi_a_optional_t ( obi_a_optional_t ),
        .obi_r_optional_t ( obi_r_optional_t )
      ) obi,
      input string name
    );
      this.drv  = new(obi);
      this.name = name;
      assert(ObiCfg.AddrWidth != 0) else $fatal(1, "ObiCfg.AddrWidth must be non-zero!");
      assert(ObiCfg.DataWidth != 0) else $fatal(1, "ObiCfg.DataWidth must be non-zero!");
    endfunction

    function void reset();
      drv.reset_subordinate();
    endfunction

    task automatic rand_wait(input int unsigned min, input int unsigned max);
      int unsigned rand_success, cycles;
      rand_success = std::randomize(cycles) with {
        cycles >= min;
        cycles <= max;
      };
      assert (rand_success) else $error("Failed to randomize wait cycles!");
      repeat (cycles) @(posedge this.drv.obi.clk_i);
    endtask

    task automatic recv_as();
      forever begin
        automatic addr_t                         a_addr;
        automatic logic [ObiCfg.DataWidth/8-1:0] a_be;
        automatic logic                          a_we;
        automatic logic [  ObiCfg.DataWidth-1:0] a_wdata;
        automatic logic [    ObiCfg.IdWidth-1:0] a_aid;
        automatic obi_a_optional_t               a_optional;
        automatic logic                          is_excl;

        rand_wait(AMinWaitCycles, AMaxWaitCycles);
        this.drv.recv_a(a_addr, a_we, a_be, a_wdata, a_aid, a_optional);
        this.a_queue.push_back(a_addr);
        this.id_queue.push_back(a_aid);
        if (ObiCfg.OptionalCfg.UseAtop) begin
          is_excl = a_optional.atop inside {obi_pkg::ATOPLR, obi_pkg::ATOPSC};
        end else begin
          is_excl = 1'b0;
        end
        this.is_excl_queue.push_back(is_excl);
      end
    endtask

    task automatic send_rs();
      forever begin
        automatic logic                        rand_success;
        automatic addr_t                       a_addr;
        automatic logic                        is_excl;
        automatic logic [ObiCfg.DataWidth-1:0] r_rdata;
        automatic logic [  ObiCfg.IdWidth-1:0] r_rid;
        automatic logic                        r_err;
        automatic obi_r_optional_t             r_optional;

        wait (this.a_queue.size() > 0);
        wait (this.id_queue.size() > 0);
        wait (this.is_excl_queue.size() > 0);

        a_addr = this.a_queue.pop_front();
        r_rid  = this.id_queue.pop_front();
        is_excl = this.is_excl_queue.pop_front();

        r_err        = RandResp ? ($urandom() % 2) : 1'b0;
        rand_success = std::randomize(r_rdata); assert(rand_success);
        rand_success = std::randomize(r_optional); assert(rand_success);

        if (ObiCfg.OptionalCfg.UseAtop) begin
          // Requirement R13.1 and R13.2: For a LR.W/D related transaction success shall be signaled
          //   via exokay [...].
          if (!is_excl) begin
            // Requirement R13.3: Other [non-exclusive] transactions shall signal exokay = 0.
            r_optional.exokay = 1'b0;
          end else if (r_err) begin
            // Requirement R13.4: The exokay and err signals shall [not issue {err, exokay} = 2'b11].
            r_optional.exokay = 1'b0;
          end else begin
            r_optional.exokay = RandResp ? ($urandom() % 2) : 1'b1;
          end
        end

        rand_wait(RMinWaitCycles, RMaxWaitCycles);
        this.drv.send_r(r_rdata, r_rid, r_err, r_optional);
      end
    endtask

    task automatic run();
      fork
        recv_as();
        send_rs();
      join
    endtask

  endclass

endpackage
