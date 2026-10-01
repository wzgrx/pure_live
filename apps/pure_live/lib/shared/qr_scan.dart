import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Reading a QR code with the camera (3.x `mobile_scanner`): device sync and
/// TV sync offer it next to the typed address. The app sets [scan] on phones
/// (M12.3); null hides the scan buttons (desktops have no scanner).
abstract final class QrScan {
  /// Opens the scanner; completes with the code's text, or null when the user
  /// left without one.
  static Future<String?> Function(BuildContext context)? scan;
}

/// The camera scanner page (3.x `QrScannerPage`): the first QR code read
/// closes it with its text; the torch can be switched; a camera that cannot
/// start says why.
Future<String?> scanQrCode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage(), fullscreenDialog: true));

/// The scanner page.
class QrScanPage extends StatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue?.trim() ?? '';
      if (text.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(text);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(i18n('scan_qr_code')),
      actions: [
        IconButton(
          tooltip: i18n('qr_scan_torch'),
          icon: const Icon(Icons.flashlight_on_rounded),
          onPressed: () => unawaited(_controller.toggleTorch()),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _detected,
          errorBuilder: (context, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                i18n('scanner_camera_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              i18n('qr_scan_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The scan button beside an address field; null where there is no
/// scanner. [onText] gets the code's text.
Widget? qrScanButton(BuildContext context, {required void Function(String text) onText, Key? key}) {
  final scan = QrScan.scan;
  if (scan == null) return null;
  return IconButton(
    key: key,
    tooltip: i18n('scan_qr_code'),
    icon: const Icon(Icons.qr_code_scanner_rounded),
    onPressed: () async {
      final text = await scan(context);
      if (text != null && text.isNotEmpty) onText(text);
    },
  );
}
