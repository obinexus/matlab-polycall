function info = describe(configPath)
%DESCRIBE Decoded polycall_ffi_describe() JSON of a configuration file.
configPath = obinexus.polycall.textArg(configPath, "configPath");
info = jsondecode(matlab_polycall_mex('describe', configPath));
end
