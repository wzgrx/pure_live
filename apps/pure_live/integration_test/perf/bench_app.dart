// The benchmarks' app (P05, UI_PLAN §9.4): the real PureLiveApp over an
// in-memory store and fake platform data, so no live platform is contacted
// (docs/cloud/RULES.md): a hot list of 300 rooms answering like a network,
// covers and avatars from a server on this device, danmaku the benchmark
// sends, and players that play nothing (the video's own cost is not in these
// figures).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

import '../../test/features/live_play/live_play_support.dart';
import '../../test/support.dart';

/// Shorter runs (`--dart-define=PERF_QUICK=true`): proves the benchmarks run
/// on a desktop or in the headless tester; the figures need the full runs on
/// a phone.
const bool perfQuick = bool.fromEnvironment('PERF_QUICK');

/// The refresh rate the budgets use (`--dart-define=PERF_HZ=120`); 0 reads
/// the display's.
const int perfHz = int.fromEnvironment('PERF_HZ');

/// The room count of the hot list.
const int benchRoomCount = 300;

/// What every scenario shares: the cover server and the device facts.
final class BenchEnvironment {
  new _(this.covers, this.dataRoot, this.totalMemoryBytes);

  /// Starts the cover server and applies the app's decoded-image budget.
  static Future<BenchEnvironment> start() async {
    final covers = await CoverServer.start();
    final dataRoot = Platform.isAndroid ? await getTemporaryDirectory() : Directory.systemTemp;
    final memory = Platform.isAndroid ? readTotalMemoryBytes() : null;
    // The budget AppBootstrap.start sets (D2).
    configureDecodedImageCache(desktop: Platform.isWindows, totalMemoryBytes: memory);
    return BenchEnvironment._(covers, dataRoot, memory);
  }

  /// Covers and avatars.
  final CoverServer covers;

  /// Where the app's data folder points (nothing is written for good).
  final Directory dataRoot;

  /// RAM read from /proc/meminfo (Android), or null.
  final int? totalMemoryBytes;

  /// The device facts of the report.
  Map<String, Object?> deviceJson(ui.FlutterView view) {
    final cache = PaintingBinding.instance.imageCache;
    return {
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'displayRefreshRate': view.display.refreshRate,
      'budgetRefreshRate': refreshRateOf(view),
      'logicalSize':
          '${(view.physicalSize.width / view.devicePixelRatio).round()}x'
          '${(view.physicalSize.height / view.devicePixelRatio).round()}',
      'devicePixelRatio': view.devicePixelRatio,
      'totalMemoryMiB': totalMemoryBytes == null ? null : totalMemoryBytes! ~/ (1024 * 1024),
      'imageCacheMaxCount': cache.maximumSize,
      'imageCacheMaxMiB': cache.maximumSizeBytes ~/ (1024 * 1024),
      'quick': perfQuick,
    };
  }

  /// Stops the server.
  Future<void> close() => covers.close();
}

/// The refresh rate of the budgets: [perfHz] when given, else the display's
/// (60 when it says nothing).
double refreshRateOf(ui.FlutterView view) {
  if (perfHz > 0) return perfHz.toDouble();
  final rate = view.display.refreshRate;
  return rate.isFinite && rate >= 30 ? rate : 60;
}

/// Covers (960×540) and avatars (160×160) over HTTP on 127.0.0.1: a few
/// pictures drawn at start; each room has its own addresses, so each card
/// loads and decodes its own like real covers.
final class CoverServer {
  new _(this._server, this._covers, this._avatars) {
    _server.listen(_answer);
  }

  /// Draws the pictures and starts serving them.
  static Future<CoverServer> start() async {
    final covers = [for (var i = 0; i < 6; i++) await benchPicture(960, 540, i)];
    final avatars = [for (var i = 0; i < 4; i++) await benchPicture(160, 160, i + 6)];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return CoverServer._(server, covers, avatars);
  }

  final HttpServer _server;
  final List<Uint8List> _covers;
  final List<Uint8List> _avatars;

  /// The cover address of room [index].
  String cover(int index) => 'http://127.0.0.1:${_server.port}/cover/$index.png';

  /// The avatar address of room [index].
  String avatar(int index) => 'http://127.0.0.1:${_server.port}/avatar/$index.png';

  /// The cover pictures (PNG).
  List<Uint8List> get covers => _covers;

