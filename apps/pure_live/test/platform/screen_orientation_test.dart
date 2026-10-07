import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/screen_orientation.dart';

// docs/O-Android系统集成/O05-方向、刷新率、常亮/O05.3-退出横屏全屏后回到竖屏: leaving a landscape
// fullscreen turns the phone upright before letting go while auto-rotate is
// off; a release still pending never undoes the next fullscreen.

const _systemAccess = MethodChannel('pure_live/system_access');
const _upright = ['DeviceOrientation.portraitUp'];
const _sideways = ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'];

/// What the page asked for, in order; [autoRotate] null: the channel has no
/// such method (an engine without the plugin).
List<Object?> _fake(WidgetTester tester, {bool? autoRotate}) {
  final calls = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemChrome.setPreferredOrientations') calls.add(call.arguments);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_systemAccess, (call) async {
    if (call.method == 'autoRotate' && autoRotate == null) throw MissingPluginException();
    calls.add(call.method);
    return call.method == 'autoRotate' ? autoRotate : true;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_systemAccess, null));
  return calls;
}

// Tests run as Android unless they say otherwise.
void main() {
  testWidgets('auto-rotate off: upright first, let go after the settle time', (tester) async {
    final calls = _fake(tester, autoRotate: false);
    await ScreenOrientation.landscape();
    await ScreenOrientation.restore();
    expect(calls, [_sideways, 'sensorLandscape', 'autoRotate', _upright]);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last, _upright, reason: 'still turning');
    await tester.pump(const Duration(seconds: 2));
    expect(calls.last, isEmpty, reason: 'then free');
  });

  testWidgets('auto-rotate on: let go at once, following the phone', (tester) async {
    final calls = _fake(tester, autoRotate: true);
    await ScreenOrientation.landscape();
    await ScreenOrientation.restore();
    expect(calls, [_sideways, 'sensorLandscape', 'autoRotate', <Object?>[]]);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, hasLength(4), reason: 'nothing more');
  });

  testWidgets('upright (横屏全屏): upright first even with auto-rotate on', (tester) async {
    final calls = _fake(tester, autoRotate: true);
    await ScreenOrientation.restore(upright: true);
    expect(calls.last, _upright);
    await tester.pump(const Duration(seconds: 4));
    expect(calls.last, isEmpty);
  });

  testWidgets('no answer about auto-rotate: taken as off', (tester) async {
    final calls = _fake(tester);
    await ScreenOrientation.restore();
    expect(calls, [_upright]);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, [_upright, <Object?>[]]);
  });

  testWidgets('a fullscreen within the settle time keeps its orientation', (tester) async {
    final calls = _fake(tester, autoRotate: false);
    await ScreenOrientation.restore();
    await tester.pump(const Duration(seconds: 1));
    await ScreenOrientation.landscape();
    await tester.pump(const Duration(seconds: 4));
    expect(calls.last, 'sensorLandscape', reason: 'the pending release is dropped');
    await ScreenOrientation.restore();
    await ScreenOrientation.portrait();
    await tester.pump(const Duration(seconds: 4));
    expect(calls.last, _upright, reason: 'the portrait fullscreen too');
    await ScreenOrientation.restore();
    await ScreenOrientation.free();
    await tester.pump(const Duration(seconds: 4));
    expect(calls.sublist(calls.length - 2), [_upright, <Object?>[]], reason: 'one release, not a second one later');
  });

  testWidgets('iOS: let go at once, as before', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = _fake(tester, autoRotate: false);
    await ScreenOrientation.restore();
    debugDefaultTargetPlatformOverride = null;
    expect(calls, [<Object?>[]]);
  });
}
