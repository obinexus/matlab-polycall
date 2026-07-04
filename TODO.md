# TODO — matlab-polycall

Status: implemented thin MATLAB/MEX adapter for libpolycall 1.5.

- [x] Publishable `@obinexusltd/matlab-polycall` npm source package
- [x] MATLAB package namespace with status and exception APIs
- [x] UTF-8 MEX gateway with correct MATLAB memory ownership
- [x] Exact `polycall_ffi_run_config(config_path, 1)` forwarding
- [x] Portable MATLAB build function and shell Makefile
- [x] Native forwarding test and MATLAB unit tests
- [x] Thin-adapter source audit for Windows and POSIX shells
- [ ] Exercise the MEX test suite in MATLAB release CI
- [ ] Publish signed platform-specific MEX binaries

Do not add configuration parsing or runtime policy here; adapt the core only.
