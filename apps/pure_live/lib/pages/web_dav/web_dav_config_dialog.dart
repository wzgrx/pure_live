import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/web_dav/web_dav_client.dart';

/// Checks a server before it is saved; throws [WebDavFailure].
typedef WebDavCheck = Future<void> Function(WebDavConfig config);

/// The message for [failure].
String webDavFailureText(Object failure) => switch (failure) {
  WebDavFailure(problem: WebDavProblem.auth) => i18n('webdav_error_auth'),
  WebDavFailure(problem: WebDavProblem.notFound) => i18n('webdav_error_not_found'),
  WebDavFailure(problem: WebDavProblem.network) => i18n('webdav_error_network'),
  WebDavFailure(:final status) => i18n('webdav_error_server', args: {'status': '${status ?? '-'}'}),
  _ => i18n('webdav_load_failed'),
};

/// Adds a server ([existing] null) or edits [existing]; returns the entered
/// server, or null when cancelled. [taken] are the names in use; [check]
/// tests the connection.
Future<WebDavConfig?> showWebDavConfigDialog(
  BuildContext context, {
  required Set<String> taken,
  required WebDavCheck check,
  WebDavConfig? existing,
}) => showDialog<WebDavConfig>(
  context: context,
  builder: (_) => _WebDavConfigDialog(existing: existing, taken: taken, check: check),
);

class _WebDavConfigDialog extends StatefulWidget {
  const new({required this.existing, required this.taken, required this.check});

  final WebDavConfig? existing;
  final Set<String> taken;
  final WebDavCheck check;

  @override
  State<_WebDavConfigDialog> createState() => _WebDavConfigDialogState();
}

enum _CheckState { idle, running, ok, failed }

class _WebDavConfigDialogState extends State<_WebDavConfigDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _user = TextEditingController(text: widget.existing?.username);
  late final _password = TextEditingController(text: widget.existing?.password);
  bool _showPassword = false;
  _CheckState _check = _CheckState.idle;
  String _checkText = '';

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  WebDavConfig get _entered => WebDavConfig(
    name: _name.text.trim(),
    address: _address.text.trim(),
    username: _user.text.trim(),
    password: _password.text,
  );

  void _setCheck(_CheckState state, String text) => setState(() {
    _check = state;
    _checkText = text;
  });

  Future<void> _test() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    _setCheck(_CheckState.running, i18n('webdav_checking'));
    try {
      await widget.check(_entered);
      if (mounted) _setCheck(_CheckState.ok, i18n('webdav_check_ok'));
    } on Object catch (error) {
      if (mounted) _setCheck(_CheckState.failed, webDavFailureText(error));
    }
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _entered);
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) => InputDecoration(
    labelText: label,
    errorMaxLines: 4,
    prefixIcon: Icon(icon, size: 20),
    suffixIcon: suffix,
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = _editing
        ? i18n('webdav_edit_config', args: {'name': widget.existing!.name})
        : i18n('webdav_add_new_config');
    final checkColor = switch (_check) {
      _CheckState.ok => Colors.green,
      _CheckState.failed => colors.error,
      _ => colors.onSurfaceVariant,
    };
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(title, style: context.textStyles.t18Bold, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('webdav-name'),
                controller: _name,
                enabled: !_editing,
                decoration: _decoration(i18n('webdav_config_name'), Remix.bookmark_line),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return i18n('webdav_config_name_empty');
                  if (!_editing && widget.taken.contains(name)) return i18n('webdav_config_name_exists');
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('webdav-address'),
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _decoration(
                  i18n('webdav_address'),
                  Remix.global_line,
                ).copyWith(hintText: 'https://dav.jianguoyun.com/dav/'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return i18n('webdav_address_empty');
                  return WebDavConfig.isValidAddress(value) ? null : i18n('webdav_address_invalid');
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('webdav-user'),
                controller: _user,
                autocorrect: false,
                decoration: _decoration(i18n('webdav_username'), Remix.user_3_line),
                validator: (value) => value == null || value.trim().isEmpty ? i18n('webdav_username_empty') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('webdav-password'),
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _decoration(
                  i18n('webdav_password'),
                  Remix.lock_password_line,
                  suffix: IconButton(
                    tooltip: i18n(_showPassword ? 'webdav_hide_password' : 'webdav_show_password'),
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty ? i18n('webdav_password_empty') : null,
              ),
              if (_check != _CheckState.idle)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    key: const ValueKey('webdav-check-result'),
                    children: [
                      if (_check == _CheckState.running)
                        const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(
                          _check == _CheckState.ok ? Icons.check_circle_outline : Icons.error_outline,
                          size: 18,
                          color: checkColor,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_checkText, style: context.textStyles.t13.copyWith(color: checkColor)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          key: const ValueKey('webdav-test'),
          onPressed: _check == _CheckState.running ? null : _test,
          child: Text(i18n('webdav_check')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('webdav_cancel'))),
        FilledButton(
          key: const ValueKey('webdav-save'),
          onPressed: _save,
          child: Text(i18n(_editing ? 'webdav_update' : 'webdav_add')),
        ),
      ],
    );
  }
}
