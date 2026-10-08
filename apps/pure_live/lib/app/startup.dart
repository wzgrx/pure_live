import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/account/account_services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

/// How long the splash page waits for the first follow check before home
/// (3.x `app_pages.dart`: a bounded part of the launch transition).
const Duration splashFollowWait = Duration(milliseconds: 350);

/// How long after start the Bilibili login is checked (3.x
/// `BiliBiliAccountService.initialLoadDelay`).
const Duration bilibiliCheckDelay = Duration(seconds: 1);

/// The sign-ins the 3.x import could not keep: the platform cipher failed
/// on this device ([LegacyImportReport.skippedSecrets]), so the user is told
/// once to sign in again.
abstract final class LegacyReloginNotice {
  /// The meta record of a notice still owed.
  static const String key = 'app.legacyReloginNotice';

  /// Records after the import that [report] owes the notice.
  static Future<void> record(MetaStore meta, LegacyImportReport report) async {
    if (report.skippedSecrets.isNotEmpty) await meta.set(key, '${report.skippedSecrets.length}');
  }

  /// Shows the owed notice once ([toast] by default the app's); whether it
  /// was shown.
  static Future<bool> showOnce(MetaStore meta, {void Function(String message)? toast}) async {
    if (await meta.get(key) == null) return false;
    await meta.set(key, null);
    (toast ?? AppNavigator.toast)(i18n('legacy_import_relogin'));
    return true;
  }
}

/// What the app starts once its first frame is up (3.x started these with
/// its services, in every window): the first check of every follow, the
/// exit timer, the timed cover refresh, Android 17's local-network
/// permission for a LAN proxy, the display mode, the one-time removal of
/// masked blocked names ([MaskedNameBlocks], B01), and one second later the
/// Bilibili login check and the 3.x import's [LegacyReloginNotice].
final class AppStartup {
  /// Creates the start-up over [_ref]'s providers.
  new(this._ref);

  final Ref _ref;
  Timer? _bilibili;
  CoverRefreshTimer? _covers;
  LocalNetworkGuard? _localNetwork;
  bool _started = false;

  /// The first check of every follow once started; the splash page waits for
  /// it, at most [splashFollowWait].
  static Future<void>? followCheck;

  /// Starts the work once.
  void start() {
    if (_started) return;
    _started = true;
    final store = _ref.read(storeProvider);
    AutoExitTimer.instance.attach(store.settings);
    _covers = CoverRefreshTimer(store.settings)..start();
    if (Platform.isAndroid) _localNetwork = LocalNetworkGuard(store.settings)..start();
    unawaited(DisplayMode.refresh());
    unawaited(
      MaskedNameBlocks.cleanOnce(store.blockLists, store.meta).catchError((Object error, StackTrace stack) {
        log('Masked block cleanup failed', name: 'Startup', error: error, stackTrace: stack);
        return 0;
      }),
    );
    followCheck = _ref.read(favoriteControllerProvider).firstCheck;
    _bilibili = Timer(bilibiliCheckDelay, () {
      unawaited(LegacyReloginNotice.showOnce(store.meta).catchError((Object _) => false));
      unawaited(
        verifyBilibiliLogin(actions: _ref.read(accountActionsProvider), verify: _ref.read(accountVerifierProvider)),
      );
    });
  }

  /// Stops what is still waiting.
  void dispose() {
    _bilibili?.cancel();
    unawaited(_covers?.dispose());
    unawaited(_localNetwork?.dispose());
    if (_started) {
      AutoExitTimer.instance.detach();
      followCheck = null;
    }
  }
}

/// The app's start-up (one per app).
final Provider<AppStartup> appStartupProvider = Provider((ref) {
  final startup = AppStartup(ref);
  ref.onDispose(startup.dispose);
  return startup;
});

/// Checks the stored Bilibili login (3.x `BiliBiliAccountService.loadUserInfo`,
/// the account page's check): remembers the uid of a valid one, signs an
/// expired one out and says so, and says when the check failed. Nothing
/// happens without a cookie, or when the cookie changed meanwhile.
Future<void> verifyBilibiliLogin({required AccountActions actions, required AccountVerifier verify}) async {
  final cookie = actions.cookieOf(SiteIds.bilibili);
  if (cookie.isEmpty) return;
  try {
    final identity = await verify(SiteIds.bilibili, cookie);
    if (actions.cookieOf(SiteIds.bilibili) != cookie) return;
    if (identity.uid case final uid?) await actions.rememberBilibili(uid, name: identity.name);
  } on NeedsLogin {
    if (actions.cookieOf(SiteIds.bilibili) != cookie) return;
    AppNavigator.toast(i18n('bilibili_login_expired'));
    await actions.signOut(SiteIds.bilibili);
  } on Object catch (error, stack) {
    log('Bilibili login check failed', name: 'Startup', error: error, stackTrace: stack);
    if (actions.cookieOf(SiteIds.bilibili) == cookie) AppNavigator.toast(i18n('bilibili_user_info_failed'));
  }
}

