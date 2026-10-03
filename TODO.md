# TODO — matlab-polycall

Status: MATLAB binding over the Polycall binding ABI v1 (polycall >= 1.1.0):
MEX gateway + C layer over `<polycall.h>` + the `+obinexus/+polycall` package.

- [x] C layer and MEX gateway: runConfig, runConfigOrError, describe, call, callJson, Peer
- [x] UTF-8 in and out; MEX file locked while peers are open; immediate binding against old libraries
- [x] C-layer tests against the real core (Linux; Windows MSVC and UCRT64), valgrind, ASan + UBSan, helgrind
- [x] GNU Octave compatibility run of the gateway, the M tests and the loader tests (not MATLAB evidence)
- [ ] Run `make test-matlab` and `make test-loader-matlab` in MATLAB (QA had no MATLAB licence)
- [ ] Windows MATLAB run (`build_matlab_polycall("<prefix>")`, then the MATLAB tests)
- [ ] Publish the npm source package / signed MEX binaries (not done by QA)

Do not add configuration parsing or runtime policy here; adapt the core only.
