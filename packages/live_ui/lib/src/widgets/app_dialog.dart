import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/dialog_buttons_theme.dart';
import 'package:live_ui/src/widgets/dialog_keys.dart';

// The one dialog of the app (docs/A-界面设计/A02-组件/A02.2-弹窗组件 c5–c9, c14; UI_PLAN §7):
// confirm, message, input and options are the same frame with different
// content.

/// The widest an ordinary dialog gets (U.1d c7: the screen less 16 on each
/// side, at most this).
const double appDialogMaxWidth = 400;

/// The widest a dialog of long content gets ([AppDialog.wide]).
const double appDialogWideMaxWidth = 560;

/// The space a dialog keeps from every edge of the screen.
const double appDialogMargin = 16;

/// The dialog (U.1d): `surfaceContainerHigh`, 24-point corners, in the
/// middle of the screen, as wide as the screen less 32 and at most
/// [appDialogMaxWidth] ([appDialogWideMaxWidth] when [wide]) whatever its
/// content, at most the screen's height less 32.
///
/// From the top: the [title] (20, semi-bold), the [message] (14, the
/// variant ink) and [content]; then [actions] at the bottom right, "取消"
/// (a text button) before the main button ([DialogActionButton]: filled,
/// its words say what it does, red when it destroys something), and an
/// optional [leading] at the bottom left ("重新检测", a tick box). Only the
/// middle scrolls: the title and the buttons stay put on a short landscape
/// screen (U.1d Q11). Buttons that do not fit side by side stack, the main
/// one on top (only with a very large font, U.1d D4).
///
/// Enter presses [onEnter] (the main button) on computers; Esc, Back and a
/// tap outside close the dialog unless [busy] (saving: nothing closes it).
class AppDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({
    this.title,
    this.icon,
    this.message,
    this.content,
    this.actions = const [],
    this.leading,
    this.wide = false,
    this.onEnter,
    this.busy = false,
    this.autofocus = true,
    this.scrollable = true,
    this.contentPadding,
    this.selectable = false,
    super.key,
  });

  /// The title; none for a short question.
  final String? title;

  /// An icon before the title, in the primary colour (the IPTV dialogs).
  final IconData? icon;

  /// The text under the title.
  final String? message;

  /// What comes under the message: a field, options, a list.
  final Widget? content;

  /// The buttons at the bottom right, "取消" first.
  final List<Widget> actions;

  /// A button or tick box at the bottom left.
  final Widget? leading;

  /// Long content: up to [appDialogWideMaxWidth] wide.
  final bool wide;

  /// The main button's action for Enter.
  final VoidCallback? onEnter;

  /// Saving: Back, Esc and a tap outside do nothing.
  final bool busy;

  /// Whether the dialog takes the keyboard focus when it opens (off when a
  /// field or a button inside takes it).
  final bool autofocus;

  /// Whether the middle scrolls as a whole (off when [content] scrolls by
  /// itself: a long list, a file browser).
  final bool scrollable;

  /// The padding of the middle; by default 24 on the sides.
  final EdgeInsetsGeometry? contentPadding;

  /// Whether the [message] can be selected and copied (an error's details).
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = this.title;
    final message = this.message;
    final content = this.content;
    final hasBody = message != null || content != null;
    final top = title == null ? 24.0 : 12.0;
    final messageStyle = theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: contentPadding == null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 24),
            child: selectable
                ? SelectableText(message, key: const ValueKey('app-dialog-message'), style: messageStyle)
                : Text(message, key: const ValueKey('app-dialog-message'), style: messageStyle),
          ),
        if (message != null && content != null) const SizedBox(height: 12),
        if (content != null && scrollable) content,
        if (content != null && !scrollable) Flexible(child: content),
      ],
    );
    final padding = (contentPadding ?? const EdgeInsets.symmetric(horizontal: 24)).add(EdgeInsets.only(top: top));
    final middle = scrollable
        ? SingleChildScrollView(
            key: const ValueKey('app-dialog-body'),
            physics: const ClampingScrollPhysics(),
            padding: padding,
            child: body,
          )
        : Padding(padding: padding, child: body);
    final buttons = actions.isEmpty && leading == null
        ? const SizedBox(height: 24)
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                if (leading case final leading?) ...[leading, const SizedBox(width: 8)],
                Expanded(
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowDirection: VerticalDirection.up,
                    children: actions,
                  ),
                ),
              ],
            ),
          );
    final maxWidth = wide ? appDialogWideMaxWidth : appDialogMaxWidth;
    return DialogButtonsTheme(
      child: DialogKeys(
        autofocus: autofocus,
        onEnter: busy ? null : onEnter,
        onEscape: busy ? () {} : null,
        child: PopScope(
          canPop: !busy,
          child: Dialog(
            insetPadding: const EdgeInsets.all(appDialogMargin),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (icon case final icon?)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, right: 12),
                              child: Icon(icon, size: 24, color: scheme.primary),
                            ),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                key: const ValueKey('app-dialog-title'),
                                style: theme.textTheme.titleLarge?.emphasis.copyWith(color: scheme.onSurface),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hasBody) Flexible(child: middle),
                  buttons,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The main button of a dialog (U.1d c6): filled, with the words of what it
/// does ("退出登录", "保存", "删除"); red when it destroys something
/// ([danger]); a spinner and no taps while it runs ([busy]). It is a
/// [FilledButton], so the dialog's button theme applies.
class DialogActionButton extends FilledButton {
  /// Creates the button.
  new({required String label, required VoidCallback? onPressed, this.danger = false, this.busy = false, super.key})
    : super(
        onPressed: busy ? null : onPressed,
        child: _ActionLabel(label: label, busy: busy),
      );

  /// Removing, clearing or resetting something.
  final bool danger;

  /// The action runs.
  final bool busy;

  @override
  ButtonStyle defaultStyleOf(BuildContext context) {
    final style = super.defaultStyleOf(context);
    if (!danger) return style;
    final scheme = Theme.of(context).colorScheme;
    bool off(Set<WidgetState> states) => states.contains(WidgetState.disabled);
    return style.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => off(states) ? scheme.onSurface.withValues(alpha: 0.12) : scheme.error,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => off(states) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onError,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => off(states) ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onError,
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed) || states.contains(WidgetState.focused)) {
          return scheme.onError.withValues(alpha: 0.1);
        }
        return states.contains(WidgetState.hovered) ? scheme.onError.withValues(alpha: 0.08) : null;
      }),
    );
  }
}

