import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/toolbox/toolbox_actions.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

/// Link playback on the TV (A17.5 c12, pure_live_TV `LinkPlayPage`): a field
/// typed with the remote (OK opens the input), "播放" opens the room the link
/// points to in the TV room. The phone's toolbox resolves it (the same
/// parser, platforms and 12-second limit, share codes too); while it works
/// and when it fails the line under the field says so.
class TvLinkPane extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<TvLinkPane> createState() => _TvLinkPaneState();
}

class _TvLinkPaneState extends ConsumerState<TvLinkPane> {
  late final ToolboxController _toolbox = ToolboxController(
    links: ref.read(toolboxLinksProvider),
    siteOf: ref.read(toolboxSiteProvider),
    openRoom: ({required liveRoom}) async {
      await openTvRoom(liveRoom);
    },
    notify: (key) {
      if (mounted) setState(() => _error = i18n(key));
    },
  )..addListener(_changed);
  String _link = '';
  String? _error;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _toolbox
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final link = _link.trim();
    if (link.isEmpty || _toolbox.isBusy) return;
    setState(() => _error = null);
    await _toolbox.jump(link);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final busy = _toolbox.isBusy;
    return Padding(
      padding: EdgeInsets.fromLTRB(scale.px(48), scale.px(28), scale.px(48), scale.px(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: i18n('tv_menu_link')),
          SizedBox(height: scale.px(24)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: scale.pxText(900)),
            child: TvInputField(
              key: const ValueKey('tv-link-field'),
              text: _link,
              hint: i18n('tv_link_hint'),
              title: i18n('tv_menu_link'),
              icon: AppIcons.link,
              onSubmitted: (value) {
                setState(() {
                  _link = value.trim();
                  _error = null;
                });
                unawaited(_play());
              },
            ),
          ),
          SizedBox(height: scale.px(12)),
          Text(
            busy ? i18n('tv_link_parsing') : (_error ?? i18n('tv_link_desc')),
            key: const ValueKey('tv-link-status'),
            style: scale.font(TvTextSize.body, color: _error != null && !busy ? palette.danger : palette.textSecondary),
          ),
          SizedBox(height: scale.px(20)),
          Row(
            children: [
              TvButton(
                key: const ValueKey('tv-link-play'),
                label: i18n('tv_link_play'),
                kind: TvButtonKind.primary,
                onTap: _link.trim().isEmpty || busy ? null : () => unawaited(_play()),
              ),
              if (busy) ...[
                SizedBox(width: scale.px(12)),
                TvButton(key: const ValueKey('tv-link-cancel'), label: i18n('cancel'), onTap: _toolbox.cancel),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
