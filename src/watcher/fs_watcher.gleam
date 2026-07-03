import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import watcher/event.{type FsEvent}

pub type Message {
  Subscribe(listener: Subject(FsEvent))
  Shutdown
}

type WatcherState {
  WatcherState(paths: List(String), listeners: List(Subject(FsEvent)))
}

// The exact binding for the Erlang `fs` lib (synrc/fs) — fs:start_link/1,
// fs:subscribe/1, and the {fs, file_event, {Path, Events}} mailbox message
// shape — needs checking against its README before implementing: it's a
// raw Erlang lib, not a typed Gleam one, so there's no Context7 doc for it.
pub fn start(paths: List(String)) -> actor.StartResult(Subject(Message)) {
  actor.new(WatcherState(paths:, listeners: []))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: WatcherState,
  message: Message,
) -> actor.Next(WatcherState, Message) {
  case message {
    Subscribe(listener) ->
      actor.continue(
        WatcherState(..state, listeners: [listener, ..state.listeners]),
      )
    Shutdown -> actor.stop()
  }
}
