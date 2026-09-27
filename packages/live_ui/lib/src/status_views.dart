import 'package:flutter/material.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/ui_text.dart';

/// Centered progress for a page or panel that has nothing to show yet.
class LoadingView extends StatelessWidget {
  /// Creates the view.
  const new({this.label, super.key});

  /// Optional text under the indicator.
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (label != null) ...[
          const SizedBox(height: Space.s4),
          Text(label!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    ),
  );
}

/// An empty or error state: what happened and the next step, in place
/// (principles rule 3).
class MessageView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  }) : _error = false;

  /// An error state with a retry button ("重试" unless [actionLabel] says
  /// otherwise).
  const new error({
    required this.title,
    this.message,
    this.onAction,
    this.actionLabel,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  }) : icon = Icons.error_outline,
       _error = true;

  /// Headline.
  final String title;

  /// Explanation.
  final String? message;

  /// Illustration icon.
  final IconData icon;

  /// Primary action label.
  final String? actionLabel;

  /// Primary action.
  final VoidCallback? onAction;

  /// Secondary action label.
  final String? secondaryLabel;

  /// Secondary action.
  final VoidCallback? onSecondary;

  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = LiveUiText.current;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: Space.s4),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (onAction != null || onSecondary != null) ...[
                const SizedBox(height: Space.s6),
                Wrap(
                  spacing: Space.s2,
                  runSpacing: Space.s2,
                  alignment: WrapAlignment.center,
                  children: [
                    if (onAction != null)
                      FilledButton(onPressed: onAction, child: Text(actionLabel ?? (_error ? words.retry : words.ok))),
                    if (onSecondary != null)
                      OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel ?? words.cancel)),
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
