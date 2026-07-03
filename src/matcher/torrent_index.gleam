import client/qbittorrent.{type Session}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type TorrentFile {
  TorrentFile(name: String, size: Int, progress: Float)
}

pub type TorrentEntry {
  TorrentEntry(
    hash: String,
    name: String,
    save_path: String,
    files: List(TorrentFile),
    piece_hashes: List(String),
  )
}

pub type MatchResult {
  Matched(torrent_hash: String, file_index: Int)
  NoMatch
  Ambiguous(candidates: List(String))
}

pub type Message {
  Refresh
  Lookup(piece_hash: String, reply_to: Subject(MatchResult))
  Shutdown
}

type IndexState {
  IndexState(session: Session, entries: Dict(String, TorrentEntry))
}

pub fn start(
  credentials: qbittorrent.Credentials,
  name: process.Name(Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(5000, fn(subject) {
    case qbittorrent.login(credentials) {
      Ok(session) ->
        actor.initialised(IndexState(session:, entries: dict.new()))
        |> actor.returning(subject)
        |> Ok
      Error(_reason) -> Error("qBittorrent login failed")
    }
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

fn handle_message(
  state: IndexState,
  message: Message,
) -> actor.Next(IndexState, Message) {
  case message {
    Refresh -> {
      let entries = refresh_entries(state.session)
      actor.continue(IndexState(..state, entries:))
    }
    Lookup(piece_hash, reply_to) -> {
      process.send(reply_to, find_match(state.entries, piece_hash))
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

fn refresh_entries(session: Session) -> Dict(String, TorrentEntry) {
  todo as "list torrents via qbittorrent.list_torrents, fetch files + piece_hashes for each, index by piece_hash"
}

fn find_match(
  entries: Dict(String, TorrentEntry),
  piece_hash: String,
) -> MatchResult {
  todo as "look up piece_hash in entries, handle Matched/NoMatch/Ambiguous"
}
