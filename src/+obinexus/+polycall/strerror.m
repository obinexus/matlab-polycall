function text = strerror(code)
%STRERROR polycall_strerror(): the static name of a status code.
text = matlab_polycall_mex('strerror', double(code));
end
