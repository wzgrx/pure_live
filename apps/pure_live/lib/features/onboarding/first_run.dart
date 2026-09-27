/// Decides once whether to offer the first-run wizard (F-NEW-08, store.md
/// §11): only on an installation that never offered it and follows nothing
/// yet. The wizard is marked as offered before the answer, so it never
/// comes back, whatever the user does with it.
final class FirstRunGate {
  /// Creates the gate.
  new({required this.isDone, required this.markDone, required this.followCount});

  /// Whether the wizard was offered before.
  final bool Function() isDone;

  /// Records that it was offered.
  final Future<void> Function() markDone;

  /// Number of followed rooms.
  final Future<int> Function() followCount;

  /// Whether to show the wizard now; true at most once per installation.
  Future<bool> take() async {
    if (isDone()) return false;
    await markDone();
    return await followCount() == 0;
  }
}
