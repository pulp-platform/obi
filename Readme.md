# OBI

The repository contains a collection of SystemVerilog IPs for the [OBI v1.6 standard](https://github.com/openhwgroup/obi/blob/072d9173c1f2d79471d6f2a10eae59ee387d4c6f/OBI-v1.6.0.pdf).

They are designed by PULP-platform and are available under the Solderpad v0.51 license (See [`LICENSE`](LICENSE)).

## Using the IPs
As the OBI protocol is very configurable, the IPs are designed to incorporate specific parameters for the design:

- `ObiCfg`: This specifies the configuration used for the OBI protocol being input or output from the link. A default config can be found in the `obi_pkg.sv`. This config should be aligned with the `req` and `rsp` structs.
- `obi_req_t`: The OBI request struct is designed to be generated with a macro available in the `include/obi/typedef.svh` include file and has fields for the handshake and a field for the *A* channel.
- `obi_rsp_t`: The OBI response struct is designed to be generated with a macro available in the `include/obi/typedef.svh` include file and has fields for the handshake and a filed for the *R* channel.

Most IPs will also support a SystemVerilog `interface` variant, also based on `ObiCfg`.

### Beat-framed burst extension
Beat-framed bursts are an optional extension and are disabled by default with
`BurstMode = obi_pkg::OBI_BURST_NONE`. This keeps the structures emitted by the existing
`OBI_TYPEDEF_ALL(...)` macro unchanged.

To enable the extension, instantiate burst-capable IPs with
`BurstMode = obi_pkg::OBI_BURST_BEAT_FRAMED` and use `OBI_TYPEDEF_ALL_BURST(...)` for the port
types. `BurstLenWidth` defaults to 8 and controls the width of the linear `blen = beats - 1`
field.

## Available IPs
- `obi_mux.sv`: A multiplexer IP for the OBI protocol.
- `obi_demux.sv`: A demultiplexer IP for the OBI protocol.
- `obi_xbar.sv`: A crossbar interconnect IP for the OBI protocol.
- `obi_err_sbr.sv`: A error subordinate, responding with the error bit set.
- `obi_sram_shim.sv`: An adapter for a standard sram.
- `obi_atop_resolver.sv`: An atomics filter, resolving atomic operations on an exclusive bus.
- `apb_to_obi.sv`: A protocol converter from APB to OBI.
- `obi_to_apb.sv`: A protocol converter from OBI to APB.

## License
Solderpad Hardware License, Version 0.51
