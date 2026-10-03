% test_matlab_polycall -- script-based tests of the MATLAB API against the
% REAL libpolycall (no mocks).
%   MATLAB:  runtests('tests/test_matlab_polycall.m')   (each %% section is a test)
%   Octave:  source('tests/test_matlab_polycall.m')     (compatibility run only;
%            it is never MATLAB evidence)
% Run through tests/run_core_test.sh, which starts `polycall start` and a
% `polycall peer serve --print-messages` node and exports
% MATLAB_POLYCALL_RUNTIME, MATLAB_POLYCALL_PEER, MATLAB_POLYCALL_SCRATCH,
% MATLAB_POLYCALL_ROOT, POLYCALL_DEV_TOKEN and POLYCALL_CLI; the runner then
% checks that every ml2c-*.bin payload reached the C node exactly once.
%
% Not expressible in MATLAB code, which runs MEX calls on its single
% interpreter thread (covered by tests/matlab_polycall_core_test.c instead):
% cancel()/close() waking a recv blocked on another thread, and concurrent
% senders.
root = getenv('MATLAB_POLYCALL_ROOT');
if isempty(root)
    root = fileparts(fileparts(mfilename('fullpath')));
end
addpath(fullfile(root, 'tests'));
rt = getenv('MATLAB_POLYCALL_RUNTIME');
peerEp = getenv('MATLAB_POLYCALL_PEER');
scratch = getenv('MATLAB_POLYCALL_SCRATCH');
token = getenv('POLYCALL_DEV_TOKEN');
cli = getenv('POLYCALL_CLI');
isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
errid = @polycall_error_id;

%% ABI and library version
assert(obinexus.polycall.abiVersion() == 1);
assert(strcmp(obinexus.polycall.libraryVersion(), '1.1.0'));
assert(strcmp(obinexus.polycall.strerror(-4), 'POLYCALL_E_TIMEOUT: deadline exceeded'));
assert(strncmp(obinexus.polycall.strerror(-999), 'POLYCALL_E_UNKNOWN', 18));
assert(strcmp(errid(@() matlab_polycall_mex('no_such_command')), 'polycall:E_INVALID_ARGUMENT'));

%% runConfig returns the core status unchanged
rc = fullfile(root, 'matlab-polycallrc');
assert(isequal(obinexus.polycall.runConfig(rc), int32(0)));
assert(isequal(obinexus.polycall.runConfig(fullfile(root, 'examples', 'matlab-polycallrc')), int32(0)));
if ~isOctave
    assert(isequal(obinexus.polycall.runConfig(string(rc)), int32(0)));   % string scalar
end
missing = fullfile(scratch, 'no-such-polycallrc');
assert(isequal(obinexus.polycall.runConfig(missing), int32(-7)));
assert(isequal(obinexus.polycall.runConfig(''), int32(-1)));
bad = fullfile(scratch, 'bad-polycallrc');
fid = fopen(bad, 'w'); fprintf(fid, 'max_connections=lots\n'); fclose(fid);
assert(isequal(obinexus.polycall.runConfig(bad), int32(-13)));
unk = fullfile(scratch, 'unknown-polycallrc');
fid = fopen(unk, 'w'); fprintf(fid, 'log_level=info\nmystery_key=1\n'); fclose(fid);
assert(isequal(obinexus.polycall.runConfig(unk), int32(-13)));          % strict: unknown key is an error
assert(isequal(obinexus.polycall.runConfig(unk, false), int32(0)));     % validate: a warning
tls = fullfile(scratch, 'tls-polycallrc');
fid = fopen(tls, 'w'); fprintf(fid, 'tls_enabled=true\ncert_file=/c.pem\nkey_file=/k.pem\n'); fclose(fid);
assert(isequal(obinexus.polycall.runConfig(tls), int32(-15)));          % refused, never plaintext
assert(isequal(obinexus.polycall.runConfig(tls, false), int32(0)));
assert(strcmp(errid(@() obinexus.polycall.runConfig(42)), 'OBINexus:Polycall:ConfigType'));
msg = '';
try
    obinexus.polycall.runConfigOrError(missing);
catch err
    assert(strcmp(err.identifier, 'OBINexus:Polycall:CoreFailure'));
    msg = err.message;
