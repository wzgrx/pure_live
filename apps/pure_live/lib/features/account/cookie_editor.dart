import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/account_widgets.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// One input of a cookie page.
final class CookieInput {
  /// Creates the input.
  const new({required this.controller, required this.fieldKey, this.label, this.hint, this.multiline = false});

  /// Its text.
  final TextEditingController controller;

  /// The text field's key.
  final Key fieldKey;

  /// The label above the box.
  final String? label;

  /// The hint inside the empty box.
  final String? hint;

  /// Several lines (the cookie itself).
  final bool multiline;
}

/// The decoration every account input uses (3.x
/// `accountCookieFieldDecoration`): the lowest surface, a faint outline,
/// the primary colour when focused, red with an error.
InputDecoration accountFieldDecoration(ThemeData theme, {String? hint, String? error}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    hintText: hint,
    errorText: error,
    errorMaxLines: 3,
    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
    contentPadding: const EdgeInsets.all(14),
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest,
    border: border(theme.colorScheme.outlineVariant),
    enabledBorder: border(theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
    focusedBorder: border(theme.colorScheme.primary, 1.5),
    errorBorder: border(theme.colorScheme.error, 1.5),
    focusedErrorBorder: border(theme.colorScheme.error, 1.5),
  );
}

/// An account input with its label above the box (Douyu's renewal pair).
class AccountField extends StatelessWidget {
  /// Creates the field.
  const new({required this.input, this.error, super.key});

  /// What it edits.
  final CookieInput input;

  /// The error under the box.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = input.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(label, style: context.textStyles.t12.copyWith(color: theme.colorScheme.primary)),
          ),
        TextField(
          key: input.fieldKey,
          controller: input.controller,
          minLines: input.multiline ? 3 : 1,
          maxLines: input.multiline ? 7 : 1,
          style: context.textStyles.t14,
          keyboardType: input.multiline ? TextInputType.multiline : TextInputType.text,
          textInputAction: input.multiline ? TextInputAction.newline : TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          // 3.x: keep the box above the keyboard.
          scrollPadding: const EdgeInsets.only(bottom: 120),
          decoration: accountFieldDecoration(theme, hint: input.hint, error: error),
        ),
      ],
    );
  }
}

/// A cookie page (3.x `AccountCookieEditorPage`, docs/ui/compare/U.10b):
/// the platform's status card, the instructions with a link to its
/// website, the "Cookie" group (the box, "粘贴", "清空", "保存"), any
/// [extra] groups (Douyu's renewal), "退出登录" and the privacy note.
///
/// [extraInputs] are tracked with the cookie: leaving with unsaved text
/// asks first (3.x tracked the cookie only). Saving with nothing left is
/// signing out, after asking; text without a `name=value` field is refused
/// before [onSave] runs. Ctrl+S (Cmd+S) saves.
class CookieEditorScaffold extends StatefulWidget {
  /// Creates the page.
  const new({
    required this.platform,
    required this.cookie,
    required this.tip,
    required this.status,
    required this.hasStored,
    required this.onSave,
    required this.onSignOut,
    this.statusAction,
    this.extraInputs = const [],
    this.extra = const [],
    this.banner,
    this.verifiesOnSave = false,
    super.key,
  });

  /// The platform (title, logo, name).
  final AccountPlatform platform;

  /// The cookie box.
  final CookieInput cookie;

  /// More inputs saved with the cookie (shown by [extra]).
  final List<TextEditingController> extraInputs;

  /// The instructions.
  final Widget tip;

  /// What the stored login is worth.
  final AccountStatus status;

  /// A button on the status card ("重新核验").
  final Widget? statusAction;

  /// Whether a cookie is stored ("退出登录" shows).
  final bool hasStored;

  /// Saving asks the platform first ("正在核验并保存…").
  final bool verifiesOnSave;

  /// Stores the inputs; returns false when nothing was stored (the page
  /// then keeps them marked unsaved). It may rewrite the inputs (the cookie
  /// as stored).
  final Future<bool> Function() onSave;

  /// Signs out of the platform; the page empties the inputs after it.
  final Future<void> Function() onSignOut;

  /// A notice above the status card.
  final Widget? banner;

  /// Groups between the cookie and "退出登录" (Douyu's renewal).
  final List<Widget> extra;

  @override
  State<CookieEditorScaffold> createState() => _CookieEditorScaffoldState();
}

