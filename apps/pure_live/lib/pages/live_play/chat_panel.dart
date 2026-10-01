import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/chat_feed.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The four tabs under the video (3.x `DanmakuTabView`): chat, super chats,
/// danmaku settings and the block list.
class ChatPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    animationDuration: pureLiveTabTransitionDuration,
    child: Column(
      children: [
        TabBar(
          key: const ValueKey('live-play-tabs'),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            Tab(text: i18n('danmaku_list')),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Tab(
                text: controller.superChats.isEmpty
                    ? i18n('super_chat')
                    : '${i18n('super_chat')} ${controller.superChats.length}',
              ),
            ),
            Tab(text: i18n('danmaku_settings')),
            Tab(text: i18n('block_list')),
          ],
        ),
        Expanded(
          child: TabBarView(
            physics: const PureLiveBoundedScrollPhysics(),
            children: [
              ChatList(controller: controller),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => SuperChatList(messages: controller.superChats, now: controller.now),
              ),
              const DanmakuSettingsPanel(),
              const BlockListPanel(),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The chat list (3.x `DanmakuListView`): follows new lines while at the
/// bottom; scrolled up, it stays put and offers a "new messages" button.
class ChatList extends ConsumerStatefulWidget {
  /// Creates the list.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList> {
  final ScrollController _scroll = ScrollController();
  bool _following = true;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.controller.addListener(_onChange);
    _seen = widget.controller.chat.added;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _following) setState(() => _following = atBottom);
    if (atBottom) _seen = widget.controller.chat.added;
  }

  void _onChange() {
    if (!mounted) return;
    if (_following) {
      _seen = widget.controller.chat.added;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _following) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    setState(() {});
  }

  void _toBottom() {
    setState(() => _following = true);
    _seen = widget.controller.chat.added;
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _actions(ChatLine line) async {
    final message = line.message;
    if (message == null) return;
    final name = message.userName.trim();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(name.isEmpty ? i18n('live_play_anonymous') : name),
              subtitle: Text(message.message, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(i18n('live_play_copy_message')),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: message.message));
                AppNavigator.toast(i18n('copied_to_clipboard'));
              },
            ),
            if (name.isNotEmpty)
              ListTile(
                key: const ValueKey('live-play-block-user'),
                leading: const Icon(Icons.person_off_outlined),
                title: Text(i18n('live_play_block_user', args: {'name': name})),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await widget.controller.blockUser(name);
                  AppNavigator.toast(i18n('live_play_user_blocked', args: {'name': name}));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    if (!display) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(i18n('danmaku_display_disabled_hint'), textAlign: TextAlign.center),
        ),
      );
    }
    final lines = widget.controller.chat.lines;
    final unseen = widget.controller.chat.added - _seen;
    return Stack(
      children: [
        ListView.builder(
          key: const ValueKey('live-play-chat'),
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            return _ChatLineView(
              key: ValueKey(line.id),
              line: line,
              onLongPress: line.kind == ChatLineKind.chat ? () => unawaited(_actions(line)) : null,
            );
          },
        ),
        if (!_following && unseen > 0)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: ActionChip(
                key: const ValueKey('live-play-new-messages'),
                avatar: const Icon(Icons.arrow_downward_rounded, size: 16),
                label: Text(i18n('danmaku_new_messages', args: {'count': '$unseen'})),
                onPressed: _toBottom,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatLineView extends StatelessWidget {
  const new({required this.line, this.onLongPress, super.key});

  final ChatLine line;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium;
    switch (line.kind) {
      case ChatLineKind.system:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            '${i18n('system_message')}：${line.text}',
            style: body?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
        );
      case ChatLineKind.notice:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined, size: 16, color: scheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(line.text, style: body?.copyWith(color: scheme.onSecondaryContainer)),
              ),
            ],
          ),
        );
      case ChatLineKind.superChat:
        final superChat = line.superChat!;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _parseColor(superChat.backgroundColor, scheme.tertiaryContainer),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${superChat.userName} · ${superChatPrice(superChat)}：${superChat.message}',
            style: body?.copyWith(color: Colors.black87),
          ),
        );
      case ChatLineKind.chat:
        final message = line.message!;
        final color = message.color == LiveMessageColor.white
            ? body?.color
            : Color.fromARGB(255, message.color.r, message.color.g, message.color.b);
        return InkWell(
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  if (message.fansName.trim().isNotEmpty)
                    TextSpan(
                      text: ' ${message.fansName}${message.fansLevel.isEmpty ? '' : ' ${message.fansLevel}'} ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        backgroundColor: scheme.primary,
                      ),
                    ),
                  if (message.fansName.trim().isNotEmpty) const TextSpan(text: ' '),
                  TextSpan(
                    text: message.userName.trim().isEmpty ? '' : '${message.userName}：',
                    style: body?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: message.message,
                    style: body?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

Color _parseColor(String text, Color fallback) {
  final hex = text.trim().replaceFirst('#', '');
  final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return value == null ? fallback : Color(value);
}

/// The price as shown: the platform's text, else the number (3.x showed
/// `￥price`, though only Bilibili and Douyu use yuan).
String superChatPrice(LiveSuperChatMessage superChat) =>
    superChat.priceText.trim().isNotEmpty ? superChat.priceText.trim() : '￥${superChat.price}';

/// Super chats on display with their remaining time (3.x `SuperChatPage`).
class SuperChatList extends StatelessWidget {
  /// Creates the list.
  const new({required this.messages, required this.now, super.key});

  /// Messages, oldest first.
  final List<LiveSuperChatMessage> messages;

  /// The clock.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return AppStatusView(
        type: AppStatusType.empty,
        isMini: true,
        title: i18n('super_chat_empty_title'),
        subtitle: i18n('super_chat_empty_subtitle'),
      );
    }
    final theme = Theme.of(context);
    final current = now();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final superChat = messages[messages.length - 1 - index];
        final top = _parseColor(superChat.backgroundColor, theme.colorScheme.tertiaryContainer);
        final bottom = _parseColor(superChat.backgroundBottomColor, theme.colorScheme.tertiary);
        final left = superChat.endTime.difference(current);
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: top,
                child: ListTile(
                  dense: true,
                  leading: CommonAvatar(avatarUrl: superChat.face, radius: 16, fallbackName: superChat.userName),
                  title: Text(superChat.userName, style: const TextStyle(color: Colors.black87)),
                  subtitle: Text(superChatPrice(superChat), style: const TextStyle(color: Colors.black87)),
                  trailing: Text(
                    left.isNegative ? '' : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ),
              ColoredBox(
                color: bottom,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(superChat.message, style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The main danmaku settings (3.x `DanmakuSettingsPage`, first part): they
/// apply to the video at once.
class DanmakuSettingsPanel extends ConsumerWidget {
  /// Creates the panel.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final area = watchSetting(ref, Settings.danmakuArea);
    final opacity = watchSetting(ref, Settings.danmakuOpacity);
    final speed = watchSetting(ref, Settings.danmakuSpeed);
    final fontSize = watchSetting(ref, Settings.danmakuFontSize);
    final weight = watchSetting(ref, Settings.danmakuFontWeight);
    final border = watchSetting(ref, Settings.danmakuFontBorder);
    final repeatWindow = watchSetting(ref, Settings.repeatedDanmakuWindowSeconds);
    final threshold = watchSetting(ref, Settings.danmakuSimilarityThreshold);
    return ListView(
      key: const ValueKey('live-play-danmaku-settings'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Text(i18n('danmaku_realtime_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        context.buildModernCard([
          context.buildSwitchTile(
            title: i18n('show_danmaku'),
            icon: Icons.subtitles_rounded,
            value: watchSetting(ref, Settings.enableDanmakuDisplay),
            onChanged: (value) => set(Settings.enableDanmakuDisplay, value),
          ),
          context.buildSwitchTile(
            title: i18n('live_play_danmaku_on_video'),
            icon: Icons.layers_outlined,
            value: !watchSetting(ref, Settings.hideDanmaku),
            onChanged: (value) => set(Settings.hideDanmaku, !value),
          ),
          context.buildSwitchTile(
            title: i18n('danmaku_stroke'),
            icon: Icons.format_color_text_rounded,
            value: watchSetting(ref, Settings.enableDanmakuStroke),
            onChanged: (value) => set(Settings.enableDanmakuStroke, value),
          ),
        ]),
        context.buildModernCard([
          context.buildSliderTile(
            icon: Icons.height_rounded,
            title: i18n('live_play_danmaku_area'),
            value: area,
            min: 0.1,
            max: 1,
            displayValue: '${(area * 100).round()}%',
            onChanged: (value) => set(Settings.danmakuArea, (value * 20).round() / 20),
          ),
          context.buildSliderTile(
            icon: Icons.opacity_rounded,
            title: i18n('opacity'),
            value: opacity,
            min: 0.1,
            max: 1,
            displayValue: '${(opacity * 100).round()}%',
            onChanged: (value) => set(Settings.danmakuOpacity, (value * 20).round() / 20),
          ),
          context.buildSliderTile(
            icon: Icons.speed_rounded,
            title: i18n('speed'),
            value: speed.clamp(30, 400),
            min: 30,
            max: 400,
            displayValue: '${speed.round()}',
            onChanged: (value) => set(Settings.danmakuSpeed, value.roundToDouble()),
          ),
          context.buildSliderTile(
            icon: Icons.format_size_rounded,
            title: i18n('font_size'),
            value: fontSize.clamp(10, 40),
            min: 10,
            max: 40,
            displayValue: '${fontSize.round()}',
            onChanged: (value) => set(Settings.danmakuFontSize, value.roundToDouble()),
          ),
          context.buildSliderTile(
            icon: Icons.format_bold_rounded,
            title: i18n('font_weight'),
            value: weight.clamp(100, 900).toDouble(),
            min: 100,
            max: 900,
            displayValue: '$weight',
            onChanged: (value) => set(Settings.danmakuFontWeight, (value / 100).round() * 100),
          ),
          context.buildSliderTile(
            icon: Icons.border_style_rounded,
            title: i18n('stroke'),
            value: border,
            min: 0,
            max: 4,
            displayValue: border.toStringAsFixed(1),
            onChanged: (value) => set(Settings.danmakuFontBorder, (value * 2).round() / 2),
          ),
        ]),
        context.buildGroupTitle(i18n('platform_danmaku_filter')),
        context.buildModernCard([
          context.buildSwitchTile(
            title: i18n('collapse_repeated_danmaku'),
            subtitle: i18n('collapse_repeated_danmaku_desc'),
            icon: Icons.filter_list_rounded,
            value: watchSetting(ref, Settings.collapseRepeatedDanmaku),
            onChanged: (value) => set(Settings.collapseRepeatedDanmaku, value),
          ),
          context.buildSliderTile(
            icon: Icons.timer_outlined,
            title: i18n('repeated_danmaku_window'),
            value: repeatWindow.clamp(1, 30).toDouble(),
            min: 1,
            max: 30,
            displayValue: '$repeatWindow',
            onChanged: (value) => set(Settings.repeatedDanmakuWindowSeconds, value.round()),
          ),
          context.buildSwitchTile(
            title: i18n('danmaku_similarity_filter_enable'),
            icon: Icons.compare_arrows_rounded,
            value: watchSetting(ref, Settings.enableDanmakuSimilarityFilter),
            onChanged: (value) => set(Settings.enableDanmakuSimilarityFilter, value),
          ),
          context.buildSliderTile(
            icon: Icons.tune_rounded,
            title: i18n('danmaku_similarity_threshold'),
            value: threshold.clamp(50, 100).toDouble(),
            min: 50,
            max: 100,
            displayValue: '$threshold%',
            onChanged: (value) => set(Settings.danmakuSimilarityThreshold, value.round()),
          ),
        ]),
      ],
    );
  }
}

/// Blocked words and viewers (3.x `KeywordBlockPage`): add a word, tap a
/// chip to remove it.
class BlockListPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const new({super.key});

  @override
  ConsumerState<BlockListPanel> createState() => _BlockListPanelState();
}

class _BlockListPanelState extends ConsumerState<BlockListPanel> {
  final TextEditingController _input = TextEditingController();
  late final Stream<List<String>> _keywords;
  late final Stream<List<String>> _users;

  @override
  void initState() {
    super.initState();
    final lists = ref.read(storeProvider).blockLists;
    _keywords = lists.watch(BlockKind.keyword);
    _users = lists.watch(BlockKind.user);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final words = _input.text
        .split(RegExp(r'[\n,，]'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      AppNavigator.toast(i18n('please_enter_keyword'));
      return;
    }
    final lists = ref.read(storeProvider).blockLists;
    var added = 0;
    for (final word in words) {
      if (await lists.add(BlockKind.keyword, word)) added++;
    }
    _input.clear();
    AppNavigator.toast(i18n('keyword_added_count', args: {'count': '$added'}));
  }

  Widget _chips(Stream<List<String>> stream, BlockKind kind, String empty) => StreamBuilder<List<String>>(
    stream: stream,
    builder: (context, snapshot) {
      final values = snapshot.data ?? const <String>[];
      if (values.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(empty, style: Theme.of(context).textTheme.bodySmall),
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final value in values)
            InputChip(
              label: Text(value),
              tooltip: i18n('click_to_remove'),
              onDeleted: () => unawaited(ref.read(storeProvider).blockLists.remove(kind, value)),
              onPressed: () => unawaited(ref.read(storeProvider).blockLists.remove(kind, value)),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('live-play-block-list'),
    padding: const EdgeInsets.all(12),
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('live-play-block-input'),
              controller: _input,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: i18n('please_enter_keyword'),
              ),
              onSubmitted: (_) => unawaited(_add()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('live-play-block-add'),
            onPressed: () => unawaited(_add()),
            child: Text(i18n('add')),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(i18n('danmaku_keyword_block'), style: Theme.of(context).textTheme.titleSmall),
      _chips(_keywords, BlockKind.keyword, i18n('live_play_no_blocked_words')),
      const SizedBox(height: 12),
      StreamBuilder<List<String>>(
        stream: _users,
        builder: (context, snapshot) => Text(
          i18n('blocked_danmaku_users', args: {'count': '${snapshot.data?.length ?? 0}'}),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      _chips(_users, BlockKind.user, i18n('live_play_no_blocked_users')),
    ],
  );
}
