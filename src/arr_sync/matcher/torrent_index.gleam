import arr_sync/client/qbittorrent.{type Session}
import arr_sync/logging
import arr_sync/matcher/piece_hasher
import filepath
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string

pub type TorrentFile {
  TorrentFile(
    name: String,
    size: Int,
    progress: Float,
    piece_range: #(Int, Int),
  )
}

pub type TorrentEntry {
  TorrentEntry(
    hash: String,
    name: String,
    save_path: String,
    files: List(TorrentFile),
    piece_size: Int,
    piece_hashes: List(String),
  )
}

pub type MatchResult {
  Matched(torrent_hash: String, piece_hash: String)
  NoMatch
  Ambiguous(candidates: List(String))
}

pub type ResyncError {
  UnknownMatch(torrent_hash: String, piece_hash: String)
  QbittorrentFailure(qbittorrent.QbittorrentError)
}

pub type IndexStatus {
  IndexStatus(torrent_count: Int, piece_sizes: List(Int))
}

pub type Message {
  Refresh
  Lookup(piece_hash: String, reply_to: Subject(MatchResult))
  PieceSizes(reply_to: Subject(List(Int)))
  Status(reply_to: Subject(IndexStatus))
  Resync(
    torrent_hash: String,
    piece_hash: String,
    new_absolute_path: String,
    reply_to: Subject(Result(Nil, ResyncError)),
  )
  Shutdown
}

pub type Index {
  Index(
    torrents: Dict(String, TorrentEntry),
    by_piece_hash: Dict(String, List(String)),
  )
}

type IndexState {
  IndexState(session: Session, index: Index)
}

