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

package obi_pkg;
  
  typedef logic [5:0] atop_t;

  typedef logic [1:0] memtype_t;

  typedef logic [2:0] prot_t;

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

endpackage
