function runConfigOrError(configPath)
%RUNCONFIGORERROR Run a configuration and raise for a nonzero core status.
%   Raises OBINexus:Polycall:CoreFailure; the message names the status
%   (polycall_strerror) and the configuration path.

if nargin == 0
    configPath = "matlab-polycallrc";
end

status = obinexus.polycall.runConfig(configPath);
if status ~= 0
    error("OBINexus:Polycall:CoreFailure", ...
        "libpolycall failed with status %d (%s) for config '%s'.", ...
        status, obinexus.polycall.strerror(status), char(configPath));
end
end
