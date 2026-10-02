function abi = abiVersion()
%ABIVERSION Binding ABI version of the loaded libpolycall (must be 1).
%   The MEX gateway refuses to run against a library whose
%   polycall_ffi_abi_version() is not 1.
abi = matlab_polycall_mex('abi');
end
