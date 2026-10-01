import 'dart:async';

import 'package:live_cast/src/discovery.dart';
import 'package:live_cast/src/renderer.dart';
import 'package:meta/meta.dart';

/// The URL a receiver can open: [value] trimmed when it is an http(s) URL
/// with a host and no credentials, else null (3.x `normalizeDlnaSource`).
/// Local files, RTMP, `javascript:` and URLs with `user:password@` are
/// refused, so they never reach a device on the network.
String? normalizeDlnaSource(String value) {
  final normalized = value.trim();
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      (uri.scheme.toLowerCase() != 'http' && uri.scheme.toLowerCase() != 'https') ||
      !uri.hasAuthority ||
      uri.host.trim().isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return normalized;
}

/// What the cast dialog shows (3.x `LiveDlnaViewStatus`).
enum DlnaCastStatus {
  /// Searching and nothing found yet.
  searching,

  /// Receivers listed.
  ready,

  /// The search ended without receivers.
  empty,

  /// The search could not start, or failed before finding anything.
  failed,

  /// The URL cannot be cast; no search runs.
  invalidSource,
}

/// The error line above the receiver list (3.x `_inlineErrorKey`).
enum DlnaCastError {
  /// The search failed after finding receivers (`dlna_search_interrupted`).
  searchInterrupted,

  /// The last cast failed (`dlna_cast_failed`).
  castFailed,
}

/// A one-off message for the toast (3.x `_notify`).
enum DlnaCastNotice {
  /// The receiver accepted the source and Play (`dlna_cast_started`).
  castStarted,

  /// The cast failed (`dlna_cast_failed`).
  castFailed,
}

/// Everything the cast dialog draws.
@immutable
final class DlnaCastState {
  /// Creates a state.
  const new({
    required this.status,
    this.devices = const [],
    this.starting = false,
    this.searching = false,
    this.busy = false,
    this.selectedDeviceId,
    this.castingDeviceId,
    this.error,
  });

  /// Which pane to show.
  final DlnaCastStatus status;

  /// Receivers in the order found.
  final List<DlnaCastDevice> devices;

  /// A search is opening its sockets (spinner in place of the refresh
  /// button; retry disabled).
  final bool starting;

  /// The search window is open (progress bar above the list).
  final bool searching;

  /// A cast is running: rows and the refresh button are disabled.
  final bool busy;

  /// The receiver the stream was last cast to (check mark).
  final String? selectedDeviceId;

  /// The receiver a cast is running on (spinner on its row).
  final String? castingDeviceId;

  /// The error line above the list, if any.
  final DlnaCastError? error;

  @override
  String toString() =>
      'DlnaCastState(${status.name}, ${devices.length} devices'
      '${starting ? ', starting' : ''}${searching ? ', searching' : ''}${busy ? ', busy' : ''}'
      '${selectedDeviceId == null ? '' : ', selected $selectedDeviceId'}'
      '${castingDeviceId == null ? '' : ', casting $castingDeviceId'}${error == null ? '' : ', ${error!.name}'})';
}

/// The cast dialog's logic, moved out of 3.x's `_LiveDlnaPageState`
/// (`modules/live_play/dialogs/live_dlna_dialog.dart`) unchanged: the page
/// calls [startSearch] when it opens, draws [state] on every [changes]
/// event, calls [castToDevice] when a row is tapped and [close] when it
/// closes.
///
/// - A search lasts [searchDuration] (20 seconds); each device snapshot
///   replaces the list. When it ends the list stays and can be cast to.
/// - [startSearch] while one is opening returns the same future; a new
///   search (refresh) releases the old one and ignores its late snapshots.
/// - One cast at a time: [castToDevice] while one runs returns the same
///   future. Casting to another receiver pauses the previous one first (a
///   pause failure does not block), then sets the source and plays.
/// - After [close] nothing more is sent: a late search is stopped, and a
///   cast in progress does not send Play.
final class DlnaCastController {
  /// Creates the controller for [datasource]; an unusable URL gives
  /// [DlnaCastStatus.invalidSource] and never searches. `startDiscovery`
  /// opens a search ([startDlnaDiscovery] by default; tests fake it) and
  /// `onNotice` gets the toast messages.
  new(
    String datasource, {
    this._startDiscovery = startDlnaDiscovery,
    this.searchDuration = const Duration(seconds: 20),
    this._onNotice,
    this.title = '',
  }) : source = normalizeDlnaSource(datasource) {
    if (source == null) _status = DlnaCastStatus.invalidSource;
    _state = _snapshot();
  }