end
assert(~isempty(strfind(msg, 'POLYCALL_E_NOT_FOUND')) && ~isempty(strfind(msg, missing)));
msg = '';
try
    obinexus.polycall.runConfigOrError(bad);
catch err
    msg = err.message;
end
assert(~isempty(strfind(msg, '(-13)')) || ~isempty(strfind(msg, 'status -13')));
assert(~isempty(strfind(msg, 'max_connections')));                     % the polycall_last_error detail
obinexus.polycall.runConfigOrError(rc);                                 % valid: no error

%% non-ASCII (UTF-8) config path
d = fullfile(scratch, 'ünïcødé-конфиг-設定');
mkdir(d);
p = fullfile(d, 'matlab-polycallrc-ß');
copyfile(fullfile(root, 'matlab-polycallrc'), p);
assert(isequal(obinexus.polycall.runConfig(p), int32(0)));
info = obinexus.polycall.describe(p);
assert(strcmp(info.values.max_connections, '1000'));
assert(isequal(obinexus.polycall.runConfig(fullfile(d, 'fehlt-ü')), int32(-7)));

%% describe
info = obinexus.polycall.describe(fullfile(root, 'matlab-polycallrc'));
assert(strcmp(info.layer, 'runtime') && strcmp(info.values.log_level, 'info'));
pf = fullfile(scratch, 'Polycallfile');
fid = fopen(pf, 'w'); fprintf(fid, 'server node 8080:8084\npeer_node_id=alpha\npeer beta 127.0.0.1:9002\n'); fclose(fid);
info = obinexus.polycall.describe(pf);
assert(strcmp(info.layer, 'project') && strcmp(info.peers.beta, '127.0.0.1:9002'));
assert(strcmp(errid(@() obinexus.polycall.describe(fullfile(scratch, 'none'))), 'polycall:E_NOT_FOUND'));

%% call against polycall start
out = obinexus.polycall.call(rt, 'inventory', 'get', struct('item_id', 'widget-a'));
assert(strcmp(out.item_id, 'widget-a') && out.quantity == 42 && out.in_stock);
out = obinexus.polycall.call(rt, 'debug', 'echo');                     % [] -> JSON null
assert(isempty(out.echo));
assert(strcmp(obinexus.polycall.callJson(rt, 'debug', 'echo', '[1,"x"]'), '{"echo":[1,"x"]}'));
txt = 'héllo — 世界';                                                    % UTF-8 both ways
assert(strcmp(obinexus.polycall.callJson(rt, 'debug', 'echo', ['{"t":"' txt '"}']), ['{"echo":{"t":"' txt '"}}']));
assert(strcmp(obinexus.polycall.callJson(rt, 'debug', 'echo', '1', 600000), '{"echo":1}'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'nope', 'op', '{}')), 'polycall:E_NOT_FOUND'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'debug', 'sleep', '{"ms":2000}', 300)), 'polycall:E_TIMEOUT'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'inventory', 'get', '{}')), 'polycall:E_REMOTE'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'debug', 'echo', '{bad')), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'debug', 'echo', '1', 0)), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'debug', 'echo', '1', 600001)), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() obinexus.polycall.callJson(rt, 'debug', 'echo', '1', -1)), 'polycall:E_INVALID_ARGUMENT'));
probe = obinexus.polycall.Peer('matlab-probe', '127.0.0.1:0');
free = probe.endpoint();
probe.close();
assert(strcmp(errid(@() obinexus.polycall.callJson(free, 'debug', 'echo', '1', 2000)), 'polycall:E_TRANSPORT'));
msg = '';
try
    obinexus.polycall.callJson(rt, 'nope', 'op', '{}');
catch err
    msg = err.message;
end
assert(~isempty(strfind(msg, '(-7)')) && ~isempty(strfind(msg, 'operation.unknown')));

%% two peer nodes exchange exact bytes both ways
a = obinexus.polycall.Peer('matlab-a', '127.0.0.1:0', token);
b = obinexus.polycall.Peer('matlab-b', '127.0.0.1:0', token);
a.register('matlab-b', b.endpoint());
b.register('matlab-a', a.endpoint());
a.ping('matlab-b');
names = {'empty', 'utf8', 'binNul', 'mib'};
payloads = {zeros(1, 0, 'uint8'), unicode2native('héllo wörld — 漢字', 'UTF-8'), ...
            uint8([0 0 10 13 0 0:255 0]), uint8(mod((0:1048575) * 31 + 7, 256))};
