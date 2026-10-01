/// Separates native player events of one source load from the next (3.x's
/// `SourceEventFence`, unchanged).
///
/// The player is reused for quality, line and room switches, and its
/// callbacks do not say which open they belong to. Events are fenced while a
/// replacement open is in progress and accepted again once it finished.
///
/// The native `path` is diagnostic evidence only, never a gate: libmpv may
/// report a redirected, rewritten or normalised URL, or none at all; an
/// exact match made a healthy stream look unopened (3.x).
final class SourceEventFence {
  int _generation = 0;
  bool _opening = false;
  bool _openAuthorized = false;
  bool _nativeSourceConfirmed = false;
  String? _requestedUrl;

  /// The current source generation.
  int get generation => _generation;

  /// Whether an open is in progress.
  bool get isOpening => _opening;

  /// Whether the last open finished successfully.
  bool get isOpenAuthorized => _openAuthorized;

  /// Whether the native path matched the requested URL in this generation.
  bool get isNativeSourceConfirmed => _nativeSourceConfirmed;

  /// Whether work of [eventGeneration] still belongs to the opened source.
  /// No path callback is required: some opens fail before mpv reports a
  /// path, and a generation's deadline must still be able to end it.
  bool isCurrentGeneration(int eventGeneration) => eventGeneration == _generation && !_opening && _openAuthorized;

  /// Starts a new generation for an open of [requestedUrl].
  int begin(String? requestedUrl) {
    _generation++;
    _opening = true;
    _openAuthorized = false;
    _nativeSourceConfirmed = false;
    _requestedUrl = requestedUrl?.trim();
    return _generation;
  }

  /// Points the open in progress at its final URL without a new generation,
  /// so callbacks are either wholly old or wholly new.
  void retargetOpening(String? requestedUrl) {
    if (!_opening) return;
    _nativeSourceConfirmed = false;
    _requestedUrl = requestedUrl?.trim();
  }

  /// Notes the native paths; a match confirms the source for the rest of
  /// the generation (teardown's empty notifications do not revoke it).
  void observeNativeSources(Iterable<String> urls) {
    final requested = _requestedUrl;
    if (requested == null || requested.isEmpty) return;
    if (urls.any((url) => url == requested)) _nativeSourceConfirmed = true;
  }

  /// Ends the open; events are accepted afterwards only when
  /// [authorizeSuccessfulOpen].
  void finishOpen(Iterable<String> urls, {required bool authorizeSuccessfulOpen}) {
    observeNativeSources(urls);
    _opening = false;
    _openAuthorized = authorizeSuccessfulOpen;
  }

  /// Whether an event of [eventGeneration] is accepted.
  bool accepts(int eventGeneration) => isCurrentGeneration(eventGeneration);

  /// Drops the source; every earlier event is rejected.
  void clear() {
    _generation++;
    _opening = false;
    _openAuthorized = false;
    _nativeSourceConfirmed = false;
    _requestedUrl = null;
  }
}
