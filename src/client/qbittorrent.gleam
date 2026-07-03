import gleam/http.{Post}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/result
import gleam/string
import gleam/uri

pub type Credentials {
  Credentials(url: String, username: String, password: String)
}

pub type Session {
  Session(base_url: String, cookie: String)
}

pub type QbittorrentError {
  RequestFailed(httpc.HttpError)
  InvalidUrl(String)
  AuthenticationRejected(status: Int, body: String)
  MissingSessionCookie
  UnexpectedStatus(status: Int, body: String)
}

pub fn login(credentials: Credentials) -> Result(Session, QbittorrentError) {
  use base_request <- result.try(
    request.to(credentials.url <> "/api/v2/auth/login")
    |> result.map_error(fn(_) { InvalidUrl(credentials.url) }),
  )

  let body =
    "username="
    <> uri.percent_encode(credentials.username)
    <> "&password="
    <> uri.percent_encode(credentials.password)

  let req =
    base_request
    |> request.set_method(Post)
    |> request.set_header("content-type", "application/x-www-form-urlencoded")
    |> request.set_body(body)

  use resp <- result.try(httpc.send(req) |> result.map_error(RequestFailed))

  case resp.status {
    200 -> extract_session(credentials.url, resp)
    status -> Error(AuthenticationRejected(status, resp.body))
  }
}

fn extract_session(
  base_url: String,
  resp: Response(String),
) -> Result(Session, QbittorrentError) {
  use set_cookie <- result.try(
    response.get_header(resp, "set-cookie")
    |> result.replace_error(MissingSessionCookie),
  )

  // qBittorrent returns "SID=<value>; path=/; HttpOnly" — only the first
  // segment (the key=value pair) is needed for subsequent requests.
  case string.split(set_cookie, ";") {
    [session_pair, ..] -> Ok(Session(base_url:, cookie: session_pair))
    [] -> Error(MissingSessionCookie)
  }
}

/// GET /api/v2/torrents/info
pub fn list_torrents(
  session: Session,
) -> Result(List(TorrentSummary), QbittorrentError) {
  todo as "decode JSON response into List(TorrentSummary) with gleam/dynamic/decode"
}

/// GET /api/v2/torrents/files
pub fn torrent_files(
  session: Session,
  torrent_hash: String,
) -> Result(List(RemoteTorrentFile), QbittorrentError) {
  todo as "GET torrents/files?hash=<torrent_hash>"
}

/// GET /api/v2/torrents/pieceHashes — the key to matching
pub fn piece_hashes(
  session: Session,
  torrent_hash: String,
) -> Result(List(String), QbittorrentError) {
  todo as "GET torrents/pieceHashes?hash=<torrent_hash>"
}

/// POST /api/v2/torrents/setLocation
pub fn set_location(
  session: Session,
  torrent_hash: String,
  new_location: String,
) -> Result(Nil, QbittorrentError) {
  todo as "POST torrents/setLocation with hash + location"
}

/// POST /api/v2/torrents/recheck
pub fn recheck(
  session: Session,
  torrent_hash: String,
) -> Result(Nil, QbittorrentError) {
  todo as "POST torrents/recheck with hash"
}

pub type TorrentSummary {
  TorrentSummary(hash: String, name: String, save_path: String)
}

pub type RemoteTorrentFile {
  RemoteTorrentFile(name: String, size: Int, progress: Float)
}
