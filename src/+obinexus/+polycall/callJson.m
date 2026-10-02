function outJson = callJson(endpoint, service, operation, inputJson, timeoutMs)
%CALLJSON polycall_call() with JSON text in and out ('' input = null).
if nargin < 4
    inputJson = '';
end
if nargin < 5
    timeoutMs = 5000;
end
outJson = matlab_polycall_mex('call', ...
    obinexus.polycall.textArg(endpoint, "endpoint"), ...
    obinexus.polycall.textArg(service, "service"), ...
    obinexus.polycall.textArg(operation, "operation"), ...
    obinexus.polycall.textArg(inputJson, "inputJson"), double(timeoutMs));
end
