import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The torch of the scanner's camera.
enum QrTorch {
  /// Off.
  off,

  /// On.
  on,

  /// The camera has none.
  unavailable,
}

/// The camera behind the scanner page: the picture, the codes it reads, the
/// torch and the front and back cameras (mobile_scanner in the app, a fake
/// in tests).
abstract class QrCamera {
  /// The torch's state.
  ValueListenable<QrTorch> get torch;

  /// The picture; [onCode] gets each code's text, [onError] says the camera
  /// cannot start (no permission, no camera).
  Widget view({required ValueChanged<String> onCode, required VoidCallback onError});

  /// Switches the torch.
  Future<void> toggleTorch();

  /// Switches between the front and back cameras.
  Future<void> switchCamera();

  /// Releases the camera.
  void dispose();
}

/// Reading QR codes with the camera (3.x `mobile_scanner`): device sync and
/// TV sync. The app sets [camera] on phones (M12.3); null hides the scan
/// buttons and TV sync asks for the address instead (desktops have no
/// scanner).
abstract final class QrScan {
  /// Makes the scanner's camera; null where there is none.
  static QrCamera Function()? camera;

  /// Whether this device scans.
  static bool get available => camera != null;
}

/// mobile_scanner's camera, QR codes only.
final class MobileQrCamera implements QrCamera {
  /// Opens the camera.
  new() {
    _controller.addListener(_sync);
  }

  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final ValueNotifier<QrTorch> _torch = ValueNotifier(QrTorch.off);

  void _sync() => _torch.value = switch (_controller.value.torchState) {
    TorchState.on || TorchState.auto => QrTorch.on,
    TorchState.off => QrTorch.off,
    TorchState.unavailable => QrTorch.unavailable,
  };

  @override
  ValueListenable<QrTorch> get torch => _torch;

  @override
  Widget view({required ValueChanged<String> onCode, required VoidCallback onError}) => MobileScanner(
    controller: _controller,
    onDetect: (capture) {
      for (final code in capture.barcodes) {
        final text = code.rawValue?.trim() ?? '';
        if (text.isEmpty) continue;
        onCode(text);
        return;
      }
    },
    errorBuilder: (context, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onError());
      return const ColoredBox(color: OnVideoColors.ground);
    },
  );

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<void> switchCamera() => _controller.switchCamera();

  @override
  void dispose() {
    _controller.removeListener(_sync);
    unawaited(_controller.dispose());
    _torch.dispose();
  }
}

/// Opens the scanner page and completes with the first code's text, or
/// null when the user left (or chose [onManual], "手动输入地址", which then
/// runs after the page closed).
Future<String?> scanQrCode(
  BuildContext context, {
  String? hint,
  String? unavailableHint,
  VoidCallback? onManual,
}) async {
  var manual = false;
  final text = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (pageContext) => QrScanPage(
        hint: hint ?? i18n('qr_scan_hint'),
        unavailableHint: unavailableHint,
        onCode: (text) => Navigator.of(pageContext).pop(text),
        onManual: onManual == null
            ? null
            : () {
                manual = true;
                Navigator.of(pageContext).pop();
              },
      ),
    ),
  );
  if (manual) onManual?.call();
  return text;
}

/// The scanner page of TV sync and device sync (docs/ui/compare/U.11a c8,
/// U.11c c9): "扫描二维码", the torch and the camera switch in the bar
/// (icons in the bar's colour), the picture with corner marks, [hint] and
/// "手动输入地址" ([onManual]) under it. A camera that cannot start says
/// why and offers "重试" and "输入地址". [result] replaces the picture
/// (sending, done, failed) and releases the camera; when it goes away the
/// camera starts again.
class QrScanPage extends StatefulWidget {
  /// Creates the page.
  const new({required this.hint, required this.onCode, this.onManual, this.result, this.unavailableHint, super.key});

  /// What to scan.
  final String hint;

  /// What to do when the camera cannot start (with [onManual]: retry or
  /// type the address).
  final String? unavailableHint;

  /// A code was read (once per camera start).
  final ValueChanged<String> onCode;

  /// "手动输入地址"; null hides it.
  final VoidCallback? onManual;

