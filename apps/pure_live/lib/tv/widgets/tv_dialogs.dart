import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// Shows a TV dialog: the 60 % black scrim (U.15a c16), the route keeps the
/// focus inside, Back closes it, and the focus goes back to where it was
/// when it closes (Flutter's route focus scopes, U.15a c1).
Future<T?> showTvDialog<T>(BuildContext context, {required WidgetBuilder builder}) =>
    showDialog<T>(context: context, barrierColor: TvColors.scrim, builder: builder);

/// The frame of every TV dialog (docs/T18/T18a/T18a.2 c16, the phone's
/// dialog in the TV style): the high surface container, corners of 24, no
/// ring and no glow (P17); the title (22, 600), an optional line under it
/// (14, secondary), the content and the buttons on the right, cancel before
/// the main one; [leading] sits at the left of the button row.
class TvDialog extends StatelessWidget {
  /// Creates the frame.
  const new({
    required this.child,
    this.title,
    this.subtitle,
    this.header,
    this.actions = const [],
    this.leading,
    this.width = 480,
    super.key,
  });

  /// The title.
  final String? title;

  /// The line under the title.
  final String? subtitle;

  /// A header drawn instead of [title] and [subtitle] (the card dialog's
  /// logo and names).
  final Widget? header;

  /// The content.
  final Widget child;

  /// The buttons, right-aligned.
  final List<Widget> actions;

  /// A button at the left of the button row.
  final Widget? leading;

  /// The width in canvas pixels.
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: palette.raised,
      insetPadding: EdgeInsets.symmetric(horizontal: scale.px(48), vertical: scale.px(28)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(scale.px(TvRadius.dialog))),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scale.pxText(width), maxHeight: height * 0.9),
        child: Padding(
          padding: EdgeInsets.fromLTRB(scale.px(28), scale.px(28), scale.px(28), scale.px(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header case final header?)
                header
              else if (title case final title?)
                Text(
                  title,
                  key: const ValueKey('tv-dialog-title'),
                  style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text, height: 1.3),
                ),
              if (subtitle case final subtitle? when header == null && subtitle.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: scale.px(4)),
                  child: Text(subtitle, style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4)),
                ),
              Flexible(child: child),
              if (actions.isNotEmpty || leading != null)
                Padding(
                  padding: EdgeInsets.only(top: scale.px(24)),
                  child: Row(
                    children: [
                      ?leading,
                      const Spacer(),
                      for (final (index, action) in actions.indexed) ...[
                        if (index > 0) SizedBox(width: scale.px(12)),
                        action,
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The body text of a dialog (16, secondary colour).
class TvDialogText extends StatelessWidget {
  /// Creates the text.
  const new(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return Padding(
      padding: EdgeInsets.only(top: scale.px(14)),
      child: Text(text, style: scale.font(TvTextSize.body, color: TvTheme.of(context).textSecondary, height: 1.6)),
    );
  }
}

/// Asks a yes/no question with the remote (U.15a, dialog 51–52): cancel on
/// the left, the main button naming the action on the right. A [danger]ous
/// question (unfollow, clear, delete; choice A4) has the focus on cancel and
/// its main button in the error colour; any other has the focus on the main
/// button, which ignores OK for half a second after opening (a held OK that
/// opened the dialog must not answer it).
Future<bool> showTvConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool danger = false,
}) async =>
    await showTvDialog<bool>(
      context,
      builder: (context) =>
          _TvConfirm(title: title, message: message, confirmLabel: confirmLabel ?? i18n('confirm'), danger: danger),
    ) ??
    false;

class _TvConfirm extends StatefulWidget {
  const new({required this.title, required this.message, required this.confirmLabel, required this.danger});

  final String title;
  final String message;
  final String confirmLabel;
  final bool danger;

  @override
  State<_TvConfirm> createState() => _TvConfirmState();
}

class _TvConfirmState extends State<_TvConfirm> {
  late bool _armed = widget.danger;
  Timer? _arm;

  @override
  void initState() {
    super.initState();
    if (!_armed) _arm = Timer(tvLongPressDelay, () => _armed = true);
  }

  @override
  void dispose() {
    _arm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvDialog(
    title: widget.title,
    actions: [
      TvButton(
        key: const ValueKey('tv-confirm-no'),
        label: i18n('cancel'),
        autofocus: widget.danger,
        onTap: () => Navigator.pop(context, false),
      ),
      TvButton(
        key: const ValueKey('tv-confirm-yes'),
        label: widget.confirmLabel,
        kind: widget.danger ? TvButtonKind.danger : TvButtonKind.primary,
        autofocus: !widget.danger,
        onTap: () {
          if (_armed) Navigator.pop(context, true);
        },
      ),
    ],
    child: TvDialogText(widget.message),
  );
}

/// One choice of [showTvChoice].
@immutable
final class TvChoice<T> {
  /// Creates the choice.
  const new({required this.value, required this.label, this.description, this.icon});

  /// What is chosen.
  final T value;

  /// The words.
  final String label;

  /// A second line.
  final String? description;

  /// An icon before the words.
  final IconData? icon;
}

/// Picks one of [options] (U.15a, dialog 41–43): the current one is in the
/// primary colour with a tick and has the focus when the dialog opens (a
/// long list scrolls to it); the focused one is a step lighter and ringed,
/// so the two never look alike (P3). OK picks and closes; "关闭" or Back
/// keep the value. Without [current] it is a menu.
Future<T?> showTvChoice<T>(
  BuildContext context, {
  required String title,
  required List<TvChoice<T>> options,
  T? current,
  String? subtitle,
}) => showTvDialog<T>(
  context,
  builder: (context) {
    final selected = options.indexWhere((option) => option.value == current);
    return TvDialog(
      title: title,
      subtitle: subtitle,
      width: 440,
      actions: [
        TvButton(key: const ValueKey('tv-choice-close'), label: i18n('close'), onTap: () => Navigator.pop(context)),
      ],
      child: Padding(
        padding: EdgeInsets.only(top: TvScale.of(context).px(12)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, option) in options.indexed)
                TvOptionRow(
                  key: ValueKey('tv-choice-$index'),
                  label: option.label,
                  description: option.description,
                  icon: option.icon,
                  current: index == selected,
                  autofocus: index == (selected < 0 ? 0 : selected),
                  onTap: () => Navigator.pop(context, option.value),
                ),
            ],
          ),
        ),
      ),
    );
  },
);