/// The words of a [DialogActionButton], after a spinner while it runs (in
/// the button's ink).
class _ActionLabel extends StatelessWidget {
  const new({required this.label, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (busy) ...[
        SizedBox.square(
          key: const ValueKey('dialog-action-busy'),
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: IconTheme.of(context).color),
        ),
        const SizedBox(width: 8),
      ],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// "取消" of a dialog: a text button that closes it with nothing (or runs
/// [onPressed]).
class DialogCancelButton extends StatelessWidget {
  /// Creates the button.
  const new({this.label, this.onPressed, this.autofocus = false, this.enabled = true, super.key});

  /// Its words; "取消" by default.
  final String? label;

  /// What it does; null closes the dialog.
  final VoidCallback? onPressed;

  /// Whether it takes taps (not while the dialog saves).
  final bool enabled;

  /// Takes the focus when the dialog opens (a destructive question, U.1d:
  /// the focus starts on "取消").
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextButton(
    autofocus: autofocus,
    onPressed: enabled ? onPressed ?? () => Navigator.of(context).pop() : null,
    child: Text(label ?? LiveUiScope.of(context).strings.cancel),
  );
}

/// One option of a dialog (U.1d c3, c9): 48 high, 24 from the sides, the
/// current one in the primary colour, semi-bold, with a tick at the end;
/// an optional picture before it and a line of [description] under it.
class DialogOptionRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
    this.leading,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    this.descriptionMaxLines,
    this.trailing,
    super.key,
  });

  /// The option's name.
  final String label;

  /// Its explanation.
  final String? description;

  /// A picture before the name (a platform's logo).
  final Widget? leading;

  /// Whether it is the current option.
  final bool selected;

  /// Picks it.
  final VoidCallback? onTap;

  /// Whether it takes taps.
  final bool enabled;

  /// Around the row's content (24 from the dialog's edges).
  final EdgeInsetsGeometry padding;

  /// At most this many lines of [description] (an address: one).
  final int? descriptionMaxLines;

  /// In place of the tick at the end (a spinner while the option works).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    final ink = !enabled ? colors.onSurface.withValues(alpha: 0.38) : (selected ? colors.primary : colors.onSurface);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                if (leading case final leading?) ...[leading, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: base.copyWith(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: ink,
                        ),
                      ),
                      if (description case final description?)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          // UI_PLAN §7: nothing under 14 in a popup.
                          child: Text(
                            description,
                            maxLines: descriptionMaxLines,
                            overflow: descriptionMaxLines == null ? null : TextOverflow.ellipsis,
                            style: base.copyWith(fontSize: 14, height: 1.4, color: colors.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: trailing ?? (selected ? Icon(AppIcons.selected, size: 22, color: colors.primary) : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The look of a field in a dialog (U.1d c8): an outline with 12-point
/// corners on the dialog's colour, 2 wide in the primary colour when
/// focused and in the error colour with [error]; the [label] on the line;
/// [helper] or [error] and the counter under it.
InputDecoration dialogFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  String? error,
  String? suffix,
  Widget? suffixIcon,
}) {
  final scheme = Theme.of(context).colorScheme;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    filled: false,
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    errorText: error,
    errorMaxLines: 3,
    suffixText: suffix,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(scheme.outline, 1),
    enabledBorder: border(scheme.outline, 1),
    focusedBorder: border(scheme.primary, 2),
    errorBorder: border(scheme.error, 2),
    focusedErrorBorder: border(scheme.error, 2),
  );
}

