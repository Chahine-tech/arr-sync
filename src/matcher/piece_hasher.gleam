pub type HashError {
  CannotOpenFile(path: String)
  FileTooSmall(path: String)
}

// gleam_stdlib has no SHA1/SHA256 — this needs the native Erlang :crypto
// module (crypto:hash/2) via @external(erlang, "crypto", "hash").
pub type PieceSize {
  PieceSize(bytes: Int)
}

/// Hashes the first `count` pieces of a file, for comparison against a
/// candidate torrent's BitTorrent piece hashes.
pub fn hash_first_pieces(
  path: String,
  piece_size: PieceSize,
  count: Int,
) -> Result(List(String), HashError) {
  todo as "read the first `count` slices of piece_size.bytes and hash each via :crypto"
}
