import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// The colours around a QR code: it is always dark on white, whatever the
/// theme, so scanners read it; states laid over it use these too.
abstract final class QrColors {
  /// The code's paper.
  static const Color paper = Color(0xFFFFFFFF);

  /// The modules, and text laid over the code.
  static const Color ink = Color(0xFF191C20);

  /// A veil over the code while it is loading, scanned or expired.
  static const Color veil = Color(0xE6FFFFFF);
}

/// A QR code of [data] painted module by module (3.x `QrCodeWidget`, the
/// Bilibili login code), low error correction.
class QrCodeWidget extends StatelessWidget {
  /// Creates the code.
  const new({
    required this.data,
    this.size = 180,
    this.padding = const EdgeInsets.all(12),
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black,
    super.key,
  });

  /// The text encoded.
  final String data;

  /// Width and height, quiet zone included.
  final double size;

  /// Quiet zone.
  final EdgeInsets padding;

  /// Background colour.
  final Color backgroundColor;

  /// Module colour.
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final qrCode = QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.low);

    final qrImage = QrImage(qrCode);

    return Container(
      width: size,
      height: size,
      padding: padding,
      color: backgroundColor,
      child: CustomPaint(
        painter: _QrCodePainter(qrImage: qrImage, foregroundColor: foregroundColor),
        size: Size.infinite,
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  const new({required this.qrImage, required this.foregroundColor});

  final QrImage qrImage;
  final Color foregroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final moduleCount = qrImage.moduleCount;
    final moduleSize = size.width / moduleCount;

    final paint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    for (var row = 0; row < moduleCount; row++) {
      for (var col = 0; col < moduleCount; col++) {
        if (qrImage.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTRB(col * moduleSize, row * moduleSize, (col + 1) * moduleSize, (row + 1) * moduleSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) {
    return oldDelegate.qrImage != qrImage || oldDelegate.foregroundColor != foregroundColor;
  }
}