/// Opens [builder]'s dialog (usually an [AppDialog]) in the middle of the
/// screen over a 54 % scrim; a tap outside closes it unless not
/// [dismissible].
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  useRootNavigator: useRootNavigator,
  builder: builder,
);

/// A question (U.1d 确认, 危险确认): [message] under an optional [title],
/// "取消" and the button that says what happens ([confirmLabel]); red and
/// with the focus starting on "取消" when it destroys something
/// ([danger]). Enter answers yes otherwise. True when confirmed.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String message,
  required String confirmLabel,
  String? title,
  bool danger = false,
  String? cancelLabel,
  Widget? content,
  Key? key,
  Key? confirmKey,
  Key? cancelKey,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        key: key,
        title: title,
        message: message,
        content: content,
        autofocus: !danger,
        onEnter: danger ? null : () => Navigator.of(dialogContext).pop(true),
        actions: [
          DialogCancelButton(
            key: cancelKey,
            label: cancelLabel,
            autofocus: danger,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          DialogActionButton(
            key: confirmKey,
            label: confirmLabel,
            danger: danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    ) ??
    false;

/// A message (U.1d 消息, c14): one "知道了" ([buttonLabel]); with
/// [actionLabel] a main button after it ("去设置"). True when the main
/// button was pressed.
Future<bool> showAppMessageDialog({
  required BuildContext context,
  required String message,
  String? title,
  String? buttonLabel,
  String? actionLabel,
  Widget? content,
  bool wide = false,
  Key? key,
  Key? actionKey,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final close = buttonLabel ?? LiveUiScope.of(dialogContext).strings.gotIt;
        return AppDialog(
          key: key,
          title: title,
          message: message,
          content: content,
          wide: wide,
          onEnter: () => Navigator.of(dialogContext).pop(actionLabel != null),
          actions: [
            if (actionLabel == null)
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(close))
            else ...[
              DialogCancelButton(label: close, onPressed: () => Navigator.of(dialogContext).pop(false)),
              DialogActionButton(
                key: actionKey,
                label: actionLabel,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ],
        );
      },
    ) ??
    false;

/// One option of [showAppOptionDialog].
@immutable
final class AppDialogOption<T> {
  /// Creates the option.
  const new({
    required this.value,
    required this.label,
    this.description,
    this.descriptionMaxLines,
    this.leading,
    this.key,
  });

  /// What picking it returns.
  final T value;

  /// Its name.
  final String label;

  /// A line under the name.
  final String? description;

  /// At most this many lines of [description].
  final int? descriptionMaxLines;

  /// A picture before the name.
  final Widget? leading;

  /// The row's key.
  final Key? key;
}

/// A choice (U.1d 选项, c9): the [options] as [DialogOptionRow]s, the
/// current one ([selected]) in the primary colour with a tick; a tap picks
/// one and closes the dialog with it. The title and "取消" stay put while
/// a long list scrolls. Without [showCancel] there is no button (3.x's
/// theme and language choices); [leading] is a button at the bottom left
/// that keeps the dialog open ("重新检测"). Null when cancelled.
Future<T?> showAppOptionDialog<T>({
  required BuildContext context,
  required List<AppDialogOption<T>> options,
  String? title,
  IconData? icon,
  T? selected,
  String? message,
  bool showCancel = true,
  Widget? leading,
  Key? key,
}) => showAppDialog<T>(
  context: context,
  builder: (dialogContext) => AppDialog(
    key: key,
    title: title,
    icon: icon,
    message: message,
    contentPadding: EdgeInsets.zero,
    leading: leading,
    actions: [if (showCancel) DialogCancelButton(onPressed: () => Navigator.of(dialogContext).pop())],
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          DialogOptionRow(
            key: option.key,
            label: option.label,
            description: option.description,
            descriptionMaxLines: option.descriptionMaxLines,
            leading: option.leading,
            selected: option.value == selected,
            onTap: () => Navigator.of(dialogContext).pop(option.value),
          ),
      ],
    ),
  ),
);

/// Checks a field's text: the reason it is not acceptable, or null.
typedef DialogTextCheck = String? Function(String text);

/// Saves a field's text (it may take a while: the dialog shows a spinner
/// and cannot be closed): the reason it failed, or null when done.
typedef DialogTextSave = Future<String?> Function(String text);

/// A text (U.1d 输入, c8): one field, a single line by default
/// ([maxLines]), the [label] on its outline, [helper] and the counter of
/// [maxLength] under it; [check] puts its reason under the field in red
/// instead of closing; [save] runs while the main button ([confirmLabel])
/// spins and nothing closes the dialog. The field has the focus and Enter
/// saves. Returns the text (trimmed unless not [trim]), or null when
/// cancelled.
Future<String?> showAppInputDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String initial = '',
  String? message,
  String? label,
  String? hint,
  String? helper,
  int? maxLength,
  int maxLines = 1,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  bool obscure = false,
  bool trim = true,
  bool allowEmpty = false,
  bool danger = false,
  String? suffix,
  DialogTextCheck? check,
  DialogTextSave? save,
  Widget? extra,
  Key? key,
  Key? fieldKey,
  Key? confirmKey,
}) => showAppDialog<String>(
  context: context,
  builder: (_) => _InputDialog(
    key: key,
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
    message: message,
    label: label,
    hint: hint,
    helper: helper,
    maxLength: maxLength,
    maxLines: maxLines,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    obscure: obscure,
    trim: trim,
    allowEmpty: allowEmpty,
    danger: danger,
    suffix: suffix,
    check: check,
    save: save,
    extra: extra,
    fieldKey: fieldKey,
    confirmKey: confirmKey,
  ),
);

