import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show PageMargin;
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';

/// Rebuilds with a setting's current value; the value is read synchronously
/// first, so the tile never flashes a default.
class SettingBuilder<T extends Object> extends ConsumerStatefulWidget {
  const new({required this.setting, required this.builder, super.key});

  /// The setting.
  final Setting<T> setting;

  /// Builds with the value and a setter.
  final Widget Function(BuildContext context, T value, ValueChanged<T> set) builder;

  @override
  ConsumerState<SettingBuilder<T>> createState() => _SettingBuilderState<T>();
}

class _SettingBuilderState<T extends Object> extends ConsumerState<SettingBuilder<T>> {
  late SettingsStore _settings;
  late T _value;
  StreamSubscription<T>? _subscription;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(storeProvider).settings;
    _value = _settings.get(widget.setting);
    _subscription = _settings.watch(widget.setting).listen((value) => setState(() => _value = value));
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, (value) => unawaited(_settings.set(widget.setting, value)));
}

/// An on/off setting.
class SwitchSettingTile extends StatelessWidget {
  const new({required this.setting, required this.title, this.subtitle, super.key});

  final BoolSetting setting;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SettingAnchor(
    id: setting.id,
    child: SettingBuilder<bool>(
      setting: setting,
      builder: (context, value, set) => SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: set,
      ),
    ),
  );
}

/// One of several values, chosen in a dialog.
class ChoiceSettingTile<T extends Object> extends StatelessWidget {
  const new({required this.setting, required this.title, required this.labels, super.key});

  final Setting<T> setting;
  final String title;

  /// Choices in display order with their labels.
  final Map<T, String> labels;

  @override
  Widget build(BuildContext context) => SettingAnchor(id: setting.id, child: _tile(context));

  Widget _tile(BuildContext context) => SettingBuilder<T>(
    setting: setting,
    builder: (context, value, set) => ListTile(
      title: Text(title),
      subtitle: Text(labels[value] ?? '$value'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final chosen = await showDialog<T>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(title),
            children: [
              RadioGroup<T>(
                groupValue: value,
                onChanged: (choice) => Navigator.pop(context, choice),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in labels.entries) RadioListTile<T>(value: entry.key, title: Text(entry.value)),
                  ],
                ),
              ),
            ],
          ),
        );
        if (chosen != null) set(chosen);
      },
    ),
  );
}

/// A number on a slider; changes are stored when the thumb is released.
class SliderSettingTile extends StatefulWidget {
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

  /// Label for a value; the number with one decimal by default.
  final String Function(double value)? format;

  @override
  State<SliderSettingTile> createState() => _SliderSettingTileState();
}

class _SliderSettingTileState extends State<SliderSettingTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) => SettingAnchor(id: widget.setting.id, child: _tile(context));

  Widget _tile(BuildContext context) => SettingBuilder<num>(
    setting: widget.setting,
    builder: (context, value, set) {
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
          onChanged: (next) => setState(() => _dragging = next),
          onChangeEnd: (next) {
            setState(() => _dragging = null);
            set(widget.setting is IntSetting ? next.round() : next);
          },
        ),
        trailing: Text(label, style: Theme.of(context).textTheme.labelLarge),
      );
    },
  );
}

/// A section heading inside a settings page.
class SettingsHeader extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    // On the rows' line (principles §2.4).
    padding: PageMargin.rowInsets(context).copyWith(top: 20, bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
