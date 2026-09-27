import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show Sizes, Space;
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_presets.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Location of the block-list page.
const blockListLocation = '/danmaku/blocks';

/// Every danmaku setting in one list (F-DM-02: one panel instead of 3.x's
/// three entries). Used by 设置 › 弹幕 and by the room's settings sheet, where
/// style changes show on the playing video while the thumb moves.
class DanmakuSettingsTiles extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchSettingTile(setting: Settings.danmakuEnabled, title: t.danmaku.show, subtitle: t.danmaku.showSubtitle),
      SettingsHeader(t.danmaku.style),
      const DanmakuPresetRow(),
      DanmakuSliderTile(
        setting: Settings.danmakuFontSize,
        title: t.danmaku.fontSize,
        min: 10,
        max: 30,
        divisions: 20,
        format: _integer,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuFontWeight,
        title: t.danmaku.fontWeight,
        min: 100,
        max: 900,
        divisions: 8,
        format: _integer,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuOpacity,
        title: t.danmaku.opacity,
        min: 0.1,
        max: 1,
        divisions: 18,
        format: _percent,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuSpeed,
        title: t.danmaku.speedHint,
        min: 20,
        max: 400,
        divisions: 38,
        format: _integer,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuArea,
        title: t.danmaku.area,
        min: 0.1,
        max: 1,
        divisions: 18,
        format: _percent,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuTopArea,
        title: t.danmaku.topMargin,
        min: 0,
        max: 200,
        divisions: 40,
        format: _dp,
      ),
      DanmakuSliderTile(
        setting: Settings.danmakuBottomArea,
        title: t.danmaku.bottomMargin,
        min: 0,
        max: 200,
        divisions: 40,
        format: _dp,
      ),
      SwitchSettingTile(setting: Settings.danmakuStroke, title: t.danmaku.stroke),
      DanmakuSliderTile(
        setting: Settings.danmakuStrokeWidth,
        title: t.danmaku.strokeWidth,
        min: 0.5,
        max: 4,
        divisions: 7,
        format: _oneDecimal,
      ),
      SwitchSettingTile(
        setting: Settings.danmakuNoEmoji,
        title: t.danmaku.hideEmoji,
        subtitle: t.danmaku.hideEmojiSubtitle,
      ),
      SwitchSettingTile(
        setting: Settings.danmakuAutoFps,
        title: t.danmaku.autoFps,
        subtitle: t.danmaku.autoFpsSubtitle,
      ),
      SettingBuilder<bool>(
        setting: Settings.danmakuAutoFps,
        builder: (context, auto, _) => auto
            ? const SizedBox.shrink()
            : DanmakuSliderTile(
                setting: Settings.danmakuFps,
                title: t.danmaku.fps,
                min: 30,
                max: 240,
                divisions: 7,
                format: _integer,
              ),
      ),
      SettingsHeader(t.danmaku.videoTaps),
      SwitchSettingTile(
        setting: Settings.danmakuTapInteraction,
        title: t.danmaku.tapDanmaku,
        subtitle: t.danmaku.opensActions,
      ),
      SwitchSettingTile(
        setting: Settings.danmakuLongPressInteraction,
        title: t.danmaku.longPressDanmaku,
        subtitle: t.danmaku.opensActions,
      ),
      SettingsHeader(t.danmaku.filters),
      ListTile(
        leading: const Icon(Icons.block),
        title: Text(t.danmaku.blockListTitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(blockListLocation),
      ),
      SwitchSettingTile(setting: Settings.danmakuCollapseRepeated, title: t.danmaku.collapseRepeated),
      SettingBuilder<bool>(
        setting: Settings.danmakuCollapseRepeated,
        builder: (context, on, _) => on
            ? DanmakuSliderTile(
                setting: Settings.danmakuRepeatedWindowSeconds,
                title: t.danmaku.collapseWindow,
                min: 1,
                max: 30,
                divisions: 29,
                format: _seconds,
              )
            : const SizedBox.shrink(),
      ),
      SwitchSettingTile(
        setting: Settings.danmakuSimilarityFilter,
        title: t.danmaku.filterSimilar,
        subtitle: t.danmaku.filterSimilarSubtitle,
      ),
      SettingBuilder<bool>(
        setting: Settings.danmakuSimilarityFilter,
        builder: (context, on, _) => on
            ? Column(
                children: [
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityThreshold,
                    title: t.danmaku.similarityThreshold,
                    min: 50,
                    max: 100,
                    divisions: 50,
                    format: _integerPercent,
                  ),
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityCacheDuration,
                    title: t.danmaku.compareRecent,
                    min: 1,
                    max: 60,
                    divisions: 59,
                    format: _seconds,
                  ),
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityMaxCacheSize,
                    title: t.danmaku.compareMost,
                    min: 20,
                    max: 1000,
                    divisions: 49,
                    format: _lines,
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
      SwitchSettingTile(
        setting: Settings.danmakuFilterDouyuAutomated,
        title: t.danmaku.douyuBots,
        subtitle: t.danmaku.douyuBotsSubtitle,
      ),
    ],
  );
}

