import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/core/store.dart';

/// Where picture-in-picture is (spec/modules/playback.md §9).
enum PipMode {
  /// Normal layout.
  off,

  /// Requested: the app already shows only the video (PIP-2).
  entering,

  /// The system PiP window (Android) or the small window (Windows) shows the
  /// video.
  active,
}

/// Picture-in-picture state for the UI.
@immutable
final class PipState {
  /// Creates a state.
  const new({this.mode = PipMode.off, this.supported = false});

  /// Mode.
  final PipMode mode;

  /// The platform offers picture-in-picture.
  final bool supported;

  /// The room shows only its video: from the request on, so the system's
  /// entry animation captures no controls (PIP-2).
  bool get videoOnly => mode != PipMode.off;

  /// A copy with [mode] or [supported] replaced.
  PipState copyWith({PipMode? mode, bool? supported}) =>
      PipState(mode: mode ?? this.mode, supported: supported ?? this.supported);

  @override
  bool operator ==(Object other) => other is PipState && other.mode == mode && other.supported == supported;

  @override
  int get hashCode => Object.hash(mode, supported);

  @override
  String toString() => 'PipState(${mode.name}, supported: $supported)';
}

/// Android accepts aspect ratios between 1:2.39 and 2.39:1; a small margin
/// keeps rounding inside the limits.
const double maxPipAspect = 2.35;

/// The narrowest aspect ratio sent to the platform.
const double minPipAspect = 1 / maxPipAspect;

/// The aspect ratio for picture-in-picture: the committed geometry, else the
/// decoded size, else 16:9 (GEO-6: one geometry for every presentation).
double pipAspect(PlaybackState state) {
  final width = state.videoWidth;
  final height = state.videoHeight;
  final decoded = width != null && height != null && width > 0 && height > 0 ? width / height : null;
  final aspect = state.geometry.aspectRatio ?? decoded ?? 16 / 9;
  return aspect.clamp(minPipAspect, maxPipAspect);
}

/// Whether picture-in-picture may start for [state] (PIP-1): the engine
/// exists, no PiP transition runs and the user has not paused.
bool pipEntryAllowed({required PlaybackState state, required bool engineReady, required PipMode mode}) =>
    mode == PipMode.off &&
    engineReady &&
    state.wantsPlay &&
    !const {PlaybackPhase.idle, PlaybackPhase.error, PlaybackPhase.ended}.contains(state.phase);

/// Parameters for the platform.
@immutable
final class PipRequest {
  /// Creates parameters.
  const new({required this.aspect, this.sourceRect, this.playing = true, this.autoEnter = false});

  /// Width / height of the video.
  final double aspect;

  /// Where the video is, in physical pixels of the window (Android's source
  /// rect hint for a smooth entry).
  final Rect? sourceRect;

  /// Playing or paused, for the play/pause action.
  final bool playing;

  /// Enter automatically when the user leaves the app (Android 12+).
  final bool autoEnter;

  /// Whether sending this after [other] changes anything: aspect differences
  /// below 0.004 do not count (PIP-2, GEO-6).
  bool differsFrom(PipRequest? other) =>
      other == null ||
      (aspect - other.aspect).abs() >= 0.004 ||
      playing != other.playing ||
      autoEnter != other.autoEnter ||
      sourceRect != other.sourceRect;
}

/// A picture-in-picture event from the platform.
sealed class PipEvent {
  const new();
}

/// The system entered or left picture-in-picture.
final class PipModeChanged extends PipEvent {
  /// Creates the event.
  const new({required this.active});

  /// In picture-in-picture now.
  final bool active;
}

/// The play/pause action of the PiP window.
final class PipPlayToggled extends PipEvent {
  /// Creates the event.
  const new({required this.play});

  /// The action asked to play (true) or pause (false).
  final bool play;
}

/// The platform side of picture-in-picture.
abstract interface class PipPlatform {
  /// Whether the device offers it.
  Future<bool> isSupported();