for k = 1:numel(payloads)
    a.send('matlab-b', payloads{k}, ['a2b-' names{k}], 10000);
    [from, id, bytes] = b.recv(10000);
    assert(strcmp(from, 'matlab-a') && strcmp(id, ['a2b-' names{k}]) && isequal(reshape(bytes, 1, []), payloads{k}));
    b.send('matlab-a', payloads{k}, ['b2a-' names{k}], 10000);
    [from, id, bytes] = a.recv(10000);
    assert(strcmp(from, 'matlab-b') && strcmp(id, ['b2a-' names{k}]) && isequal(reshape(bytes, 1, []), payloads{k}));
end
a.send('matlab-b', 'héllo', 'a2b-char');                                % char -> its UTF-8 bytes
[~, ~, bytes] = b.recv(5000);
assert(isequal(reshape(bytes, 1, []), unicode2native('héllo', 'UTF-8')));
assert(strcmp(errid(@() a.send('matlab-b', zeros(1, 1048577, 'uint8'), 'too-big')), 'polycall:E_TOO_LARGE'));
assert(strcmp(errid(@() b.recv(100)), 'polycall:E_TIMEOUT'));
assert(strcmp(errid(@() b.recv(0)), 'polycall:E_TIMEOUT'));            % poll
assert(strcmp(errid(@() b.recv(-1)), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() b.recv(1.5)), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() a.send('matlab-b', 1:3, 'dbl')), 'polycall:E_INVALID_ARGUMENT'));   % double payload
a.send('matlab-b', 'x', repmat('i', 1, 63));                           % 63-byte id is the maximum
[~, id] = b.recv(5000);
assert(strcmp(id, repmat('i', 1, 63)));
assert(strcmp(errid(@() a.send('matlab-b', 'x', repmat('i', 1, 64))), 'polycall:E_INVALID_ARGUMENT'));
a.send('matlab-b', 'max', 'm-inf');                                     % Inf = wait for a message
[~, id] = b.recv(Inf);
assert(strcmp(id, 'm-inf'));
a.close();
b.close();

%% registry ownership, duplicates, auth, dead peer, wrong identity
a = obinexus.polycall.Peer('matlab-reg-a', '127.0.0.1:0', token);
b = obinexus.polycall.Peer('matlab-reg-b', '127.0.0.1:0', token);
epb = b.endpoint();
assert(strcmp(a.list(), '{}'));
a.register('matlab-reg-b', epb);
assert(strcmp(a.list(), ['{"matlab-reg-b":"' epb '"}']));
c = obinexus.polycall.Peer('matlab-reg-c', '', token);                   % send-only node
assert(strcmp(c.endpoint(), ''));
c.send(epb, 'hi', 'from-c');
[from, id] = b.recv(5000);
assert(strcmp(from, 'matlab-reg-c') && strcmp(id, 'from-c'));
assert(strcmp(b.list(), '{}'));                                         % receiving never registers the sender
assert(strcmp(errid(@() a.send('nobody', 'x')), 'polycall:E_NOT_FOUND'));
assert(strcmp(errid(@() a.unregister('nobody')), 'polycall:E_NOT_FOUND'));
assert(strcmp(errid(@() a.register('bad id', epb)), 'polycall:E_INVALID_ARGUMENT'));
a.send('matlab-reg-b', 'once', 'dup-1');
a.send('matlab-reg-b', 'once', 'dup-1');                                % acknowledged again, stored once
[~, id] = b.recv(5000);
assert(strcmp(id, 'dup-1'));
assert(strcmp(errid(@() b.recv(300)), 'polycall:E_TIMEOUT'));
assert(~isempty(strfind(b.health(), '"duplicates":1')));
wrong = obinexus.polycall.Peer('matlab-mallory', '', 'not-the-token');
anon = obinexus.polycall.Peer('matlab-anon');
assert(strcmp(errid(@() wrong.send(epb, 'x')), 'polycall:E_AUTH'));
assert(strcmp(errid(@() anon.send(epb, 'x')), 'polycall:E_AUTH'));
assert(strcmp(errid(@() b.recv(300)), 'polycall:E_TIMEOUT'));           % nothing was queued
dead = obinexus.polycall.Peer('matlab-dead', '127.0.0.1:0', token);
epd = dead.endpoint();
dead.close();
assert(strcmp(errid(@() a.send(epd, 'void', '', 2000)), 'polycall:E_TRANSPORT'));
assert(strcmp(errid(@() a.ping(epd, 1000)), 'polycall:E_TRANSPORT'));
a.register('impostor', epb);                                            % answers under another id
assert(strcmp(errid(@() a.ping('impostor', 2000)), 'polycall:E_PROTOCOL'));
a.unregister('impostor');
a.unregister('matlab-reg-b');
assert(strcmp(a.list(), '{}'));
a.close(); b.close(); c.close(); wrong.close(); anon.close();