class _InputDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.message,
    required this.label,
    required this.hint,
    required this.helper,
    required this.maxLength,
    required this.maxLines,
    required this.keyboardType,
    required this.inputFormatters,
    required this.obscure,
    required this.trim,
    required this.allowEmpty,
    required this.danger,
    required this.suffix,
    required this.check,
    required this.save,
    required this.extra,
    required this.fieldKey,
    required this.confirmKey,
    super.key,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? message;
  final String? label;
  final String? hint;
  final String? helper;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final bool trim;
  final bool allowEmpty;
  final bool danger;
  final String? suffix;
  final DialogTextCheck? check;
  final DialogTextSave? save;
  final Widget? extra;
  final Key? fieldKey;
  final Key? confirmKey;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _input = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_edited);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  // The error goes with the next edit; the main button follows whether
  // there is anything to save.
  void _edited() => setState(() => _error = null);

  String get _text => widget.trim ? _input.text.trim() : _input.text;

  bool get _canSave => !_busy && (widget.allowEmpty || _text.isNotEmpty);

  Future<void> _submit() async {
    if (!_canSave) return;
    final text = _text;
    final problem = widget.check?.call(text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final save = widget.save;
    if (save != null) {
      setState(() => _busy = true);
      final failed = await save(text);
      if (!mounted) return;
      if (failed != null) {
        setState(() {
          _busy = false;
          _error = failed;
        });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.title,
    message: widget.message,
    busy: _busy,
    autofocus: false,
    actions: [
      DialogCancelButton(enabled: !_busy),
      DialogActionButton(
        key: widget.confirmKey,
        label: widget.confirmLabel,
        danger: widget.danger,
        busy: _busy,
        onPressed: _canSave ? () => unawaited(_submit()) : null,
      ),
    ],
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Room above the label on the outline.
        const SizedBox(height: 6),
        TextField(
          key: widget.fieldKey,
          controller: _input,
          autofocus: true,
          enabled: !_busy,
          obscureText: widget.obscure,
          maxLines: widget.obscure ? 1 : math.max(1, widget.maxLines),
          minLines: 1,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
          onSubmitted: widget.maxLines > 1 ? null : (_) => unawaited(_submit()),
          decoration: dialogFieldDecoration(
            context,
            label: widget.label,
            hint: widget.hint,
            helper: widget.helper,
            error: _error,
            suffix: widget.suffix,
          ),
        ),
        ?widget.extra,
      ],
    ),
  );
}