  /// Enters; true when the platform accepted.
  Future<bool> enter(PipRequest request);

  /// Updates the parameters of the PiP window (or of a future automatic entry).
  Future<void> update(PipRequest request);

  /// Leaves; false when the platform could not restore the window.
  Future<bool> exit();

  /// Mode changes and actions.
  Stream<PipEvent> get events;
}

/// No picture-in-picture.
final class NoPipPlatform implements PipPlatform {
  /// Creates the no-op platform.
  const new();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> enter(PipRequest request) async => false;

  @override
  Future<void> update(PipRequest request) async {}

  @override
  Future<bool> exit() async => true;

  @override
  Stream<PipEvent> get events => const Stream.empty();
}

/// Android system picture-in-picture over channel `purelive/pip`
/// (`PictureInPicture.kt`).
final class AndroidPipPlatform implements PipPlatform {
  /// Listens on [channel].
  new([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('purelive/pip') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final _events = StreamController<PipEvent>.broadcast();

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'modeChanged':
        if (call.arguments case final bool active) _events.add(PipModeChanged(active: active));
      case 'action':
        if (call.arguments case final String action) _events.add(PipPlayToggled(play: action == 'play'));
    }
  }

  static Map<String, Object?> _arguments(PipRequest request) {
    // The platform wants an integer ratio.
    const scale = 10000;
    return {
      'width': (request.aspect * scale).round(),
      'height': scale,
      'sourceRect': switch (request.sourceRect) {
        final rect? => [rect.left.round(), rect.top.round(), rect.right.round(), rect.bottom.round()],
        null => null,
      },
      'playing': request.playing,
      'autoEnter': request.autoEnter,
    };
  }

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> enter(PipRequest request) async {
    try {
      return await _channel.invokeMethod<bool>('enter', _arguments(request)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> update(PipRequest request) async {
    try {
      await _channel.invokeMethod<void>('update', _arguments(request));
    } on PlatformException {
      // Best effort: the next update or entry sends everything again.
    } on MissingPluginException {
      // Not on Android.
    }
  }

  /// The user leaves PiP through the system window; the app cannot.
  @override
  Future<bool> exit() async => true;

  @override
  Stream<PipEvent> get events => _events.stream;
}

/// The Windows picture-in-picture window (F-PIP-02, PIP-3): the main window
/// becomes a small frameless window with the video's aspect ratio in the
/// bottom-right corner of its screen, optionally above other windows; leaving
/// restores the previous bounds, maximised and fullscreen state.
final class WindowsPipPlatform implements PipPlatform {
  /// Uses [window]; [alwaysOnTop] reads the "画中画窗口置顶" setting.
  new(this.window, {required this.alwaysOnTop, this.longEdge = 480});

  /// The main window.
  final DesktopWindowOps window;

  /// Keep the PiP window above others.
  final bool Function() alwaysOnTop;

  /// Longest edge of the PiP window, logical pixels.
  final double longEdge;

  final _events = StreamController<PipEvent>.broadcast();
  _SavedWindow? _saved;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter(PipRequest request) async {
    if (_saved != null) return true;
    final saved = _SavedWindow(
      bounds: await window.getBounds(),
      maximized: await window.isMaximized(),
      fullScreen: await window.isFullScreen(),
      alwaysOnTop: await window.isAlwaysOnTop(),
    );
    _saved = saved;
    if (saved.fullScreen) await window.setFullScreen(fullScreen: false);
    if (saved.maximized) await window.unmaximize();
    final area = await window.workAreaContaining(saved.bounds) ?? saved.bounds;
    await window.setFrameless(frameless: true);
    await window.setMinimumSize(pipMinimumWindowSize);
    await window.setBounds(pipWindowRect(aspect: request.aspect, workArea: area, longEdge: longEdge));
    await window.setAspectRatio(request.aspect);
    await window.setAlwaysOnTop(alwaysOnTop: alwaysOnTop());
    _events.add(const PipModeChanged(active: true));
    return true;
  }

  @override
  Future<void> update(PipRequest request) async {
    if (_saved == null) return;
    // Keep the long edge and the bottom-right corner; the orientation may flip.
    final bounds = await window.getBounds();
    final edge = math.max(bounds.width, bounds.height);
    final size = request.aspect >= 1 ? Size(edge, edge / request.aspect) : Size(edge * request.aspect, edge);
    await window.setAspectRatio(request.aspect);
    await window.setBounds(
      Rect.fromLTWH(bounds.right - size.width, bounds.bottom - size.height, size.width, size.height),
    );
  }

  @override
  Future<bool> exit() async {
    final saved = _saved;
    if (saved == null) return true;
    _saved = null;
    try {
      await window.setAspectRatio(0);
      await window.setAlwaysOnTop(alwaysOnTop: saved.alwaysOnTop);
      await window.setFrameless(frameless: false);
      await window.setMinimumSize(minimumWindowSize);
      await window.setBounds(saved.bounds);
      if (saved.maximized) await window.maximize();
      if (saved.fullScreen) await window.setFullScreen(fullScreen: true);
      return true;
    } on Object {
      return false;
    } finally {
      _events.add(const PipModeChanged(active: false));
    }
  }

  @override
  Stream<PipEvent> get events => _events.stream;
}

final class _SavedWindow {
  const new({required this.bounds, required this.maximized, required this.fullScreen, required this.alwaysOnTop});

  final Rect bounds;
  final bool maximized;
  final bool fullScreen;
  final bool alwaysOnTop;
}

/// The smallest the Windows PiP window may be resized to.
const pipMinimumWindowSize = Size(160, 90);

/// The Windows PiP window: [longEdge] on the long side with the video's
/// [aspect], [margin] from the bottom-right corner of [workArea], shrunk to fit
/// small screens.
Rect pipWindowRect({required double aspect, required Rect workArea, double longEdge = 480, double margin = 16}) {
  final safeAspect = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
  var width = safeAspect >= 1 ? longEdge : longEdge * safeAspect;
  var height = safeAspect >= 1 ? longEdge / safeAspect : longEdge;
  final maxWidth = math.max(workArea.width - 2 * margin, pipMinimumWindowSize.width);
  final maxHeight = math.max(workArea.height - 2 * margin, pipMinimumWindowSize.height);
  final fit = math.min(1, math.min(maxWidth / width, maxHeight / height));
  width *= fit;
  height *= fit;
  return Rect.fromLTWH(workArea.right - margin - width, workArea.bottom - margin - height, width, height);
}

/// The platform of this device.
final pipPlatformProvider = Provider<PipPlatform>((ref) {
  if (Platform.isAndroid) return AndroidPipPlatform();
  if (Platform.isWindows) {
    final settings = ref.watch(storeProvider).settings;
    return WindowsPipPlatform(
      ref.watch(desktopWindowProvider),
      alwaysOnTop: () => settings.get(Settings.pipAlwaysOnTop),
    );
  }
  return const NoPipPlatform();
});

/// Waits until the video-only layout is on screen: two frames, so the frame
/// is rasterised before the system captures it (PIP-2).
final pipFrameWaiterProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await SchedulerBinding.instance.endOfFrame;
    await SchedulerBinding.instance.endOfFrame;
  },
);

/// Picture-in-picture for the room video (F-PIP-01, F-PIP-02, §9).
///
/// [enter] switches the UI to the video-only layout, waits for it to be on
/// screen and then asks the platform. The platform's mode reports win over
/// the request's result (PIP-2). [cancel] drops an entry in progress when the
/// room closes or switches.
class PipController extends Notifier<PipState> {
  late PipPlatform _platform;
  late StreamController<bool> _toggles;
  var _serial = 0;
  var _reported = false;
  PipRequest? _last;
  Timer? _fallback;