pub fn start(
  credentials: qbittorrent.Credentials,
  name: process.Name(Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(15_000, fn(subject) {
    case qbittorrent.login(credentials) {
      Ok(session) ->
        // Fetch the index synchronously at startup — nothing else ever
        // sends Refresh on its own, so without this the actor would stay
        // permanently empty and every match/resync would silently miss.
        actor.initialised(IndexState(session:, index: fetch_index(session)))
        |> actor.returning(subject)
        |> Ok
      Error(_reason) -> Error("qBittorrent login failed")
    }
  })
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start
}

fn empty_index() -> Index {
  Index(torrents: dict.new(), by_piece_hash: dict.new())
}

fn handle_message(
  state: IndexState,
  message: Message,
) -> actor.Next(IndexState, Message) {
  case message {
    Refresh -> {
      let index = fetch_index(state.session)
      actor.continue(IndexState(..state, index:))
    }
    Lookup(piece_hash, reply_to) -> {
      process.send(reply_to, find_match(state.index, piece_hash))
      actor.continue(state)
    }
    PieceSizes(reply_to) -> {
      process.send(reply_to, piece_sizes(state.index))
      actor.continue(state)
    }
    Status(reply_to) -> {
      process.send(
        reply_to,
        IndexStatus(
          torrent_count: dict.size(state.index.torrents),
          piece_sizes: piece_sizes(state.index),
        ),
      )
      actor.continue(state)
    }
    Resync(torrent_hash, piece_hash, new_absolute_path, reply_to) -> {
      process.send(
        reply_to,
        do_resync(
          state.session,
          state.index,
          torrent_hash,
          piece_hash,
          new_absolute_path,
        ),
      )
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

pub fn fetch_index(session: Session) -> Index {
  case qbittorrent.list_torrents(session) {
    Error(_reason) -> {
      logging.log(logging.Warning, "could not list torrents from qBittorrent")
      empty_index()
    }
    Ok(summaries) ->
      summaries
      |> list.filter_map(fn(summary) { fetch_entry(session, summary) })
      |> build_index
  }
}

fn fetch_entry(
  session: Session,
  summary: qbittorrent.TorrentSummary,
) -> Result(TorrentEntry, Nil) {
  case
    qbittorrent.torrent_files(session, summary.hash),
    qbittorrent.piece_hashes(session, summary.hash),
    qbittorrent.properties(session, summary.hash)
  {
    Ok(files), Ok(piece_hashes), Ok(properties) ->
      Ok(TorrentEntry(
        hash: summary.hash,
        name: summary.name,
        save_path: summary.save_path,
        files: list.map(files, fn(file) {
          TorrentFile(
            name: file.name,
            size: file.size,
            progress: file.progress,
            piece_range: file.piece_range,
          )
        }),
        piece_size: properties.piece_size,
        piece_hashes:,
      ))
    _, _, _ -> {
      logging.log(
        logging.Warning,
        "skipping torrent "
          <> summary.hash
          <> ": could not fetch its files/piece hashes/properties",
      )
      Error(Nil)
    }
  }
}

/// The distinct piece sizes present in the index. In practice a small,
/// stable set (BitTorrent clients pick from a handful of standard sizes),
/// so this drives how many times a candidate file needs re-hashing.
pub fn piece_sizes(index: Index) -> List(Int) {
  index.torrents
  |> dict.values
  |> list.map(fn(entry) { entry.piece_size })
  |> list.unique
}

pub fn build_index(entries: List(TorrentEntry)) -> Index {
  let torrents =
    entries
    |> list.map(fn(entry) { #(entry.hash, entry) })
    |> dict.from_list

  // A torrent can repeat the same piece hash internally (e.g. a long run of
  // identical bytes hashes identically) — dedupe per torrent_hash so that
  // doesn't get mistaken for cross-torrent ambiguity.
  let by_piece_hash =
    list.fold(entries, dict.new(), fn(index, entry) {
      list.fold(entry.piece_hashes, index, fn(index, piece_hash) {
        dict.upsert(index, piece_hash, fn(existing) {
          case existing {
            Some(torrent_hashes) ->
              case list.contains(torrent_hashes, entry.hash) {
                True -> torrent_hashes
                False -> [entry.hash, ..torrent_hashes]
              }
            None -> [entry.hash]
          }
        })
      })
    })

  Index(torrents:, by_piece_hash:)
}

pub fn find_match(index: Index, piece_hash: String) -> MatchResult {
  case dict.get(index.by_piece_hash, piece_hash) {
    Error(Nil) -> NoMatch
    Ok([]) -> NoMatch
    Ok([torrent_hash]) -> Matched(torrent_hash:, piece_hash:)
    Ok(candidates) -> Ambiguous(candidates:)
  }
}

/// Resolves a matched piece hash down to the specific file inside the
/// torrent it belongs to, using the [start, end] piece_range qBittorrent
/// reports per file (torrents/files) — no cumulative offset math needed.
pub fn resolve(
  index: Index,
  torrent_hash: String,
  piece_hash: String,
) -> Result(#(TorrentEntry, TorrentFile), Nil) {
  use entry <- result.try(
    dict.get(index.torrents, torrent_hash) |> result.replace_error(Nil),
  )
  use piece_index <- result.try(piece_index_of(entry.piece_hashes, piece_hash))
  use file <- result.try(
    list.find(entry.files, fn(file) {
      let #(start, end) = file.piece_range
      piece_index >= start && piece_index <= end
    }),
  )
  Ok(#(entry, file))
}

fn piece_index_of(
  piece_hashes: List(String),
  piece_hash: String,
) -> Result(Int, Nil) {
  piece_hashes
  |> list.index_map(fn(hash, index) { #(hash, index) })
  |> list.find_map(fn(pair) {
    case pair.0 == piece_hash {
      True -> Ok(pair.1)
      False -> Error(Nil)
    }
  })
}

/// Renames/moves the resolved file inside qBittorrent to match where it now
/// actually lives on disk, then forces a recheck.
///
/// Verified live this needs to branch in two genuinely different ways:
/// - If the new path is still somewhere under the torrent's current
///   save_path (even in a different subdirectory — file.name for a
///   multi-file torrent already carries its own subdirectory prefix, e.g.
///   "ShowPack/episode.bin"), renameFile alone is correct. Comparing
///   directory_name(new_path) to save_path directly is wrong here: it's
///   almost always a deeper path than save_path once file.name has a
///   subdirectory prefix, which caused a spurious setLocation that doubled
///   the path into ".../ShowPack/ShowPack/...".
/// - Only when the new path leaves save_path's tree entirely (e.g. moved
///   from downloads/complete into the media library) does the torrent's
///   save_path itself need to move.
fn do_resync(
  session: Session,
  index: Index,
  torrent_hash: String,
  piece_hash: String,
  new_absolute_path: String,
) -> Result(Nil, ResyncError) {
  use #(entry, file) <- result.try(
    resolve(index, torrent_hash, piece_hash)
    |> result.replace_error(UnknownMatch(torrent_hash:, piece_hash:)),
  )

  use new_relative_path <- result.try(
    case relative_to(entry.save_path, new_absolute_path) {
      Ok(relative_path) -> Ok(relative_path)
      Error(Nil) -> {
        // Left save_path's tree entirely: move save_path to the new parent
        // directory, then rename with just the filename — we can't infer
        // intended subdirectory structure from a path outside the torrent's
        // own tree.
        let new_dir = filepath.directory_name(new_absolute_path)
        use _ <- result.try(
          qbittorrent.set_location(session, torrent_hash, new_dir)
          |> result.map_error(QbittorrentFailure),
        )
        Ok(filepath.base_name(new_absolute_path))
      }
    },
  )

  use _ <- result.try(
    qbittorrent.rename_file(session, torrent_hash, file.name, new_relative_path)
    |> result.map_error(QbittorrentFailure),
  )

  qbittorrent.recheck(session, torrent_hash)
  |> result.map_error(QbittorrentFailure)
}

@internal
pub fn relative_to(base: String, path: String) -> Result(String, Nil) {
  case string.starts_with(path, base <> "/") {
    True -> Ok(string.drop_start(path, string.length(base) + 1))
    False -> Error(Nil)
  }
}

/// Tries each candidate piece size against `path` (a file's piece hash only
/// lines up with a torrent using the same piece size), stopping at the
/// first one that produces a match. `lookup` is injected so this works both
/// synchronously against an already-fetched `Index` (the CLI) and via
/// actor round-trips against a running torrent_index (the daemon).
pub fn find_first_match(
  path: String,
  piece_sizes: List(Int),
  lookup: fn(String) -> MatchResult,
) -> Result(MatchResult, Nil) {
  case piece_sizes {
    [] -> Error(Nil)
    [piece_size, ..rest] ->
      case
        piece_hasher.hash_first_pieces(
          path,
          piece_hasher.PieceSize(piece_size),
          1,
        )
      {
        Ok([piece_hash, ..]) ->
          case lookup(piece_hash) {
            NoMatch -> find_first_match(path, rest, lookup)
            result -> Ok(result)
          }
        _ -> find_first_match(path, rest, lookup)
      }
  }
}
