# MATLAB adapter

Three layers, none of which parses configuration or implements runtime policy:

- `+obinexus/+polycall/*.m` — the MATLAB API; argument normalisation, JSON
  encode/decode, UTF-8 decoding of results (`native2unicode`).
- `matlab_polycall_mex.c` — the MEX gateway; mxArray conversion only
  (UTF-8 in, uint8 UTF-8 out for free text), MException identifiers
  `polycall:E_<NAME>`, `mexLock` while peers are open.
- `matlab_polycall.c` — the C layer over `<polycall.h>`; buffer sizing and
  growth, error text from `polycall_strerror` + `polycall_last_error`. It is
  what `tests/matlab_polycall_core_test.c` exercises without MATLAB.

The documented entry point is unchanged:

    obinexus.polycall.runConfig(path) == polycall_ffi_run_config(path, /*run=*/1)
