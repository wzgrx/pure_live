import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/shared/qr_scan.dart';

/// A scanner camera for widget tests: [read] hands the page a code,
/// [fail] says the camera cannot start.
final class FakeQrCamera implements QrCamera {
  /// The camera the page opened last.
  static FakeQrCamera? last;

  /// Makes the cameras of [QrScan.camera] until [uninstall].
  static void install() => QrScan.camera = () => last = FakeQrCamera();

  /// No scanner (a computer).
  static void uninstall() {
    QrScan.camera = null;
    last = null;
  }

  final ValueNotifier<QrTorch> _torch = ValueNotifier(QrTorch.off);
  ValueChanged<String>? _onCode;
  VoidCallback? _onError;

  /// Camera switches asked for.
  int switches = 0;

  /// Whether the page released it.
  bool disposed = false;

  /// Reads [text] as if a QR code held it.
  void read(String text) => _onCode?.call(text);

  /// The camera cannot start.
  void fail() => _onError?.call();

  @override
  ValueListenable<QrTorch> get torch => _torch;

  @override
  Widget view({required ValueChanged<String> onCode, required VoidCallback onError}) {
    _onCode = onCode;
    _onError = onError;
    return const SizedBox.expand(key: ValueKey('fake-camera'));
  }

  @override
  Future<void> toggleTorch() async => _torch.value = _torch.value == QrTorch.on ? QrTorch.off : QrTorch.on;

  @override
  Future<void> switchCamera() async => switches++;

  @override
  void dispose() => disposed = true;
}
