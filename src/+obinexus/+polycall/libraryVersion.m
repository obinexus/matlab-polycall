function v = libraryVersion()
%LIBRARYVERSION Version string of the loaded libpolycall (e.g. '1.1.0').
v = matlab_polycall_mex('version');
end
