import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/app_dialog.dart';

/// A button of a [CardDialog] (outlined, with its words).
@immutable
final class CardDialogAction {
  /// Creates the button.
  const new({required this.label, required this.icon, required this.onPressed, this.key, this.danger = false});

  /// The button's key (tests find it by this).
  final Key? key;

  /// Its words.
  final String label;

  /// Its icon.
  final IconData icon;

  /// What it does.
  final VoidCallback onPressed;

  /// Drawn in the error colour (removing something).
  final bool danger;
}

/// The dialog a card opens on long press or right click, the same for room
/// cards (docs/T07/T07d/T07d.1 c10, choice A1: in the middle of the screen,
/// like 3.x) and area cards (U.4d X3, coordinator 2026-10-01; UI_PLAN §3
/// rule 7: one component for one action everywhere).
///
/// [leading] (the platform's logo) and [title] with [subtitle] and [detail]
/// under it; the whole [body] text in a box; [actions] as rows of outlined
/// buttons with their words (a row shares its width); then "关闭" and an
/// optional [trailing] button (the follow pill). Back, Esc and a tap outside
/// close it too.
class CardDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({
    required this.leading,
    required this.title,
    required this.closeLabel,
    this.subtitle,
    this.detail,
    this.body,
    this.actions = const [],
    this.trailing,
    super.key,
  });

  /// The picture before the title (a platform logo).
  final Widget leading;

  /// The streamer or the area.
  final String title;

  /// "platform · room id" or "platform · category"; selectable.
  final String? subtitle;

  /// A further line under the subtitle (the history's watch time).
  final String? detail;

  /// The whole title of a room.
  final String? body;

  /// Rows of buttons.
  final List<List<CardDialogAction>> actions;

  /// The words of the close button.
  final String closeLabel;

  /// The button after "关闭".
  final Widget? trailing;

  /// The widest the dialog gets (the one dialog's width, U.1d c7; 3.x's
  /// room dialog was 428).
  static const double maxWidth = appDialogMaxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = AppTextStyles(theme);
    final muted = styles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.4).tabular;

    Widget button(CardDialogAction action) => OutlinedButton.icon(
      key: action.key,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        backgroundColor: scheme.surface,
        foregroundColor: action.danger ? scheme.error : scheme.primary,
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        textStyle: styles.t14.copyWith(fontWeight: FontWeight.w500),
      ),
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 18),
      label: Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );

    final body = this.body;
    // The one dialog's frame (docs/T01/T01d/T01d.1): its width, corners,
    // keys and buttons at the bottom right.
    return AppDialog(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 12,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                child: ClipRRect(borderRadius: BorderRadius.circular(7), child: leading),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('card-dialog-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.t16.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    if (subtitle case final text? when text.isNotEmpty)
                      SelectableText(text, key: const ValueKey('card-dialog-subtitle'), maxLines: 1, style: muted),
                    if (detail case final text? when text.isNotEmpty)
                      Text(text, key: const ValueKey('card-dialog-detail'), style: muted),
                  ],
                ),
              ),
            ],
          ),
          if (body != null)
            Container(
              key: const ValueKey('card-dialog-body'),
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
              child: Text(
                body,
                style: styles.t14.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500, height: 1.45),
              ),
            ),
          for (final (index, row) in actions.indexed)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 14 : 8),
              child: Row(spacing: 8, children: [for (final action in row) Expanded(child: button(action))]),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('card-dialog-close'),
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          onPressed: () => Navigator.pop(context),
          child: Text(closeLabel),
        ),
        ?trailing,
      ],
    );
  }
}
