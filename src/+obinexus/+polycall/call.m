function out = call(endpoint, service, operation, input, timeoutMs)
%CALL One polycall_rpc v1 round trip to a running runtime / daemon.
%   OUT = obinexus.polycall.call(ENDPOINT, SERVICE, OPERATION, INPUT)
%   encodes INPUT with jsonencode ([] = JSON null; use callJson to pass
%   JSON text), calls polycall_call() and returns the decoded output. The
%   call is never retried. Failures raise MException 'polycall:E_<NAME>'
%   (E_NOT_FOUND for operation.unknown, E_TIMEOUT for deadline.exceeded,
%   E_REMOTE with the remote error JSON in the message).
if nargin < 4
    input = [];
end
if nargin < 5
    timeoutMs = 5000;
end
if isempty(input) && isnumeric(input)
    inputJson = 'null';
else
    inputJson = jsonencode(input);
end
out = jsondecode(obinexus.polycall.callJson(endpoint, service, operation, inputJson, timeoutMs));
end