  /// The URL cast, or null when it cannot be.
  final String? source;

  /// The title the receiver shows (`CastMedia.roomTitle`); empty shows the
  /// URL, as 3.x.
  final String title;

  /// How long one search runs.
  final Duration searchDuration;

  final DlnaDiscoveryStarter _startDiscovery;
  final void Function(DlnaCastNotice notice)? _onNotice;
  final StreamController<DlnaCastState> _changes = StreamController<DlnaCastState>.broadcast();
  final Map<String, DlnaCastDevice> _devices = {};

  DlnaDiscoverySession? _session;
  StreamSubscription<List<DlnaCastDevice>>? _subscription;
  Timer? _searchTimer;
  Future<void>? _startTask;
  Future<void>? _castTask;

  DlnaCastStatus _status = DlnaCastStatus.searching;
  String? _selectedDeviceId;
  String? _castingDeviceId;
  DlnaCastError? _error;
  int _searchRevision = 0;
  bool _starting = false;
  bool _closed = false;
  late DlnaCastState _state;

  /// The current state.
  DlnaCastState get state => _state;

  /// Every new state, delivered asynchronously; closes on [close].
  Stream<DlnaCastState> get changes => _changes.stream;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Starts a search, or a new one in place of the running one (refresh).
  Future<void> startSearch() {
    if (source == null || _closed) return Future<void>.value();
    final current = _startTask;
    if (_starting && current != null) return current;

    final completer = Completer<void>();
    final task = completer.future;
    _startTask = task;
    unawaited(_runSearchTransaction(completer, task));
    return task;
  }

