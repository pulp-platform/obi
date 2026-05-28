// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module obi_err_sbr #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t           ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// The request struct.
  parameter type                         obi_req_t   = logic,
  /// The response struct.
  parameter type                         obi_rsp_t   = logic,
  /// Numper of transactions accepted before stalling if UseRReady
  parameter int unsigned                 NumMaxTrans = 1,
  /// Data to respond with from error subordinate
  parameter logic [ObiCfg.DataWidth-1:0] RspData     = 32'hBADCAB1E,
  /// The burst extension mode.
  parameter obi_pkg::obi_burst_mode_e    BurstMode   = obi_pkg::OBI_BURST_NONE,
  /// The width of the beat-framed burst length field.
  parameter int unsigned                 BurstLenWidth = 32'd8
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o
);

  logic fifo_full, fifo_empty, fifo_pop;

  if (ObiCfg.UseRReady) begin : gen_pop_rready
    assign fifo_pop = obi_rsp_o.rvalid && obi_req_i.rready;
  end else begin : gen_pop_default
    assign fifo_pop = obi_rsp_o.rvalid;
  end

  if (BurstMode == obi_pkg::OBI_BURST_BEAT_FRAMED) begin : gen_burst
    typedef struct packed {
      logic [ObiCfg.IdWidth-1:0] rid;
    } rsp_meta_t;

    rsp_meta_t rsp_meta;

    always_comb begin
      obi_rsp_o.r.rdata = '0;
      obi_rsp_o.r.rdata = RspData;
      obi_rsp_o.r.rid   = rsp_meta.rid;
      obi_rsp_o.r.err   = 1'b1;
      obi_rsp_o.r.r_optional = '0;
      obi_rsp_o.gnt = ~fifo_full;
      obi_rsp_o.rvalid = ~fifo_empty;
    end

    fifo_v3 #(
      .DEPTH        ( ObiCfg.UseRReady ? NumMaxTrans : 1 ),
      .FALL_THROUGH ( 1'b0                               ),
      .DATA_WIDTH   ( $bits(rsp_meta_t)                  )
    ) i_meta_fifo (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .flush_i   ( '0                                                      ),
      .full_o    ( fifo_full                                               ),
      .empty_o   ( fifo_empty                                              ),
      .usage_o   (),
      .data_i    ( '{rid: obi_req_i.a.aid}                              ),
      .push_i    ( obi_req_i.req && obi_rsp_o.gnt                          ),
      .data_o    ( rsp_meta                                                ),
      .pop_i     ( fifo_pop                                                )
    );
  end else begin : gen_no_burst
    logic [ObiCfg.IdWidth-1:0] rid;

    always_comb begin
      obi_rsp_o.r.rdata = '0;
      obi_rsp_o.r.rdata = RspData;
      obi_rsp_o.r.rid   = rid;
      obi_rsp_o.r.err   = 1'b1;
      obi_rsp_o.r.r_optional = '0;
      obi_rsp_o.gnt = ~fifo_full;
      obi_rsp_o.rvalid = ~fifo_empty;
    end

    fifo_v3 #(
      .DEPTH        ( ObiCfg.UseRReady ? NumMaxTrans : 1 ),
      .FALL_THROUGH ( 1'b0                               ),
      .DATA_WIDTH   ( ObiCfg.IdWidth                     )
    ) i_id_fifo (
      .clk_i,
      .rst_ni,
      .testmode_i,
      .flush_i   ( '0                             ),
      .full_o    ( fifo_full                      ),
      .empty_o   ( fifo_empty                     ),
      .usage_o   (),
      .data_i    ( obi_req_i.a.aid                ),
      .push_i    ( obi_req_i.req && obi_rsp_o.gnt ),
      .data_o    ( rid                            ),
      .pop_i     ( fifo_pop                       )
    );
  end

endmodule

`include "obi/typedef.svh"
`include "obi/assign.svh"

module obi_err_sbr_intf #(
  /// The OBI configuration for all ports.
  parameter obi_pkg::obi_cfg_t           ObiCfg      = obi_pkg::ObiDefaultConfig,
  /// Numper of transactions accepted before stalling if UseRReady
  parameter int unsigned                 NumMaxTrans = 1,
  /// Data to respond with from error subordinate
  parameter logic [ObiCfg.DataWidth-1:0] RspData     = 32'hBADCAB1E,
  /// The burst extension mode.
  parameter obi_pkg::obi_burst_mode_e    BurstMode   = obi_pkg::OBI_BURST_NONE,
  /// The width of the beat-framed burst length field.
  parameter int unsigned                 BurstLenWidth = 32'd8
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic testmode_i,

  OBI_BUS.Subordinate sbr_port
);

  if (BurstMode == obi_pkg::OBI_BURST_BEAT_FRAMED) begin : gen_burst
    `OBI_TYPEDEF_ALL_BURST(obi, ObiCfg, BurstLenWidth)

    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    `OBI_ASSIGN_TO_REQ(obi_req, sbr_port, ObiCfg)
    `OBI_ASSIGN_FROM_RSP(sbr_port, obi_rsp, ObiCfg)

    obi_err_sbr #(
      .ObiCfg        ( ObiCfg        ),
      .obi_req_t     ( obi_req_t     ),
      .obi_rsp_t     ( obi_rsp_t     ),
      .NumMaxTrans   ( NumMaxTrans   ),
      .RspData       ( RspData       ),
      .BurstMode     ( BurstMode     ),
      .BurstLenWidth ( BurstLenWidth )
    ) i_err_sbr (
      .clk_i,
      .rst_ni,
      .testmode_i,

      .obi_req_i  ( obi_req ),
      .obi_rsp_o  ( obi_rsp )
    );
  end else begin : gen_no_burst
    `OBI_TYPEDEF_ALL(obi, ObiCfg)

    obi_req_t obi_req;
    obi_rsp_t obi_rsp;

    `OBI_ASSIGN_TO_REQ(obi_req, sbr_port, ObiCfg)
    `OBI_ASSIGN_FROM_RSP(sbr_port, obi_rsp, ObiCfg)

    obi_err_sbr #(
      .ObiCfg        ( ObiCfg        ),
      .obi_req_t     ( obi_req_t     ),
      .obi_rsp_t     ( obi_rsp_t     ),
      .NumMaxTrans   ( NumMaxTrans   ),
      .RspData       ( RspData       ),
      .BurstMode     ( BurstMode     ),
      .BurstLenWidth ( BurstLenWidth )
    ) i_err_sbr (
      .clk_i,
      .rst_ni,
      .testmode_i,

      .obi_req_i  ( obi_req ),
      .obi_rsp_o  ( obi_rsp )
    );
  end

endmodule
