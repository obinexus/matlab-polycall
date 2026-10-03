# matlab-polycall tests

Everything here runs against the REAL libpolycall (no mocks) and starts its
own `polycall start`, `polycall daemon start` and `polycall peer serve`
processes on ephemeral `127.0.0.1` ports (`tests/run_core_test.sh`).

| File | Runs in | Covers |
| --- | --- | --- |
| `test_matlab_polycall.m` | MATLAB (`make test-matlab`, `runtests`); GNU Octave as a script (`make test-octave`, compatibility only) | ABI/version; `runConfig` (valid, missing, empty, invalid, strict unknown key, TLS refused) and `runConfigOrError` with the `polycall_last_error` detail; non-ASCII config path; `describe`; `call`/`callJson` against `polycall start` (success, `[]` → null, UTF-8 round trip, timeout 600000/600001/0/-1, unknown operation, deadline, invalid input, invalid JSON, no runtime); two peers both ways with empty, UTF-8, binary-with-NUL and exactly 1 MiB payloads; 1 MiB + 1; receive timeout and poll; 63/64-byte ids; registry ownership; duplicate id delivered once; auth failure (wrong and missing token); dead peer; wrong identity; double close, calls after close, invalid handles; cancel semantics; the MEX lock while peers are open; `delete` closing a peer; interop with the C CLI both ways (`peer serve` checked byte-exact by the runner, `peer send` checked in MATLAB) |
| `matlab_polycall_core_test.c` | C (`make test-core`, also under valgrind, ASan + UBSan, helgrind, TSan) | the C layer the gateway uses, incl. what single-threaded MATLAB code cannot express: concurrent senders and calls, cancel and close waking a receive blocked on another thread; buffer growth at 64 KiB / 64 KiB + 1, 512-byte registry and 4096-byte describe; `call` against `polycall daemon start` |
| `run_loader_test.sh` | MATLAB (`make test-loader-matlab`) or Octave (`make test-loader-octave`) | missing library, an old 1.0 library (no ABI v1 symbols) and a library reporting ABI 2 give a clear, catchable error, never a crash (fake libraries from `fixtures/fake_polycall.c`) |
| `package.test.js` | Node (`npm test`) | npm metadata and packaged files |

Without MATLAB the MATLAB targets exit 77 (SKIP) — never success. C-layer and
Octave results are not MATLAB evidence.
