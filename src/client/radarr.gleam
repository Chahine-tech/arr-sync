import gleam/http.{Post}
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/result

pub type Credentials {
  Credentials(url: String, api_key: String)
}

pub type NotifyError {
  RequestFailed(httpc.HttpError)
  InvalidUrl(String)
  UnexpectedStatus(status: Int, body: String)
}

/// Notifies Radarr that a file has been resynced, so it refreshes its
/// internal state (DownloadedMoviesScan command). Structurally correct
/// against Radarr's documented v3 API (same request-building pattern as the
/// qBittorrent client), but — unlike qBittorrent — not verified against a
/// live Radarr instance.
pub fn notify_file_synced(
  credentials: Credentials,
  _path: String,
) -> Result(Nil, NotifyError) {
  use base_request <- result.try(
    request.to(credentials.url <> "/api/v3/command")
    |> result.map_error(fn(_) { InvalidUrl(credentials.url) }),
  )

  let body = json.object([#("name", json.string("DownloadedMoviesScan"))])

  let req =
    base_request
    |> request.set_method(Post)
    |> request.set_header("x-api-key", credentials.api_key)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(body))

  use resp <- result.try(httpc.send(req) |> result.map_error(RequestFailed))

  case resp.status {
    200 | 201 | 202 -> Ok(Nil)
    status -> Error(UnexpectedStatus(status, resp.body))
  }
}