/// A row of a choice or a list in a dialog: 48 high, an optional icon, the
/// words (16) and a second line; [current] is the primary colour with a
/// tick; a [leading] widget replaces the icon (a check box). Focused rows
/// are a step lighter and ringed, never grown (c2). It scrolls itself into
/// view when focused.
class TvOptionRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.label,
    this.description,
    this.icon,
    this.leading,
    this.current = false,
    this.accent = false,
    this.autofocus = false,
    this.onTap,
    super.key,
  });

  /// The words.
  final String label;

  /// A second line.
  final String? description;

  /// The icon.
  final IconData? icon;

  /// Drawn instead of [icon].
  final Widget? leading;

  /// The current choice: primary colour and a tick.
  final bool current;

  /// Words and icon in the primary colour without a tick (an action such
  /// as "新建标签").
  final bool accent;

  /// Takes the focus when first built.
  final bool autofocus;

  /// OK.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final color = current || accent ? palette.accent : palette.text;
    final iconColor = current || accent ? palette.accent : palette.textSecondary;
    return Padding(
      padding: EdgeInsets.only(top: scale.px(2)),
      child: TvFocusable(
        autofocus: autofocus,
        zoom: false,
        onTap: onTap,
        onFocusChange: (focused) {
          if (!focused) return;
          final element = context;
          if (element.mounted) {
            Scrollable.ensureVisible(element, alignment: 0.5, duration: const Duration(milliseconds: 150));
          }
        },
        builder: (context, focused) => Container(
          constraints: BoxConstraints(minHeight: scale.pxText(48)),
          padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(6)),
          decoration: BoxDecoration(
            color: focused ? palette.highest : null,
            borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
          ),
          child: Row(
            children: [
              if (leading case final leading?) ...[
                leading,
                SizedBox(width: scale.px(14)),
              ] else if (icon != null) ...[
                Icon(icon, size: scale.pxText(22), color: iconColor),
                SizedBox(width: scale.px(14)),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: scale.font(
                        TvTextSize.body,
                        weight: current ? FontWeight.w600 : FontWeight.w400,
                        color: color,
                      ),
                    ),
                    if (description case final description? when description.isNotEmpty)
                      Text(description, style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.3)),
                  ],
                ),
              ),
              if (current)
                Icon(
                  AppIcons.selected,
                  key: const ValueKey('tv-option-current'),
                  size: scale.pxText(22),
                  color: palette.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reads one line of text with the remote.
///
/// Android shows a native input dialog (`pure_live/app` `inputText`): an
/// EditText opens the system keyboard (the TV's own IME, voice input where
/// the box has it) reliably, where Flutter's text input stays closed on some
/// TV boxes (pure_live_TV used a native platform view for the same reason,
/// flutter#154924). Elsewhere the TV input dialog ([TvInputDialog]). Tests
/// replace [prompt].
abstract final class TvTextInput {
  /// Asks for the text; null when cancelled.
  static Future<String?> Function(
    BuildContext context, {
    required String title,
    String hint,
    String text,
    String? subtitle,
    bool numeric,
    String? suffix,
    int? maxLength,
  })
  prompt = defaultPrompt;

  /// The prompt of the system ([prompt] starts as this).
  static Future<String?> defaultPrompt(
    BuildContext context, {
    required String title,
    String hint = '',
    String text = '',
    String? subtitle,
    bool numeric = false,
    String? suffix,
    int? maxLength,
  }) {
    if (Platform.isAndroid) return _native(context, title: title, hint: hint, text: text);
    return showTvInput(
      context,
      title: title,
      hint: hint,
      text: text,
      subtitle: subtitle,
      numeric: numeric,
      suffix: suffix,
      maxLength: maxLength,
    );
  }

  static const MethodChannel _channel = MethodChannel('pure_live/app');

  static Future<String?> _native(
    BuildContext context, {
    required String title,
    required String hint,
    required String text,
  }) async {
    try {
      return await _channel.invokeMethod<String>('inputText', {'title': title, 'hint': hint, 'text': text});
    } on MissingPluginException {
      return context.mounted ? await showTvInput(context, title: title, hint: hint, text: text) : null;
    } on PlatformException {
      return context.mounted ? await showTvInput(context, title: title, hint: hint, text: text) : null;
    }
  }
}

/// Shows the TV input dialog ([TvInputDialog]); null when cancelled.
Future<String?> showTvInput(
  BuildContext context, {
  required String title,
  String hint = '',
  String text = '',
  String? subtitle,
  bool numeric = false,
  String? suffix,
  int? maxLength,
}) => showTvDialog<String>(
  context,
  builder: (_) => TvInputDialog(
    title: title,
    hint: hint,
    text: text,
    subtitle: subtitle,
    numeric: numeric,
    suffix: suffix,
    maxLength: maxLength,
  ),
);

/// The input dialog of the TV (U.15a, dialog 61–63): the field has the focus
/// when it opens, so the keyboard comes up at once (pure_live_TV); under it
/// a line says how to type with a remote (c16); "取消 / 确定".
class TvInputDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({
    required this.title,
    this.hint = '',
    this.text = '',
    this.subtitle,
    this.numeric = false,
    this.suffix,
    this.maxLength,
    super.key,
  });

  /// The title.
  final String title;

  /// Shown while the field is empty.
  final String hint;

  /// The text to start with.
  final String text;

  /// The line under the title.
  final String? subtitle;

  /// Digits only (the remote's number keys type them).
  final bool numeric;

  /// A unit after the text ("条").
  final String? suffix;

  /// The longest text.
  final int? maxLength;

  @override
  State<TvInputDialog> createState() => _TvInputDialogState();
}

