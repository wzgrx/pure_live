/// Where the store reports recoverable problems (invalid stored values,
/// unreadable secrets). Messages never contain secret values or cookies.
final class StoreLog {
  /// Sends warnings to [sink].
  const new(this.sink);

  /// Drops every message.
  static const silent = StoreLog(_ignore);

  /// Receives each message.
  final void Function(String message) sink;

  /// Reports a recoverable problem.
  void warning(String message) => sink(message);

  static void _ignore(String message) {}
}
