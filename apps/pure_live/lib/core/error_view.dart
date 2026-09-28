import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';

/// Whether [error] is a connection problem (no network, a proxy, a reset):
/// its picture is the broken antenna (principles §3.3).
bool isNetworkError(Object error) => error is NetworkFailure || error is TransportFailure;

/// The error state of a page or list (principles rule 3, §3.3): what
/// happened in the user's words ([describeError], never the exception's
/// text), the picture for its kind, and 重试 when trying again can help.
///
/// [title] replaces the described title where the page knows better what
/// failed ("读取关注失败"); the described message still explains why. Sheets
/// and panels pass [compact] for the small icon instead of the picture.
class ErrorView extends StatelessWidget {
  const new(this.error, {this.onRetry, this.title, this.compact = false, this.actions = const [], super.key});

  /// What failed.
  final Object error;

  /// Tries again; shown when the failure is one that retrying can fix.
  final VoidCallback? onRetry;

  /// A title that names what failed; the described one when null.
  final String? title;

  /// The small icon instead of the illustration.
  final bool compact;

  /// Further buttons after 重试 (three at most in all).
  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    final text = describeError(error);
    return MessageView.error(
      illustration: compact ? null : (isNetworkError(error) ? Illustration.offline : Illustration.error),
      title: title ?? text.title,
      message: text.message,
      onAction: text.retryable ? onRetry : null,
      actions: actions,
    );
  }
}
