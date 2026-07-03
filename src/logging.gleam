import gleam/io

pub type Level {
  Debug
  Info
  Warning
  Error
}

pub fn log(level: Level, message: String) -> Nil {
  io.println("[" <> level_label(level) <> "] " <> message)
}

fn level_label(level: Level) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARN"
    Error -> "ERROR"
  }
}
