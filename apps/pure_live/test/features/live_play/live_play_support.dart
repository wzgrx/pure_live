import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

/// A platform with scripted answers (the live room's tests).
class FakeSite extends LiveSite {
  /// Creates the platform; [room] is what the detail answers.
  new(this.room);

  /// The detail's answer.
  LiveRoom room;

  /// Thrown by the detail instead of answering.
  Exception? detailError;

  /// The qualities.
  List<LivePlayQuality> qualities = const [
    LivePlayQuality(quality: '原画', id: 10000),
    LivePlayQuality(quality: '超清', id: 250),
    LivePlayQuality(quality: '流畅', id: 80),
  ];

  /// Super chats on display when the room opens.
  List<LiveSuperChatMessage> superChats = const [];

  /// Detail requests so far.
  int detailCalls = 0;

  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => '哔哩哔哩';

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    detailCalls++;
    if (detailError case final error?) throw error;
    return room;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => qualities;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${quality.id}.flv',
    'https://b.example/${quality.id}.flv',
  ];

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async => superChats;
}

/// A platform that downgrades every request to [applied] (Bilibili guests).
class DowngradingSite extends FakeSite implements LivePlayUrlResolver {
  /// Creates the platform.
  new(super.room, {required this.applied});

  /// The quality id the platform really serves.
  final Object applied;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(urls: ['https://a.example/$applied.flv'], appliedQualityData: applied);
}

/// A danmaku connection driven by the test.
final class FakeDanmaku implements DanmakuConnection {
  final StreamController<DanmakuEvent> _events = StreamController.broadcast(sync: true);

  /// Arguments of every connect.
  final List<Object?> connects = [];

  /// Number of closes.
  int closes = 0;

  @override
  DanmakuStatus status = DanmakuStatus.idle;

  @override
  Stream<DanmakuEvent> get events => _events.stream;

  @override
  bool get isConnected => status == DanmakuStatus.connected;

  @override
  Duration get heartbeatInterval => Duration.zero;

  @override
  Future<void> connect(Object? args) async {
    connects.add(args);
    status = DanmakuStatus.connected;
    _events.add(const DanmakuReady());
  }

  /// Reports [event].
  void emit(DanmakuEvent event) {
    if (event is DanmakuClosed) status = DanmakuStatus.closed;
    _events.add(event);
  }

  /// Reports a chat message.
  void chat(String text, {String user = '观众', String id = ''}) => emit(
    DanmakuReceived(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: user,
        userId: user,
        message: text,
        color: LiveMessageColor.white,
        messageId: id,
      ),
    ),
  );

  @override
  void heartbeat() {}

  @override
  Future<void> close() async {
    closes++;
    status = DanmakuStatus.idle;
  }
}

/// An engine that plays whatever it opens.
final class FakeEngine implements PlayerEngine {
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);

  /// Opened media, in order.
  final List<EngineMedia> opens = [];

  @override
  bool get reportsFrames => false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  /// Reports [event] as the engine.
  void emit(EngineEvent event) => _events.add(event);

  /// The position [advance] reports next.
  Duration position = Duration.zero;

  /// Reports playback moving on by a second (mpv's `time-pos`).
  void advance() {
    position += const Duration(seconds: 1);
    _events.add(EnginePosition(position));
  }

  /// What the next opens do instead of playing (B02: an open that hangs
  /// keeps a recovery on screen); null plays.
  Future<void> Function(EngineMedia media)? onOpen;

  @override
  Future<void> open(EngineMedia media) async {
    opens.add(media);
    if (onOpen case final script?) {
      await script(media);
      return;
    }
    _events
      ..add(const EngineBuffering(buffering: false))
      ..add(const EnginePlaying(playing: true));
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioOnly({required bool enabled}) async {}

  /// Whether the session released it.
  bool disposed = false;

  @override
  Future<void> dispose() {
    disposed = true;
    return _events.close();
  }
}

/// A session over [engine].
PlaybackSession fakeSession(FakeEngine engine) => PlaybackSession(engine: () async => engine, opener: MediaOpener());

/// A live Bilibili room.
LiveRoom liveRoom({
  LiveStatus status = LiveStatus.live,
  LiveRestriction? restriction,
  DateTime? startedAt,
  String? link,
}) => LiveRoom(
  link: link,
  platform: SiteIds.bilibili,
  roomId: '6',
  nick: '主播',
  title: '今晚开黑',
  area: '英雄联盟',
  liveStatus: status,
  popularity: '120000',
  restriction: restriction,
  startedAt: startedAt,
  notice: '每晚八点开播',
  danmakuData: 'args-6',
);
