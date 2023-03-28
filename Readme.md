# OBI

The repository contains a collection of SystemVerilog IPs for the [OBI v1.5 standard](https://github.com/openhwgroup/obi/blob/188c87089975a59c56338949f5c187c1f8841332/OBI-v1.5.0.pdf).

They are designed by PULP-platform and are available under the Solderpad v0.51 license (See LICENSE).

## Using the IPs
As the OBI protocol is very configurable, the IPs are designed to incorporate specific parameters for the design:

- `ObiCfg`: This specifies the configuration used for the OBI protocol being input or output from the link. A default config can be found in the `obi_pkg.sv`. This config should be aligned with the `req` and `rsp` structs.
- `obi_req_t`: The OBI request struct is designed to be generated with a macro available in the `include/obi/typedef.svh` include file and has fields for the handshake and a field for the *A* channel.
- `obi_rsp_t`: The OBI response struct is designed to be generated with a macro available in the `include/obi/typedef.svh` include file and has fields for the handshake and a filed for the *R* channel.

## Available IPs
- `obi_mux.sv`: A multiplexer IP for the OBI protocol.
- `obi_demux.sv`: A demultiplexer IP for the OBI protocol.
- `obi_xbar.sv`: A crossbar interconnect IP for the OBI protocol.

## License
Solderpad Hardware License, Version 0.51
