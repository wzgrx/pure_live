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
      const SwitchSettingTile(setting: Settings.danmakuEnabled, title: '显示弹幕', subtitle: '关闭后不再连接弹幕'),
      const SettingsHeader('样式'),
      const DanmakuPresetRow(),
      const DanmakuSliderTile(
        setting: Settings.danmakuFontSize,
        title: '字号',
        min: 10,
        max: 30,
        divisions: 20,
        format: _integer,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuFontWeight,
        title: '字重',
        min: 100,
        max: 900,
        divisions: 8,
        format: _integer,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuOpacity,
        title: '不透明度',
        min: 0.1,
        max: 1,
        divisions: 18,
        format: _percent,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuSpeed,
        title: '速度（越大越快）',
        min: 20,
        max: 400,
        divisions: 38,
        format: _integer,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuArea,
        title: '显示区域',
        min: 0.1,
        max: 1,
        divisions: 18,
        format: _percent,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuTopArea,
        title: '顶部留白',
        min: 0,
        max: 200,
        divisions: 40,
        format: _dp,
      ),
      const DanmakuSliderTile(
        setting: Settings.danmakuBottomArea,
        title: '底部留白',
        min: 0,
        max: 200,
        divisions: 40,
        format: _dp,
      ),
      const SwitchSettingTile(setting: Settings.danmakuStroke, title: '描边'),
      const DanmakuSliderTile(
        setting: Settings.danmakuStrokeWidth,
        title: '描边粗细',
        min: 0.5,
        max: 4,
        divisions: 7,
        format: _oneDecimal,
      ),
      const SwitchSettingTile(setting: Settings.danmakuNoEmoji, title: '隐藏表情', subtitle: '只有表情的弹幕不显示'),
      const SwitchSettingTile(setting: Settings.danmakuAutoFps, title: '帧率自动', subtitle: '跟随“通用 › 刷新率”'),
      SettingBuilder<bool>(
        setting: Settings.danmakuAutoFps,
        builder: (context, auto, _) => auto
            ? const SizedBox.shrink()
            : const DanmakuSliderTile(
                setting: Settings.danmakuFps,
                title: '帧率',
                min: 30,
                max: 240,
                divisions: 7,
                format: _integer,
              ),
      ),
      const SettingsHeader('画面弹幕的点击'),
      const SwitchSettingTile(setting: Settings.danmakuTapInteraction, title: '点击弹幕', subtitle: '打开复制和屏蔽'),
      const SwitchSettingTile(setting: Settings.danmakuLongPressInteraction, title: '长按弹幕', subtitle: '打开复制和屏蔽'),
      const SettingsHeader('过滤'),
      ListTile(
        leading: const Icon(Icons.block),
        title: const Text('屏蔽词和屏蔽用户'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(blockListLocation),
      ),
      const SwitchSettingTile(setting: Settings.danmakuCollapseRepeated, title: '合并重复弹幕'),
      SettingBuilder<bool>(
        setting: Settings.danmakuCollapseRepeated,
        builder: (context, on, _) => on
            ? const DanmakuSliderTile(
                setting: Settings.danmakuRepeatedWindowSeconds,
                title: '合并窗口',
                min: 1,
                max: 30,
                divisions: 29,
                format: _seconds,
              )
            : const SizedBox.shrink(),
      ),
      const SwitchSettingTile(setting: Settings.danmakuSimilarityFilter, title: '过滤相似弹幕', subtitle: '热门房间里短弹幕可能被过滤'),
      SettingBuilder<bool>(
        setting: Settings.danmakuSimilarityFilter,
        builder: (context, on, _) => on
            ? const Column(
                children: [
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityThreshold,
                    title: '相似度阈值',
                    min: 50,
                    max: 100,
                    divisions: 50,
                    format: _integerPercent,
                  ),
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityCacheDuration,
                    title: '比较最近',
                    min: 1,
                    max: 60,
                    divisions: 59,
                    format: _seconds,
                  ),
                  DanmakuSliderTile(
                    setting: Settings.danmakuSimilarityMaxCacheSize,
                    title: '最多比较',
                    min: 20,
                    max: 1000,
                    divisions: 49,
                    format: _lines,
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
      const SwitchSettingTile(
        setting: Settings.danmakuFilterDouyuAutomated,
        title: '过滤斗鱼疑似机器人弹幕',
        subtitle: '默认关闭，可能误伤正常弹幕',
      ),
    ],
  );
}

String _integer(double value) => value.round().toString();
String _integerPercent(double value) => '${value.round()}%';
String _percent(double value) => '${(value * 100).round()}%';
String _dp(double value) => '${value.round()}';
String _oneDecimal(double value) => value.toStringAsFixed(1);
String _seconds(double value) => '${value.round()} 秒';
String _lines(double value) => '${value.round()} 条';

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
      children: const [
        ListTile(title: Text('弹幕设置')),
        DanmakuSettingsTiles(),
        SizedBox(height: 24),
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
                say('已应用“${preset.name}”');
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('保存为我的样式'),
            onPressed: () async {
              await DanmakuTemplate.save(settings);
              say('已保存当前弹幕样式');
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.bookmark_outline, size: 18),
            label: const Text('恢复我的样式'),
            onPressed: DanmakuTemplate.exists(settings)
                ? () async {
                    final restored = await DanmakuTemplate.restore(settings);
                    say(restored ? '已恢复保存的弹幕样式' : '保存的样式已损坏，没能恢复');
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader('画中画弹幕'),
        SwitchSettingTile(setting: Settings.danmakuPipEnabled, title: '画中画里显示弹幕'),
        SliderSettingTile(
          setting: Settings.danmakuPipFontSize,
          title: '字号',
          min: 8,
          max: 24,
          divisions: 16,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipSpeed,
          title: '速度',
          min: 20,
          max: 400,
          divisions: 38,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipOpacity,
          title: '不透明度',
          min: 0.1,
          max: 1,
          divisions: 9,
          format: _percent,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipArea,
          title: '显示区域',
          min: 0.1,
          max: 1,
          divisions: 9,
          format: _percent,
        ),
        SliderSettingTile(
          setting: Settings.danmakuPipMaxVisibleCount,
          title: '同屏最多',
          min: 1,
          max: 20,
          divisions: 19,
          format: _integer,
        ),
        SwitchSettingTile(setting: Settings.danmakuPipNoEmoji, title: '不显示表情'),
      ],
    );
  }
}
