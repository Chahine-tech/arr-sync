-module(arr_sync_fs_watcher_ffi).
-export([watch/2, decode_raw_event/1]).

%% Starts an `fs` (synrc/fs) watcher for `Path`, registered under `Name`,
%% and subscribes the calling process to its file events. `fs` auto-selects
%% inotify/FSEvents/kqueue based on os:type/0. `backwards_compatible` is
%% disabled so starting the `fs` application doesn't also spawn its own
%% `default_fs` watcher on the daemon's cwd.
watch(Name, Path) ->
    application:set_env(fs, backwards_compatible, false),
    application:ensure_all_started(fs),
    NameAtom = binary_to_atom(Name, utf8),
    fs:start_link(NameAtom, binary_to_list(Path)),
    fs:subscribe(NameAtom),
    nil.

%% `fs` delivers events as {Pid, {fs, file_event}, {Path, Flags}} directly
%% in the subscriber's mailbox (see fs_event_bridge:handle_event/2), with
%% Path as an Erlang charlist and Flags as a list of atoms — neither of
%% which a Gleam actor's typed selector can match on directly.
decode_raw_event({_Pid, {fs, file_event}, {Path, Flags}}) ->
    PathBin = unicode:characters_to_binary(Path),
    FlagBins = [atom_to_binary(F, utf8) || F <- Flags],
    {ok, {PathBin, FlagBins}};
decode_raw_event(_Other) ->
    {error, nil}.
