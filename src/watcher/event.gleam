pub type FsEvent {
  Created(path: String)
  Renamed(from: String, to: String)
  Moved(from: String, to: String)
  Deleted(path: String)
}