/// The steps before `runApp`, in their order; each one's number in the
/// `startup-timing` line is how long that step took (ms):
///
/// * `binding`: `main` until `WidgetsFlutterBinding.ensureInitialized`;
/// * `imageCache`: the decoded-image budget (reads /proc/meminfo);
/// * `tvDetect`: `TvDevice.detect` (one native call);
/// * `dataRoot`: the command line, the data folder and the cipher;
/// * `store`: `LiveStore.open`;
/// * `legacy`: the 3.x settings and IPTV import (main window; a `stat` once
///   imported);
/// * `wire`: `AppBootstrap.wire`;
/// * `log`: the plugin hooks and the log file;
/// * `strings`: the language and its words;
/// * `fonts`: the app and danmaku fonts;
/// * `desktop`: the desktop window (nothing on a phone).
const List<String> startupSteps = [
  'binding',
  'imageCache',
  'tvDetect',
  'dataRoot',
  'store',
  'legacy',
  'wire',
  'log',
  'strings',
  'fonts',
  'desktop',
];

/// The moments from `runApp` on, in their order; each one's number is the
/// time since `main` began (ms): `runApp` called, the first frame
/// rasterized (the splash page when it is on), home's first frame, and
/// home's first content ([StartupTiming.firstContent]).
const List<String> startupMarks = ['runApp', 'firstFrame', 'home', 'firstPage'];

/// What Android says about the process when asked once at start: `cold` is
/// true for the first `main` of the process (false after the activity was
/// recreated over a live process, or a Dart restart in it), and
/// `processToMain` is how long the process ran before `main` (ms), null when
/// unknown (not Android).
typedef StartupProcess = ({bool cold, int? processToMain});

/// The time from the process's start to `main` (ms): the process's age that
/// Android measured between [sent] and [received] (times since `main`), less
/// the middle of that call, so the call's own time counts at most half.
int processToMainMs({required int sinceProcessStart, required Duration sent, required Duration received}) {
  final middle = (sent.inMicroseconds + received.inMicroseconds) ~/ 2000;
  return math.max(0, sinceProcessStart - middle);
}

/// The `startup-timing` line
/// (docs/R-性能和流畅度/R04-启动速度/R04.1-启动速度/record.md), for example:
///
/// ```text
/// startup-timing cold=true splash=on tab=popular content=rooms process=180 binding=12 … desktop=0 runApp=131 firstFrame=260 home=1420 firstPage=1980 total=2160
/// ```
///
/// [steps] are durations, [marks] times since `main` (both ms, by name,
/// [startupSteps] and [startupMarks] in that order); a missing one shows as
/// `-`. `process` is the process's start to `main`, `total` the process's
/// start to `firstPage`; both need [processToMain].
String formatStartupTiming({
  required bool cold,
  required bool? splash,
  required String? tab,
  required String? content,
  required int? processToMain,
  required Map<String, int> steps,
  required Map<String, int> marks,
}) {
  String value(int? ms) => ms == null ? '-' : '$ms';
  final firstPage = marks['firstPage'];
  return [
    'startup-timing',
    'cold=$cold',
    'splash=${splash == null ? '-' : (splash ? 'on' : 'off')}',
    'tab=${tab ?? '-'}',
    'content=${content ?? '-'}',
    'process=${value(processToMain)}',
    for (final name in startupSteps) '$name=${value(steps[name])}',
    for (final name in startupMarks) '$name=${value(marks[name])}',
    'total=${value(processToMain == null || firstPage == null ? null : processToMain + firstPage)}',
  ].join(' ');
}

/// The start-up's timing (docs/R-性能和流畅度/R04-启动速度/R04.1-启动速度): `main`
/// begins it ([begin]); the start records its [step]s before `runApp` and
/// its [mark]s after; home's first content ([firstContent]) calls Android's
/// `reportFullyDrawn` once and, on a cold start only, writes one
/// `startup-timing` line ([formatStartupTiming]) to the app log and
/// `debugPrint`.
///
/// Home's first content, the first of these, once per `main`:
///
/// * popular as the first home tab: the first rooms of the platform shown,
///   or its empty or error state, drawn (the popular page reports it);
/// * follows as the first home tab: the stored follows read and drawn
///   ([followsFirstContent]; the first check of their live states runs on
///   afterwards);
/// * areas or the recording centre as the first home tab, and the TV
///   interface: home's first frame (their pages do not report);
/// * with the splash page on, home is built only once the splash page has
///   left, so its content always comes after it.
///
/// Everything is measured from `main`; the clock and the native side are
/// replaceable for tests.
final class StartupTiming {
  /// A timing over `clock` (the time since `main`); [process] asks Android
  /// about the process, [write] puts the line out and [reportFullyDrawn]
  /// tells Android that home is usable.
  new({
    required this._clock,
    Future<StartupProcess> Function(Duration Function() clock)? process,
    void Function(String line)? write,
    Future<void> Function()? reportFullyDrawn,
  }) : _ask = process ?? askAndroidProcess,
       _write = write ?? _writeLine,
       _reportFullyDrawn = reportFullyDrawn ?? _reportToAndroid;

