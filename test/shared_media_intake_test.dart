import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/shared_media_intake.dart';
import 'package:share_handler/share_handler.dart';

void main() {
  test('a room command takes precedence over file attachments and is handled once', () async {
    final commands = <String>[];
    final files = <String>[];
    final unsupported = <String>[];
    final intake = SharedMediaIntake(
      isRoomCommand: (text) => text == 'room-command',
      consumeRoomCommand: (text) async {
        commands.add(text);
        return true;
      },
      importPlaylist: (path) async {
        files.add(path);
        return true;
      },
      importEpg: (path) async {
        files.add(path);
        return true;
      },
      notifyUnsupported: unsupported.add,
    );

    final result = await intake.ingest(
      SharedMedia(content: ' room-command ', attachments: [_attachment('/cache/ignored.m3u')]),
    );

    expect(result.kind, SharedMediaIntakeKind.roomCommand);
    expect(result.attemptedCount, 1);
    expect(result.acceptedCount, 1);
    expect(commands, ['room-command']);
    expect(files, isEmpty);
    expect(unsupported, isEmpty);
  });

  test('Android attachment paths are deduplicated and routed by supported extension', () async {
    final operations = <String>[];
    final intake = _intake(
      importPlaylist: (path) async {
        operations.add('playlist:$path');
        return true;
      },
      importEpg: (path) async {
        operations.add('epg:$path');
        return true;
      },
    );

    final result = await intake.ingest(
      SharedMedia(
        attachments: [
          _attachment('/cache/Fixture.M3U'),
          _attachment('/cache/guide.XML'),
          _attachment('/cache/Fixture.M3U'),
          null,
          _attachment('/cache/poster.png'),
        ],
      ),
    );

    expect(result.kind, SharedMediaIntakeKind.files);
    expect(result.attemptedCount, 2);
    expect(result.acceptedCount, 2);
    expect(operations, ['playlist:/cache/Fixture.M3U', 'epg:/cache/guide.XML']);
  });

  test('legacy content paths retain file URI decoding and query-safe extension matching', () async {
    final operations = <String>[];
    final intake = _intake(
      importPlaylist: (path) async {
        operations.add(path);
        return true;
      },
    );

    final first = await intake.ingest(SharedMedia(content: 'file:///cache/Fixture.M3U8'));
    final second = await intake.ingest(SharedMedia(content: '/cache/second.txt?source=share'));

    expect(first.kind, SharedMediaIntakeKind.files);
    expect(second.kind, SharedMediaIntakeKind.files);
    expect(operations, ['file:///cache/Fixture.M3U8', '/cache/second.txt?source=share']);
  });

  test('unsupported and empty shares emit one localized feedback each', () async {
    final unsupported = <String>[];
    final intake = _intake(notifyUnsupported: unsupported.add);

    final first = await intake.ingest(SharedMedia(content: 'ordinary shared text'));
    final second = await intake.ingest(SharedMedia(attachments: [_attachment('/cache/poster.png')]));
    final third = await intake.ingest(SharedMedia());

    expect([first.kind, second.kind, third.kind], everyElement(SharedMediaIntakeKind.unsupported));
    expect(unsupported, List.filled(3, 'unsupported_file_format'));
  });

  test('a failing queued import is contained and a later share still runs', () async {
    final errors = <Object>[];
    final operations = <String>[];
    final intake = _intake(
      importPlaylist: (_) async => throw StateError('fixture playlist failure'),
      importEpg: (path) async {
        operations.add(path);
        return true;
      },
      reportError: (error, _) => errors.add(error),
    );

    final failed = intake.ingest(SharedMedia(attachments: [_attachment('/cache/list.m3u')]));
    final recovered = intake.ingest(SharedMedia(attachments: [_attachment('/cache/guide.json')]));

    expect((await failed).kind, SharedMediaIntakeKind.failed);
    expect((await recovered).kind, SharedMediaIntakeKind.files);
    expect(operations, ['/cache/guide.json']);
    expect(errors, hasLength(1));
  });

  test('receiver subscribes before awaiting cold-start media, consumes it and resets it', () async {
    final initial = Completer<SharedMedia?>();
    final stream = StreamController<SharedMedia>();
    final operations = <String>[];
    var resets = 0;
    final liveHandled = Completer<void>();
    final intake = _intake(
      consumeRoomCommand: (text) async {
        operations.add('command:$text');
        return true;
      },
      isRoomCommand: (text) => text == 'cold-command',
      importEpg: (path) async {
        operations.add('epg:$path');
        liveHandled.complete();
        return true;
      },
    );
    final receiver = SharedMediaReceiver(
      readInitialMedia: () => initial.future,
      resetInitialMedia: () async => resets++,
      mediaStream: stream.stream,
      intake: intake,
    );

    final start = receiver.start();
    expect(identical(start, receiver.start()), isTrue);
    stream.add(SharedMedia(attachments: [_attachment('/cache/live.xml')]));
    await liveHandled.future;
    initial.complete(SharedMedia(content: 'cold-command'));
    await start;

    expect(operations, ['epg:/cache/live.xml', 'command:cold-command']);
    expect(resets, 1);
    await receiver.dispose();
    await stream.close();
  });

  test('receiver resets unsupported cold-start media and reports source errors without escaping', () async {
    final errors = <Object>[];
    final unsupported = <String>[];
    var resets = 0;
    final receiver = SharedMediaReceiver(
      readInitialMedia: () async => SharedMedia(content: 'unsupported cold text'),
      resetInitialMedia: () async => resets++,
      mediaStream: const Stream<SharedMedia>.empty(),
      intake: _intake(notifyUnsupported: unsupported.add),
      reportError: (error, _) => errors.add(error),
    );

    await receiver.start();
    await receiver.dispose();

    expect(unsupported, ['unsupported_file_format']);
    expect(resets, 1);
    expect(errors, isEmpty);
  });

  test('receiver contains asynchronous media stream errors and remains disposable', () async {
    final errors = <Object>[];
    final stream = StreamController<SharedMedia>();
    final errorObserved = Completer<void>();
    final receiver = SharedMediaReceiver(
      readInitialMedia: () async => null,
      resetInitialMedia: () async {},
      mediaStream: stream.stream,
      intake: _intake(),
      reportError: (error, _) {
        errors.add(error);
        errorObserved.complete();
      },
    );

    await receiver.start();
    stream.addError(StateError('fixture stream failure'), StackTrace.current);
    await errorObserved.future;
    await receiver.dispose();
    await stream.close();

    expect(errors.single, isA<StateError>());
  });

  test('Android share declarations are scoped to supported content and use the real target', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final targets = File('android/app/src/main/res/xml/share_targets.xml').readAsStringSync();

    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
    expect(manifest, isNot(contains('android:mimeType="*/*"')));
    expect(targets, contains('com.mystyle.purelive.MainActivity'));
    expect(targets, contains('com.mystyle.purelive.dynamic_share_target'));
    expect(targets, isNot(contains('{your.package.identifier}')));
  });

  test('app-owned navigator defers cold share presentation until splash has finished', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final windowSource = File('lib/common/global/platform/desktop_manager.dart').readAsStringSync();

    expect(mainSource, contains('navigatorKey: appNavigatorKey'));
    expect(windowSource, contains('appNavigatorKey.currentContext'));
    expect(windowSource, contains('currentRoute != RoutePath.kSplash'));
    expect(windowSource, contains('ShareCommandImportDialog.show(context: navigatorContext'));
    expect(windowSource, isNot(contains('ShareCommandImportDialog.show(context: context')));
  });
}

SharedAttachment _attachment(String path) => SharedAttachment(path: path, type: SharedAttachmentType.file);

SharedMediaIntake _intake({
  SharedRoomCommandPredicate? isRoomCommand,
  SharedRoomCommandConsumer? consumeRoomCommand,
  SharedFileImporter? importPlaylist,
  SharedFileImporter? importEpg,
  SharedMediaFeedback? notifyUnsupported,
  SharedMediaErrorReporter? reportError,
}) {
  return SharedMediaIntake(
    isRoomCommand: isRoomCommand ?? (_) => false,
    consumeRoomCommand: consumeRoomCommand ?? (_) async => true,
    importPlaylist: importPlaylist ?? (_) async => true,
    importEpg: importEpg ?? (_) async => true,
    notifyUnsupported: notifyUnsupported ?? (_) {},
    reportError: reportError,
  );
}