  void _answer(HttpRequest request) {
    final segments = request.uri.pathSegments;
    final index = segments.length == 2 ? int.tryParse(segments[1].split('.').first) : null;
    final pictures = switch (segments.firstOrNull) {
      'cover' => _covers,
      'avatar' => _avatars,
      _ => null,
    };
    final response = request.response;
    if (pictures == null || index == null) {
      response.statusCode = HttpStatus.notFound;
    } else {
      final bytes = pictures[index % pictures.length];
      response.headers
        ..contentType = ContentType('image', 'png')
        ..contentLength = bytes.length
        ..set(HttpHeaders.cacheControlHeader, 'max-age=86400');
      response.add(bytes);
    }
    unawaited(response.close());
  }

  /// Stops serving.
  Future<void> close() => _server.close(force: true);
}

/// A PNG of [width]×[height] with a gradient, discs and bars in the colours
/// of [seed] (stand-ins for real covers: varied, not flat).
Future<Uint8List> benchPicture(int width, int height, int seed) async {
  final random = math.Random(seed);
  Color colour() => Color.fromARGB(255, random.nextInt(256), random.nextInt(256), random.nextInt(256));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final area = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
    area,
    Paint()..shader = ui.Gradient.linear(area.topLeft, area.bottomRight, [colour(), colour(), colour()], [0, 0.6, 1]),
  );
  for (var i = 0; i < 24; i++) {
    final paint = Paint()..color = colour().withValues(alpha: 0.35 + random.nextDouble() * 0.5);
    final centre = Offset(random.nextDouble() * width, random.nextDouble() * height);
    if (i.isEven) {
      canvas.drawCircle(centre, 8 + random.nextDouble() * height / 4, paint);
    } else {
      canvas.drawRect(Rect.fromCenter(center: centre, width: width / 6, height: height / 14), paint);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

const List<String> _titles = [
  '今晚冲分，不上王者不下播',
  '新游首发 全流程实况',
  '深夜电台：聊聊最近的电影',
  '【高能】极限操作合集回放',
  '户外｜城市夜景慢慢走',
  '一起学做家常菜 第 37 期',
  '赛事直播：半决赛 BO5',
  '钢琴即兴 点歌请发弹幕',
];

const List<String> _areas = ['英雄联盟', '原神', '聊天', '单机游戏', '户外', '美食', '赛事', '音乐'];

/// Room [index] of the hot list, its cover and avatar from [covers].
LiveRoom benchRoom(int index, CoverServer? covers) => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: '$index',
  title: _titles[index % _titles.length],
  nick: '主播$index',
  cover: covers?.cover(index) ?? '',
  avatar: covers?.avatar(index) ?? '',
  area: _areas[index % _areas.length],
  audienceMetricType: AudienceMetricType.popularity,
  popularity: '${(benchRoomCount - index) * 3271}',
  liveStatus: LiveStatus.live,
  startedAt: DateTime.now().subtract(Duration(minutes: 5 + index % 300)),
  danmakuData: 'args-$index',
);

/// Bilibili with [benchRoomCount] live rooms in pages, each page answering
/// after [delay] like a network.
final class BenchSite extends FakeSite {
  /// Creates the platform.
  new(this.covers, {this.delay = const Duration(milliseconds: 300)}) : super(benchRoom(0, covers));

  /// Covers and avatars.
  final CoverServer? covers;

  /// How long a page takes.
  final Duration delay;

  /// Rooms handed out so far.
  int roomsServed = 0;

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    await Future<void>.delayed(delay);
    final start = (page - 1) * pageSize;
    final rooms = [for (var i = start; i < math.min(start + pageSize, benchRoomCount); i++) benchRoom(i, covers)];
    roomsServed += rooms.length;
    return rooms;
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    detailCalls++;
    return benchRoom(int.tryParse(roomId) ?? 0, covers);
  }
}

/// Every danmaku connection the app opened, to send to.
final class DanmakuHub {
  /// The connections, in order.
  final List<FakeDanmaku> connections = [];

  /// A new connection (the registry's factory).
  FakeDanmaku create() {
    final connection = FakeDanmaku();
    connections.add(connection);
    return connection;
  }

  static const List<String> _phrases = [
    '666',
    '主播好强',
    '这波操作可以',
    '哈哈哈哈哈哈',
    '来了来了',
    '前方高能预警',
    '这个配置能跑满帧吗？',
    '晚上好，今天打几把',
    '支持一下[dog]',
    '刚下班，赶上了',
    '弹幕护体',
    '这首歌叫什么名字啊有没有人知道',
  ];

