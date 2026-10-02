import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The local danmaku style (U.2k-c, 3.x `local_danmaku_style_editor.dart`):
/// the same panel everywhere (c4): under the picture in portrait, on the
/// right in landscape and on wide screens, as the local interaction panel's
/// second page (with [onBack]) and over the settings page. The preview stays
/// on top while the settings scroll; settings that do not apply grey out and
/// say what turns them on (c5); "恢复默认" applies "清爽" (c5).
class LocalDanmakuStylePanel extends ConsumerWidget {
  /// Creates the panel.
  const new({required this.onClose, this.onBack, this.dragToClose = false, super.key});

  /// Closes the panel.
  final VoidCallback onClose;

  /// Back to the local interaction panel (#17); null when opened by itself.
  final VoidCallback? onBack;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interaction = ref.watch(localInteractionProvider);
    return RoomSidePanel(
      key: const ValueKey('local-style-panel'),
      title: i18n('local_danmaku_style'),
      onClose: onClose,
      dragToClose: dragToClose,
      leading: onBack == null
          ? null
          : IconButton(
              key: const ValueKey('local-style-back'),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: const Icon(AppIcons.back),
            ),
      actions: [
        TextButton(
          key: const ValueKey('local-style-reset'),
          onPressed: interaction.resetStyle,
          child: Text(i18n('restore_default')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LocalDanmakuPreview(interaction: interaction),
          ),
          Expanded(child: LocalDanmakuStyleControls(interaction: interaction)),
        ],
      ),
    );
  }
}

/// Opens [LocalDanmakuStylePanel] where there is no picture (the settings
/// page): the app's panel for such pages (docs/ui/compare/U.1d c10, UI_PLAN
/// §7), from the bottom on a phone, on the right on a wide screen.
Future<void> showLocalDanmakuStyleSheet(BuildContext context) =>
    showRoomPanelSheet(context, heightFactor: 0.86, builder: (_, close) => LocalDanmakuStylePanel(onClose: close));

/// The live preview (3.x `_DanmakuPreview`): a dark stage with
/// "Pure Live 本地弹幕预览" in the current style, scrolling at the chosen speed
/// or held at the top or bottom. The scrolling runs only while it is shown.
class LocalDanmakuPreview extends StatelessWidget {
  /// Creates the preview.
  const new({required this.interaction, this.height = 82, super.key});

  /// The style.
  final LocalInteraction interaction;

  /// Its height.
  final double height;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interaction,
    builder: (context, _) {
      final style = interaction.currentStyle;
      final text = i18n('local_danmaku_preview_text');
      final textStyle = localDanmakuTextStyle(style, interaction.color);
      return RepaintBoundary(
        child: Container(
          key: const ValueKey('local-style-preview'),
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: OnVideoColors.stage,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: Icon(AppIcons.localPreviewStage, size: 38, color: OnVideoColors.stageMark)),
              Positioned(
                left: 9,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: OnVideoColors.stageBadge, borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.localPreviewLive, size: 12, color: OnVideoColors.secondary),
                        const SizedBox(width: 4),
                        Text(
                          i18n('local_danmaku_live_preview'),
                          style: Theme.of(context).textTheme.labelSmall?.regular
                              .copyWith(fontSize: 11, color: OnVideoColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (style.placement == LiveMessagePlacement.scroll)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _ScrollingText(text: text, style: textStyle, speed: style.baseSpeed),
                )
              else
                Align(
                  alignment: style.placement == LiveMessagePlacement.top ? Alignment.topCenter : Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, style.placement == LiveMessagePlacement.top ? 26 : 0, 10, 8),
                    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// [style] as text in [color] (the preview and the fullscreen field): the
/// outline as four offset shadows and the glow as a blurred one (3.x).
TextStyle localDanmakuTextStyle(LiveMessageStyle style, int color) => TextStyle(
  color: Color(color).withValues(alpha: style.opacity),
  fontSize: style.fontSize,
  fontWeight: FontWeight.values[(style.fontWeight ~/ 100 - 1).clamp(0, 8)],
  fontFamily: style.fontFamily,
  fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
  letterSpacing: style.letterSpacing,
  height: 1.2,
  shadows: [
    if (style.showShadow)
      Shadow(
        color: Color(style.shadowColor).withValues(alpha: style.opacity),
        blurRadius: style.shadowBlur,
        offset: Offset(style.shadowOffset, style.shadowOffset),
      ),
    if (style.showStroke)
      for (final offset in [
        Offset(style.strokeWidth, 0),
        Offset(-style.strokeWidth, 0),
        Offset(0, style.strokeWidth),
        Offset(0, -style.strokeWidth),
      ])
        Shadow(color: Color(style.strokeColor), offset: offset),
  ],
);

/// The preview's text crossing the stage at [speed] pixels per second.
class _ScrollingText extends StatefulWidget {
  const new({required this.text, required this.style, required this.speed});

  final String text;
  final TextStyle style;
  final double speed;

  @override
  State<_ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<_ScrollingText> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(vsync: this);
  double _travel = 0;

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _run(double travel) {
    if ((travel - _travel).abs() < 1 && _animation.isAnimating) return;
    _travel = travel;
    final progress = _animation.value;
    final millis = (travel / widget.speed.clamp(60, 260) * 1000).round().clamp(900, 9000);
    _animation.duration = Duration(milliseconds: millis);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0.3;
      return;
    }
    _animation
      ..repeat()
      ..value = progress;
  }

  @override
  void didUpdateWidget(_ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) _travel = 0;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      final travel = constraints.maxWidth + width + 20;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(travel);
      });
      return ClipRect(
        child: AnimatedBuilder(
          animation: _animation,
          child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style),
          builder: (context, child) => Transform.translate(
            offset: Offset(constraints.maxWidth + 10 - _animation.value * travel, 0),
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ),
      );
    },
  );
}

