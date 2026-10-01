import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// A centred message of a TV page: loading, empty or failed, with an action
/// the remote can reach (pure_live_TV `EmptyScene`).
class TvMessage extends StatelessWidget {
  /// Creates the message.
  const new({
    required this.title,
    this.icon,
    this.subtitle,
    this.action,
    this.onAction,
    this.busy = false,
    this.autofocus = false,
    super.key,
  });

  /// The icon; none while [busy].
  final IconData? icon;

  /// The main line.
  final String title;

  /// A second line.
  final String? subtitle;

  /// The action's label.
  final String? action;

  /// The action.
  final VoidCallback? onAction;

  /// Shows a spinner instead of the icon.
  final bool busy;

  /// Focuses the action when shown.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(scale(40)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: scale(56),
                child: CircularProgressIndicator(color: palette.focus, strokeWidth: scale(5)),
              )
            else if (icon != null)
              Icon(icon, size: scale(72), color: palette.textSecondary),
            SizedBox(height: scale(20)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: scale.style(26, weight: FontWeight.w600, color: palette.text),
            ),
            if (subtitle case final subtitle? when subtitle.isNotEmpty) ...[
              SizedBox(height: scale(10)),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: scale.style(20, color: palette.textSecondary),
              ),
            ],
            if (action != null && onAction != null) ...[
              SizedBox(height: scale(28)),
              TvButton(label: action!, icon: Icons.refresh_rounded, autofocus: autofocus, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// A dialog frame of the TV interface (pure_live_TV `TvDialog`): a title,
/// the content and, when [cancel] is set, a cancel button.
class TvDialog extends StatelessWidget {
  /// Creates the frame.
  const new({required this.title, required this.child, this.width = 760, this.cancel = true, super.key});

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// The width in design pixels.
  final double width;

  /// Shows a cancel button.
  final bool cancel;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: palette.background,
      insetPadding: EdgeInsets.all(scale(40)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(scale(28))),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scale(width), maxHeight: height * 0.86),
        child: Padding(
          padding: EdgeInsets.all(scale(32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: scale.style(30, weight: FontWeight.w700, color: palette.text),
              ),
              SizedBox(height: scale(20)),
              Flexible(child: child),
              if (cancel) ...[
                SizedBox(height: scale(20)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TvButton(label: i18n('cancel'), onTap: () => Navigator.pop(context)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of [showTvChoice].
typedef TvChoice<T> = ({T value, String label, String? description});

/// Picks one of [options] (pure_live_TV `TvSelectDialog`): the current one
/// is ticked and has the focus when the dialog opens; null when cancelled.
Future<T?> showTvChoice<T>(
  BuildContext context, {
  required String title,
  required List<TvChoice<T>> options,
  T? current,
}) => showDialog<T>(
  context: context,
  builder: (context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final selected = options.indexWhere((option) => option.value == current);
    return TvDialog(
      title: title,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, option) in options.indexed)
              Padding(
                padding: EdgeInsets.only(bottom: scale(8)),
                child: TvFocusable(
                  key: ValueKey('tv-choice-$index'),
                  autofocus: index == (selected < 0 ? 0 : selected),
                  scale: 1.02,
                  onTap: () => Navigator.pop(context, option.value),
                  builder: (context, focused) {
                    final color = focused ? palette.onFocusedCard : palette.text;
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: scale.text(20), vertical: scale.text(14)),
                      decoration: BoxDecoration(
                        color: focused ? palette.focusedCard : palette.subtleFill,
                        borderRadius: BorderRadius.circular(scale(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.label,
                                  style: scale.style(22, weight: FontWeight.w600, color: color),
                                ),
                                if (option.description case final description? when description.isNotEmpty)
                                  Text(description, style: scale.style(17, color: color.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          if (index == selected) Icon(Icons.check_rounded, color: palette.focus, size: scale.text(28)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  },
);

/// Asks a yes/no question with the remote (pure_live_TV `TvConfirmDialog`);
/// the safe answer has the focus.
Future<bool> showTvConfirm(BuildContext context, {required String title, required String message}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = TvTheme.of(context);
        final scale = TvScale.of(context);
        return TvDialog(
          title: title,
          cancel: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: scale.style(22, color: palette.text)),
              SizedBox(height: scale(28)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvButton(
                    key: const ValueKey('tv-confirm-no'),
                    label: i18n('cancel'),
                    autofocus: true,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  SizedBox(width: scale(16)),
                  TvButton(
                    key: const ValueKey('tv-confirm-yes'),
                    label: i18n('confirm'),
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ) ??
    false;

/// Reads one line of text with the remote.
///
/// Android shows a native input dialog (`pure_live/app` `inputText`): an
/// EditText opens the system keyboard (the TV's own IME, voice input where
/// the box has it) reliably, where Flutter's text input stays closed on some
/// TV boxes (pure_live_TV used a native platform view for the same reason,
/// flutter#154924). Elsewhere a Flutter dialog with a text field. Tests
/// replace [prompt].
abstract final class TvTextInput {
  /// Asks for the text; null when cancelled.
  static Future<String?> Function(BuildContext context, {required String title, String hint, String text}) prompt =
      defaultPrompt;

  /// The prompt of the system ([prompt] starts as this).
  static Future<String?> defaultPrompt(
    BuildContext context, {
    required String title,
    String hint = '',
    String text = '',
  }) => _prompt(context, title: title, hint: hint, text: text);

  static const MethodChannel _channel = MethodChannel('pure_live/app');

  static Future<String?> _prompt(BuildContext context, {required String title, String hint = '', String text = ''}) {
    if (Platform.isAndroid) return _native(context, title: title, hint: hint, text: text);
    return _flutter(context, title: title, hint: hint, text: text);
  }

  static Future<String?> _native(
    BuildContext context, {
    required String title,
    required String hint,
    required String text,
  }) async {
    try {
      return await _channel.invokeMethod<String>('inputText', {'title': title, 'hint': hint, 'text': text});
    } on MissingPluginException {
      return context.mounted ? await _flutter(context, title: title, hint: hint, text: text) : null;
    } on PlatformException {
      return context.mounted ? await _flutter(context, title: title, hint: hint, text: text) : null;
    }
  }

  static Future<String?> _flutter(
    BuildContext context, {
    required String title,
    required String hint,
    required String text,
  }) async {
    final controller = TextEditingController(text: text);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) {
          final palette = TvTheme.of(context);
          final scale = TvScale.of(context);
          return TvDialog(
            title: title,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('tv-text-input'),
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: scale.style(24, color: palette.text),
                  decoration: InputDecoration(hintText: hint),
                  onSubmitted: (value) => Navigator.pop(context, value),
                ),
                SizedBox(height: scale(20)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TvButton(label: i18n('confirm'), onTap: () => Navigator.pop(context, controller.text)),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

/// A text field for the remote (pure_live_TV `TvInputField`, the read-only
/// display half): it shows the text or the hint; OK opens [TvTextInput].
class TvInputField extends StatelessWidget {
  /// Creates the field.
  const new({
    required this.text,
    required this.hint,
    required this.onSubmitted,
    this.title,
    this.focusNode,
    this.autofocus = false,
    this.icon = Icons.search_rounded,
    this.onKey,
    super.key,
  });

  /// The current text.
  final String text;

  /// Shown while [text] is empty, and in the input dialog.
  final String hint;

  /// The input dialog's title; [hint] when null.
  final String? title;

  /// The text the user confirmed.
  final ValueChanged<String> onSubmitted;

  /// The node.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  /// The leading icon.
  final IconData icon;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvFocusable(
      key: const ValueKey('tv-input-field'),
      focusNode: focusNode,
      autofocus: autofocus,
      onKey: onKey,
      scale: 1.02,
      radius: 40,
      onTap: () async {
        final value = await TvTextInput.prompt(context, title: title ?? hint, hint: hint, text: text);
        if (value != null) onSubmitted(value.trim());
      },
      builder: (context, focused) {
        final color = focused ? palette.onFocusedCard : palette.text;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: scale.text(24), vertical: scale.text(14)),
          decoration: BoxDecoration(
            color: focused ? palette.focusedCard : palette.card,
            borderRadius: BorderRadius.circular(scale(40)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: scale.text(28)),
              SizedBox(width: scale(14)),
              Expanded(
                child: Text(
                  text.isEmpty ? hint : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.style(24, color: text.isEmpty ? color.withValues(alpha: 0.6) : color),
                ),
              ),
              Text(i18n('tv_input_ok_hint'), style: scale.style(17, color: color.withValues(alpha: 0.6))),
            ],
          ),
        );
      },
    );
  }
}