  /// Sends [perSecond] chat messages for [duration] to each of [targets]
  /// (the newest connection by default), spread evenly over 20 ms ticks;
  /// answers how many went out in all.
  Future<int> send({required int perSecond, required Duration duration, List<FakeDanmaku>? targets}) async {
    final to = targets ?? [connections.last];
    final random = math.Random(perSecond);
    final clock = Stopwatch()..start();
    final done = Completer<void>();
    var sent = 0;
    Timer.periodic(const Duration(milliseconds: 20), (timer) {
      final elapsed = clock.elapsed;
      final due = (math.min(elapsed.inMicroseconds, duration.inMicroseconds) * perSecond / 1e6).floor();
      for (; sent < due; sent++) {
        final text = '${_phrases[random.nextInt(_phrases.length)]} ${sent % 97}';
        for (final connection in to) {
          connection.chat(text, user: '观众${random.nextInt(5000)}', id: '$sent');
        }
      }
      if (elapsed >= duration) {
        timer.cancel();
        done.complete();
      }
    });
    await done.future;
    return sent * to.length;
  }
}

/// One app run: the services, the fakes and the app on screen.
final class BenchApp {
  new _(this.services, this.site, this.danmaku);

  /// The settings of every run: the hot list first among the home tabs,
  /// Bilibili only, no splash, no update check, and the display's highest
  /// rate all the time, so the budget stays one period of it.
  static Future<void> _settle(LiveStore store) async {
    final settings = store.settings;
    await settings.set(Settings.savedMenuIds, ['popular', 'favorites', 'areas']);
    await settings.set(Settings.showSplashPage, false);
    await settings.set(Settings.hotAreasList, [SiteIds.bilibili]);
    await settings.set(Settings.enableAutoCheckUpdate, false);
    await settings.set(Settings.refreshRateMode, 'performance');
  }

  /// Shows the app at its home (the hot list) with [follows] followed rooms.
  static Future<BenchApp> pump(WidgetTester tester, BenchEnvironment environment, {int follows = 0}) async {
    final cipher = FakeCipher();
    final store = await LiveStore.memory(cipher: cipher);
    await _settle(store);
    for (var i = 1; i <= follows; i++) {
      await store.follows.add(benchRoom(i, environment.covers));
    }
    final base = AppBootstrap.wire(
      store: store,
      cipher: cipher,
      launch: const LaunchArgs(),
      dataRoot: environment.dataRoot,
      http: NoNetworkHttp(),
      background: false,
    );
    final site = BenchSite(environment.covers);
    final danmaku = DanmakuHub();
    final services = AppServices(
      store: base.store,
      cipher: base.cipher,
      http: base.http,
      proxy: base.proxy,
      cookies: base.cookies,
      sites: SiteRegistry({SiteIds.bilibili: () => site}),
      danmaku: DanmakuRegistry({SiteIds.bilibili: danmaku.create}),
      launch: base.launch,
      dataRoot: base.dataRoot,
      followsReady: base.followsReady,
      mediaOpener: base.mediaOpener,
      recording: base.recording,
    );
    final strings = await AppStrings.load(AppLanguage.zh, rootBundle);
    currentStrings = strings;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
        ],
        child: PureLiveApp(strings: strings),
      ),
    );
    AppNavigator.toast = (_) {};
    final app = BenchApp._(services, site, danmaku);
    await waitFor(tester, find.text(app.site.room.title).hitTestable());
    await idle(tester, const Duration(seconds: 1));
    return app;
  }

  /// The services.
  final AppServices services;

  /// The platform.
  final BenchSite site;

  /// The danmaku connections.
  final DanmakuHub danmaku;

  /// Takes the app down.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await idle(tester, const Duration(milliseconds: 500));
    await services.close();
  }
}

/// Lets the app run for [duration]: frames come as the engine and the app
/// ask for them (the benchmarks' frame policy ignores the test's pumps).
Future<void> idle(WidgetTester tester, Duration duration) => Future<void>.delayed(duration);

/// Waits until [finder] finds something; fails after [timeout].
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) =>
    waitUntil(tester, () => finder.evaluate().isNotEmpty, timeout: timeout, what: '$finder');

/// Waits until [condition] holds; fails after [timeout].
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String what = 'a condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The resident memory now, in MiB.
int residentMiB() => ProcessInfo.currentRss ~/ (1024 * 1024);
