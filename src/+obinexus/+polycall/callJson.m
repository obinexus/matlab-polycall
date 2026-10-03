function outJson = callJson(endpoint, service, operation, inputJson, timeoutMs)
%CALLJSON polycall_call() with JSON text in and out ('' input = null).
%   The output JSON crosses the MEX boundary as UTF-8 bytes and is decoded
%   here, so non-ASCII text survives whatever the default encoding is.
if nargin < 4
    inputJson = '';
end
if nargin < 5
    timeoutMs = 5000;
end
bytes = matlab_polycall_mex('call', ...
    obinexus.polycall.textArg(endpoint, "endpoint"), ...
    obinexus.polycall.textArg(service, "service"), ...
    obinexus.polycall.textArg(operation, "operation"), ...
    obinexus.polycall.textArg(inputJson, "inputJson"), double(timeoutMs));
outJson = native2unicode(bytes, 'UTF-8');
end