  /// The timing of this `main`; null before [begin] (tests set their own).
  static StartupTiming? current;

  /// Starts the timing of this `main` (its first line).
  static void begin() {
    final watch = Stopwatch()..start();
    current = StartupTiming(clock: () => watch.elapsed);
  }

  /// The activity's app channel (`startupInfo`, `reportFullyDrawn`).
  static const MethodChannel channel = MethodChannel('pure_live/app');

  final Duration Function() _clock;
  final Future<StartupProcess> Function(Duration Function() clock) _ask;
  final void Function(String line) _write;
  final Future<void> Function() _reportFullyDrawn;
  final Map<String, int> _steps = {};
  final Map<String, int> _marks = {};
  Duration _lap = Duration.zero;
  Future<StartupProcess>? _process;
  bool _abandoned = false;
  bool _reported = false;

  /// Whether the splash page was on (`splash=` in the line).
  bool? splash;

  /// Whether home's first content was reported.
  bool get reported => _reported;

  /// Records step [name] as the time since the previous step (or `main`);
  /// a step recorded again (a retried start) keeps its first time.
  void step(String name) {
    if (_steps.containsKey(name)) return;
    final now = _clock();
    _steps[name] = (now - _lap).inMilliseconds;
    _lap = now;
  }

  /// Records moment [name] as the time since `main`; once.
  void mark(String name) => _marks.putIfAbsent(name, () => _clock().inMilliseconds);

  /// Asks Android about the process (once; after the binding, which the
  /// channel needs). [firstContent] asks when this was not called.
  void askProcess() => _process ??= _ask(_clock);

  /// The start failed and showed why: the numbers include the failure page
  /// and the retry, so no line is written (home still reports drawn).
  void abandon() => _abandoned = true;

  /// Home's first content is drawn ([tab]: the home tab's id or `tv`;
  /// [content]: `rooms`, `empty`, `error`, or `home` for a page measured at
  /// home's first frame): marks `firstPage`, reports fully drawn and, on a
  /// cold start, writes the line. Only the first call counts.
  Future<void> firstContent({required String tab, required String content}) async {
    if (_reported) return;
    _reported = true;
    mark('firstPage');
    try {
      await _reportFullyDrawn();
    } on Object catch (error) {
      log('reportFullyDrawn failed', name: 'Startup', error: error);
    }
    if (_abandoned) return;
    final process = await (_process ??= _ask(_clock));
    if (!process.cold) return;
    _write(
      formatStartupTiming(
        cold: true,
        splash: splash,
        tab: tab,
        content: content,
        processToMain: process.processToMain,
        steps: _steps,
        marks: _marks,
      ),
    );
  }

  /// Android's answer to `startupInfo` (see [StartupProcess]); not cold
  /// when no activity answers (an engine started by a service). Other
  /// systems have no such warm start: cold, without the process's time.
  static Future<StartupProcess> askAndroidProcess(Duration Function() clock) async {
    if (!Platform.isAndroid) return (cold: true, processToMain: null);
    try {
      final sent = clock();
      final info = await channel.invokeMapMethod<String, Object?>('startupInfo');
      final received = clock();
      final since = info?['sinceProcessStart'];
      return (
        cold: info?['cold'] == true,
        processToMain: since is int ? processToMainMs(sinceProcessStart: since, sent: sent, received: received) : null,
      );
    } on Object {
      // No activity, or an answer it did not expect: not measured.
      return (cold: false, processToMain: null);
    }
  }

  static void _writeLine(String line) {
    AppLog.instance.info('startup', line);
    debugPrint(line);
  }

  static Future<void> _reportToAndroid() async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('reportFullyDrawn');
    } on MissingPluginException {
      // No activity.
    }
  }
}

/// Reports the follows as home's first content to [timing] once they were
/// read from storage (at once when they were) and drawn: `rooms`, or
/// `empty` without any (also when reading them failed).
Future<void> followsFirstContent(FavoriteController follows, StartupTiming timing) async {
  if (!follows.loaded) {
    final read = Completer<void>();
    void listener() {
      if (follows.loaded && !read.isCompleted) read.complete();
    }

    follows.addListener(listener);
    try {
      await read.future;
    } finally {
      follows.removeListener(listener);
    }
    await WidgetsBinding.instance.endOfFrame;
  }
  await timing.firstContent(tab: HomeMenu.favorites.id, content: follows.rooms.isEmpty ? 'empty' : 'rooms');
}