/// Every setting of 3.x's style editor in its order (#18-26): templates,
/// place, font, colour, size, speed, opacity, spacing, effects, outline,
/// shadow, how long a fixed one stays, then the line saying where it applies.
class LocalDanmakuStyleControls extends StatelessWidget {
  /// Creates the controls.
  const new({required this.interaction, super.key});

  /// The style.
  final LocalInteraction interaction;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interaction,
    builder: (context, _) {
      final local = interaction;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      void custom<T extends Object>(Setting<T> setting, T value) => local.setStyle(setting, value);
      final stroke = local.showStroke;
      final shadow = local.showShadow;
      final fixed = local.placement != 'scroll';
      return ListView(
        key: const ValueKey('local-style-controls'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PanelGroupTitle(i18n('local_danmaku_presets')),
          _Chips(
            groupKey: 'local-style-presets',
            children: [
              for (final preset in LocalCatalog.presets)
                _choice(
                  context,
                  key: 'local-style-preset-${preset.id}',
                  label: preset == LocalCatalog.defaultPreset
                      ? i18n('local_danmaku_preset_default', args: {'name': i18n('local_danmaku_preset_${preset.id}')})
                      : i18n('local_danmaku_preset_${preset.id}'),
                  selected: local.preset == preset.id,
                  avatar: _Dot(color: Color(preset.color)),
                  onSelected: () => local.applyPreset(preset),
                ),
            ],
          ),
          PanelGroupTitle(i18n('local_danmaku_placement')),
          _Chips(
            groupKey: 'local-style-placements',
            children: [
              for (final id in LocalCatalog.placementIds)
                _choice(
                  context,
                  key: 'local-style-placement-$id',
                  label: i18n('local_danmaku_placement_$id'),
                  selected: local.placement == id,
                  avatar: Icon(switch (id) {
                    'top' => AppIcons.localPlaceTop,
                    'bottom' => AppIcons.localPlaceBottom,
                    _ => AppIcons.localPlaceScroll,
                  }, size: 17),
                  onSelected: () => custom(Settings.localDanmakuPlacement, id),
                ),
            ],
          ),
          PanelGroupTitle(i18n('local_danmaku_typography')),
          _Chips(
            groupKey: 'local-style-fonts',
            children: [
              for (final id in LocalCatalog.fontFamilyIds)
                _choice(
                  context,
                  key: 'local-style-font-$id',
                  label: i18n('local_danmaku_font_$id'),
                  labelStyle: TextStyle(fontFamily: LocalCatalog.fontFamilyOf(id)),
                  selected: local.fontFamily == id,
                  onSelected: () => custom(Settings.localDanmakuFontFamily, id),
                ),
            ],
          ),
          _Label(i18n('local_danmaku_color')),
          _Palette(
            paletteKey: 'local-style-colors',
            values: LocalCatalog.danmakuColors,
            selected: local.color,
            size: 32,
            onSelected: (value) => custom(Settings.localDanmakuColor, value),
          ),
          const SizedBox(height: 10),
          PanelCard(
            children: [
              _Slider(
                id: 'size',
                title: i18n('local_danmaku_size'),
                value: local.fontSize,
                min: 14,
                max: 32,
                divisions: 18,
                display: '${local.fontSize.toStringAsFixed(0)} px',
                onChanged: (value) => custom(Settings.localDanmakuFontSize, value),
              ),
              _Slider(
                id: 'speed',
                title: i18n('local_danmaku_speed'),
                value: local.speed,
                min: 60,
                max: 260,
                divisions: 20,
                display: '${local.speed.toStringAsFixed(0)} px/s',
                onChanged: (value) => custom(Settings.localDanmakuSpeed, value),
              ),
              _Slider(
                id: 'opacity',
                title: i18n('local_danmaku_opacity'),
                value: local.opacity,
                min: 0.35,
                max: 1,
                divisions: 13,
                display: '${(local.opacity * 100).round()}%',
                onChanged: (value) => custom(Settings.localDanmakuOpacity, value),
              ),
              _Slider(
                id: 'spacing',
                title: i18n('local_danmaku_letter_spacing'),
                value: local.letterSpacing,
                min: -0.5,
                max: 3,
                divisions: 14,
                display: local.letterSpacing.toStringAsFixed(1),
                onChanged: (value) => custom(Settings.localDanmakuLetterSpacing, value),
              ),
            ],
          ),
          PanelGroupTitle(i18n('local_danmaku_effects')),
          _Chips(
            groupKey: 'local-style-effects',
            children: [
              _choice(
                context,
                key: 'local-style-bold',
                label: i18n('local_danmaku_bold'),
                selected: local.fontWeight >= 700,
                avatar: const Icon(AppIcons.localBold, size: 17),
                onSelected: () => custom(Settings.localDanmakuFontWeight, local.fontWeight >= 700 ? 500 : 800),
              ),
              _choice(
                context,
                key: 'local-style-italic',
                label: i18n('local_danmaku_italic'),
                selected: local.italic,
                avatar: const Icon(AppIcons.localItalic, size: 17),
                onSelected: () => custom(Settings.localDanmakuItalic, !local.italic),
              ),
              _choice(
                context,
                key: 'local-style-stroke',
                label: i18n('local_danmaku_stroke'),
                selected: stroke,
                avatar: const Icon(AppIcons.localStroke, size: 17),
                onSelected: () => custom(Settings.localDanmakuShowStroke, !stroke),
              ),
              _choice(
                context,
                key: 'local-style-shadow',
                label: i18n('local_danmaku_shadow'),
                selected: shadow,
                avatar: const Icon(AppIcons.localShadow, size: 17),
                onSelected: () => custom(Settings.localDanmakuShowShadow, !shadow),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
            groupKey: 'local-style-group-stroke',
            enabled: stroke,
            children: [
              _Label(i18n('local_danmaku_stroke_color'), condition: stroke ? null : i18n('local_danmaku_needs_stroke')),
              _Palette(
                paletteKey: 'local-style-stroke-colors',
                values: LocalCatalog.effectColors,
                selected: local.strokeColor,
                size: 28,
                onSelected: stroke ? (value) => custom(Settings.localDanmakuStrokeColor, value) : null,
              ),
              _Slider(
                id: 'strokeWidth',
                title: i18n('local_danmaku_stroke_width'),
                value: local.strokeWidth,
                min: 0.5,
                max: 4,
                divisions: 7,
                display: local.strokeWidth.toStringAsFixed(1),
                onChanged: stroke ? (value) => custom(Settings.localDanmakuStrokeWidth, value) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
            groupKey: 'local-style-group-shadow',
            enabled: shadow,
            children: [
              _Label(i18n('local_danmaku_shadow_color'), condition: shadow ? null : i18n('local_danmaku_needs_shadow')),
              _Palette(
                paletteKey: 'local-style-shadow-colors',
                values: LocalCatalog.effectColors,
                selected: local.shadowColor,
                size: 28,
                onSelected: shadow ? (value) => custom(Settings.localDanmakuShadowColor, value) : null,
              ),
              _Slider(
                id: 'shadowBlur',
                title: i18n('local_danmaku_shadow_blur'),
                value: local.shadowBlur,
                min: 0,
                max: 6,
                divisions: 12,
                display: local.shadowBlur.toStringAsFixed(1),
                onChanged: shadow ? (value) => custom(Settings.localDanmakuShadowBlur, value) : null,
              ),
              _Slider(
                id: 'shadowOffset',
                title: i18n('local_danmaku_shadow_offset'),
                value: local.shadowOffset,
                min: 0,
                max: 4,
                divisions: 8,
                display: local.shadowOffset.toStringAsFixed(1),
                onChanged: shadow ? (value) => custom(Settings.localDanmakuShadowOffset, value) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
            groupKey: 'local-style-group-fixed',
            enabled: fixed,
            children: [
              _Slider(
                id: 'fixedDuration',
                title: i18n('local_danmaku_fixed_duration'),
                value: local.fixedDurationMs.toDouble(),
                min: 2000,
                max: 10000,
                divisions: 16,
                display: '${(local.fixedDurationMs / 1000).toStringAsFixed(1)} s',
                onChanged: fixed ? (value) => custom(Settings.localDanmakuFixedDurationMs, value.round()) : null,
              ),
              if (!fixed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    i18n('local_danmaku_needs_fixed'),
                    key: const ValueKey('local-style-fixed-condition'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.localStyleSync, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    i18n('local_danmaku_style_sync_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  /// A chip: chosen ones are tinted and ticked (UI_PLAN §7: "主色 + 勾").
  Widget _choice(
    BuildContext context, {
    required String key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    Widget? avatar,
    TextStyle? labelStyle,
  }) => ChoiceChip(
    key: ValueKey(key),
    label: Text(label, style: labelStyle),
    selected: selected,
    showCheckmark: true,
    avatar: selected ? null : avatar,
    onSelected: (_) => onSelected(),
  );
}

class _Chips extends StatelessWidget {
  const new({required this.groupKey, required this.children});

  final String groupKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey(groupKey),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(spacing: 8, runSpacing: 4, children: children),
  );
}

class _Dot extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), width: 0.5),
    ),
  );
}

class _Label extends StatelessWidget {
  const new(this.text, {this.condition});

  final String text;

  /// What turns the row on, after the name while it is off (c5).
  final String? condition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text, style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14)),
            if (condition case final note?)
              TextSpan(
                text: '  $note',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of colour circles; the chosen one has a thick primary ring and a
/// tick; a null [onSelected] greys them out.
class _Palette extends StatelessWidget {
  const new({
    required this.paletteKey,
    required this.values,
    required this.selected,
    required this.size,
    required this.onSelected,
  });

  final String paletteKey;
  final List<int> values;
  final int selected;
  final double size;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(paletteKey),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 4,
        children: [
          for (final value in values)
            Semantics(
              button: true,
              selected: value == selected,
              label:
                  '${i18n('local_danmaku_color')} #${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              child: InkResponse(
                key: ValueKey('$paletteKey-$value'),
                radius: 22,
                onTap: onSelected == null ? null : () => onSelected!(value),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: value == selected ? scheme.primary : scheme.outlineVariant,
                          width: value == selected ? 2.5 : 1,
                        ),
                      ),
                      child: value == selected
                          ? Icon(AppIcons.selected, size: size * 0.55, color: InkOnColor.on(Color(value)))
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card of rows that greys out (and ignores touches) while it does not
/// apply (c5: grey, not gone).
class _Group extends StatelessWidget {
  const new({required this.groupKey, required this.enabled, required this.children});

  final String groupKey;
  final bool enabled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey(groupKey),
    child: Opacity(
      opacity: enabled ? 1 : 0.38,
      child: PanelCard(children: [...children, const SizedBox(height: 4)]),
    ),
  );
}

/// A title with its value in a pill and a slider under it (the U.2f rows);
/// a null [onChanged] greys it out.
class _Slider extends StatelessWidget {
  const new({
    required this.id,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String id;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('local-style-$id'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15))),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    display,
                    key: ValueKey('local-style-value-$id'),
                    style: theme.textTheme.labelMedium?.emphasis.tabular.copyWith(color: scheme.primary),
                  ),
                ),
              ),
            ],
          ),
          Slider(
            key: ValueKey('local-style-slider-$id'),
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (_) => '$title, $display',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