class _TvInputDialogState extends State<TvInputDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);
  final FocusNode _field = FocusNode(debugLabel: 'tv input field');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _field.addListener(() {
      if (mounted) setState(() => _focused = _field.hasFocus);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TvButton(key: const ValueKey('tv-input-cancel'), label: i18n('cancel'), onTap: () => Navigator.pop(context)),
        TvButton(
          key: const ValueKey('tv-input-confirm'),
          label: i18n('tv_ok'),
          kind: TvButtonKind.primary,
          onTap: _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: scale.px(18)),
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
              border: _focused
                  ? Border.all(
                      color: palette.focusRing,
                      width: scale.px(tvFocusRingWidth),
                      strokeAlign: BorderSide.strokeAlignOutside,
                    )
                  : null,
            ),
            child: TextField(
              key: const ValueKey('tv-text-input'),
              controller: _controller,
              focusNode: _field,
              autofocus: true,
              maxLength: widget.maxLength,
              keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
              inputFormatters: widget.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
              textInputAction: TextInputAction.done,
              cursorColor: palette.accent,
              style: scale.font(18, color: palette.text),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: scale.font(18, color: palette.textSecondary),
                counterText: '',
                filled: true,
                fillColor: palette.low,
                suffixText: widget.suffix,
                suffixStyle: scale.font(TvTextSize.small, color: palette.textSecondary),
                contentPadding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(14)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(height: scale.px(8)),
          Text(
            i18n(widget.numeric ? 'tv_input_hint_numeric' : 'tv_input_hint_text'),
            key: const ValueKey('tv-input-how'),
            style: scale.font(TvTextSize.small, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A text field for the remote (pure_live_TV `TvInputField`, the read-only
/// display half): it shows the text or the hint; OK opens [TvTextInput].
/// Like the other whole-width parts it is ringed, not grown, when focused.
class TvInputField extends StatelessWidget {
  /// Creates the field.
  const new({
    required this.text,
    required this.hint,
    required this.onSubmitted,
    this.title,
    this.focusNode,
    this.autofocus = false,
    this.icon = TvIcons.search,
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
      zoom: false,
      onTap: () async {
        final value = await TvTextInput.prompt(context, title: title ?? hint, hint: hint, text: text);
        if (value != null) onSubmitted(value.trim());
      },
      builder: (context, focused) => Container(
        constraints: BoxConstraints(minHeight: scale.pxText(52)),
        padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(8)),
        decoration: BoxDecoration(
          color: focused ? palette.highest : palette.low,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Row(
          children: [
            Icon(icon, color: palette.textSecondary, size: scale.pxText(24)),
            SizedBox(width: scale.px(12)),
            Expanded(
              child: Text(
                text.isEmpty ? hint : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: scale.font(18, color: text.isEmpty ? palette.textSecondary : palette.text),
              ),
            ),
            Text(i18n('tv_input_ok_hint'), style: scale.font(TvTextSize.small, color: palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
