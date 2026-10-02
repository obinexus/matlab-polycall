% test_matlab_polycall -- script-based tests of the MATLAB API against the
% REAL libpolycall. MATLAB: runtests('tests/test_matlab_polycall.m'); GNU
% Octave runs the same file as a plain script (Octave compatibility only).
% Run through tests/run_core_test.sh, which starts `polycall start` and a
% `polycall peer serve --print-messages` node and exports
% MATLAB_POLYCALL_RUNTIME, MATLAB_POLYCALL_PEER, MATLAB_POLYCALL_SCRATCH,
% POLYCALL_DEV_TOKEN and POLYCALL_CLI.
rt = getenv('MATLAB_POLYCALL_RUNTIME');
peerEp = getenv('MATLAB_POLYCALL_PEER');
scratch = getenv('MATLAB_POLYCALL_SCRATCH');
token = getenv('POLYCALL_DEV_TOKEN');
cli = getenv('POLYCALL_CLI');

%% ABI and library version
assert(obinexus.polycall.abiVersion() == 1);
v = obinexus.polycall.libraryVersion();
assert(ischar(v) && strncmp(v, '1.', 2));
assert(strcmp(obinexus.polycall.strerror(-4), 'POLYCALL_E_TIMEOUT: deadline exceeded'));

%% runConfig returns the core status unchanged
assert(isequal(obinexus.polycall.runConfig('matlab-polycallrc'), int32(0)));
assert(isequal(obinexus.polycall.runConfig("matlab-polycallrc"), int32(0)));
assert(isequal(obinexus.polycall.runConfig('no-such-polycallrc'), int32(-7)));
f = fullfile(scratch, 'tls-polycallrc');
fid = fopen(f, 'w'); fprintf(fid, 'tls_enabled=true\ncert_file=/c.pem\nkey_file=/k.pem\n'); fclose(fid);
assert(isequal(obinexus.polycall.runConfig(f), int32(-15)));
assert(isequal(obinexus.polycall.runConfig(f, false), int32(0)));
raised = false;
try
    obinexus.polycall.runConfigOrError('no-such-polycallrc');
catch err
    raised = strcmp(err.identifier, 'OBINexus:Polycall:CoreFailure') && ~isempty(strfind(err.message, 'POLYCALL_E_NOT_FOUND'));
end
assert(raised);

%% call against polycall start
out = obinexus.polycall.call(rt, 'inventory', 'get', struct('item_id', 'widget-a'));
assert(strcmp(out.item_id, 'widget-a') && out.quantity == 42 && out.in_stock);
assert(strcmp(obinexus.polycall.callJson(rt, 'debug', 'echo', '[1,"x"]'), '{"echo":[1,"x"]}'));
ids = {};
cases = {{'nope', 'op', '{}'}, {'debug', 'sleep', '{"ms":2000}'}, {'inventory', 'get', '{}'}};
for k = 1:numel(cases)
    c = cases{k};
    try
        obinexus.polycall.callJson(rt, c{1}, c{2}, c{3}, 300);
        ids{end + 1} = 'no error'; %#ok<AGROW>
    catch err
        ids{end + 1} = err.identifier; %#ok<AGROW>
    end
end
assert(isequal(ids, {'polycall:E_NOT_FOUND', 'polycall:E_TIMEOUT', 'polycall:E_REMOTE'}));

%% two peer nodes exchange exact bytes both ways
a = obinexus.polycall.Peer('matlab-a', '127.0.0.1:0', token);
b = obinexus.polycall.Peer('matlab-b', '127.0.0.1:0', token);
a.register('matlab-b', b.endpoint());
b.register('matlab-a', a.endpoint());
payload = uint8([0 1 2 0 255 10 13 0]);
a.send('matlab-b', payload, 'a2b-1');
[from, id, bytes] = b.recv(5000);
assert(strcmp(from, 'matlab-a') && strcmp(id, 'a2b-1') && isequal(bytes, payload));
big = uint8(mod((0:1048575) * 31 + 7, 256));
b.send('matlab-a', big, 'b2a-mib');
[from, id, bytes] = a.recv(5000);
assert(strcmp(from, 'matlab-b') && strcmp(id, 'b2a-mib') && isequal(bytes, big));
tooBig = '';
try
    a.send('matlab-b', zeros(1, 1048577, 'uint8'), 'too-big');
catch err
    tooBig = err.identifier;
end
assert(strcmp(tooBig, 'polycall:E_TOO_LARGE'));
timedOut = '';
try
    b.recv(100);
catch err
    timedOut = err.identifier;
end
assert(strcmp(timedOut, 'polycall:E_TIMEOUT'));
b.close();
closedId = '';
try
    b.close();
catch err
    closedId = err.identifier;
end
assert(strcmp(closedId, 'polycall:E_INVALID_HANDLE'));
a.close();

%% interop with polycall peer serve and polycall peer send (the C CLI)
a = obinexus.polycall.Peer('matlab-a', '127.0.0.1:0', token);
a.register('c-printer', peerEp);
a.ping('c-printer');
payload = uint8([104 195 169 0 1 2 255]);
fid = fopen(fullfile(scratch, 'ml2c-mapi.bin'), 'wb'); fwrite(fid, payload, 'uint8'); fclose(fid);
a.send('c-printer', payload, 'ml2c-mapi');   % the runner checks what the C node printed
cmd = sprintf('"%s" peer send --to %s --payload-file "%s" --from cli-sender --id c2ml-mapi', cli, a.endpoint(), ...
    fullfile(scratch, 'ml2c-mapi.bin'));
status = system(cmd);
assert(status == 0);
[from, id, bytes] = a.recv(5000);
assert(strcmp(from, 'cli-sender') && strcmp(id, 'c2ml-mapi') && isequal(bytes(:)', payload));
a.close();
disp('test_matlab_polycall: all sections passed');
