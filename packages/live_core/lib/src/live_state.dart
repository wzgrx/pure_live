/// Whether a room is broadcasting (docs/adr/0010-core-domain-model.md, rule 2).
///
/// There is no "unknown": an adapter that cannot tell throws a `SiteError`.
enum LiveState {
  /// Broadcasting now.
  live,

  /// Not broadcasting.
  offline,

  /// Playing a loop or a recording instead of a live broadcast.
  replay,
}
