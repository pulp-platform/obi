// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

package obi_pkg;

  /// The OBI atomics type, to be expanded.
  typedef logic [5:0] atop_t;

  /// The OBI memtype type, to be expanded.
  typedef logic [1:0] memtype_t;

  /// The OBI prot type, to be expanded.
  typedef logic [2:0] prot_t;

  /// The OBI bus config type.
  typedef struct packed {
    bit          UseRReady;
    bit          UseAtop;
    bit          UseMemtype;
    bit          UseProt;
    bit          CombGnt;
    int unsigned AUserWidth;
    int unsigned WUserWidth;
    int unsigned RUserWidth;
    int unsigned AddrWidth;
    int unsigned DataWidth;
    int unsigned IdWidth;
    int unsigned AChkWidth;
    int unsigned RChkWidth;
    bit          Integrity;
    bit          BeFull;
  } obi_cfg_t;

  /// The default OBI bus config.
  localparam obi_cfg_t ObiDefaultConfig = '{
    UseRReady:  1'b0,
    UseAtop:    1'b0,
    UseMemtype: 1'b0,
    UseProt:    1'b0,
    CombGnt:    1'b0,
    AUserWidth:    0,
    WUserWidth:    0,
    RUserWidth:    0,
    AddrWidth:    32,
    DataWidth:    32,
    IdWidth:       0,
    AChkWidth:     0,
    RChkWidth:     0,
    Integrity:  1'b0,
    BeFull:     1'b0
  };

  typedef enum atop_t {
    AMOLR   = 6'h22,
    AMOSC   = 6'h23,
    AMOSWAP = 6'h21,
    AMOADD  = 6'h20,
    AMOXOR  = 6'h24,
    AMOAND  = 6'h2C,
    AMOOR   = 6'h28,
    AMOMIN  = 6'h30,
    AMOMAX  = 6'h34,
    AMOMINU = 6'h38,
    AMOMAXU = 6'h3C,
    AMONONE = 6'h0
  } obi_atop_e;

endpackage
