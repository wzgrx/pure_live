import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/toolbox/toolbox_actions.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/links/supported_platforms.dart';

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

/// Open a link (3.x `lib/modules/toolbox`, docs/ui/compare/U.12a).
///
/// Routes: `RoutePath.kToolbox`.
///
/// One link box for both of 3.x's tools: open the room, or copy a stream
/// address after choosing quality and line. A platform link on the
/// clipboard fills the empty box when the page opens. The platforms whose
/// links are understood come from the platform list itself
/// ([SupportedPlatformsCard]). At most 720 wide on large windows (c9).
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
  /// the user typed meanwhile (3.x `autoCheckClipboard`); no requests. The
  /// app's usual message bar says so (c7; 3.x used a different snackbar).
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
      builder: (dialogContext) => ToolboxChoiceDialog<T>(title: title, items: items, label: label, subtitle: subtitle),
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
    final short = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: AppBar(
        centerTitle: centredPageTitle,
        toolbarHeight: short ? 48 : null,
        title: Text(i18n('toolbox_title')),
      ),
      body: ListView(
        key: const ValueKey('toolbox-scroll'),
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // c9: the cards of the settings pages, at most 720 wide.
          for (final child in [
            SettingsGroup(
              key: const ValueKey('toolbox-link-card'),
              first: true,
              title: i18n('toolbox_link_title'),
              children: [
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _LinkCard(
                    link: _link,
                    controller: _controller,
                    onPaste: _paste,
                    onJump: _jump,
                    onDirectLink: _directLink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SupportedPlatformsCard(),
          ])
            ReadableContent(
              child: SizedBox(width: double.infinity, child: child),
            ),
        ],
      ),
    );
  }
}

/// The card of the link (c2, c3, c5, c6): a line on what it does, the box
/// (paste when empty, clear when not), the two actions side by side, and
/// what is being done with "取消" while an action runs.
class _LinkCard extends StatelessWidget {
  const new({
    required this.link,
    required this.controller,
    required this.onPaste,
    required this.onJump,
    required this.onDirectLink,
  });

  final TextEditingController link;
  final ToolboxController controller;
  final VoidCallback onPaste;
  final VoidCallback onJump;
  final VoidCallback onDirectLink;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = context.textStyles.t13.copyWith(color: colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n('toolbox_link_subtitle'), style: muted.copyWith(height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('toolbox-link'),
            controller: link,
            minLines: 3,
            maxLines: 5,
            style: context.textStyles.t14,
            decoration: InputDecoration(
              hintText: i18n('toolbox_input_hint'),
              filled: true,
              fillColor: colors.surfaceContainerHighest,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
              suffixIcon: ListenableBuilder(
                listenable: link,
                builder: (context, _) => link.text.isEmpty
                    ? IconButton(
                        key: const ValueKey('toolbox-paste'),
                        tooltip: i18n('toolbox_paste'),
                        icon: const Icon(AppIcons.pasteText, size: 20),
                        onPressed: onPaste,
                      )
                    : IconButton(
                        key: const ValueKey('toolbox-clear'),
                        tooltip: i18n('clear'),
                        icon: const Icon(AppIcons.clearField, size: 20),
                        onPressed: link.clear,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionButtons(controller: controller, onJump: onJump, onDirectLink: onDirectLink),
          if (controller.isBusy) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    i18n(controller.action == ToolboxAction.jump ? 'toolbox_opening' : 'toolbox_reading_stream'),
                    key: const ValueKey('toolbox-busy'),
                    style: muted,
                  ),
                ),
                TextButton(
                  key: const ValueKey('toolbox-cancel'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: controller.cancel,
                  child: Text(i18n('cancel')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Choosing a quality or a line (c8; 3.x had a 24 px title and centred
/// options): a 20 px title, the options at the start, each at least 56
/// high, a line's address on one line; "取消" at the bottom.
class ToolboxChoiceDialog<T> extends StatelessWidget {
  /// Offers [items] under [title].
  const new({required this.title, required this.items, required this.label, this.subtitle, super.key});

  /// "选择清晰度" or "选择线路".
  final String title;

  /// The choices.
  final List<T> items;

  /// The name of a choice.
  final String Function(T item, int index) label;

  /// A line under the name (a line's address).
  final String Function(T item)? subtitle;

  @override
  Widget build(BuildContext context) => AppDialog(
    key: const ValueKey('toolbox-choice-dialog'),
    title: title,
    wide: true,
    contentPadding: EdgeInsets.zero,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, item) in items.indexed)
          DialogOptionRow(
            key: ValueKey('toolbox-choice-$index'),
            label: label(item, index),
            description: subtitle?.call(item),
            descriptionMaxLines: 1,
            selected: false,
            onTap: () => Navigator.of(context).pop(item),
          ),
      ],
    ),
    actions: const [DialogCancelButton(key: ValueKey('toolbox-choice-cancel'))],
  );
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
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
    );
    final jump = FilledButton.icon(
      key: const ValueKey('toolbox-jump'),
      onPressed: controller.isBusy ? null : onJump,
      style: style,
      icon: icon(ToolboxAction.jump, AppIcons.linkJump),
      label: Text(i18n('toolbox_link_jump')),
    );
    final directLink = FilledButton.tonalIcon(
      key: const ValueKey('toolbox-direct-link'),
      onPressed: controller.isBusy ? null : onDirectLink,
      style: style,
      icon: icon(ToolboxAction.directLink, AppIcons.streamLink),
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