  /// How long an accepted entry may wait for the platform's report.
  static const reportTimeout = Duration(seconds: 3);

  @override
  PipState build() {
    _platform = ref.watch(pipPlatformProvider);
    _toggles = StreamController<bool>.broadcast();
    final events = _platform.events.listen(_onEvent);
    ref.onDispose(() {
      _fallback?.cancel();
      unawaited(events.cancel());
      unawaited(_toggles.close());
    });
    unawaited(
      _platform.isSupported().then((supported) {
        if (!ref.mounted || supported == state.supported) return;
        state = state.copyWith(supported: supported);
        // Parameters that arrived before support was known go out now.
        final last = _last;
        if (supported && last != null) unawaited(_platform.update(last));
      }),
    );
    return const PipState();
  }

  /// The PiP window's play/pause action: true asks to play.
  Stream<bool> get playToggles => _toggles.stream;

  /// Enters picture-in-picture with [session]'s video. [sourceRect] is where
  /// the video is, in physical pixels of the window. Returns false when PIP-1
  /// does not allow it or the platform refused.
  Future<bool> enter(PlaybackSession session, {Rect? sourceRect}) async {
    final playback = session.state;
    if (!state.supported || !pipEntryAllowed(state: playback, engineReady: session.engine != null, mode: state.mode)) {
      return false;
    }
    final serial = ++_serial;
    _reported = false;
    state = state.copyWith(mode: PipMode.entering);
    await ref.read(pipFrameWaiterProvider)();
    if (!ref.mounted || serial != _serial || state.mode != PipMode.entering) return false;
    final request = PipRequest(
      aspect: pipAspect(session.state),
      sourceRect: sourceRect,
      playing: session.state.wantsPlay,
      // Automatic entry stays as the last update set it.
      autoEnter: _last?.autoEnter ?? false,
    );
    _last = request;
    bool accepted;
    try {
      accepted = await _platform.enter(request);
    } on Object {
      accepted = false;
    }
    if (!ref.mounted || serial != _serial) return false;
    if (_reported) return state.mode == PipMode.active;
    if (!accepted) {
      state = state.copyWith(mode: PipMode.off);
      return false;
    }
    _fallback?.cancel();
    _fallback = Timer(reportTimeout, () {
      if (ref.mounted && serial == _serial && !_reported && state.mode == PipMode.entering) {
        state = state.copyWith(mode: PipMode.off);
      }
    });
    return true;
  }

