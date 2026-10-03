function info = describe(configPath)
%DESCRIBE Decoded polycall_ffi_describe() JSON of a configuration file.
%   INFO has the fields layer, network, servers, peers, values and
%   warnings; secrets are never resolved.
configPath = obinexus.polycall.textArg(configPath, "configPath");
info = jsondecode(native2unicode(matlab_polycall_mex('describe', configPath), 'UTF-8'));
end
