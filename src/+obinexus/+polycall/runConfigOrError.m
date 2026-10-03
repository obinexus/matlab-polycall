function runConfigOrError(configPath)
%RUNCONFIGORERROR Validate a configuration for running; raise on failure.
%   Calls polycall_ffi_run_config(CONFIGPATH, 1) and raises
%   OBINexus:Polycall:CoreFailure for a nonzero status. The message carries
%   the status code, its polycall_strerror name, the configuration path and
%   the polycall_last_error detail (read right after the call).
%   Omitting the path uses "matlab-polycallrc".

if nargin == 0
    configPath = "matlab-polycallrc";
end
configPath = obinexus.polycall.textArg(configPath, "configPath");
[status, detail] = matlab_polycall_mex('run_config', configPath, 1);
if status ~= 0
    error("OBINexus:Polycall:CoreFailure", ...
        "libpolycall failed with status %d (%s) for config '%s': %s", ...
        status, obinexus.polycall.strerror(status), configPath, native2unicode(detail, 'UTF-8'));
end
end