  /// Drops an entry in progress (the room closed or switched, PIP-2).
  void cancel() {
    if (state.mode != PipMode.entering) return;
    _serial++;
    _fallback?.cancel();
    state = state.copyWith(mode: PipMode.off);
  }

  /// Leaves picture-in-picture where the app can (Windows); false when the
  /// window could not be restored (PIP-3 asks for a message).
  Future<bool> exit() async {
    _serial++;
    _fallback?.cancel();
    if (state.mode == PipMode.off) return true;
    final restored = await _platform.exit();
    if (ref.mounted && state.mode == PipMode.entering) state = state.copyWith(mode: PipMode.off);
    return restored;
  }

  /// Keeps the platform current: the aspect ratio after a geometry change,
  /// the play state for the action icon and automatic entry (Android 12+).
  /// Changes below the thresholds of [PipRequest.differsFrom] are not sent.
  Future<void> update({required double aspect, required bool playing, required bool autoEnter}) async {
    final request = PipRequest(aspect: aspect, playing: playing, autoEnter: autoEnter);
    if (!request.differsFrom(_last)) return;
    _last = request;
    if (!state.supported) return;
    await _platform.update(request);
  }

  void _onEvent(PipEvent event) {
    switch (event) {
      case PipModeChanged(:final active):
        _reported = true;
        _fallback?.cancel();
        if (!active) _serial++;
        state = state.copyWith(mode: active ? PipMode.active : PipMode.off);
      case PipPlayToggled(:final play):
        _toggles.add(play);
    }
  }
}

/// Picture-in-picture state and commands.
final pipProvider = NotifierProvider<PipController, PipState>(PipController.new);
