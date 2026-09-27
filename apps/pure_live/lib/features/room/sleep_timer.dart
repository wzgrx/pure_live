import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart' show Sizes, Space;
import 'package:pure_live_app/features/room/presentation.dart';

/// What happens when the sleep timer ends (F-TMR-01/02 merged: pause, or
/// quit the app).
enum SleepAction {
  /// Pause playback (and so its background audio).
  pause,

  /// Pause, then quit the app.
  exit,
}

/// The sleep timer (F-TMR-01, F-TMR-02 merged into one "定时关闭").
@immutable
final class SleepTimerState {
  const new({this.endsAt, this.duration, this.action = SleepAction.pause, this.fired = 0});

  /// When it ends; null when not running.
  final DateTime? endsAt;

  /// The chosen length.
  final Duration? duration;

  /// What happens at the end.
  final SleepAction action;

  /// How many times it has ended; the room pauses on each increase.
  final int fired;

  /// Whether it is running.
  bool get active => endsAt != null;

  /// Time left at [now]; zero when not running.
  Duration remaining(DateTime now) {
    final end = endsAt;
    if (end == null) return Duration.zero;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Quits the app: the Activity on Android, the process on desktops.
Future<void> quitApp() async {
  if (touchPlatform) {
    await SystemNavigator.pop();
  } else {
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}

/// How the app quits; tests replace it.
final Provider<Future<void> Function()> appQuitProvider = Provider<Future<void> Function()>((ref) => quitApp);

/// One app-wide timer, so it keeps running when the user switches rooms. The
/// open room listens and pauses when it fires; "退出应用" then quits, giving
/// the room a moment to pause first.
class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState();
  }

  /// Starts (or restarts) the timer for [duration].
  void start(Duration duration, {SleepAction action = SleepAction.pause}) {
    _timer?.cancel();
    _timer = Timer(duration, _fire);
    state = SleepTimerState(
      endsAt: DateTime.now().add(duration),
      duration: duration,
      action: action,
      fired: state.fired,
    );
  }

  /// Changes what happens at the end without restarting.
  void setAction(SleepAction action) {
    state = SleepTimerState(endsAt: state.endsAt, duration: state.duration, action: action, fired: state.fired);
  }

  /// Stops the timer.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = SleepTimerState(action: state.action, fired: state.fired);
  }

  void _fire() {
    _timer = null;
    final action = state.action;
    state = SleepTimerState(action: action, fired: state.fired + 1);
    if (action == SleepAction.exit) {
      final quit = ref.read(appQuitProvider);
      _timer = Timer(const Duration(milliseconds: 300), () {
        _timer = null;
        unawaited(quit());
      });
    }
  }
}

/// The sleep timer.
final NotifierProvider<SleepTimerNotifier, SleepTimerState> sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);

/// Preset lengths in minutes.
const List<int> sleepPresets = [15, 30, 45, 60, 90, 120];

/// Longest custom length: one year (F-TMR-02).
const int maxSleepMinutes = 525600;

/// "01:05:09" or "05:09" for a remaining time, counting whole seconds up
/// (a fresh 2-minute timer reads 02:00).
String formatRemaining(Duration left) {
  final seconds = (left.inMilliseconds + 999) ~/ 1000;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// The timer sheet: presets, a custom length in minutes, pause or quit, the
/// time left and cancel. [onAudioOnly] offers the sleep preset of 3.x's ASMR
/// mode (F-ROOM-10): audio only plus the timer.
Future<void> showSleepTimerSheet(BuildContext context, {VoidCallback? onAudioOnly}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
  builder: (context) => SleepTimerPanel(onAudioOnly: onAudioOnly),
);

/// The content of the timer sheet.
class SleepTimerPanel extends ConsumerStatefulWidget {
  const new({this.onAudioOnly, super.key});

  final VoidCallback? onAudioOnly;

  @override
  ConsumerState<SleepTimerPanel> createState() => _SleepTimerPanelState();
}

class _SleepTimerPanelState extends ConsumerState<SleepTimerPanel> {
  Timer? _tick;
  bool _audioOnly = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTicker(bool active) {
    if (active && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _start(int minutes) {
    ref
        .read(sleepTimerProvider.notifier)
        .start(Duration(minutes: minutes), action: ref.read(sleepTimerProvider).action);
    if (_audioOnly) widget.onAudioOnly?.call();
    Navigator.pop(context);
  }

  Future<void> _custom() async {
    final minutes = await showDialog<int>(context: context, builder: (context) => const _MinutesDialog());
    if (minutes != null && mounted) _start(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sleepTimerProvider);
    _syncTicker(state.active);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('定时关闭', style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.s2),
            if (state.active)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatRemaining(state.remaining(DateTime.now()))} 后'
                      '${state.action == SleepAction.exit ? '退出应用' : '暂停播放'}',
                      style: theme.textTheme.bodyLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(sleepTimerProvider.notifier).cancel(),
                    child: const Text('取消定时'),
                  ),
                ],
              )
            else
              Text('到时间后暂停播放，并停止后台声音', style: theme.textTheme.bodyMedium),
            const SizedBox(height: Space.s3),
            Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                for (final minutes in sleepPresets)
                  ActionChip(label: Text('$minutes 分钟'), onPressed: () => _start(minutes)),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('自定义'),
                  onPressed: _custom,
                ),
              ],
            ),
            const SizedBox(height: Space.s3),
            SegmentedButton<SleepAction>(
              segments: const [
                ButtonSegment(value: SleepAction.pause, label: Text('暂停播放'), icon: Icon(Icons.pause)),
                ButtonSegment(value: SleepAction.exit, label: Text('退出应用'), icon: Icon(Icons.exit_to_app)),
              ],
              selected: {state.action},
              onSelectionChanged: (value) => ref.read(sleepTimerProvider.notifier).setAction(value.first),
            ),
            if (widget.onAudioOnly != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时切换为纯音频'),
                subtitle: const Text('助眠：只保留声音'),
                value: _audioOnly,
                onChanged: (value) => setState(() => _audioOnly = value),
              ),
          ],
        ),
      ),
    );
  }
}

class _MinutesDialog extends StatefulWidget {
  const new();

  @override
  State<_MinutesDialog> createState() => _MinutesDialogState();
}

class _MinutesDialogState extends State<_MinutesDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_text.text.trim());
    if (minutes == null || minutes < 1 || minutes > maxSleepMinutes) {
      setState(() => _error = '请输入 1 到 $maxSleepMinutes 之间的分钟数');
      return;
    }
    Navigator.pop(context, minutes);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义时长'),
    content: TextField(
      controller: _text,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(suffixText: '分钟', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: const Text('开始')),
    ],
  );
}

/// The top-bar chip of a running timer, "23:05".
class SleepTimerChip extends ConsumerStatefulWidget {
  const new({this.onTap, this.color, super.key});

  final VoidCallback? onTap;
  final Color? color;

  @override
  ConsumerState<SleepTimerChip> createState() => _SleepTimerChipState();
}

class _SleepTimerChipState extends ConsumerState<SleepTimerChip> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sleepTimerProvider);
    if (!state.active) {
      _tick?.cancel();
      _tick = null;
      return const SizedBox.shrink();
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: color),
      onPressed: widget.onTap,
      icon: const Icon(Icons.bedtime_outlined, size: 18),
      label: Text(
        formatRemaining(state.remaining(DateTime.now())),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}
