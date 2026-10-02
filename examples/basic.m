% basic.m -- matlab-polycall tour (add src/ and lib/ to the path first).
configPath = "matlab-polycallrc";
obinexus.polycall.runConfigOrError(configPath);
fprintf("libpolycall %s (binding ABI %d) accepted '%s'\n", ...
    obinexus.polycall.libraryVersion(), obinexus.polycall.abiVersion(), configPath);

% call an operation on a running `polycall start` / `polycall daemon start`
% out = obinexus.polycall.call("127.0.0.1:8084", "inventory", "get", struct("item_id", "widget-a"));

% peer-to-peer: two nodes in this process
a = obinexus.polycall.Peer("alpha", "127.0.0.1:0");
b = obinexus.polycall.Peer("beta", "127.0.0.1:0");
a.register("beta", b.endpoint());
a.send("beta", uint8('hello from MATLAB'), "m-1");
[from, id, bytes] = b.recv(5000);
fprintf("%s sent %s: %s\n", from, id, char(bytes));
a.close();
b.close();