  /// Shown instead of the picture.
  final Widget? result;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  QrCamera? _camera;
  bool _failed = false;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    if (widget.result == null) _open();
  }

  @override
  void didUpdateWidget(QrScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.result != null && _camera != null) _close();
    if (widget.result == null && _camera == null && !_failed) _open();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _open() {
    _read = false;
    _camera = QrScan.camera?.call();
    _failed = _camera == null;
  }

  void _close() {
    _camera?.dispose();
    _camera = null;
  }

  void _retry() => setState(() {
    _close();
    _open();
  });

  void _code(String text) {
    if (_read) return;
    _read = true;
    widget.onCode(text);
  }

  void _cameraFailed() {
    if (!mounted || _failed) return;
    setState(() {
      _close();
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final result = widget.result;
    return Scaffold(
      appBar: settingsPageAppBar(
        context,
        title: i18n('scan_qr_code'),
        actions: [
          if (result == null && camera != null) ...[
            ValueListenableBuilder(
              valueListenable: camera.torch,
              builder: (context, torch, _) => IconButton(
                key: const ValueKey('qr-torch'),
                tooltip: i18n('qr_scan_torch'),
                onPressed: torch == QrTorch.unavailable ? null : () => unawaited(camera.toggleTorch()),
                icon: Icon(switch (torch) {
                  QrTorch.on => AppIcons.torchOn,
                  QrTorch.off => AppIcons.torchOff,
                  QrTorch.unavailable => AppIcons.torchUnavailable,
                }),
              ),
            ),
            IconButton(
              key: const ValueKey('qr-switch-camera'),
              tooltip: i18n('scanner_switch_camera'),
              onPressed: () => unawaited(camera.switchCamera()),
              icon: const Icon(AppIcons.switchCamera),
            ),
          ],
        ],
      ),
      body:
          result ??
          (_failed || camera == null
              ? QrScanStatus(
                  key: const ValueKey('qr-camera-unavailable'),
                  icon: AppIcons.cameraUnavailable,
                  title: i18n('qr_camera_unavailable'),
                  message: widget.unavailableHint ?? i18n('scanner_camera_error'),
                  primary: (label: i18n('retry'), icon: null, onPressed: _retry),
                  secondary: widget.onManual == null
                      ? null
                      : (label: i18n('qr_type_address'), icon: AppIcons.typeAddress, onPressed: widget.onManual!),
                )
              : _picture(camera)),
    );
  }

  Widget _picture(QrCamera camera) => ColoredBox(
    color: OnVideoColors.ground,
    child: Stack(
      fit: StackFit.expand,
      children: [
        camera.view(onCode: _code, onError: _cameraFailed),
        const IgnorePointer(child: Center(child: _Corners())),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: OnVideoColors.hint,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(
                      widget.hint,
                      textAlign: TextAlign.center,
                      style: context.textStyles.t14.copyWith(color: OnVideoColors.foreground),
                    ),
                  ),
                ),
                if (widget.onManual case final onManual?) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('qr-manual'),
                    onPressed: onManual,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OnVideoColors.foreground,
                      backgroundColor: OnVideoColors.buttonFill,
                      side: const BorderSide(color: OnVideoColors.buttonOutline),
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(AppIcons.typeAddress, size: 20),
                    label: Text(i18n('qr_manual_address')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The corner marks of the scan area.
class _Corners extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 240, child: CustomPaint(painter: _CornerPainter()));
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = OnVideoColors.foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const arm = 32.0;
    final w = size.width;
    final h = size.height;
    for (final (corner, dx, dy) in [
      (Offset.zero, 1.0, 1.0),
      (Offset(w, 0), -1.0, 1.0),
      (Offset(0, h), 1.0, -1.0),
      (Offset(w, h), -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(corner, corner + Offset(arm * dx, 0), paint)
        ..drawLine(corner, corner + Offset(0, arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

/// A button of [QrScanStatus].
typedef QrScanAction = ({String label, IconData? icon, VoidCallback onPressed});

/// A state of the scanner page in place of the picture (sending, done,
/// failed, no camera): a round icon, a title, a line, a filled button and
/// an outlined one (U.11a c8).
class QrScanStatus extends StatelessWidget {
  /// Creates the state.
  const new({
    required this.title,
    required this.message,
    this.icon,
    this.iconColor,
    this.busy = false,
    this.primary,
    this.secondary,
    super.key,
  });

  /// The icon in the circle (none while [busy]).
  final IconData? icon;

  /// The icon's colour (success green, error red); the secondary text
  /// colour when null.
  final Color? iconColor;

  /// A spinner instead of the icon.
  final bool busy;

  /// The title.
  final String title;

  /// What happened, what to do.
  final String message;

  /// The filled button.
  final QrScanAction? primary;

  /// The outlined (or text) button.
  final QrScanAction? secondary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: colors.surfaceContainerHigh, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: busy
                    ? const SizedBox.square(dimension: 32, child: CircularProgressIndicator(strokeWidth: 3))
                    : Icon(icon, size: 40, color: iconColor ?? colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: styles.t16.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: styles.t14.copyWith(color: colors.onSurfaceVariant),
              ),
              if (primary != null || secondary != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (primary case final primary?)
                      FilledButton(
                        key: const ValueKey('qr-status-primary'),
                        onPressed: primary.onPressed,
                        child: Text(primary.label),
                      ),
                    if (secondary case (:final label, icon: null, :final onPressed))
                      TextButton(key: const ValueKey('qr-status-secondary'), onPressed: onPressed, child: Text(label))
                    else if (secondary case (:final label, :final icon?, :final onPressed))
                      OutlinedButton.icon(
                        key: const ValueKey('qr-status-secondary'),
                        onPressed: onPressed,
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The scan button beside an address field; null where there is no
/// scanner. [onText] gets the code's text.
Widget? qrScanButton(BuildContext context, {required void Function(String text) onText, Key? key, String? hint}) {
  if (!QrScan.available) return null;
  return IconButton(
    key: key,
    tooltip: i18n('scan_qr_code'),
    icon: const Icon(AppIcons.scanQr),
    onPressed: () async {
      final text = await scanQrCode(context, hint: hint);
      if (text != null && text.isNotEmpty) onText(text);
    },
  );
}
