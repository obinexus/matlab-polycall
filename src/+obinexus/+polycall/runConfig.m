function status = runConfig(configPath, strict)
%RUNCONFIG Validate a Polycall configuration file and return its status.
%   STATUS = obinexus.polycall.runConfig(CONFIGPATH) calls
%   polycall_ffi_run_config(CONFIGPATH, 1) in libpolycall and returns the
%   status unchanged as int32 (0 = POLYCALL_OK, negative = POLYCALL_E_*).
%   STRICT = false validates instead (unknown keys are warnings).
%   Omitting the path uses "matlab-polycallrc".

if nargin < 1
    configPath = "matlab-polycallrc";
end
if nargin < 2
    strict = true;
end
configPath = obinexus.polycall.textArg(configPath, "configPath");
status = matlab_polycall_mex('run_config', configPath, double(logical(strict)));
end
