-module(arr_sync_distribution_ffi).
-export([fixed_name/1, ensure_started/2, hostname/0, node_name/0, ping/1,
         restrict_permissions/1, random_cookie/0, os_pid/0, rpc_query_status/2]).

%% Deterministic Name(msg) (no random suffix, unlike gleam_erlang's
%% process.new_name/1) so a function invoked over RPC by a separate node
%% can reconstruct the exact same Name and find the already-running actor.
fixed_name(Prefix) ->
    binary_to_atom(Prefix, utf8).

%% Turns the current node into a distributed one under ShortName@hostname.
%% net_kernel:start/1 requires epmd to already be listening — unlike
%% `erl -name`, it does not start epmd itself when called after boot — so
%% this starts it first if needed.
ensure_started(ShortName, Cookie) ->
    case net_kernel:get_state() of
        #{started := no} ->
            os:cmd("epmd -daemon"),
            timer:sleep(300),
            case net_kernel:start([binary_to_atom(ShortName, utf8), shortnames]) of
                {ok, _Pid} ->
                    erlang:set_cookie(binary_to_atom(Cookie, utf8)),
                    {ok, nil};
                {error, Reason} ->
                    {error, format_error(Reason)}
            end;
        _Started ->
            erlang:set_cookie(binary_to_atom(Cookie, utf8)),
            {ok, nil}
    end.

%% inet:gethostname/0, not net_adm:localhost/0 — the latter appends mDNS
%% suffixes (e.g. ".local" on macOS) that `node()` itself does not use,
%% which breaks matching the daemon's actual registered node name.
hostname() ->
    {ok, Hostname} = inet:gethostname(),
    unicode:characters_to_binary(Hostname).

node_name() ->
    unicode:characters_to_binary(atom_to_list(node())).

ping(NodeName) ->
    net_adm:ping(binary_to_atom(NodeName, utf8)) =:= pong.

restrict_permissions(Path) ->
    case file:change_mode(binary_to_list(Path), 8#600) of
        ok -> {ok, nil};
        {error, Reason} -> {error, format_error(Reason)}
    end.

random_cookie() ->
    string:lowercase(binary:encode_hex(crypto:strong_rand_bytes(24))).

os_pid() ->
    unicode:characters_to_binary(os:getpid()).

rpc_query_status(NodeName, Timeout) ->
    Node = binary_to_atom(NodeName, utf8),
    case rpc:call(Node, 'arr_sync@distribution', query_status, [], Timeout) of
        {badrpc, Reason} -> {error, format_error(Reason)};
        Result -> {ok, Result}
    end.

format_error(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
