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
/// Bilibili login code), low error correction: black on white in every
/// theme (scanners read it), a 12-point quiet zone, 12-point corners
/// (docs/ui/compare/U.1c c11; 3.x had square and round codes).
class QrCodeWidget extends StatelessWidget {
  /// Creates the code.
  const new({
    required this.data,
    this.size = 180,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.backgroundColor = QrColors.paper,
    this.foregroundColor = QrColors.ink,
    super.key,
  });

  /// The text encoded.
  final String data;

  /// Width and height, quiet zone included.
  final double size;

  /// Quiet zone.
  final EdgeInsets padding;

  /// The corners.
  final BorderRadius borderRadius;

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
      decoration: BoxDecoration(color: backgroundColor, borderRadius: borderRadius),
      child: CustomPaint(
        painter: _QrCodePainter(qrImage: qrImage, foregroundColor: foregroundColor),
        size: Size.infinite,
      ),
    );
  }
}

/// Where a [QrCodeCard] is.
enum QrCodeStatus {
  /// The code is being fetched: a spinner on a white square of its size.
  loading,

  /// The code waits to be scanned: nothing over it.
  ready,

  /// The code was scanned (confirm on the phone).
  scanned,

  /// The code expired: a button gets a new one.
  expired,

  /// Fetching or checking the code failed: a button retries.
  failed,

  /// Something runs after the scan (checking the login).
  working,

  /// Done.
  done,
}

/// The QR code in its card (docs/ui/compare/U.1c c11): the code on the
/// `surfaceContainerLow` card (16-point corners); every state is laid over
/// the code in its place, so nothing below it moves (3.x swapped the code
/// for text). The veil is always white like the code; [message] says what
/// happens, [actionLabel] is the expired or failed state's button.
class QrCodeCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.data,
    required this.status,
    this.size = 200,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  /// The text encoded; null while there is none yet.
  final String? data;

  /// The state.
  final QrCodeStatus status;

  /// The code's side, quiet zone included.
  final double size;

  /// The words over the code.
  final String? message;

  /// The button of [QrCodeStatus.expired] and [QrCodeStatus.failed].
  final String? actionLabel;

  /// What the button does.
  final VoidCallback? onAction;

  /// Key of the button.
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(fontSize: 14, color: QrColors.ink);
    final heading = ink.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    // The veil is white in every theme: the dark theme's light primary
    // would fade on it.
    final mark = scheme.brightness == Brightness.dark ? QrColors.ink : scheme.primary;
    final words = message;
    Widget? text(TextStyle style) =>
        words == null || words.isEmpty ? null : Text(words, textAlign: TextAlign.center, style: style);
    const spinner = SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3));
    Widget? button() => onAction == null || actionLabel == null
        ? null
        : FilledButton.icon(
            key: actionKey,
            onPressed: onAction,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(actionLabel!),
          );
    final children = switch (status) {
      QrCodeStatus.ready => null,
      QrCodeStatus.loading || QrCodeStatus.working => [spinner, ?_gap(12, text(ink))],
      QrCodeStatus.scanned || QrCodeStatus.done => [
        Icon(Icons.check_circle_outline_rounded, size: 44, color: mark),
        ?_gap(8, text(status == QrCodeStatus.scanned ? heading : ink)),
      ],
      QrCodeStatus.expired || QrCodeStatus.failed => [
        Icon(Icons.error_outline_rounded, size: 32, color: status == QrCodeStatus.failed ? scheme.error : QrColors.ink),
        ?_gap(8, text(ink)),
        ?_gap(8, button()),
      ],
    };
    final code = data;
    return Center(
      child: Container(
        key: const ValueKey('qr-card'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              children: [
                if (code != null && code.isNotEmpty)
                  QrCodeWidget(key: const ValueKey('qr-code'), data: code, size: size)
                else
                  const Positioned.fill(child: ColoredBox(color: QrColors.paper)),
                if (children != null)
                  Positioned.fill(
                    key: ValueKey('qr-${status.name}'),
                    child: ColoredBox(
                      color: QrColors.veil,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: children),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget? _gap(double height, Widget? child) => child == null
      ? null
      : Padding(
          padding: EdgeInsets.only(top: height),
          child: child,
        );
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
