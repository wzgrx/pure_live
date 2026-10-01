import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

RecordTask _task(String directory, {RecordStatus status = RecordStatus.running, DateTime? attempt}) => RecordTask(
  taskId: 'bilibili_1',
  roomId: '1',
  platform: 'bilibili',
  title: 't',
  nick: 'n',
  avatar: '',
  cover: '',
  createTime: attempt ?? DateTime(2026, 10, 1, 20),
  status: status,
)..outputDir = directory;

LiveMessage _chat(String text, {String user = 'u'}) =>
    LiveMessage(type: LiveMessageType.chat, userName: user, message: text, color: LiveMessageColor.white);

/// Waits (real time, at most 5 s) until [done].
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  late Directory folder;
  setUp(() async => folder = await Directory.systemTemp.createTemp('live_record_chat_'));
  tearDown(() => folder.delete(recursive: true));

  test('the XML file is a complete document after every flush (3.x left it unterminated)', () async {
    final file = File(p.join(folder.path, 'a.xml'));
    final writer = await RecordChatWriter.open(file, startedAt: DateTime(2026, 10, 1, 20));
    writer.add(_chat('a<b & "c"\u0001'), receivedAt: DateTime(2026, 10, 1, 20, 0, 1, 500));
    await writer.flush();
    var text = await file.readAsString();
    expect(text, endsWith('</i>\n'));
    expect(text, contains('<d p="1.500,1,25,16777215,'));
    expect(text, contains('>a&lt;b &amp; &quot;c&quot;</d>'));
    writer.add(_chat('second'), receivedAt: DateTime(2026, 10, 1, 19, 59));
    await writer.close();
    text = await file.readAsString();
    expect('</i>'.allMatches(text), hasLength(1));
    expect(text, contains('<d p="0.000,'), reason: 'chat before the video start is clamped to 0');
    expect(writer.count, 2);
  });

  test('one file per attempt beside its video; reconnect gaps and other statuses write nothing', () async {
    final connected = <String>[];
    void Function(LiveMessage message)? deliver;
    final stopped = Completer<void>();
    final chat = RecordChatRecorder(
      enabled: () => true,
      flushInterval: const Duration(seconds: 1),
      connect: (task, {required onMessage, required onEnded}) async {
        connected.add(task.taskId);
        deliver = onMessage;
        return RecordChatConnection(stop: () async => stopped.complete());
      },
    );
    addTearDown(chat.dispose);
    final first = _task(folder.path);
    chat.sync([first]);
    await _until(() => chat.fileOf('bilibili_1') != null && deliver != null);
    deliver!(_chat('one'));
    deliver!(
      const LiveMessage(type: LiveMessageType.online, userName: '', message: '42', color: LiveMessageColor.white),
    );

    chat.sync([first..status = RecordStatus.reconnecting]);
    await pumpEventQueue();
    deliver!(_chat('lost in the gap'));

    final second = _task(folder.path, attempt: DateTime(2026, 10, 1, 20, 5));
    chat.sync([second]);
    await _until(() => chat.fileOf('bilibili_1')?.path.contains(second.recordingFilePrefix) ?? false);
    deliver!(_chat('two'));
    chat.sync([second..status = RecordStatus.stopped]);
    await stopped.future.timeout(const Duration(seconds: 5));

    expect(connected, ['bilibili_1'], reason: 'one connection across the attempts');
    final firstXml = await File(p.join(folder.path, '${first.recordingFilePrefix}.xml')).readAsString();
    final secondXml = await File(p.join(folder.path, '${second.recordingFilePrefix}.xml')).readAsString();
    expect(firstXml, contains('>one</d>'));
    expect(firstXml, isNot(contains('>42<')));
    expect(firstXml, isNot(contains('gap')));
    expect(secondXml, contains('>two</d>'));
    expect(secondXml, endsWith('</i>\n'));
  });

  test('switched off or a platform without chat: no file; a lost connection is opened again later', () async {
    var enabled = false;
    var attempts = 0;
    void Function()? ended;
    final chat = RecordChatRecorder(
      enabled: () => enabled,
      retryDelay: Duration.zero,
      connect: (task, {required onMessage, required onEnded}) async {
        attempts++;
        ended = onEnded;
        return RecordChatConnection(stop: () async {});
      },
    );
    addTearDown(chat.dispose);
    final task = _task(folder.path);
    chat.sync([task]);
    await pumpEventQueue();
    expect(attempts, 0);
    expect(folder.listSync(), isEmpty);

    enabled = true;
    chat.sync([task]);
    await pumpEventQueue();
    expect(attempts, 1);
    ended!();
    chat.sync([task]);
    await pumpEventQueue();
    expect(attempts, 2);
  });

  test("a task's own choice wins over the setting; the session's count spans its attempts (U.2f)", () async {
    void Function(LiveMessage message)? deliver;
    final chat = RecordChatRecorder(
      enabled: () => false,
      connect: (task, {required onMessage, required onEnded}) async {
        deliver = onMessage;
        return RecordChatConnection(stop: () async {});
      },
    );
    addTearDown(chat.dispose);
    final session = DateTime(2026, 10, 1, 20);
    final first = _task(folder.path)
      ..recordDanmakuOverride = true
      ..recordingStartedAt = session;
    chat.sync([first]);
    await _until(() => chat.fileOf('bilibili_1') != null && deliver != null);
    deliver!(_chat('one'));
    deliver!(_chat('two'));
    expect(chat.countOf(first), 2);

    final second = _task(folder.path, attempt: DateTime(2026, 10, 1, 20, 5))
      ..recordDanmakuOverride = true
      ..recordingStartedAt = session;
    chat.sync([second]);
    await _until(() => chat.fileOf('bilibili_1')?.path.contains(second.recordingFilePrefix) ?? false);
    deliver!(_chat('three'));
    expect(chat.countOf(second), 3);
    chat.sync([second..status = RecordStatus.completed]);
    await _until(() => chat.fileOf('bilibili_1') == null);
    await pumpEventQueue();
    expect(chat.countOf(second), 3, reason: 'kept for the saved summary');

    final declined = _task(folder.path, attempt: DateTime(2026, 10, 1, 21))
      ..recordDanmakuOverride = false
      ..recordingStartedAt = DateTime(2026, 10, 1, 21);
    final quiet = RecordChatRecorder(
      enabled: () => true,
      connect: (task, {required onMessage, required onEnded}) async => fail('the task said no'),
    );
    addTearDown(quiet.dispose);
    quiet.sync([declined]);
    await pumpEventQueue();
    expect(quiet.fileOf('bilibili_1'), isNull);
    expect(chat.countOf(declined), 0, reason: 'another session');
  });
}
