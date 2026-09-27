import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/modules/toolbox/toolbox_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ToolBoxController controller;
  late List<Completer<List<String>>> parses;
  late List<LiveRoom> opened;
  late List<String> notices;
  late List<Completer<void>> links;
  setUp(() {
    parses = [];
    opened = [];
    notices = [];
    links = [];
    controller = ToolBoxController(
      parseLink: (_) {
        final value = Completer<List<String>>();
        parses.add(value);
        return value.future;
      },
      openRoom: (room) async {
        opened.add(room);
      },
      obtainLink: (_) {
        final value = Completer<void>();
        links.add(value);
        return value.future;
      },
      notify: notices.add,
    );
  });
  tearDown(() {
    if (!controller.isClosed) controller.onDelete();
    for (final request in parses) {
      if (!request.isCompleted) request.complete([]);
    }
    for (final request in links) {
      if (!request.isCompleted) request.complete();
    }
  });

  test('duplicate room actions share one parse', () async {
    final a = controller.jumpToRoom('fixture');
    final b = controller.jumpToRoom('fixture');
    for (final request in parses) {
      request.complete(['123', 'bilibili']);
    }
    await Future.wait([a, b]);
    expect(parses, hasLength(1));
    expect(opened, hasLength(1));
  });
  test('closed controller does not navigate on a late parse', () async {
    final action = controller.jumpToRoom('fixture');
    controller.onDelete();
    parses.single.complete(['123', 'bilibili']);
    await action;
    expect(opened, isEmpty);
    expect(notices, isEmpty);
  });
  test('editing the submitted field invalidates pending navigation', () async {
    controller.roomJumpToController.text = 'fixture';
    final action = controller.jumpToRoom('fixture');
    controller.roomJumpToController.text = 'new draft';
    parses.single.complete(['123', 'bilibili']);
    await action;
    expect(opened, isEmpty);
    expect(controller.roomJumpToController.text, 'new draft');
  });
  test('whitespace is rejected before resolving', () async {
    final action = controller.jumpToRoom('   ');
    for (final request in parses) {
      request.complete([]);
    }
    await action;
    expect(parses, isEmpty);
    expect(notices, ['toolbox_empty_link']);
  });
  test('partial identity is reported without indexing beyond the result', () async {
    final action = controller.jumpToRoom('fixture');
    parses.single.complete(['123']);
    await expectLater(action, completes);
    expect(opened, isEmpty);
    expect(notices, ['toolbox_parse_failed']);
  });
  test('resolver exception is contained and leaves a retry', () async {
    final action = controller.jumpToRoom('fixture');
    parses.single.completeError(StateError('fixture parse failure'));
    await expectLater(action, completes);
    expect(notices, ['toolbox_parse_failed']);
    final retry = controller.jumpToRoom('retry');
    parses.last.complete(['456', 'bilibili']);
    await retry;
    expect(opened.single.roomId, '456');
  });
  test('duplicate direct-link actions enter the workflow only once', () async {
    final a = controller.getPlayUrl('fixture');
    final b = controller.getPlayUrl('fixture');
    for (final request in links) {
      request.complete();
    }
    await Future.wait([a, b]);
    expect(links, hasLength(1));
  });
  test('room and direct-link actions do not overlap', () async {
    final a = controller.jumpToRoom('fixture');
    final b = controller.getPlayUrl('fixture');
    parses.single.complete(['123', 'bilibili']);
    for (final request in links) {
      request.complete();
    }
    await Future.wait([a, b]);
    expect(links, isEmpty);
  });
}
