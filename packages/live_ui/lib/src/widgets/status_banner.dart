import 'package:flutter/material.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/theme/text_wrapping.dart';

/// The colour of a [StatusBanner].
enum StatusBannerKind {
  /// An explanation (a partial directory): a light bar with ⓘ.
  info,

  /// A reminder (mobile data): warm.
  warning,

  /// A failure while the old content stays (a failed refresh): the error
  /// container.
  error,
}

/// One action of a [StatusBanner]: a short text button under the words.
typedef StatusBannerAction = ({String label, VoidCallback? onPressed, Key? key});

/// The bar at the top of a page whose content still shows
/// (docs/A-界面设计/A02-组件/A02.1-通用组件): one component in three colours for an explanation, a reminder
/// and a failure (3.x had an unstyled line, a primary-tinted card and a
/// `MaterialBanner`).
///
/// An 18 icon, 13-point words (an explanation keeps to two lines until
/// tapped), text buttons under the words, ✕ at the end when [onClose] is
/// given (48 to tap), or › when [onTap] opens more.
class StatusBanner extends StatefulWidget {
  /// Creates the bar.
  const new({
    required this.kind,
    required this.text,
    this.icon,
    this.actions = const [],
    this.onClose,
    this.onTap,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 0),
    super.key,
  });

  /// The colour.
  final StatusBannerKind kind;

  /// The words.
  final String text;

  /// The icon; null takes the kind's (ⓘ, a warning, an error mark).
  final IconData? icon;

  /// Buttons under the words ("不再显示", "重试", "详情").
  final List<StatusBannerAction> actions;

  /// Shows ✕, which calls it.
  final VoidCallback? onClose;

  /// A tap on the bar; shows › at the end. Without it an explanation
  /// unfolds on tap.
  final VoidCallback? onTap;

  /// Space around the bar.
  final EdgeInsetsGeometry margin;

  @override
  State<StatusBanner> createState() => _StatusBannerState();
}

class _StatusBannerState extends State<StatusBanner> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;
    final (Color background, Color ink, Color iconColor, IconData glyph) = switch (widget.kind) {
      StatusBannerKind.info => (
        scheme.surfaceContainerLow,
        scheme.onSurfaceVariant,
        scheme.primary,
        Icons.info_outline_rounded,
      ),
      StatusBannerKind.warning => (
        LiveSemanticColors.warningContainer(brightness),
        scheme.onSurface,
        LiveSemanticColors.warning(brightness),
        Icons.warning_amber_rounded,
      ),
      StatusBannerKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
    };
    final folds = widget.kind == StatusBannerKind.info && widget.onTap == null;
    final tap = widget.onTap ?? (folds ? () => setState(() => _open = !_open) : null);
    final style = context.textStyles.t13.copyWith(color: ink, height: 1.5);
    final close = widget.onClose;
    return Padding(
      padding: widget.margin,
      child: Semantics(
        container: true,
        liveRegion: widget.kind == StatusBannerKind.error,
        child: Material(
          color: background,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            onTap: tap,
            child: Padding(
              // The buttons are 48 to tap: less padding under them.
              padding: EdgeInsetsDirectional.fromSTEB(
                14,
                10,
                close != null || widget.onTap != null ? 2 : 14,
                widget.actions.isEmpty ? 10 : 0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(widget.icon ?? glyph, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          withoutOrphan(widget.text),
                          maxLines: folds && !_open ? 2 : null,
                          overflow: folds && !_open ? TextOverflow.ellipsis : null,
                          style: style,
                        ),
                        if (widget.actions.isNotEmpty)
                          Transform.translate(
                            offset: const Offset(-12, 0),
                            child: Wrap(
                              spacing: 2,
                              children: [
                                for (final action in widget.actions)
                                  TextButton(
                                    key: action.key,
                                    onPressed: action.onPressed,
                                    style: TextButton.styleFrom(
                                      foregroundColor: widget.kind == StatusBannerKind.error ? ink : null,
                                      minimumSize: const Size(48, 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      textStyle: context.textStyles.t13.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    child: Text(action.label),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (close != null)
                    Transform.translate(
                      offset: const Offset(0, -8),
                      child: IconButton(
                        key: const ValueKey('status-banner-close'),
                        tooltip: LiveUiScope.of(context).strings.close,
                        onPressed: close,
                        color: widget.kind == StatusBannerKind.error ? ink : scheme.onSurfaceVariant,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    )
                  else if (widget.onTap != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
