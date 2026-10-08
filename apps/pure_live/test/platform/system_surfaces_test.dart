import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/app/recording_notice.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/platform/recording_platform.dart';

import '../support.dart';

// docs/A-界面设计/A14-系统界面/A14.1-系统界面 (Android): what the system draws with the app's
// words — the notifications, the picture-in-picture action, the icons and
// the splash screen.

RecordTask _task(String id, String nick, {RecordStatus status = RecordStatus.running, DateTime? started}) =>
    RecordTask(
        taskId: id,
        roomId: id,
        platform: 'douyu',
        title: '深夜电台 · 点歌接龙到天亮',
        nick: nick,
        avatar: '',
        cover: '',
        createTime: DateTime(2026, 10, 2, 20),
      )
      ..status = status
      ..selectedQuality = '原画'
      ..recordingStartedAt = started;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStrings);

  group('recording notification (c3, c4)', () {
    test('one room: who, what and the quality; several: how many and who; the clock from the first', () {
      final first = DateTime(2026, 10, 2, 21);
      final one = recordNotificationContent([
        _task('a', '晚风', started: first),
        _task('b', '星河长明', status: RecordStatus.waitingLive),
      ]);
      expect((one.title, one.text, one.stop, one.since), ('正在录制 · 晚风', '深夜电台 · 点歌接龙到天亮 · 原画', '停止录制', first));
      final two = recordNotificationContent([
        _task('a', '晚风', started: DateTime(2026, 10, 2, 22)),
        _task('b', '星河长明', status: RecordStatus.reconnecting, started: first),
      ]);
      expect((two.title, two.text, two.stop, two.since), ('正在录制 2 个直播间', '晚风、星河长明', '全部停止', first));
    });

    test('one room says what it does: only writing is "正在录制" (U.2a2 X4)', () {
      String title(RecordStatus status) => recordNotificationContent([_task('a', '晚风', status: status)]).title;
      expect(title(RecordStatus.running), '正在录制 · 晚风');
      expect(title(RecordStatus.preparing), '准备录制 · 晚风');
      expect(title(RecordStatus.reconnecting), '正在重连 · 晚风');
      expect(title(RecordStatus.processing), '正在整理录像 · 晚风');
    });

    test('the keep-alive sends the words, again only when they change, and "停止录制" stops all', () async {
      const channel = MethodChannel('pure_live/recorder');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var title = '正在录制 · 晚风';
      var stops = 0;
      final keepAlive = AndroidRecordKeepAlive(
        title: () => title,
        text: () => '深夜电台',
        extra: () => {'stop': '停止录制', 'channel': '录制'},
        onInterrupted: (_) async {},
        onStopAll: () async => stops++,
      );
      final owner = Object();
      await keepAlive.acquire(owner);
      expect(calls.single.arguments, {
        'active': true,
        'title': '正在录制 · 晚风',
        'text': '深夜电台',
        'stop': '停止录制',
        'channel': '录制',
      });
      await keepAlive.refresh();
      expect(calls, hasLength(1), reason: 'nothing changed');
      title = '正在录制 2 个直播间';
      await keepAlive.refresh();
      expect((calls.last.method, (calls.last.arguments as Map)['title']), ('update', '正在录制 2 个直播间'));
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('stopAll')),
        (_) {},
      );
      await pumpEventQueue();
      expect(stops, 1);
      await keepAlive.release(owner);
      await keepAlive.refresh();
      expect(calls.last.method, 'setActive', reason: 'no update once stopped');
    });

    test('one room names its task; several or none name none (H05.2)', () {
      expect(recordNotificationContent([_task('a', '晚风')]).task, 'a');
      for (final status in [RecordStatus.preparing, RecordStatus.reconnecting, RecordStatus.processing]) {
        expect(recordNotificationContent([_task('a', '晚风', status: status)]).task, 'a', reason: '$status');
      }
      expect(
        recordNotificationContent([_task('a', '晚风'), _task('b', '星河长明', status: RecordStatus.waitingLive)]).task,
        'a',
      );
      expect(recordNotificationContent([_task('a', '晚风'), _task('b', '星河长明')]).task, isNull);
      expect(recordNotificationContent([_task('b', '星河长明', status: RecordStatus.waitingLive)]).task, isNull);
      expect(recordNotificationContent(const []).task, isNull);
    });

    test('the keep-alive sends the task again when the recording changes (H05.2)', () async {
      const channel = MethodChannel('pure_live/recorder');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      String? task = 'a';
      final keepAlive = AndroidRecordKeepAlive(
        title: () => '正在录制 · 晚风',
        text: () => '深夜电台',
        extra: () => {'task': task},
        onInterrupted: (_) async {},
      );
      final owner = Object();
      await keepAlive.acquire(owner);
      expect((calls.single.method, (calls.single.arguments as Map)['task']), ('setActive', 'a'));
      task = 'b';
      await keepAlive.refresh();
      expect((calls.last.method, (calls.last.arguments as Map)['task']), ('update', 'b'));
      task = null;
      await keepAlive.refresh();
      expect(calls, hasLength(3));
      expect((calls.last.method, (calls.last.arguments as Map)['task']), ('update', null));
      await keepAlive.release(owner);
    });

    test('one room joining shows how far, without the clock; several show no bar (H05.3)', () {
      final first = DateTime(2026, 10, 2, 21);
      final joining = _task('a', '晚风', status: RecordStatus.processing, started: first)..mergeProgress = 0.42;
      final one = recordNotificationContent([joining]);
      expect((one.title, one.text, one.progress, one.since), ('正在整理录像 · 晚风', '深夜电台 · 点歌接龙到天亮 · 原画 · 42%', 42, null));
      joining.mergeProgress = null;
      final unknown = recordNotificationContent([joining]);
      expect((unknown.text, unknown.progress, unknown.since), ('深夜电台 · 点歌接龙到天亮 · 原画', null, null));
      final running = recordNotificationContent([_task('a', '晚风', started: first)]);
      expect((running.progress, running.since), (null, first));
      joining.mergeProgress = 0.42;
      final two = recordNotificationContent([joining, _task('b', '星河长明', started: first)]);
      expect((two.progress, two.since), (null, first));
      expect(
        recordNotificationContent([_task('a', '晚风', status: RecordStatus.preparing, started: first)]).since,
        isNull,
        reason: 'no clock before writing',
      );
    });

    test('the keep-alive sends the join progress at most once a second, the end at once (H05.3)', () async {
      const channel = MethodChannel('pure_live/recorder');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      var clock = DateTime(2026, 10, 8, 12);
      var title = '正在整理录像 · 晚风';
      int? progress = 42;
      Object? sent() => (calls.last.arguments as Map)['progress'];
      final keepAlive = AndroidRecordKeepAlive(
        title: () => title,
        text: () => '深夜电台${progress == null ? '' : ' · $progress%'}',
        extra: () => {'progress': progress},
        onInterrupted: (_) async {},
        now: () => clock,
      );
      final owner = Object();
      await keepAlive.acquire(owner);
      expect((calls.single.method, sent()), ('setActive', 42));
      progress = 43;
      await keepAlive.refresh();
      clock = clock.add(const Duration(milliseconds: 500));
      progress = 44;
      await keepAlive.refresh();
      expect(calls, hasLength(1), reason: 'within a second of the last');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect((calls.length, calls.last.method, sent()), (2, 'update', 44), reason: 'the last one still goes');
      progress = 100;
      await keepAlive.refresh();
      expect((calls.length, sent()), (3, 100), reason: '100% at once');
      title = '正在录制 · 晚风';
      progress = null;
      await keepAlive.refresh();
      expect((calls.length, sent()), (4, null), reason: 'the join ended: at once');
      await keepAlive.release(owner);
    });
  });

  group('"录制已停止" (c5)', () {
    test('the reason and what was saved', () {
      final task = _task('a', '晚风')
        ..lastErrorStage = 'background'
        ..lastError = 'timeout'
        ..recordedSeconds = 5 * 3600 + 52 * 60 + 10;
      expect(recordStoppedContent(task), (title: '录制已停止 · 晚风', text: '系统给后台录制的时间用完了。已录下的 5:52:10 已保存，回到应用可以重新开始。'));
      task
        ..lastErrorStage = 'ffmpeg.inputopen'
        ..recordedSeconds = 0;
      expect(recordStoppedContent(task).text, '录制出错停止了。回到应用可以重新开始。');
      expect(formatRecordDuration(754), '12:34');
    });

    test('a reminder when Android stopped it, or a failure out of sight; the words follow every change', () async {
      final changes = StreamController<List<RecordTask>>.broadcast();
      final alerts = <String>[];
      var refreshed = 0;
      var front = true;
      final a = _task('a', '晚风');
      final b = _task('b', '星河长明');
      final stopped = <String>[];
      final notices = RecordingNotices(
        tasks: () => [a, b],
        changes: changes.stream,
        stopTask: (task) async => stopped.add(task.taskId),
        refresh: () async => refreshed++,
        alert: (id, title, text) async => alerts.add('$id $title'),
        inFront: () => front,
      )..start();
      a
        ..status = RecordStatus.failed
        ..lastErrorStage = 'ffmpeg.inputopen';
      notices.changed([a, b]);
      expect(alerts, isEmpty, reason: 'the app shows it in front');
      b
        ..status = RecordStatus.failed
        ..lastErrorStage = 'background'
        ..lastError = 'timeout';
      notices.changed([a, b]);
      expect(alerts, ['b 录制已停止 · 星河长明']);
      front = false;
      a.status = RecordStatus.running;
      notices.changed([a, b]);
      a.status = RecordStatus.failed;
      notices
        ..changed([a, b])
        ..changed([a, b]);
      expect(alerts, ['b 录制已停止 · 星河长明', 'a 录制已停止 · 晚风'], reason: 'once per failure');
      expect(refreshed, 5);
      a.status = RecordStatus.running;
      b.status = RecordStatus.waitingLive;
      await notices.stopAll();
      expect(stopped, ['a'], reason: 'only what records now');
      await notices.dispose();
      await changes.close();
    });
  });

  test('media buttons in Chinese (c6)', () {
    final playing = mediaControls(playing: true);
    expect(playing.map((control) => (control.label, control.action)), [
      ('暂停', audio.MediaAction.pause),
      ('停止', audio.MediaAction.stop),
    ]);
    expect(playing.first.androidIcon, audio.MediaControl.pause.androidIcon);
    expect(mediaControls(playing: false).first.label, '播放');
  });

  test("picture-in-picture: the room's pause / play action (c7)", () async {
    PictureInPicture.debugAndroid = true;
    addTearDown(() => PictureInPicture.debugAndroid = null);
    const channel = MethodChannel('pure_live/pip');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final sent = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setPlaying') sent.add((call.arguments as Map)['playing']);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final owner = Object();
    final commands = <String>[];
    void bind({required bool playing}) => PictureInPicture.bindPlayback(
      owner: owner,
      playing: playing,
      play: () async => commands.add('play'),
      pause: () async => commands.add('pause'),
    );
    bind(playing: true);
    bind(playing: true);
    await pumpEventQueue();
    expect(sent, [true], reason: 'sent on a change only');
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('togglePlay')),
      (_) {},
    );
    bind(playing: false);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('togglePlay')),
      (_) {},
    );
    PictureInPicture.unbindPlayback(owner);
    await pumpEventQueue();
    expect(commands, ['pause', 'play']);
    expect(sent, [true, false, null], reason: 'the action goes away with the room');
  });

  group('Android resources (c2, c8, c9, c15)', () {
    String res(String path) => File('android/app/src/main/res/$path').readAsStringSync();

    test('one-colour small icons, a larger television with a themed layer', () {
      expect(res('drawable/ic_stat_playback.xml'), contains('#FFFFFFFF'));
      expect(res('drawable/ic_stat_recording.xml'), contains('evenOdd'));
      // U.2a2 c10: the recording glyph (a disc with its rounded square
      // knocked out), not the idle ring and dot.
      expect(res('drawable/ic_stat_recording.xml'), contains('M10.05,8.25h3.9'));
      final icon = res('mipmap-anydpi-v26/ic_launcher.xml');
      expect(icon, contains('android:inset="2%"'));
      expect(icon, contains('<monochrome android:drawable="@drawable/ic_launcher_monochrome" />'));
      expect(
        File('lib/features/live_play/logic/background_playback.dart').readAsStringSync(),
        contains("'drawable/ic_stat_playback'"),
      );
    });

    test('every drawable named only from Dart survives the release resource shrinker', () {
      // audio_service looks these up by name; a shrunk one resolves to 0 and,
      // from Android 13, its CustomAction.Builder throws (release fixes, item 1).
      final named = {
        'drawable/ic_stat_playback',
        for (final playing in [true, false]) ...mediaControls(playing: playing).map((control) => control.androidIcon),
      };
      expect(named, containsAll(['drawable/audio_service_pause', 'drawable/audio_service_stop']));
      final keep = res('raw/keep.xml');
      for (final name in named) {
        expect(keep, contains('@$name'), reason: name);
      }
    });

    test("the plugins' permission and activity request codes are unique", () {
      // Flutter hands every result to every plugin's listener; a shared code
      // lets one plugin answer another's request (release fixes, item 5).
      final codes = <String, String>{};
      final plugins = Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>();
      for (final file in plugins.where((file) => file.path.endsWith('.kt'))) {
        final source = file.readAsStringSync();
        for (final match in RegExp(r'const val (\w+_REQUEST) = (\d+)').allMatches(source)) {
          final name = '${file.uri.pathSegments.last} ${match[1]}';
          expect(codes[match[2]!], isNull, reason: '$name reuses ${match[2]}');
          codes[match[2]!] = name;
        }
      }
      expect(codes, hasLength(greaterThanOrEqualTo(4)));
    });

    test("the system splash screen in the splash page's colours, no white circle", () {
      expect(res('values/colors.xml'), contains('<color name="splash_background">#FAF8FF</color>'));
      expect(res('values-night/colors.xml'), contains('<color name="splash_background">#121318</color>'));
      for (final styles in ['values-v31/styles.xml', 'values-night-v31/styles.xml']) {
        expect(res(styles), contains('android:windowSplashScreenAnimatedIcon">@drawable/splash_icon'));
        expect(res(styles), isNot(contains('windowSplashScreenIconBackgroundColor')));
      }
      expect(res('values-v31/styles.xml'), contains('SplashTheme.Dark'));
      expect(res('drawable-v21/launch_background.xml'), contains('@color/splash_background'));
      expect(File('android/app/src/main/res/drawable-nodpi/splash_logo.png').existsSync(), isTrue);
    });

    test('shortcut labels in both languages', () {
      expect(res('values/strings.xml'), contains('<string name="shortcut_search">搜索直播</string>'));
      expect(res('values/strings.xml'), contains('<string name="shortcut_recordings">录制中心</string>'));
      expect(res('values-en/strings.xml'), contains('shortcut_recordings'));
    });
  });
}
