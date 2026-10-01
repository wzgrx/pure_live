import 'package:flutter/material.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/loading_styles.dart';

/// What [AppStatusView] shows.
enum AppStatusType {
  /// The loading animation the user picked.
  loading,

  /// Nothing to show.
  empty,

  /// Loading failed.
  error,
}

/// Loading, empty and error states of a page or a tile (3.x
/// `AppStatusView`).
///
/// The empty and error states show an icon in a circle that pops in, a title,
/// a text and, with [onButtonPressed], a button (retry unless [buttonText]
/// and [buttonIcon] say otherwise) in the tonal filled style, and with
/// [onSecondaryButtonPressed] a second one as a text button (U.1c C1, the
/// same on every status page). Missing texts fall back to the words of
/// [LiveUiScope]. [isMini] is the small form for a card cover: a small icon,
/// no button, and a title or text only when given non-empty.
class AppStatusView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.type,
    this.title,
    this.subtitle,
    this.icon,
    this.buttonText,
    this.buttonIcon,
    this.onButtonPressed,
    this.isMini = false,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
    super.key,
  });

  /// The state.
  final AppStatusType type;

  /// Title; null takes the state's default.
  final String? title;

  /// Text under the title; null takes the state's default.
  final String? subtitle;

  /// Icon; null takes the state's default (no network for errors, a TV for
  /// empty).
  final IconData? icon;

  /// Button label; null takes "retry".
  final String? buttonText;

  /// Button icon, matching what [buttonText] does; null takes the retry
  /// icon (3.x showed it on every button, also "search" and "log in").
  final IconData? buttonIcon;

  /// Shows the button (not in [isMini]).
  final VoidCallback? onButtonPressed;

  /// The small form.
  final bool isMini;

  /// Icon colour, and the loading colour when the user picked none.
  final Color? iconColor;

  /// Title colour.
  final Color? titleColor;

  /// Text colour.
  final Color? subtitleColor;

  /// The second button's label (a text button after the first).
  final String? secondaryButtonText;

  /// Shows the second button (not in [isMini]).
  final VoidCallback? onSecondaryButtonPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = LiveUiScope.of(context);
    if (type == AppStatusType.loading) {
      final size = isMini ? 24.0 : (MediaQuery.sizeOf(context).width > 680 ? 32.0 : 24.0);
      return Center(
        child: LoadingStyles.build(
          LoadingStyles.normalize(config.loadingStyle),
          color: config.loadingColor ?? iconColor ?? theme.colorScheme.primary,
          size: size,
          colors: theme.colorScheme,
        ),
      );
    }

    final words = config.strings;
    final isError = type == AppStatusType.error;
    final finalTitle = title ?? (isError ? words.errorTitle : words.emptyTitle);
    final finalSubtitle = subtitle ?? (isError ? words.errorSubtitle : words.emptySubtitle);
    final styles = AppTextStyles(theme);
    final effectiveIconColor = iconColor ?? theme.colorScheme.primary;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.elasticOut,
            builder: (context, value, child) => Transform.scale(scale: value, child: child),
            child: Container(
              padding: EdgeInsets.all(isMini ? 8 : 22),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: effectiveIconColor.withValues(alpha: 0.05)),
              ),
              child: Icon(
                icon ?? (isError ? Icons.wifi_off_rounded : Icons.live_tv_rounded),
                size: isMini ? 16 : 42,
                color: iconColor ?? theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (!isMini || finalTitle.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              finalTitle,
              style: styles.t15.copyWith(
                fontWeight: FontWeight.w600,
                color: titleColor ?? theme.textTheme.titleMedium?.color,
              ),
            ),
          ],
          if (!isMini || finalSubtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  finalSubtitle,
                  textAlign: TextAlign.center,
                  style: styles.t13.copyWith(color: subtitleColor ?? theme.hintColor, height: 1.5),
                ),
              ),
            ),
          if (!isMini && (onButtonPressed != null || onSecondaryButtonPressed != null)) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onButtonPressed case final pressed?)
                  FilledButton.tonalIcon(
                    key: const ValueKey('status-button'),
                    onPressed: pressed,
                    icon: Icon(buttonIcon ?? Icons.refresh_rounded, size: 18),
                    label: Text(buttonText ?? words.retry),
                  ),
                if (onSecondaryButtonPressed case final pressed?)
                  TextButton(
                    key: const ValueKey('status-secondary-button'),
                    onPressed: pressed,
                    child: Text(secondaryButtonText ?? words.retry),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The empty state (3.x `EmptyView`): [AppStatusView] with
/// [AppStatusType.empty].
class EmptyView extends StatelessWidget {
  /// Creates the view.
  const new({
    this.title,
    this.subtitle,
    this.icon,
    this.buttonText,
    this.buttonIcon,
    this.onButtonPressed,
    this.isMini = false,
    this.iconColor,
    this.titleColor,
    this.subtitleColor,
    this.secondaryButtonText,
    this.onSecondaryButtonPressed,
    super.key,
  });

  /// See [AppStatusView.title].
  final String? title;

  /// See [AppStatusView.subtitle].
  final String? subtitle;

  /// See [AppStatusView.icon].
  final IconData? icon;

  /// See [AppStatusView.buttonText].
  final String? buttonText;

  /// See [AppStatusView.buttonIcon].
  final IconData? buttonIcon;

  /// See [AppStatusView.onButtonPressed].
  final VoidCallback? onButtonPressed;

  /// See [AppStatusView.isMini].
  final bool isMini;

  /// See [AppStatusView.iconColor].
  final Color? iconColor;

  /// See [AppStatusView.titleColor].
  final Color? titleColor;

  /// See [AppStatusView.subtitleColor].
  final Color? subtitleColor;

  /// See [AppStatusView.secondaryButtonText].
  final String? secondaryButtonText;

  /// See [AppStatusView.onSecondaryButtonPressed].
  final VoidCallback? onSecondaryButtonPressed;

  @override
  Widget build(BuildContext context) {
    return AppStatusView(
      type: AppStatusType.empty,
      title: title,
      subtitle: subtitle,
      icon: icon,
      buttonText: buttonText,
      buttonIcon: buttonIcon,
      onButtonPressed: onButtonPressed,
      isMini: isMini,
      iconColor: iconColor,
      titleColor: titleColor,
      subtitleColor: subtitleColor,
      secondaryButtonText: secondaryButtonText,
      onSecondaryButtonPressed: onSecondaryButtonPressed,
    );
  }
}
