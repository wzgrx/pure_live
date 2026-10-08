import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/danmaku_page.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/playback_tiles.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The groups of a settings page built from the catalogue (or of one of its
/// sub-pages); the row [highlight] (an entry id, from search) is scrolled
/// into view and highlighted for a moment.
class SettingsSectionView extends StatefulWidget {
  /// Creates the view.
  const new({required this.section, this.subpage, this.highlight, super.key});

  /// The page.
  final SettingsSection section;

  /// The sub-page, or null for the page itself.
  final SettingsSubpage? subpage;

  /// The entry to highlight.
  final String? highlight;

  @override
  State<SettingsSectionView> createState() => _SettingsSectionViewState();
}

class _SettingsSectionViewState extends State<SettingsSectionView> {
  final GlobalKey _highlighted = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.highlight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _highlighted.currentContext;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(row, alignment: 0.3, duration: const Duration(milliseconds: 250)).ignore();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = SettingsEnv.current();
    final groups = groupsOf(settingsCatalog, widget.section, env, subpage: widget.subpage);
    const note = settingsGroupNotes;
    return SettingsPageBody(
      key: ValueKey('settings-section-view-${widget.subpage?.name ?? widget.section.name}'),
      start: SettingsPane.of(context),
      children: [
        if (settingsPageIntros[widget.subpage?.name ?? widget.section.name] case final intro?)
          SettingsNote(i18n(intro), padding: const EdgeInsets.fromLTRB(4, 4, 4, 0)),
        for (final (index, (group, entries)) in groups.indexed)
          SettingsGroup(
            first: index == 0,
            title: settingsUntitledGroup(group) ? null : i18n(group),
            note: switch (note[group]?.$1) {
              final key? => i18n(key),
              null => null,
            },
            footer: switch (note[group]?.$2) {
              final key? => i18n(key),
              null => null,
            },
            footerWidget: settingsGroupFooters[group]?.call(context),
            children: [
              for (final entry in entries)
                if (entry.id == widget.highlight)
                  _Flash(key: _highlighted, child: entry.build(context, entry))
                else
                  entry.build(context, entry),
            ],
          ),
      ],
    );
  }
}

/// A row highlighted for a moment (the target of a search result).
class _Flash extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeIn,
      child: child,
      builder: (context, alpha, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(color: primary.withValues(alpha: alpha)),
        child: child,
      ),
    );
  }
}

/// A settings page of the catalogue on its own page (or in the right pane
/// of the wide layout, [SettingsPane]).
class SettingsSectionPage extends StatelessWidget {
  /// Creates the page.
  const new({required this.section, this.highlight, this.onBack, super.key});

  /// The page.
  final SettingsSection section;

  /// The entry to highlight.
  final String? highlight;

  /// The back button of the one-column layout's first page (back to the
  /// overview); null uses the navigator's.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (section == SettingsSection.configPreview) return ConfigPreviewPage(onBack: onBack);
    // The room's mini window group (A08.6 c4); the catalogue's rows are
    // only for search.
    if (section == SettingsSection.pipDanmaku) return PipDanmakuPage(onBack: onBack);
    // The live room's danmaku settings (F02 c1); the catalogue's danmaku
    // rows are only for search.
    if (section == SettingsSection.danmaku) return DanmakuSettingsPage(onBack: onBack);
    final embedded = SettingsPane.of(context);
    return Scaffold(
      key: ValueKey('settings-page-${section.name}'),
      appBar: settingsAppBar(
        context,
        title: i18n(section.titleKey),
        embedded: embedded,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: SettingsSectionView(section: section, highlight: highlight),
    );
  }
}

/// A sub-page of the catalogue (the pager settings).
class SettingsSubpagePage extends StatelessWidget {
  /// Creates the page.
  const new({required this.subpage, this.highlight, super.key});

  /// The sub-page.
  final SettingsSubpage subpage;

  /// The entry to highlight.
  final String? highlight;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: settingsAppBar(context, title: i18n(subpage.titleKey), embedded: SettingsPane.of(context)),
    body: SettingsSectionView(section: subpage.section, subpage: subpage, highlight: highlight),
  );
}
