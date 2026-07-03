import config/config.{type Config}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import matcher/torrent_index
import watcher/event.{type FsEvent}

pub type Message {
  HandleFsEvent(FsEvent)
  Shutdown
}

type SyncerState {
  SyncerState(config: Config, index: Subject(torrent_index.Message))
}

pub fn start(
  config: Config,
  index_name: process.Name(torrent_index.Message),
) -> actor.StartResult(Subject(Message)) {
  let index = process.named_subject(index_name)
  actor.new(SyncerState(config:, index:))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: SyncerState,
  message: Message,
) -> actor.Next(SyncerState, Message) {
  case message {
    HandleFsEvent(fs_event) -> {
      handle_fs_event(state, fs_event)
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

fn handle_fs_event(_state: SyncerState, _fs_event: FsEvent) -> Nil {
  todo as "hash the affected file, query the index (torrent_index.Lookup), then qbittorrent.set_location + recheck on a match"
}
