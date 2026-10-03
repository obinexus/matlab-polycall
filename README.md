# @obinexusltd/matlab-polycall

MATLAB binding for the [Polycall](https://github.com/obinexus/polycall) C
library, **binding ABI v1** (`polycall >= 1.1.0`): a MEX gateway
(`src/matlab_polycall_mex.c`) over a small C layer (`src/matlab_polycall.c`)
that calls `<polycall.h>` directly, and the MATLAB package
`+obinexus/+polycall`.

Configuration parsing, validation, networking and runtime policy stay in
libpolycall; this binding converts MATLAB values, sizes buffers and turns
status codes into MATLAB errors. npm source package:
`@obinexusltd/matlab-polycall` (not published yet). It ships sources only —
build the MEX file for your MATLAB and platform.

> **Test status.** The MATLAB tests have **not** been run: QA had no MATLAB
> licence. The C layer is tested against the real library on Linux, Windows
> MSVC and Windows UCRT64, and the gateway and M files are exercised in GNU
> Octave as compatibility evidence only. See [tests/TESTS.md](tests/TESTS.md).

## Requirements

- MATLAB R2020b or newer, with a C compiler configured by `mex -setup C`
- an installed libpolycall >= 1.1.0 (headers, import library or `.so`, and the
  shared library at run time)
- for the standalone C-layer tests: GNU Make, a C11 compiler, `pkg-config`

## Build the MEX gateway

From MATLAB, pass the libpolycall install prefix (it must contain
`include/polycall/polycall.h` and `lib/`):

```matlab
build_matlab_polycall("C:\polycall")     % MSVC: polycall.lib, MinGW: libpolycall.dll.a
build_matlab_polycall("/opt/polycall")   % Linux: libpolycall.so
addpath("src"); addpath("lib")
```

or from a shell, with `PKG_CONFIG_PATH=<prefix>/lib/pkgconfig`:

```shell
make mex
```

At run time MATLAB must find the shared library: `polycall.dll` /
`libpolycall.dll` on `PATH` (Windows), `libpolycall.so.1` on
`LD_LIBRARY_PATH` or the system library path (Linux). On Linux and macOS the
gateway is linked with immediate binding (`-Wl,-z,now` / `-bind_at_load`), so
an old 1.0 library without the ABI v1 symbols is refused when the MEX file
loads ("undefined symbol: polycall_..."); a library reporting another binding
ABI raises `polycall:E_UNSUPPORTED` on the first call.

## API

```matlab
obinexus.polycall.abiVersion()          % 1
obinexus.polycall.libraryVersion()      % '1.1.0'
obinexus.polycall.strerror(-4)          % 'POLYCALL_E_TIMEOUT: deadline exceeded'

% configuration: polycall_ffi_run_config(path, 1); status returned unchanged (int32)
status = obinexus.polycall.runConfig("matlab-polycallrc");
status = obinexus.polycall.runConfig("matlab-polycallrc", false);   % validate only
obinexus.polycall.runConfigOrError("matlab-polycallrc");           % raises on failure
info = obinexus.polycall.describe("Polycallfile");                 % decoded JSON struct

% one RPC round trip to `polycall start` / `polycall daemon start` (never retried)
out = obinexus.polycall.call("127.0.0.1:8084", "inventory", "get", struct("item_id", "widget-a"));
json = obinexus.polycall.callJson(endpoint, "debug", "echo", '[1,"x"]', 5000);

% peers (each node owns its registry and inbox)
a = obinexus.polycall.Peer("alpha", "127.0.0.1:0", token);   % bind "" = send-only node
b = obinexus.polycall.Peer("beta", "127.0.0.1:0", token);
a.register("beta", b.endpoint());
a.send("beta", uint8([0 1 2 0 255]), "m-1");    % uint8/int8 bytes, or text (sent as UTF-8)
[from, id, bytes] = b.recv(5000);               % Inf waits until a message arrives
a.close(); b.close();
```

`Peer` also has `nodeId`, `unregister`, `list` (registry JSON), `health`
(JSON), `ping`, `cancel` and `isOpen`; deleting an open `Peer` closes it.

**Errors.** Failures raise an MException whose identifier names the status
(`polycall:E_TIMEOUT`, `polycall:E_INVALID_HANDLE`, ...) and whose message
carries the code, the `polycall_strerror` text and the `polycall_last_error`
detail, e.g. `POLYCALL_E_NOT_FOUND (-7): not found -- <detail>`; a failed
`call` appends the remote error object. `runConfig` returns the
status instead (the documented contract); `runConfigOrError` raises
`OBINexus:Polycall:CoreFailure` with the status, its name, the path and the
detail. Calls after `close`, a second `close` and forged handles raise
`polycall:E_INVALID_HANDLE`.

**Text** crosses as UTF-8 in both directions (paths, JSON, payloads given as
text); JSON results come back from the gateway as UTF-8 bytes and are decoded
with `native2unicode`, so non-ASCII text survives any default encoding.

**Threads.** MATLAB runs MEX calls on its interpreter thread, so a `recv`
blocks MATLAB until a message arrives or the timeout expires; `cancel` wakes
receivers blocked on other (native) threads. While any `Peer` is open the
MEX file is locked (`mislocked("matlab_polycall_mex")`), so `clear mex` /
`clear all` cannot unload libpolycall under the core's listener threads.

## Tests

| Command | What runs | Evidence for |
| --- | --- | --- |
| `make test-matlab` | the MATLAB tests (`tests/test_matlab_polycall.m`) against the real library, `polycall start`, `polycall daemon` and a `polycall peer serve` C node | MATLAB (needs MATLAB; exit 77 = SKIP without it) |
| `make test-loader-matlab` | missing / 1.0 / ABI-2 library through the MEX file | MATLAB loader errors |
| `make test-core` | `tests/matlab_polycall_core_test.c`: the C layer against the real library (84 checks, incl. C CLI interop both ways, daemon, concurrency, cancel/close) | the C layer only |
| `make test-core-valgrind`, `test-core-asan`, `test-core-helgrind`, `test-core-tsan` | the same under memcheck, ASan + UBSan, helgrind, TSan | the C layer only |
| `make test-octave`, `test-loader-octave`, `test-octave-asan` | the same gateway and M tests in GNU Octave (`mkoctfile --mex`) | Octave compatibility only, never MATLAB |
| `npm test` | npm metadata, packaged files, thin-adapter audit | the npm package |

All runners start their own `polycall` processes on ephemeral `127.0.0.1`
ports (`POLYCALL_CLI` or `polycall` on `PATH`) and need
`PKG_CONFIG_PATH=<prefix>/lib/pkgconfig`.

## Package layout

- `src/+obinexus/+polycall/` — MATLAB package API
- `src/matlab_polycall_mex.c` — MEX gateway (MATLAB `mex -R2018a`, Octave `mkoctfile --mex`)
- `src/matlab_polycall.c`, `include/matlab_polycall.h` — C layer over `<polycall.h>`
- `build_matlab_polycall.m` — MATLAB build function
- `examples/`, `tests/` — usage and verification

## Author and license

Copyright © 2026 Nnamdi Michael Okpala
<okpalan@protonmail.com>.

Released under the [MIT License](LICENSE).
