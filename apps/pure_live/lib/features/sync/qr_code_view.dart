import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A QR code of [data], drawn dark on white in every theme (scanners need the
/// contrast) with the four-module quiet zone the standard asks for.
class QrCodeView extends StatelessWidget {
  const new({required this.data, this.size = 200, this.semanticLabel, super.key});

  /// Encoded text.
  final String data;

  /// Edge length in logical pixels.
  final double size;

  /// What a screen reader says instead of the pattern.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(data)));
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const new(this.image);

  final QrImage image;

  static const _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final count = image.moduleCount;
    final module = size.shortestSide / (count + _quietZone * 2);
    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < count; row++) {
      for (var column = 0; column < count; column++) {
        if (!image.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH((column + _quietZone) * module, (row + _quietZone) * module, module + 0.5, module + 0.5),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
