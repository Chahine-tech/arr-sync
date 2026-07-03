import argv
import client/qbittorrent
import config/config
import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import logging
import matcher/torrent_index
import syncer
import watcher/fs_watcher

pub fn main() {
  case argv.load().arguments {
    ["start"] -> start("arr-sync.toml")
    ["start", "--config", path] -> start(path)
    ["match", path] -> match_file(path)
    ["status"] ->
      todo as "read daemon state, e.g. via a registered process name"
    ["list"] -> todo as "ask torrent_index for its indexed entries"
    ["resync", _torrent_hash] ->
      todo as "force a resync on a single torrent hash"
    _ ->
      logging.log(
        logging.Error,
        "usage: arr_sync <start|match|status|list|resync> [args]",
      )
  }
}

fn start(config_path: String) -> Nil {
  case config.load(config_path) {
    Error(_reason) ->
      logging.log(logging.Error, "failed to load config from " <> config_path)
    Ok(loaded_config) -> {
      let credentials =
        qbittorrent.Credentials(
          url: loaded_config.qbittorrent.url,
          username: loaded_config.qbittorrent.username,
          password: loaded_config.qbittorrent.password,
        )

      // Created once at startup and closed over by both children below, so
      // syncer can look up torrent_index's Subject without a runtime handshake.
      let index_name = process.new_name("torrent_index")

      let assert Ok(_supervisor) =
        supervisor.new(supervisor.OneForOne)
        |> supervisor.add(
          supervision.worker(fn() {
            fs_watcher.start(loaded_config.watch.paths)
          }),
        )
        |> supervisor.add(
          supervision.worker(fn() {
            torrent_index.start(credentials, index_name)
          })
          |> supervision.timeout(ms: 10_000),
        )
        |> supervisor.add(
          supervision.worker(fn() { syncer.start(loaded_config, index_name) }),
        )
        |> supervisor.restart_tolerance(intensity: 3, period: 60)
        |> supervisor.start

      logging.log(logging.Info, "arr-sync started, watching " <> config_path)
      process.sleep_forever()
    }
  }
}

fn match_file(path: String) -> Nil {
  todo as "hash the file's pieces and print the matching torrent, without touching qBittorrent"
}