String _integer(double value) => value.round().toString();
String _integerPercent(double value) => '${value.round()}%';
String _percent(double value) => '${(value * 100).round()}%';
String _dp(double value) => '${value.round()}';
String _oneDecimal(double value) => value.toStringAsFixed(1);
String _seconds(double value) => t.common.seconds(n: value.round());
String _lines(double value) => t.common.items(n: value.round());

/// A number setting on a slider that stores while the thumb moves (at most
/// every 150 ms) and on release, so the on-video style follows the drag.
class DanmakuSliderTile extends StatefulWidget {
  const new({
    required this.setting,
    required this.title,
    required this.min,
    required this.max,
    this.divisions,
    this.format,
    super.key,
  });

  /// A [DoubleSetting] or an [IntSetting].
  final Setting<num> setting;
  final String title;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value)? format;

  @override
  State<DanmakuSliderTile> createState() => _DanmakuSliderTileState();
}

class _DanmakuSliderTileState extends State<DanmakuSliderTile> {
  double? _dragging;
  Timer? _throttle;
  num? _pending;
  void Function(num value)? _store;

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  num _typed(double value) => widget.setting is IntSetting ? value.round() : value;

  void _storeSoon(num value) {
    _pending = value;
    if (_throttle != null) return;
    _flush();
    _throttle = Timer(const Duration(milliseconds: 150), () {
      _throttle = null;
      if (_pending != null) _flush();
    });
  }

  void _flush() {
    final value = _pending;
    _pending = null;
    if (value != null) _store?.call(value);
  }

  @override
  Widget build(BuildContext context) => SettingBuilder<num>(
    setting: widget.setting,
    builder: (context, value, set) {
      _store = set;
      final shown = (_dragging ?? value.toDouble()).clamp(widget.min, widget.max);
      final label = widget.format?.call(shown) ?? shown.toStringAsFixed(1);
      return ListTile(
        title: Text(widget.title),
        subtitle: Slider(
          value: shown,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: label,
          onChanged: (next) {
            setState(() => _dragging = next);
            _storeSoon(_typed(next));
          },
          onChangeEnd: (next) {
            _throttle?.cancel();
            _throttle = null;
            _pending = null;
            setState(() => _dragging = null);
            set(_typed(next));
          },
        ),
        trailing: SizedBox(
          width: 56,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.end),
        ),
      );
    },
  );
}

/// The room's danmaku settings (F-DM-02) as a sheet over the video; a light
/// barrier keeps the picture visible so style changes can be judged live.
Future<void> showDanmakuSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  barrierColor: const Color(0x33000000),
  constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.3,
    maxChildSize: 0.9,
    builder: (context, controller) => ListView(
      controller: controller,
      children: [
        ListTile(title: Text(t.danmaku.settings)),
        const DanmakuSettingsTiles(),
        const SizedBox(height: 24),
      ],
    ),
  ),
);

/// F-DM-02: one-tap looks and the user's own saved style.
class DanmakuPresetRow extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DanmakuPresetRow> createState() => _DanmakuPresetRowState();
}

class _DanmakuPresetRowState extends ConsumerState<DanmakuPresetRow> {
  StreamSubscription<Object?>? _changes;

  @override
  void initState() {
    super.initState();
    // The chips show which preset is in force; any danmaku change may alter it.
    _changes = ref.read(storeProvider).settings.changes.where((id) => id.startsWith('danmaku.')).listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(storeProvider).settings;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String text) => messenger?.showSnackBar(SnackBar(content: Text(text)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
      child: Wrap(
        spacing: Space.s2,
        runSpacing: Space.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final preset in danmakuPresets)
            ChoiceChip(
              label: Text(preset.name),
              selected: preset.matches(settings),
              onSelected: (_) async {
                await preset.apply(settings);
                say(t.danmaku.presetApplied(name: preset.name));
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(t.danmaku.saveMyStyle),
            onPressed: () async {
              await DanmakuTemplate.save(settings);
              say(t.danmaku.styleSaved);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_outline, size: 18),
            label: Text(t.danmaku.restoreMyStyle),
            onPressed: DanmakuTemplate.exists(settings)
                ? () async {
                    final restored = await DanmakuTemplate.restore(settings);
                    say(restored ? t.danmaku.styleRestored : t.danmaku.styleBroken);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 画中画弹幕 (F-DM-07): the light danmaku of picture-in-picture, on the
/// platforms that have it.
class PipDanmakuTiles extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isWindows) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(t.danmaku.pip),
        SwitchSettingTile(setting: Settings.danmakuPipEnabled, title: t.danmaku.pipShow),
        SliderSettingTile(
          setting: Settings.danmakuPipFontSize,
          title: t.danmaku.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipSpeed,
          title: t.danmaku.speed,
          min: 20,
          max: 400,
          divisions: 38,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipOpacity,
          title: t.danmaku.opacity,
          min: 0.1,
          max: 1,
          divisions: 9,
          format: _percent,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipArea,
          title: t.danmaku.area,
          min: 0.1,
          max: 1,
          divisions: 9,
          format: _percent,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipMaxVisibleCount,
          title: t.danmaku.maxOnScreen,
          min: 1,
          max: 20,
          divisions: 19,
          format: _integer,
        ),
        SwitchSettingTile(setting: Settings.danmakuPipNoEmoji, title: t.danmaku.noEmoji),
      ],
    );
  }
}
