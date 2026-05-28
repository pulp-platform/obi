# OBI Beat-Framed Burst Extension

## Scope

- The extension is optional and disabled by default.
- Beat-framed bursts remain explicit per beat, so non-bursting components can still accept each
  request beat independently when they do not need the burst metadata.
- Only incremental bursts are supported.
- Beat size is fixed by the interface data width.

## Configuration

- Burst support is not part of `obi_cfg_t` or `obi_optional_cfg_t`, so existing configurations and
  generated non-burst optional structs remain unchanged.
- Modules use:
  - `BurstMode = obi_pkg::OBI_BURST_NONE` by default.
  - `BurstMode = obi_pkg::OBI_BURST_BEAT_FRAMED` to enable this extension.
  - `BurstLenWidth = 8` by default.
- `BurstLenWidth` is the width of the linear `blen` field, not the data width.
- Existing `OBI_TYPEDEF_ALL(...)` remains non-burst. Use `OBI_TYPEDEF_ALL_BURST(...)` for
  beat-framed burst ports.

## Interface Shape

### Request Phase

- `obi_req_i`: request valid.
- `obi_gnt_o`: request accepted.
- `obi_a_addr_i[ObiAddrWidth-1:0]`: byte address of the current beat.
- `obi_a_optional_blen_i[BurstLenWidth-1:0]`: burst length encoded as beats minus one.
- `obi_a_optional_bfirst_i`: burst beginning indicator.
- `obi_a_optional_blast_i`: burst termination indicator.

Request behavior:

- A request is accepted when `obi_req_i && obi_gnt_o`.
- The total number of beats in the burst is `obi_a_optional_blen_i + 1`.
- For both read and write bursts, `obi_a_optional_blen_i + 1` requests must be sent.
- All beats must be sequential and incrementing.
- `obi_a_addr_i` increments for every beat, making each beat a legal OBI request on its own.
- `obi_a_optional_blen_i` is valid on the first burst request and remains stable from advertising
  the first request until the last request is accepted.
- `obi_a_optional_bfirst_i` is `1` for the first request of a burst and zero otherwise.
- `obi_a_optional_blast_i` is `1` for the last request of a burst and zero otherwise.

### Response Phase

- `obi_rvalid_o`: response valid.
- `obi_rready_i`: response accepted, if `UseRReady` is enabled.

Response behavior:

- A response beat transfers when `obi_rvalid_o && obi_rready_i` if `UseRReady` is enabled, or when
  `obi_rvalid_o` if `UseRReady` is disabled.
- The target returns exactly one response for every accepted request beat.
- The response for a beat may only be sent after that beat's request was accepted.

## Signal Meaning

### Burst Length

- `obi_a_optional_blen_i = 0` means a single-beat burst.
- In general, burst beats = `obi_a_optional_blen_i + 1`.
- With the default `BurstLenWidth = 8`, the maximum burst is 256 beats.

### Beat Size

- There is no external size signal.
- Beat size is fixed by `ObiCfg.DataWidth`.
- Each beat transfers `ObiCfg.DataWidth / 8` bytes.

Examples:

- `ObiCfg.DataWidth = 16` -> 2 bytes per beat.
- `ObiCfg.DataWidth = 32` -> 4 bytes per beat.
- `ObiCfg.DataWidth = 64` -> 8 bytes per beat.

### Addressing

- `obi_a_addr_i` is the byte address of the current beat.
- Bursts are incremental only.
- Each successive beat advances by `ObiCfg.DataWidth / 8` bytes.

## Ordering Rules

- The intended usage is one burst in flight to a subordinate at a time.
- Interconnect elements lock routing on an accepted request with `obi_a_optional_bfirst_i`.
- Interconnect elements release routing on an accepted request with `obi_a_optional_blast_i`.
