import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/toolbox/toolbox_action_scope.dart';
import 'package:pure_live/modules/toolbox/toolbox_direct_link_flow.dart';

import 'support/toolbox_test_site.dart';

void main() {
  late ToolBoxTestSite site;
  late ToolBoxActionScope scope;
  late ToolBoxDirectLinkFlow flow;
  late List<String> notices;
  late List<String> copies;
  late Future<LivePlayQuality?> Function(List<LivePlayQuality>) qualityChoice;
  late Future<String?> Function(List<String>) lineChoice;
  Future<void>? copyReply;
  setUp(() {
    site = ToolBoxTestSite();
    scope = ToolBoxActionScope(timeout: const Duration(milliseconds: 100));
    notices = [];
    copies = [];
    copyReply = null;
    qualityChoice = (items) async => items.last;
    lineChoice = (items) async => items.last;
    flow = ToolBoxDirectLinkFlow(
      siteFor: (_) => site,
      copyText: (text) {
        copies.add(text);
        return copyReply ?? Future.value();
      },
    );
  });
  tearDown(() => scope.cancel());
  Future<void> run() => flow.run(
    room: site.room,
    scope: scope,
    chooseQuality: (items) => qualityChoice(items),
    chooseLine: (items) => lineChoice(items),
    notify: notices.add,
  );

  test('success follows the selected quality and acknowledges actual copy completion', () async {
    final pending = Completer<void>();
    copyReply = pending.future;
    final action = run();
    await Future<void>.delayed(Duration.zero);
    expect(site.calls, ['detail', 'qualities', 'urls']);
    expect(site.requestedQuality, same(site.qualities.last));
    expect(copies, [site.urls.last]);
    expect(notices, isEmpty);
    pending.complete();
    await action;
    expect(notices, ['toolbox_copy_success']);
  });
  test('quality cancellation stops before loading lines', () async {
    qualityChoice = (_) async => null;
    await run();
    expect(site.calls, ['detail', 'qualities']);
    expect(copies, isEmpty);
    expect(notices, isEmpty);
  });
  test('line cancellation leaves clipboard and notifications untouched', () async {
    lineChoice = (_) async => null;
    await run();
    expect(copies, isEmpty);
    expect(notices, isEmpty);
  });
  test('empty quality list produces a retryable failure without choices', () async {
    site.qualities = [];
    await run();
    expect(site.calls, ['detail', 'qualities']);
    expect(notices, ['toolbox_quality_failed']);
  });
  test('blank line list does not open an empty selector', () async {
    site.urls = [' ', ''];
    var choices = 0;
    lineChoice = (_) async {
      choices++;
      return null;
    };
    await run();
    expect(choices, 0);
    expect(notices, ['toolbox_get_url_failed']);
  });
  test('line choices retain order and remove blank and duplicate URLs', () async {
    site.urls = [' https://cdn.example/a ', '', 'https://cdn.example/a', 'https://cdn.example/b'];
    List<String>? offered;
    lineChoice = (items) async {
      offered = items;
      return items.first;
    };
    await run();
    expect(offered, ['https://cdn.example/a', 'https://cdn.example/b']);
    expect(copies, ['https://cdn.example/a']);
  });
  test('clipboard failure never reports success', () async {
    final pending = Completer<void>();
    copyReply = pending.future;
    final action = run();
    await Future<void>.delayed(Duration.zero);
    pending.completeError(PlatformException(code: 'fixture_denied'));
    await action;
    expect(notices, ['toolbox_copy_failed']);
  });
  test('cancel during clipboard completion suppresses late success', () async {
    final pending = Completer<void>();
    copyReply = pending.future;
    final action = run();
    final observed = expectLater(action, throwsA(isA<ToolBoxActionCancelled>()));
    await Future<void>.delayed(Duration.zero);
    scope.cancel();
    await observed;
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(notices, isEmpty);
  });
  test('stale quality choice is not sent to the platform', () async {
    qualityChoice = (_) async => LivePlayQuality(quality: 'stale');
    await run();
    expect(site.calls, ['detail', 'qualities']);
    expect(copies, isEmpty);
  });
  test('stale line choice is not copied', () async {
    lineChoice = (_) async => 'https://stale.example';
    await run();
    expect(copies, isEmpty);
  });
  test('detail timeout prevents late follow-up requests', () async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await expectLater(run(), throwsA(isA<TimeoutException>()));
    pending.complete(site.room);
    await Future<void>.delayed(Duration.zero);
    expect(site.calls, ['detail']);
    expect(copies, isEmpty);
  });
  test('user choices have no automatic timeout', () async {
    final pending = Completer<LivePlayQuality?>();
    qualityChoice = (_) => pending.future;
    final action = run();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(site.calls, ['detail', 'qualities']);
    pending.complete(site.qualities.first);
    await action;
    expect(notices, ['toolbox_copy_success']);
  });
  for (final stage in ['detail', 'qualities', 'urls', 'qualityChoice', 'lineChoice']) {
    test('cancelling $stage releases the action and ignores its late result', () async {
      final detail = Completer<LiveRoom>();
      final qualities = Completer<List<LivePlayQuality>>();
      final urls = Completer<List<String>>();
      final quality = Completer<LivePlayQuality?>();
      final line = Completer<String?>();
      if (stage == 'detail') site.detailReply = detail.future;
      if (stage == 'qualities') site.qualityReply = qualities.future;
      if (stage == 'urls') site.urlReply = urls.future;
      if (stage == 'qualityChoice') qualityChoice = (_) => quality.future;
      if (stage == 'lineChoice') lineChoice = (_) => line.future;
      final action = run();
      final observed = expectLater(action, throwsA(isA<ToolBoxActionCancelled>()));
      await Future<void>.delayed(Duration.zero);
      final calls = site.calls.toList();
      scope.cancel();
      await observed;
      detail.complete(site.room);
      qualities.complete(site.qualities);
      urls.complete(site.urls);
      quality.complete(site.qualities.first);
      line.complete(site.urls.first);
      await Future<void>.delayed(Duration.zero);
      expect(site.calls, calls);
      expect(copies, isEmpty);
      expect(notices, isEmpty);
    });
  }
}
