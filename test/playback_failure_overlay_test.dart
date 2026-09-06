import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/playback_failure_overlay.dart';

void main() {
  Widget build({
    bool error = true,
    Future<void> Function()? retry,
    double scale = 1,
    Size size = const Size(640, 360),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: PlaybackFailureOverlay(
                hasError: error,
                onRetry: retry ?? () async {},
                child: const ColoredBox(key: ValueKey('video'), color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('terminal failure persists and preserves the video element', (tester) async {
    await tester.pumpWidget(build(error: false));
    final element = tester.element(find.byKey(const ValueKey('video')));
    await tester.pumpWidget(build());
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Playback interrupted'), findsOneWidget);
    expect(tester.element(find.byKey(const ValueKey('video'))), same(element));
    await tester.pumpWidget(build(error: false));
    expect(find.text('Playback interrupted'), findsNothing);
    expect(tester.element(find.byKey(const ValueKey('video'))), same(element));
  });

  testWidgets('retry is deduplicated and remains available after failure', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    Future<void> retry() {
      calls++;
      return pending.future;
    }

    await tester.pumpWidget(build(retry: retry));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    expect(calls, 1);
    await tester.pumpWidget(build(error: false, retry: retry));
    pending.completeError(StateError('refresh failed'));
    await tester.pump();
    expect(find.text('Playback interrupted'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending retry can outlive widget disposal', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(build(retry: () => pending.future));
    await tester.tap(find.text('Retry'));
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('small player and large text remain scrollable', (tester) async {
    await tester.pumpWidget(build(size: const Size(240, 135), scale: 2));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
