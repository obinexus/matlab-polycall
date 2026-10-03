classdef Peer < handle
    %PEER A Polycall peer node (polycall_peer_* over the binding ABI v1).
    %   p = obinexus.polycall.Peer("alpha", "127.0.0.1:0", token)
    %   p.register("beta", "127.0.0.1:9002");
    %   p.send("beta", uint8([0 1 2]), "m-1");
    %   [from, id, bytes] = p.recv(5000);   % Inf waits until a message arrives
    %   p.close();
    %   Each node owns its registry and inbox. Failures raise MException
    %   'polycall:E_<NAME>'; any call after close raises
    %   'polycall:E_INVALID_HANDLE'. Deleting an open Peer closes it.
    %   MATLAB runs MEX calls on its one interpreter thread, so a recv
    %   blocked there can only end by message or timeout; cancel() wakes
    %   receivers blocked on other (native) threads.

    properties (SetAccess = private)
        Handle = int32(0)
        Closed = false
    end

    methods
        function obj = Peer(nodeId, bindEndpoint, authToken)
            if nargin < 2
                bindEndpoint = '';   % send-only node
            end
            if nargin < 3
                authToken = '';
            end
            obj.Handle = matlab_polycall_mex('peer_open', ...
                obinexus.polycall.textArg(nodeId, "nodeId"), ...
                obinexus.polycall.textArg(bindEndpoint, "bindEndpoint"), ...
                obinexus.polycall.textArg(authToken, "authToken"));
        end

        function close(obj)
            matlab_polycall_mex('peer_close', double(obj.Handle));
            obj.Closed = true;
        end

        function tf = isOpen(obj)
            tf = obj.Handle > 0 && ~obj.Closed;
        end

        function delete(obj)
            if obj.Handle > 0 && ~obj.Closed
                try
                    matlab_polycall_mex('peer_close', double(obj.Handle));
                catch
                    % the core refused the handle: nothing left to release
                end
            end
        end

        function ep = endpoint(obj)
            ep = matlab_polycall_mex('peer_endpoint', double(obj.Handle));
        end

        function id = nodeId(obj)
            id = matlab_polycall_mex('peer_node_id', double(obj.Handle));
        end

        function register(obj, peerId, endpoint)
            matlab_polycall_mex('peer_register', double(obj.Handle), ...
                obinexus.polycall.textArg(peerId, "peerId"), obinexus.polycall.textArg(endpoint, "endpoint"));
        end

        function unregister(obj, peerId)
            matlab_polycall_mex('peer_unregister', double(obj.Handle), obinexus.polycall.textArg(peerId, "peerId"));
        end

        function json = list(obj)
            json = matlab_polycall_mex('peer_list', double(obj.Handle));
        end

        function json = health(obj)
            json = matlab_polycall_mex('peer_health', double(obj.Handle));
        end

        function ping(obj, peer, timeoutMs)
            if nargin < 3
                timeoutMs = 5000;
            end
            matlab_polycall_mex('peer_ping', double(obj.Handle), obinexus.polycall.textArg(peer, "peer"), double(timeoutMs));
        end

        function send(obj, peer, payload, messageId, timeoutMs)
            if nargin < 4
                messageId = '';
            end
            if nargin < 5
                timeoutMs = 5000;
            end
            if isstring(payload)
                payload = char(payload);
            end
            matlab_polycall_mex('peer_send', double(obj.Handle), obinexus.polycall.textArg(peer, "peer"), ...
                payload, obinexus.polycall.textArg(messageId, "messageId"), double(timeoutMs));
        end

        function [from, id, payload] = recv(obj, timeoutMs)
            if nargin < 2
                timeoutMs = Inf;
            end
            [from, id, payload] = matlab_polycall_mex('peer_recv', double(obj.Handle), double(timeoutMs));
        end

        function cancel(obj)
            matlab_polycall_mex('peer_cancel', double(obj.Handle));
        end
    end
end
