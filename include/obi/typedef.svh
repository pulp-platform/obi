// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`ifndef OBI_TYPEDEF_SVH
`define OBI_TYPEDEF_SVH

// Use this function to ensure no infintie field
// `let` command not supported in VCS
function automatic integer unsigned sigwidth (input integer unsigned width);
  return (width != 32'd0) ? unsigned'(width-1) : 32'd0;
endfunction

`define OBI_TYPEDEF_A_CHAN_T(a_chan_t, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, a_optional_t) \
  typedef struct packed {                                                              \
    logic [  ADDR_WIDTH-1:0] addr;                                                     \
    logic                    we;                                                       \
    logic [DATA_WIDTH/8-1:0] be;                                                       \
    logic [  DATA_WIDTH-1:0] wdata;                                                    \
    logic [    ID_WIDTH-1:0] aid;                                                      \
    a_optional_t             a_optional;                                               \
  } a_chan_t;

`define OBI_TYPEDEF_TYPE_A_CHAN_T(a_chan_t, addr_t, data_t, strb_t, id_t, a_optional_t) \
  typedef struct packed {                                                               \
    addr_t       addr;                                                                  \
    logic        we;                                                                    \
    strb_t       be;                                                                    \
    data_t       wdata;                                                                 \
    id_t         aid;                                                                   \
    a_optional_t a_optional;                                                            \
  } a_chan_t;

`define OBI_TYPEDEF_MINIMAL_A_OPTIONAL(a_optional_t) \
  typedef logic a_optional_t;

`define OBI_TYPEDEF_ATOP_A_OPTIONAL(a_optional_t) \
  typedef struct packed {                         \
    obi_pkg::atop_t atop;                         \
  } a_optional_t;

`define OBI_TYPEDEF_ALL_A_OPTIONAL(a_optional_t, AUSER_WIDTH, WUSER_WIDTH, MID_WIDTH, ACHK_WIDTH) \
  typedef struct packed {                                                                         \
    logic [sigwidth(AUSER_WIDTH):0] auser;                                                        \
    logic [sigwidth(WUSER_WIDTH):0] wuser;                                                        \
    obi_pkg::atop_t                 atop;                                                         \
    obi_pkg::memtype_t              memtype;                                                      \
    logic [  sigwidth(MID_WIDTH):0] mid;                                                          \
    obi_pkg::prot_t                 prot;                                                         \
    logic                           dbg;                                                          \
    logic [ sigwidth(ACHK_WIDTH):0] achk;                                                         \
  } a_optional_t;

`define OBI_TYPEDEF_R_CHAN_T(r_chan_t, RDATA_WIDTH, ID_WIDTH, r_optional_t) \
  typedef struct packed {                                                   \
    logic [RDATA_WIDTH-1:0] rdata;                                          \
    logic [   ID_WIDTH-1:0] rid;                                            \
    logic                   err;                                            \
    r_optional_t            r_optional;                                     \
  } r_chan_t;

`define OBI_TYPEDEF_TYPE_R_CHAN_T(r_chan_t, data_t, id_t, r_optional_t) \
  typedef struct packed {                                               \
    data_t       rdata;                                                 \
    id_t         rid;                                                   \
    logic        err;                                                   \
    r_optional_t r_optional;                                            \
  } r_chan_t;

`define OBI_TYPEDEF_MINIMAL_R_OPTIONAL(r_optional_t) \
  typedef logic r_optional_t;

`define OBI_TYPEDEF_ALL_R_OPTIONAL(r_optional_t, RUSER_WIDTH, RCHK_WIDTH) \
  typedef struct packed {                                                 \
    logic [sigwidth(RUSER_WIDTH):0] ruser;                                \
    logic                           exokay;                               \
    logic [ sigwidth(RCHK_WIDTH):0] rchk;                                 \
  } r_optional_t;

`define OBI_TYPEDEF_DEFAULT_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                          \
    a_chan_t a;                                    \
    logic    req;                                  \
  } req_t;

`define OBI_TYPEDEF_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                  \
    a_chan_t a;                            \
    logic    req;                          \
    logic    rready;                       \
  } req_t;

`define OBI_TYPEDEF_RSP_T(rsp_t, r_chan_t) \
  typedef struct packed {                  \
    r_chan_t r;                            \
    logic    gnt;                          \
    logic    rvalid;                       \
  } rsp_t;

`define OBI_TYPEDEF_INTEGRITY_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                            \
    a_chan_t a;                                      \
    logic    req;                                    \
    logic    rready;                                 \
    logic    reqpar;                                 \
    logic    rreadypar;                              \
  } req_t;

