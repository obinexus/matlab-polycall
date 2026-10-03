function id = polycall_error_id(f)
%POLYCALL_ERROR_ID Identifier of the error f() raises, or 'no error'.
%   Test helper for tests/test_matlab_polycall.m (a function file, because
%   MATLAB wants script-local functions at the end of a script and GNU
%   Octave before their first use).
try
    f();
    id = 'no error';
catch err
    id = err.identifier;
end
end
