function status = runConfig(configPath)
%RUNCONFIG Run a libpolycall configuration and return its status.

if nargin == 0
    configPath = "matlab-polycallrc";
end

if isstring(configPath)
    if ~isscalar(configPath)
        error("OBINexus:Polycall:ConfigType", ...
            "The configuration path must be a string scalar.");
    end
    configPath = char(configPath);
elseif ischar(configPath)
    if size(configPath, 1) ~= 1
        error("OBINexus:Polycall:ConfigType", ...
            "The configuration path must be a character row vector.");
    end
else
    error("OBINexus:Polycall:ConfigType", ...
        "The configuration path must be text.");
end

status = matlab_polycall_mex(configPath);
end
