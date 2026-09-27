import 'dart:ui';

import 'package:pure_live_app/core/desktop_window.dart';

/// A desktop window that records what the app asks of it.
final class FakeWindow implements DesktopWindowOps {
  new({this._bounds = const Rect.fromLTWH(100, 100, 1280, 720), this.workArea = const Rect.fromLTWH(0, 0, 1920, 1040)});

  final Rect? workArea;
  final calls = <String>[];
  Rect _bounds;
  bool maximized = false;
  bool fullScreen = false;
  bool alwaysOnTop = false;
  bool visible = true;
  bool minimized = false;
  bool preventClose = false;
  bool destroyed = false;
  double aspectRatio = 0;
  bool frameless = false;
  Size minimumSize = minimumWindowSize;

  Rect get bounds => _bounds;

  @override
  Future<Rect> getBounds() async => _bounds;

  @override
  Future<void> setBounds(Rect bounds) async {
    calls.add('setBounds');
    _bounds = bounds;
  }

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    calls.add('unmaximize');
    maximized = false;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen({required bool fullScreen}) async {
    calls.add('fullScreen $fullScreen');
    this.fullScreen = fullScreen;
  }

  @override
  Future<bool> isAlwaysOnTop() async => alwaysOnTop;

  @override
  Future<void> setAlwaysOnTop({required bool alwaysOnTop}) async {
    calls.add('alwaysOnTop $alwaysOnTop');
    this.alwaysOnTop = alwaysOnTop;
  }

  @override
  Future<void> setAspectRatio(double aspectRatio) async => this.aspectRatio = aspectRatio;

  @override
  Future<void> setMinimumSize(Size size) async => minimumSize = size;

  @override
  Future<void> setFrameless({required bool frameless}) async {
    calls.add('frameless $frameless');
    this.frameless = frameless;
  }

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<Rect?> workAreaContaining(Rect bounds) async => workArea;

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<bool> isMinimized() async => minimized;

  @override
  Future<void> show() async {
    calls.add('show');
    visible = true;
    minimized = false;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    visible = false;
  }

  @override
  Future<void> focus() async => calls.add('focus');

  @override
  Future<void> setPreventClose({required bool preventClose}) async => this.preventClose = preventClose;

  @override
  Future<void> destroy() async {
    calls.add('destroy');
    destroyed = true;
  }
}
