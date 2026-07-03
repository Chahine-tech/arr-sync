import gleam/io
import gleam/time/duration
import gleam/time/timestamp

pub type Level {
  Debug
  Info
  Warning
  Error
}

pub fn log(level: Level, message: String) -> Nil {
  let now = timestamp.to_rfc3339(timestamp.system_time(), duration.seconds(0))
  io.println(now <> " [" <> level_label(level) <> "] " <> message)
}

fn level_label(level: Level) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARN"
    Error -> "ERROR"
  }
}
