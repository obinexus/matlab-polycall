function runConfigOrError(configPath)
%RUNCONFIGORERROR Run a configuration and raise for a nonzero core status.

if nargin == 0
    configPath = "matlab-polycallrc";
end

status = obinexus.polycall.runConfig(configPath);
if status ~= 0
    error("OBINexus:Polycall:CoreFailure", ...
        "libpolycall failed with status %d for config '%s'.", ...
        status, string(configPath));
end
end
