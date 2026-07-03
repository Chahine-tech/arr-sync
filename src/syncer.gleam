import client/radarr
import client/sonarr
import config/config.{type Config}
import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import logging
import matcher/torrent_index
import watcher/event.{type FsEvent}
import watcher/fs_watcher

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
  watcher_name: process.Name(fs_watcher.Message),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(1000, fn(subject) {
    let index = process.named_subject(index_name)
    let watcher = process.named_subject(watcher_name)

    // fs_watcher only knows Subject(FsEvent), not our own Message type, so
    // we hand it a dedicated subject and fold its events into our own
    // mailbox pre-wrapped as HandleFsEvent via select_map.
    let fs_event_subject = process.new_subject()
    process.send(watcher, fs_watcher.Subscribe(fs_event_subject))

    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_map(fs_event_subject, HandleFsEvent)

    actor.initialised(SyncerState(config:, index:))
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
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

fn handle_fs_event(state: SyncerState, fs_event: FsEvent) -> Nil {
  case fs_event {
    event.Deleted(_) -> Nil
    event.Created(path) | event.Renamed(_, path) | event.Moved(_, path) ->
      resync(state, path)
  }
}

fn resync(state: SyncerState, path: String) -> Nil {
  let piece_sizes = process.call(state.index, 5000, torrent_index.PieceSizes)
  let lookup = fn(hash) {
    process.call(state.index, 5000, torrent_index.Lookup(hash, _))
  }

  case torrent_index.find_first_match(path, piece_sizes, lookup) {
    Ok(torrent_index.Matched(torrent_hash, piece_hash)) -> {
      let result =
        process.call(state.index, 10_000, torrent_index.Resync(
          torrent_hash,
          piece_hash,
          path,
          _,
        ))
      case result {
        Ok(Nil) -> {
          logging.log(
            logging.Info,
            path <> " resynced with torrent " <> torrent_hash,
          )
          notify_arr_stack(state.config, path)
        }
        Error(reason) ->
          logging.log(
            logging.Error,
            "failed to resync "
              <> path
              <> " with torrent "
              <> torrent_hash
              <> ": "
              <> string.inspect(reason),
          )
      }
    }
    Ok(torrent_index.Ambiguous(candidates)) ->
      logging.log(
        logging.Warning,
        path
          <> " matches multiple torrents, skipping: "
          <> string.join(candidates, ", "),
      )
    Ok(torrent_index.NoMatch) | Error(Nil) ->
      logging.log(logging.Info, "no torrent matches " <> path)
  }
}

fn notify_arr_stack(config: Config, path: String) -> Nil {
  case config.sonarr {
    None -> Nil
    Some(arr_config) -> {
      let credentials =
        sonarr.Credentials(url: arr_config.url, api_key: arr_config.api_key)
      case sonarr.notify_file_synced(credentials, path) {
        Ok(Nil) -> Nil
        Error(reason) ->
          logging.log(
            logging.Warning,
            "sonarr notification failed: " <> string.inspect(reason),
          )
      }
    }
  }

  case config.radarr {
    None -> Nil
    Some(arr_config) -> {
      let credentials =
        radarr.Credentials(url: arr_config.url, api_key: arr_config.api_key)
      case radarr.notify_file_synced(credentials, path) {
        Ok(Nil) -> Nil
        Error(reason) ->
          logging.log(
            logging.Warning,
            "radarr notification failed: " <> string.inspect(reason),
          )
      }
    }
  }
}
