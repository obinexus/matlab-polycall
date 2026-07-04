# @obinexusltd/matlab-polycall

MATLAB MEX binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5. The adapter maps
MATLAB calls to the single core entry point:

```c
polycall_ffi_run_config(config_path, 1)
```

Configuration parsing, validation, networking, and runtime policy remain in
libpolycall. The MATLAB and MEX layers only validate the API shape, marshal the
UTF-8 configuration path, and return the core status unchanged.

## Install the source package

```shell
npm install @obinexusltd/matlab-polycall
```

The npm package publishes the complete MATLAB package namespace, MEX and C
sources, headers, build scripts, examples, and tests. Calling
`require('@obinexusltd/matlab-polycall')` returns absolute paths to those files.

## Requirements

- MATLAB R2020b or newer
- a compiler configured with `mex -setup C`
- libpolycall 1.5 import/static library and shared runtime library
- GNU Make and a C11 compiler for the standalone native tests

## Build the MEX gateway

From MATLAB, pass the libpolycall import or static library to the portable build
function:

```matlab
build_matlab_polycall("C:\path\to\polycall.lib")
```

On Linux or macOS, pass the corresponding library or linker arguments accepted
by `mex`. The compiled platform-specific MEX file is written under `lib/`.

You can also build from the shell:

```shell
export POLYCALL_LDFLAGS='-L/path/to/lib -lpolycall'
make mex
```

Add both the MATLAB source and MEX output directories:

```matlab
addpath("src")
addpath("lib")
```

## API

```matlab
status = obinexus.polycall.runConfig("matlab-polycallrc");
obinexus.polycall.runConfigOrError("matlab-polycallrc");
```

- `runConfig` returns the exact core status as a MATLAB `int32`.
- `runConfigOrError` raises `OBINexus:Polycall:CoreFailure` for non-zero status.
- Omitting the path uses `matlab-polycallrc`.
- String scalars and character row vectors are accepted.

See [`examples/basic.m`](examples/basic.m) for a runnable example.

## Verification

The default test suite does not require MATLAB:

```shell
npm test
```

It verifies exact path forwarding, the validation flag, status propagation,
MEX ownership rules, UTF-8 conversion, source constraints, and npm package
completeness.

With MATLAB and a configured MEX compiler, run the end-to-end suite:

```shell
npm run test:matlab
```

## Package layout

- `src/+obinexus/+polycall/` — MATLAB package API
- `src/matlab_polycall_mex.c` — MEX gateway
- `src/matlab_polycall.c` — native forwarding adapter
- `build_matlab_polycall.m` — portable MATLAB build function
- `include/` and `generated/polycall/` — C declarations
- `examples/` and `tests/` — usage and verification

## Author and license

Copyright © 2026 Nnamdi Michael Okpala
<okpalan@protonmail.com>.

Released under the [MIT License](LICENSE).
