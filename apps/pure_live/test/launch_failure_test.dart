import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/launch_failure.dart';

import 'support.dart';

// Release fixes, item 7: a start that throws (LiveStore.open on a full disk,
// a damaged database) shows why instead of the splash screen forever.

void main() {
  testWidgets('a failed start says why, tries again and exports the log', (tester) async {
    await tester.runAsync(loadStrings);
    Widget? shown;
    var retries = 0;
    var exports = 0;
    final ready = await tester.runAsync(
      () => launchOrExplain<String>(
        () async => throw const FileSystemException(
          'Cannot open file',
          '/data/user/0/com.mystyle.purelive/files/pure_live.db',
          OSError('No space left on device', 28),
        ),
        show: (app) => shown = app,
        retry: () async => retries++,
        exportLog: () async {
          exports++;
          return '日志已保存到 /tmp/pure_live_log.txt';
        },
      ),
    );
    expect(ready, isNull);
    final logged = AppLog.instance.entries.last;
    expect((logged.level, logged.tag), (LogLevel.error, 'startup'));
    expect(logged.message, contains('No space left on device'));

    await tester.pumpWidget(shown!);
    await tester.pumpAndSettle();
    expect(find.text('纯粹直播没能启动'), findsOneWidget);
    expect(find.textContaining('/data/user/0/com.mystyle.purelive/files/pure_live.db'), findsOneWidget);
    expect(find.textContaining('No space left on device'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester.tap(find.text('导出日志'));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(find.text('日志已保存到 /tmp/pure_live_log.txt'), findsOneWidget);

    expect(launchFailureReason(StateError('database disk image is malformed')), contains('应用数据无法打开'));
    final started = await tester.runAsync(
      () => launchOrExplain<String>(
        () async => 'ready',
        show: (_) => fail('no failure page'),
        retry: () async {},
        exportLog: () async => null,
      ),
    );
    expect(started, 'ready');
  });
}
