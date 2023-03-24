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

`ifndef OBI_TYPEDEF_SVH
`define OBI_TYPEDEF_SVH

`define OBI_TYPEDEF_A_CHAN_T(a_chan_t, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, a_optional_t) \
  typedef struct packed {                                                              \
    logic [  ADDR_WIDTH-1:0] addr;                                                     \
    logic                    we;                                                       \
    logic [DATA_WIDTH/8-1:0] be;                                                       \
    logic [  DATA_WIDTH-1:0] wdata;                                                    \
    logic [    ID_WIDTH-1:0] aid;                                                      \
    a_optional_t             optional;                                                 \
  } a_chan_t;

`define OBI_TYPEDEF_MINIMAL_A_OPTIONAL(a_optional_t) \
  typedef logic a_optional_t;

`define OBI_TYPEDEF_ATOP_A_OPTIONAL(a_optional_t) \
  typdef struct packed {
    obi_pkg::atop_t atop;
  } a_optional_t;

`define OBI_TYPEDEF_ALL_A_OPTIONAL(a_optional_t, AUSER_WIDTH, WUSER_WIDTH, ACHK_WIDTH) \
  typedef struct packed {                                                              \
    logic [ AUSER_WIDTH-1:0] auser;                                                    \
    logic [ WUSER_WIDTH-1:0] wuser;                                                    \
    obi_pkg::atop_t          atop;                                                     \
    obi_pkg::memtype_t       memtype;                                                  \
    obi_pkg::prot_t          prot;                                                     \
    logic                    dbg;                                                      \
    logic [  ACHK_WIDTH-1:0] achk;                                                     \
  } a_optional_t;

`define OBI_TYPEDEF_R_CHAN_T(r_chan_t, RDATA_WIDTH, ID_WIDTH, r_optional_t) \
  typedef struct packed {                                                   \
    logic [RDATA_WIDTH-1:0] rdata;                                          \
    logic [   ID_WIDTH-1:0] rid;                                            \
    r_optional_t            optional;                                       \
  } r_chan_t;

`define OBI_TYPEDEF_ALL_R_OPTIONAL(r_optional_t, RUSER_WIDTH, RCHK_WIDTH) \
  typedef struct packed {                                                                        \
    logic                   err;                                                                 \
    logic [RUSER_WIDTH-1:0] ruser;                                                               \
    logic                   exokay;                                                              \
    logic [ RCHK_WIDTH-1:0] rchk;                                                                \
  } r_optional_t;

`define OBI_TYPEDEF_DEFAULT_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                          \
    a_chan_t a;                                    \
    logic    req;                                  \
  } req_t;

`define OBI_TYPEDEF_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                          \
    a_chan_t a;                                    \
    logic    req;                                  \
    logic    rready;                               \
  } req_t;

`define OBI_TYPEDEF_RSP_T(rsp_t, r_chan_t) \
  typedef struct packed {                          \
    r_chan_t r;                                    \
    logic    gnt;                                  \
    logic    rvalid;                               \
  } rsp_t;

`define OBI_TYPEDEF_INTEGRITY_REQ_T(req_t, a_chan_t) \
  typedef struct packed {                  \
    a_chan_t a;                            \
    logic    req;                          \
    logic    rready;                       \
    logic    reqpar;                       \
    logic    rreadypar;                    \
  } req_t;

`define OBI_TYPEDEF_INTEGRITY_RSP_T(rsp_t, r_chan_t) \
  typedef struct packed {                  \
    r_chan_t r;                            \
    logic    gnt;                          \
    logic    gntpar;                       \
    logic    rvalid;                       \
    logic    rvalidpar;                    \
  } rsp_t;

`endif // OBI_TYPEDEF_SVH