`define OBI_TYPEDEF_INTEGRITY_RSP_T(rsp_t, r_chan_t) \
  typedef struct packed {                            \
    r_chan_t r;                                      \
    logic    gnt;                                    \
    logic    gntpar;                                 \
    logic    rvalid;                                 \
    logic    rvalidpar;                              \
  } rsp_t;

`define OBI_TYPEDEF_ALL(obi_t, cfg)                                                                                                                              \
  `OBI_TYPEDEF_ALL_A_OPTIONAL(obi_t``_a_optional_t, cfg.OptionalCfg.AUserWidth, cfg.OptionalCfg.WUserWidth, cfg.OptionalCfg.MidWidth, cfg.OptionalCfg.AChkWidth) \
  `OBI_TYPEDEF_A_CHAN_T(obi_t``_a_chan_t, cfg.AddrWidth, cfg.DataWidth, cfg.IdWidth, obi_t``_a_optional_t)                                                       \
  `OBI_TYPEDEF_INTEGRITY_REQ_T(obi_t``_req_t, obi_t``_a_chan_t)                                                                                                  \
  `OBI_TYPEDEF_ALL_R_OPTIONAL(obi_t``_r_optional_t, cfg.OptionalCfg.RUserWidth, cfg.OptionalCfg.RChkWidth)                                                       \
  `OBI_TYPEDEF_R_CHAN_T(obi_t``_r_chan_t, cfg.DataWidth, cfg.IdWidth, obi_t``_r_optional_t)                                                                      \
  `OBI_TYPEDEF_INTEGRITY_RSP_T(obi_t``_rsp_t, obi_t``_r_chan_t)

`define RELOBI_TYPEDEF_A_CHAN_T(a_chan_t, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, a_optional_t)       \
  typedef struct packed {                                                                       \
    logic [                      ADDR_WIDTH+hsiao_ecc_pkg::min_ecc(ADDR_WIDTH)-1:0] addr;       \
    logic                                                                           we;         \
    logic [                                                       DATA_WIDTH/8-1:0] be;         \
    logic [                      DATA_WIDTH+hsiao_ecc_pkg::min_ecc(DATA_WIDTH)-1:0] wdata;      \
    logic [                                                           ID_WIDTH-1:0] aid;        \
    a_optional_t                                                                    a_optional; \
    logic [hsiao_ecc_pkg::min_ecc(1+DATA_WIDTH/8+ID_WIDTH+$bits(a_optional_t))-1:0] other_ecc;  \
  } a_chan_t;

`define RELOBI_TYEPDEF_DEFAULT_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                     \
    a_chan_t    a;                            \
    logic [2:0] req;                          \
  } req_t;

`define RELOBI_TYEPDEF_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                     \
    a_chan_t    a;                            \
    logic [2:0] req;                          \
    logic [2:0] rready;                       \
  } req_t;

`define RELOBI_TYPEDEF_R_CHAN_T(r_chan_t, RDATA_WIDTH, ID_WIDTH, r_optional_t)     \
  typedef struct packed {                                                          \
    logic [       RDATA_WIDTH+hsiao_ecc_pkg::min_ecc(RDATA_WIDTH)-1:0] rdata;      \
    logic [                                              ID_WIDTH-1:0] rid;        \
    logic                                                              err;        \
    r_optional_t                                                       r_optional; \
    logic [hsiao_ecc_pkg::min_ecc(ID_WIDTH+1+$bits(r_optional_t))-1:0] other_ecc;  \
  } r_chan_t;

`define RELOBI_TYPEDEF_RSP_T(rsp_t, r_chan_t) \
  typedef struct packed {                     \
    r_chan_t    r;                            \
    logic [2:0] gnt;                          \
    logic [2:0] rvalid;                       \
  } rsp_t;

`define RELOBI_TYPEDEF_ALL(relobi_t, cfg)                                                                                                                           \
  `OBI_TYPEDEF_ALL_A_OPTIONAL(relobi_t``_a_optional_t, cfg.OptionalCfg.AUserWidth, cfg.OptionalCfg.WUserWidth, cfg.OptionalCfg.MidWidth, cfg.OptionalCfg.AChkWidth) \
  `RELOBI_TYPEDEF_A_CHAN_T(relobi_t``_a_chan_t, cfg.AddrWidth, cfg.DataWidth, cfg.IdWidth, relobi_t``_a_optional_t)                                                 \
  `RELOBI_TYEPDEF_REQ_T(relobi_t``_req_t, relobi_t``_a_chan_t)                                                                                                      \
  `OBI_TYPEDEF_ALL_R_OPTIONAL(relobi_t``_r_optional_t, cfg.OptionalCfg.RUserWidth, cfg.OptionalCfg.RChkWidth)                                                       \
  `RELOBI_TYPEDEF_R_CHAN_T(relobi_t``_r_chan_t, cfg.DataWidth, cfg.IdWidth, relobi_t``_r_optional_t)                                                                \
  `RELOBI_TYPEDEF_RSP_T(relobi_t``_rsp_t, relobi_t``_r_chan_t)

`endif // OBI_TYPEDEF_SVH
