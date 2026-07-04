# MATLAB adapter

The MATLAB package API is under `+obinexus/+polycall`. The MEX gateway converts
the configuration path to UTF-8 and calls `matlab_polycall_run_config`, whose
only operation is `polycall_ffi_run_config(config_path, 1)`.

No configuration parsing or runtime policy belongs in this binding.
