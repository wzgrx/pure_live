import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/account/account_state.dart';
import 'package:pure_live/features/account/account_widgets.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// One input of a cookie editor.
final class CookieInput {
  /// Creates the input.
  const new({required this.controller, required this.fieldKey, this.label, this.hint, this.multiline = false});

  /// Its text.
  final TextEditingController controller;

  /// The text field's key.
  final Key fieldKey;

  /// The label above the text.
  final String? label;

  /// The hint inside the empty field.
  final String? hint;

  /// Several lines (the cookie itself).
  final bool multiline;
}

/// The decoration every account input uses (3.x
/// `accountCookieFieldDecoration`).
InputDecoration accountFieldDecoration(ThemeData theme, {String? label, String? hint, String? error}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    errorMaxLines: 3,
    hintStyle: TextStyle(color: theme.hintColor.withValues(alpha: 0.5)),
    contentPadding: const EdgeInsets.all(14),
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerLowest,
    border: border(theme.dividerColor.withValues(alpha: 0.1)),
    enabledBorder: border(theme.dividerColor.withValues(alpha: 0.05)),
    focusedBorder: border(theme.colorScheme.primary, 1.5),
  );
}

/// A cookie page (3.x `AccountCookieEditorPage`): instructions, the current
/// state, the cookie and any extra inputs, save and sign out.
///
/// The first of [inputs] is the cookie. The page tracks every input:
/// leaving with unsaved text asks first (3.x tracked the cookie only).
/// Saving an empty cookie signs out after asking; text without a
/// `name=value` field is refused before [onSave] runs.
class CookieEditorScaffold extends StatefulWidget {
  /// Creates the page.
  const new({
    required this.title,
    required this.name,
    required this.inputs,
    required this.tip,
    required this.status,
    required this.hasStored,
    required this.onSave,
    required this.onSignOut,
    this.banner,
    this.extra = const [],
    this.actions = const [],
    super.key,
  });

  /// The app bar title.
  final String title;

  /// The platform's name (the sign-out question).
  final String name;

  /// The inputs; the first is the cookie.
  final List<CookieInput> inputs;

  /// The instructions.
  final Widget tip;

  /// The current state of the stored login.
  final Widget status;

  /// Whether a cookie is stored (sign-out shows).
  final bool hasStored;

  /// Stores the inputs; returns false when nothing was stored (the page
  /// then keeps them marked unsaved). It may rewrite the inputs (the cookie
  /// as stored).
  final Future<bool> Function() onSave;

  /// Signs out of the platform; the page empties the inputs after it.
  final Future<void> Function() onSignOut;

  /// A notice above the instructions.
  final Widget? banner;

  /// Widgets below the buttons (Douyu's renewal and switch).
  final List<Widget> extra;

  /// App bar actions.
  final List<Widget> actions;

  @override
  State<CookieEditorScaffold> createState() => _CookieEditorScaffoldState();
}

class _CookieEditorScaffoldState extends State<CookieEditorScaffold> {
  late List<String> _saved;
  bool _dirty = false;
  bool _busy = false;
  bool _confirmingDiscard = false;
  String? _error;

  TextEditingController get _cookie => widget.inputs.first.controller;

  @override
  void initState() {
    super.initState();
    _saved = _texts();
    for (final input in widget.inputs) {
      input.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final input in widget.inputs) {
      input.controller.removeListener(_changed);
    }
    super.dispose();
  }

  List<String> _texts() => [for (final input in widget.inputs) cleanPastedCookie(input.controller.text)];

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
    if (_busy) return;
    final cookie = cleanPastedCookie(_cookie.text);
    if (cookie.isEmpty) {
      // Nothing left to store: that is signing out.
      if (widget.inputs.skip(1).every((input) => cleanPastedCookie(input.controller.text).isEmpty)) {
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
    if (!await confirmSignOut(context, widget.name) || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
      for (final input in widget.inputs) {
        input.controller.clear();
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
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmDiscard());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: widget.actions),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = constraints.maxWidth < 360 ? 12.0 : 16.0;
              return ListView(
                key: const ValueKey('account-cookie-scroll'),
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
                children: [
                  if (widget.banner case final banner?) ...[banner, const SizedBox(height: 12)],
                  widget.tip,
                  const SizedBox(height: 12),
                  widget.status,
                  const SizedBox(height: 20),
                  context.buildGroupTitle(i18n('cookie')),
                  context.buildModernCard([
                    Padding(
                      padding: EdgeInsets.all(gutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, input) in widget.inputs.indexed) ...[
                            if (index > 0) const SizedBox(height: 12),
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
                              scrollPadding: const EdgeInsets.only(bottom: 120),
                              decoration: accountFieldDecoration(
                                theme,
                                label: input.label,
                                hint: input.hint,
                                error: index == 0 ? _error : null,
                              ),
                            ),
                            if (index == 0)
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton.icon(
                                    key: const ValueKey('account-cookie-paste'),
                                    onPressed: _busy ? null : _paste,
                                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                                    label: Text(i18n('account_paste')),
                                  ),
                                  TextButton.icon(
                                    key: const ValueKey('account-cookie-clear-input'),
                                    onPressed: _busy ? null : _cookie.clear,
                                    icon: const Icon(Icons.backspace_outlined, size: 18),
                                    label: Text(i18n('account_clear_input')),
                                  ),
                                ],
                              ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('account-cookie-save'),
                            onPressed: _busy || !_dirty ? null : _save,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _busy
                                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(i18n('save')),
                          ),
                          if (widget.hasStored) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              key: const ValueKey('account-cookie-sign-out'),
                              onPressed: _busy ? null : _signOut,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                                foregroundColor: theme.colorScheme.error,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Remix.logout_box_r_line, size: 18),
                              label: Text(i18n('logout')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]),
                  for (final item in widget.extra) ...[const SizedBox(height: 20), item],
                  const SizedBox(height: 12),
                  Text(i18n('account_cookie_privacy'), style: context.textStyles.t12Muted),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