%% close, double close, calls after close, invalid handles, cancel, MEX lock
n0 = matlab_polycall_mex('open_peers');
p = obinexus.polycall.Peer('matlab-life', '127.0.0.1:0', token);
assert(p.isOpen() && matlab_polycall_mex('open_peers') == n0 + 1);
assert(mislocked('matlab_polycall_mex'));                               % cannot be unloaded under the core's threads
ep = p.endpoint();
p.cancel();                                                             % nobody blocked: later calls wait normally
assert(strcmp(errid(@() p.recv(100)), 'polycall:E_TIMEOUT'));
clear matlab_polycall_mex                                               % would unload an unlocked MEX file
if ~isOctave
    clear mex
end
assert(matlab_polycall_mex('open_peers') == n0 + 1);                    % not unloaded: its state survived
assert(strcmp(p.nodeId(), 'matlab-life'));
p.close();
assert(~p.isOpen() && matlab_polycall_mex('open_peers') == n0);
if n0 == 0
    assert(~mislocked('matlab_polycall_mex'));
end
assert(strcmp(errid(@() p.close()), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() p.send(ep, 'x')), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() p.recv(0)), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() p.endpoint()), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() p.list()), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() p.cancel()), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() matlab_polycall_mex('peer_close', 0)), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() matlab_polycall_mex('peer_close', 123456)), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() matlab_polycall_mex('peer_close', 1.5)), 'polycall:E_INVALID_HANDLE'));
assert(strcmp(errid(@() obinexus.polycall.Peer('bad id!')), 'polycall:E_INVALID_ARGUMENT'));
assert(strcmp(errid(@() obinexus.polycall.Peer('x', '0.0.0.0:0')), 'polycall:E_CONFIG'));   % non-loopback, no token
q = obinexus.polycall.Peer('matlab-deleted', '127.0.0.1:0');
epq = q.endpoint();
delete(q);                                                              % deleting an open Peer closes it
probe = obinexus.polycall.Peer('matlab-probe2');
assert(strcmp(errid(@() probe.ping(epq, 1000)), 'polycall:E_TRANSPORT'));
probe.close();

%% interop with polycall peer serve and polycall peer send (the C CLI)
a = obinexus.polycall.Peer('matlab-a', '127.0.0.1:0', token);
a.register('c-printer', peerEp);
a.ping('c-printer');
names = {'mapi', 'mapi-empty', 'mapi-utf8'};
payloads = {uint8([104 195 169 0 1 2 255]), zeros(1, 0, 'uint8'), unicode2native('Grüße — 世界', 'UTF-8')};
for k = 1:numel(payloads)
    f = fullfile(scratch, ['ml2c-' names{k} '.bin']);
    fid = fopen(f, 'wb'); fwrite(fid, payloads{k}, 'uint8'); fclose(fid);
    a.send('c-printer', payloads{k}, ['ml2c-' names{k}]);              % the runner checks what the C node printed
    cmd = sprintf('"%s" peer send --to %s --payload-file "%s" --from cli-sender --id c2ml-%s', ...
        cli, a.endpoint(), f, names{k});
    if ispc
        cmd = ['"' cmd '"'];                                            % cmd.exe strips one outer pair of quotes
    end
    assert(system(cmd) == 0);
    [from, id, bytes] = a.recv(5000);
    assert(strcmp(from, 'cli-sender') && strcmp(id, ['c2ml-' names{k}]) && isequal(reshape(bytes, 1, []), payloads{k}));
end
a.close();
disp('test_matlab_polycall: all sections passed');
