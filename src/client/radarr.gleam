pub type Credentials {
  Credentials(url: String, api_key: String)
}

pub type NotifyError {
  RequestFailed(String)
}

/// Notifies Radarr that a file has been resynced, so it refreshes its
/// internal state (DownloadedMoviesScan command).
pub fn notify_file_synced(
  credentials: Credentials,
  path: String,
) -> Result(Nil, NotifyError) {
  todo as "POST /api/v3/command with {\"name\": \"DownloadedMoviesScan\"}"
}
