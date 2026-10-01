import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/toolbox/toolbox_actions.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// Reads the clipboard text (tests replace it).
final Provider<Future<String?> Function()> toolboxClipboardProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  },
);

/// Open a link (3.x `lib/modules/toolbox`).
///
/// Routes: `RoutePath.kToolbox`.
///
/// One link box for both of 3.x's tools: open the room, or copy a stream
/// address after choosing quality and line. A platform link on the
/// clipboard fills the empty box when the page opens. The platforms whose
/// links are understood come from the platform list itself.
class ToolboxPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<ToolboxPage> createState() => _ToolboxPageState();
}

class _ToolboxPageState extends ConsumerState<ToolboxPage> {
  final _link = TextEditingController();
  late final ToolboxController _controller = ToolboxController(
    links: ref.read(toolboxLinksProvider),
    siteOf: ref.read(toolboxSiteProvider),
  );
  int _edits = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _link.addListener(_edited);
    final argument = widget.route.arguments;
    if (argument is String && argument.trim().isNotEmpty) {
      _link.text = argument;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_fillFromClipboard()));
    }
  }

  @override
  void dispose() {
    _link
      ..removeListener(_edited)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Editing the link stops the action that works on the old one (3.x).
  void _edited() {
    // The controller also reports cursor moves; only text changes count.
    if (_link.text == _lastText) return;
    _lastText = _link.text;
    _edits++;
    if (_controller.isBusy) _controller.cancel();
  }

  /// Fills the empty box with a platform link from the clipboard, unless
  /// the user typed meanwhile (3.x `autoCheckClipboard`); no requests.
  Future<void> _fillFromClipboard() async {
    if (!mounted || _link.text.isNotEmpty) return;
    final edits = _edits;
    final text = await ref.read(toolboxClipboardProvider)();
    if (!mounted || text == null || _edits != edits || _link.text.isNotEmpty) return;
    if (!ref.read(toolboxLinksProvider).containsSupportedLink(text)) return;
    _link.text = text.trim();
    AppNavigator.toast(i18n('toolbox_auto_fill'));
  }

  Future<void> _paste() async {
    final text = await ref.read(toolboxClipboardProvider)();
    if (!mounted || text == null || text.trim().isEmpty) return;
    _link.text = text.trim();
  }

  void _jump() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_controller.jump(_link.text));
  }

  void _directLink() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(
      _controller.directLink(
        _link.text,
        chooseQuality: (qualities) =>
            _choose(title: i18n('toolbox_select_quality'), items: qualities, label: (quality, _) => quality.quality),
        chooseLine: (urls) => _choose(
          title: i18n('toolbox_select_line'),
          items: urls,
          label: (_, index) => i18n('toolbox_line', args: {'index': '${index + 1}'}),
          subtitle: (url) => url,
        ),
      ),
    );
  }

  /// A choice dialog that closes itself when the action is cancelled.
  Future<T?> _choose<T>({
    required String title,
    required List<T> items,
    required String Function(T item, int index) label,
    String Function(T item)? subtitle,
  }) async {
    if (!mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('toolbox-choice-dialog'),
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, item) in items.indexed)
                ListTile(
                  key: ValueKey('toolbox-choice-$index'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(label(item, index)),
                  subtitle: subtitle == null
                      ? null
                      : Text(subtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(dialogContext).pop(item),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('toolbox-choice-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(i18n('cancel')),
          ),
        ],
      ),
    );
    void close() {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    }

    _controller.addListener(close);
    try {
      return await navigator.push(route);
    } finally {
      _controller.removeListener(close);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('toolbox_title'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  context.buildModernCard([
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              i18n('toolbox_link_title'),
                              style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(i18n('toolbox_link_subtitle'), style: context.textStyles.t12Muted),
                            const SizedBox(height: 12),
                            TextField(
                              key: const ValueKey('toolbox-link'),
                              controller: _link,
                              minLines: 3,
                              maxLines: 5,
                              style: context.textStyles.t13,
                              decoration: InputDecoration(
                                hintText: i18n('toolbox_input_hint'),
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: ListenableBuilder(
                                  listenable: _link,
                                  builder: (context, _) => _link.text.isEmpty
                                      ? IconButton(
                                          key: const ValueKey('toolbox-paste'),
                                          tooltip: i18n('toolbox_paste'),
                                          icon: const Icon(Icons.content_paste_rounded, size: 20),
                                          onPressed: _paste,
                                        )
                                      : IconButton(
                                          key: const ValueKey('toolbox-clear'),
                                          tooltip: i18n('clear'),
                                          icon: const Icon(Icons.cancel_outlined, size: 20),
                                          onPressed: _link.clear,
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ActionButtons(controller: _controller, onJump: _jump, onDirectLink: _directLink),
                            if (_controller.isBusy) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      i18n(
                                        _controller.action == ToolboxAction.jump
                                            ? 'toolbox_opening'
                                            : 'toolbox_reading_stream',
                                      ),
                                      style: context.textStyles.t12Muted,
                                    ),
                                  ),
                                  TextButton(
                                    key: const ValueKey('toolbox-cancel'),
                                    onPressed: _controller.cancel,
                                    child: Text(i18n('cancel')),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const _SupportedPlatforms(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const new({required this.controller, required this.onJump, required this.onDirectLink});

  final ToolboxController controller;
  final VoidCallback onJump;
  final VoidCallback onDirectLink;

  @override
  Widget build(BuildContext context) {
    Widget icon(ToolboxAction action, IconData data) => controller.action == action
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(data, size: 18);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final jump = FilledButton.icon(
      key: const ValueKey('toolbox-jump'),
      onPressed: controller.isBusy ? null : onJump,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: shape),
      icon: icon(ToolboxAction.jump, Icons.play_circle_outline_rounded),
      label: Text(i18n('toolbox_link_jump')),
    );
    final directLink = FilledButton.tonalIcon(
      key: const ValueKey('toolbox-direct-link'),
      onPressed: controller.isBusy ? null : onDirectLink,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: shape),
      icon: icon(ToolboxAction.directLink, Icons.link_rounded),
      label: Text(i18n('toolbox_get_direct_link')),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 320
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [jump, const SizedBox(height: 8), directLink],
            )
          : Row(
              children: [
                Expanded(child: jump),
                const SizedBox(width: 8),
                Expanded(child: directLink),
              ],
            ),
    );
  }
}

/// The platforms whose links are understood, with their logos (3.x showed
/// a fixed text that still listed retired Kick and missed most platforms).
class _SupportedPlatforms extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = linkPlatforms(ref.watch(sitesProvider));
    return context.buildModernCard([
      ExpansionTile(
        key: const ValueKey('toolbox-supported'),
        shape: const RoundedRectangleBorder(side: BorderSide(color: Colors.transparent)),
        leading: Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary),
        title: Text(i18n('toolbox_support_list'), style: context.textStyles.t15.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          i18n('toolbox_support_count', args: {'count': '${sites.length}'}),
          style: context.textStyles.t12Muted,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('toolbox_support_hint'), style: context.textStyles.t12Muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final site in sites)
                Chip(
                  key: ValueKey('toolbox-platform-${site.id}'),
                  avatar: PlatformLogo(site.id, size: 18),
                  label: Text(i18nOr('site_${site.id}', site.name)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    ]);
  }
}