class _CookieEditorScaffoldState extends State<CookieEditorScaffold> {
  late List<String> _saved;
  bool _dirty = false;
  bool _busy = false;
  bool _confirmingDiscard = false;
  String? _error;

  TextEditingController get _cookie => widget.cookie.controller;

  List<TextEditingController> get _controllers => [_cookie, ...widget.extraInputs];

  @override
  void initState() {
    super.initState();
    _saved = _texts();
    for (final controller in _controllers) {
      controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_changed);
    }
    super.dispose();
  }

  List<String> _texts() => [for (final controller in _controllers) cleanPastedCookie(controller.text)];

  void _changed() {
    final texts = _texts();
    final dirty = [for (var i = 0; i < texts.length; i++) texts[i] != _saved[i]].any((changed) => changed);
    if (!mounted) return;
    if (dirty != _dirty || _error != null) {
      setState(() {
        _dirty = dirty;
        _error = null;
      });
    }
  }

  void _markSaved() {
    if (!mounted) return;
    setState(() {
      _saved = _texts();
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_busy || !_dirty) return;
    final cookie = cleanPastedCookie(_cookie.text);
    if (cookie.isEmpty) {
      // Nothing left to store: that is signing out (c7).
      if (widget.extraInputs.every((controller) => cleanPastedCookie(controller.text).isEmpty)) {
        if (widget.hasStored) await _signOut();
        return;
      }
    } else if (!looksLikeCookie(cookie)) {
      setState(() => _error = i18n('account_cookie_invalid'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (await widget.onSave()) _markSaved();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    if (!await confirmSignOut(context, widget.platform.name) || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
      for (final controller in _controllers) {
        controller.clear();
      }
      _markSaved();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      AppNavigator.toast(i18n('account_clipboard_empty'));
      return;
    }
    _cookie.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard) return;
    _confirmingDiscard = true;
    final discard = await confirmAccountAction(
      context,
      title: i18n('discard_cookie_changes'),
      message: i18n('discard_cookie_changes_detail'),
      action: i18n('discard'),
      cancel: i18n('keep_editing'),
    );
    _confirmingDiscard = false;
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = widget.platform;
    Widget chip(Key key, IconData icon, String label, VoidCallback onPressed) => OutlinedButton.icon(
      key: key,
      onPressed: _busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: context.textStyles.t14,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    final saving = widget.verifiesOnSave ? i18n('account_saving_verifying') : i18n('save');
    final children = <Widget>[
      if (widget.banner case final banner?) ...[banner, const SizedBox(height: 12)],
      AccountStatusCard(
        platformId: platform.id,
        name: platform.name,
        status: widget.status,
        action: widget.statusAction,
      ),
      const SizedBox(height: 12),
      widget.tip,
      const SizedBox(height: 20),
      context.buildGroupTitle(i18n('cookie')),
      context.buildModernCard([
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountField(input: widget.cookie, error: _error),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  chip(const ValueKey('account-cookie-paste'), AppIcons.pasteText, i18n('account_paste'), _paste),
                  chip(
                    const ValueKey('account-cookie-clear-input'),
                    AppIcons.eraseText,
                    i18n('account_clear_input'),
                    _cookie.clear,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('account-cookie-save'),
                onPressed: _busy || !_dirty ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: context.textStyles.t14.emphasis,
                ),
                icon: _busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
                      )
                    : const Icon(AppIcons.save, size: 18),
                label: Text(_busy ? saving : i18n('save')),
              ),
            ],
          ),
        ),
      ]),
      for (final item in widget.extra) ...[const SizedBox(height: 20), item],
      if (widget.hasStored) ...[
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            key: const ValueKey('account-cookie-sign-out'),
            onPressed: _busy ? null : _signOut,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
              shape: const StadiumBorder(),
              textStyle: context.textStyles.t14.emphasis,
            ),
            icon: const Icon(AppIcons.signOut, size: 18),
            label: Text(i18n('logout')),
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        child: Text(
          i18n('account_cookie_privacy'),
          style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
        ),
      ),
    ];
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => unawaited(_save()),
        },
        child: Scaffold(
          appBar: AppBar(centerTitle: true, title: Text(i18n('account_editor_title', args: {'name': platform.name}))),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = constraints.maxWidth < 360 ? 12.0 : 16.0;
                return ListView(
                  key: const ValueKey('account-cookie-scroll'),
                  padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
                  children: [
                    for (final child in children)
                      ReadableContent(
                        child: SizedBox(width: double.infinity, child: child),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