  Future<void> _runSearchTransaction(Completer<void> completer, Future<void> task) async {
    try {
      await _startSearch();
    } on Object {
      if (!_closed) {
        _starting = false;
        _status = DlnaCastStatus.failed;
        _publish();
      }
    } finally {
      if (identical(_startTask, task)) _startTask = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _startSearch() async {
    final revision = ++_searchRevision;
    _searchTimer?.cancel();
    _searchTimer = null;
    if (!_closed) {
      _starting = true;
      _status = DlnaCastStatus.searching;
      _error = null;
      _devices.clear();
      _publish();
    }

    // The old search's late snapshots are fenced by the revision, so the new
    // one does not wait for its release.
    unawaited(_releaseDiscovery());
    if (!_isSearchCurrent(revision)) return;

    final DlnaDiscoverySession session;
    try {
      session = await _startDiscovery();
    } on Object {
      if (_isSearchCurrent(revision)) {
        _starting = false;
        _status = DlnaCastStatus.failed;
        _publish();
      }
      return;
    }

    if (!_isSearchCurrent(revision)) {
      await _stopSession(session);
      return;
    }

    _session = session;
    _subscription = session.devices.listen(
      (snapshot) => _receiveDevices(revision, snapshot),
      onError: (Object _) => unawaited(_finishSearch(revision, failed: true)),
      onDone: () => unawaited(_finishSearch(revision)),
    );
    _starting = false;
    _searchTimer = Timer(searchDuration, () => unawaited(_finishSearch(revision)));
    _publish();
  }

  bool _isSearchCurrent(int revision) => !_closed && revision == _searchRevision;

  void _receiveDevices(int revision, List<DlnaCastDevice> snapshot) {
    if (!_isSearchCurrent(revision)) return;
    final next = <String, DlnaCastDevice>{};
    for (final device in snapshot) {
      final id = device.id.trim();
      if (id.isNotEmpty) next[id] = device;
    }
    _devices
      ..clear()
      ..addAll(next);
    if (_selectedDeviceId != null && !_devices.containsKey(_selectedDeviceId)) _selectedDeviceId = null;
    _status = _devices.isEmpty ? DlnaCastStatus.searching : DlnaCastStatus.ready;
    _publish();
  }

  Future<void> _finishSearch(int revision, {bool failed = false}) async {
    if (!_isSearchCurrent(revision)) return;
    _searchTimer?.cancel();
    _searchTimer = null;
    _starting = false;
    if (_devices.isEmpty) {
      _status = failed ? DlnaCastStatus.failed : DlnaCastStatus.empty;
    } else {
      _status = DlnaCastStatus.ready;
      if (failed) _error = DlnaCastError.searchInterrupted;
    }
    _publish();
    await _releaseDiscovery();
  }

  Future<void> _releaseDiscovery() async {
    final cancelled = _subscription?.cancel();
    _subscription = null;
    final session = _session;
    _session = null;
    try {
      await Future.wait([?cancelled, if (session != null) _stopSession(session)]);
    } on Object {
      // A stream may already be closed while a refresh is replacing it.
    }
  }

  Future<void> _stopSession(DlnaDiscoverySession session) async {
    try {
      await session.stop();
    } on Object {
      // Discovery cleanup is best-effort and must not surface after exit.
    }
  }

  /// Casts the source to the listed receiver [deviceId]. Unknown ids, an
  /// invalid source and calls after [close] do nothing.
  Future<void> castToDevice(String deviceId) {
    final source = this.source;
    if (source == null || _closed) return Future<void>.value();
    final current = _castTask;
    if (current != null) return current;
    final target = _devices[deviceId];
    if (target == null) return Future<void>.value();

    final completer = Completer<void>();
    final task = completer.future;
    _castTask = task;
    unawaited(_runCastTransaction(target, source, completer, task));
    return task;
  }

  Future<void> _runCastTransaction(
    DlnaCastDevice target,
    String source,
    Completer<void> completer,
    Future<void> task,
  ) async {
    try {
      await _castToDevice(target, source);
    } finally {
      if (identical(_castTask, task)) _castTask = null;
      if (!_closed) _publish();
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _castToDevice(DlnaCastDevice target, String source) async {
    _castingDeviceId = target.id;
    _error = null;
    _publish();
    try {
      final previousId = _selectedDeviceId;
      final previous = previousId == null ? null : _devices[previousId];
      if (previous != null && previous.id != target.id) {
        try {
          await previous.pause();
        } on Object {
          // A receiver that no longer answers must not block a new receiver.
        }
      }
      if (!_isCastCurrent(target.id)) return;

      if (target case final CastMediaTarget media when title.trim().isNotEmpty) {
        await media.setMedia(CastMedia(url: source, title: title.trim()));
      } else {
        await target.setSource(source);
      }
      if (!_isCastCurrent(target.id)) return;

      await target.play();
      if (!_isCastCurrent(target.id)) return;

      _selectedDeviceId = target.id;
      _error = null;
      _publish();
      _onNotice?.call(DlnaCastNotice.castStarted);
    } on Object {
      if (_isCastCurrent(target.id)) {
        _error = DlnaCastError.castFailed;
        _publish();
        _onNotice?.call(DlnaCastNotice.castFailed);
      }
    } finally {
      if (!_closed) _castingDeviceId = null;
    }
  }

  bool _isCastCurrent(String deviceId) => !_closed && _devices.containsKey(deviceId);

  /// Ends the search and fences every late result. Receivers keep playing.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _searchRevision++;
    _searchTimer?.cancel();
    _searchTimer = null;
    unawaited(_changes.close());
    await _releaseDiscovery();
  }

  DlnaCastState _snapshot() => DlnaCastState(
    status: _status,
    devices: List<DlnaCastDevice>.unmodifiable(_devices.values),
    starting: _starting,
    searching: _searchTimer != null,
    busy: _castTask != null,
    selectedDeviceId: _selectedDeviceId,
    castingDeviceId: _castingDeviceId,
    error: _error,
  );

  void _publish() {
    _state = _snapshot();
    if (!_closed) _changes.add(_state);
  }
}
