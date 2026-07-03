pub type Credentials {
  Credentials(url: String, api_key: String)
}

pub type NotifyError {
  RequestFailed(String)
}

/// Notifies Sonarr that a file has been resynced, so it refreshes its
/// internal state (DownloadedEpisodesScan command).
pub fn notify_file_synced(
  credentials: Credentials,
  path: String,
) -> Result(Nil, NotifyError) {
  todo as "POST /api/v3/command with {\"name\": \"DownloadedEpisodesScan\"}"
}
