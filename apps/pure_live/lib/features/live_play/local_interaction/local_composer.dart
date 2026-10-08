import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Where a local danmaku composer sits (U.2k c6: one composer, three places).
enum LocalComposerPlace {
  /// Under the chat list (portrait; the bottom of the wide chat column).
  chat,

  /// In the local interaction panel.
  panel,

  /// In the middle of the fullscreen bottom bar (U.2c), on the picture.
  video,
}

/// The middle of the fullscreen bar narrower than this shows the star button
/// instead of the field (U.2c c3, U.2k c14).
const double localComposerCollapseWidth = 180;

/// The widest the field on the picture grows (3.x: 420).
const double localComposerVideoMaxWidth = 420;

/// Opens the local danmaku style from a composer's star: the room's panel
/// (U.2k c4), nothing outside a room.
void openLocalDanmakuStyle(BuildContext context) => RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.localStyle);

/// The local danmaku composer (3.x's three: `danmaku_list_view.dart:386-436`,
/// `video_controller_panel.dart:1584-1750`, `local_interaction_sheet.dart:126-142`):
/// the star opens the local danmaku style, the field takes the words
/// ("发送本地弹幕，只有你看得到"), the round button (or Enter) sends. A sent
/// message shows at once (K1). Nothing is drawn while the local interaction
/// is off or outside a live room.
///
/// [LocalComposerPlace.video] is the fullscreen bar's (U.2c places it in the
/// bar's middle): a dark field on the picture, the star in the local danmaku
/// colour, the words in the local style, a light blue outline while typing
/// (c13); when the bar's middle is narrower than
/// [localComposerCollapseWidth] it collapses into the star button whose row
/// opens above the bar (c14). [onHold] tells the bar to keep the controls up
/// while the field has the focus or the row is open (3.x).
class LocalDanmakuComposer extends ConsumerStatefulWidget {
  /// Creates a composer at [place].
  const new({
    this.place = LocalComposerPlace.chat,
    this.onHold,
    this.session,
    this.autofocus = false,
    this.onSent,
    this.maxWidth = localComposerVideoMaxWidth,
    super.key,
  });

  /// The fullscreen bar's composer.
  const new onVideo({ValueChanged<bool>? onHold, Key? key})
    : this(place: LocalComposerPlace.video, onHold: onHold, key: key);

  /// Where it sits.
  final LocalComposerPlace place;

  /// Told when the controls should stay up (the field has the focus) and
  /// when they may hide again.
  final ValueChanged<bool>? onHold;

  /// The room's session; found around the composer when null.
  final LocalRoomSession? session;

  /// Takes the focus at once (the narrow screen's row).
  final bool autofocus;

  /// Called after a message was sent.
  final VoidCallback? onSent;

  /// The widest the field on the picture grows.
  final double maxWidth;

  @override
  ConsumerState<LocalDanmakuComposer> createState() => _LocalDanmakuComposerState();
}

class _LocalDanmakuComposerState extends ConsumerState<LocalDanmakuComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'local-composer');
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    if (_holding) widget.onHold?.call(false);
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() {});
    final hold = _focus.hasFocus;
    if (hold == _holding) return;
    _holding = hold;
    widget.onHold?.call(hold);
  }

  LocalRoomSession? get _session => widget.session ?? LocalRoomScope.maybeOf(context);

  void _send() {
    final session = _session;
    if (session == null || !session.sendChat(_text.text)) return;
    _text.clear();
    widget.onSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null || !localInteractionAvailable(ref)) return const SizedBox.shrink();
    return switch (widget.place) {
      LocalComposerPlace.chat => _chatBar(context),
      LocalComposerPlace.panel => _row(context, session),
      // On the picture it may sit outside a page's Material (U.2c's bar).
      LocalComposerPlace.video => Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < localComposerCollapseWidth
              ? _LocalComposerStar(session: session, onHold: widget.onHold)
              : _videoField(context, session),
        ),
      ),
    };
  }

  /// U.2k-a: the bar under the chat list.
  Widget _chatBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('local-composer-bar'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 8, 8), child: _row(context, _session!)),
    );
  }

  Widget _row(BuildContext context, LocalRoomSession session) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final focused = _focus.hasFocus;
    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            key: const ValueKey('local-composer-field'),
            duration: const Duration(milliseconds: 120),
            height: 48,
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(22)),
            // The outline on top, so the star and the field take the whole
            // 48 to tap (A05.1).
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: focused ? scheme.primary : scheme.outline, width: focused ? 1.5 : 1),
            ),
            child: Row(
              children: [
                _StarButton(color: scheme.primary, size: 19, width: 48),
                Expanded(
                  child: _field(
                    context,
                    style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14, color: scheme.onSurface),
                    hint: theme.textTheme.bodyMedium?.regular.copyWith(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.all(4),
          child: IconButton.filled(
            key: const ValueKey('local-composer-send'),
            tooltip: i18n('local_send_message'),
            style: IconButton.styleFrom(fixedSize: const Size.square(40), minimumSize: const Size.square(40)),
            onPressed: _send,
            icon: const Icon(AppIcons.localSend, size: 22),
          ),
        ),
      ],
    );
  }

  /// U.2k-b: the field on the picture.
  Widget _videoField(BuildContext context, LocalRoomSession session) {
    final focused = _focus.hasFocus;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: AnimatedContainer(
          key: const ValueKey('local-composer-video'),
          duration: const Duration(milliseconds: 120),
          height: 40,
          decoration: BoxDecoration(color: OnVideoColors.dim, borderRadius: BorderRadius.circular(20)),
          // The outline on top, so the buttons and the field take the whole
          // height (A05.1).
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: focused ? localVideoFocusColor(scheme) : OnVideoColors.fieldOutline,
              width: focused ? 1.3 : 1,
            ),
          ),
          child: ListenableBuilder(
            listenable: session.interaction,
            builder: (context, _) {
              final local = session.interaction;
              final ink = Color(local.color);
              final theme = Theme.of(context);
              return Row(
                children: [
                  _StarButton(color: ink, size: 18, width: 44, shadows: OnVideoColors.shadows),
                  Expanded(
                    child: _field(
                      context,
                      // 3.x: the words in the local style (colour, weight,
                      // italic, spacing), with the picture's shadow.
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 14,
                        color: ink.withValues(alpha: local.opacity.clamp(0.35, 1)),
                        fontWeight: FontWeight.values[(local.fontWeight ~/ 100 - 1).clamp(0, 8)],
                        fontStyle: local.italic ? FontStyle.italic : FontStyle.normal,
                        letterSpacing: local.letterSpacing,
                        shadows: OnVideoColors.shadows,
                      ),
                      hint: theme.textTheme.bodyMedium?.regular.copyWith(fontSize: 13, color: OnVideoColors.secondary),
                      cursor: localVideoFocusColor(scheme),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: IconButton(
                      key: const ValueKey('local-composer-send'),
                      tooltip: i18n('local_send_message'),
                      iconSize: 18,
                      color: OnVideoColors.foreground,
                      onPressed: _send,
                      icon: const Icon(AppIcons.localSend),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context, {required TextStyle? style, required TextStyle? hint, Color? cursor}) =>
      LayoutBuilder(
        builder: (context, constraints) => TextField(
          key: const ValueKey('local-composer-input'),
          controller: _text,
          focusNode: _focus,
          autofocus: widget.autofocus,
          style: style,
          cursorColor: cursor,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          // The field is as tall as its bar, the words in the middle: a tap
          // anywhere on the bar's field types (A05.1).
          textAlignVertical: TextAlignVertical.center,
          decoration:
              InputDecoration.collapsed(
                hintText: localComposerHint(context, hint, constraints.maxWidth),
                hintStyle: hint,
              ).copyWith(
                // A long hint ends in "…" instead of wrapping.
                hintMaxLines: 1,
                constraints: BoxConstraints(minHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : 0),
              ),
        ),
      );
}

/// The composer's hint for a field [width] wide (A07.17 c4): the long one
/// ("发送本地弹幕，只有你看得到") where it fits, else the short "发送一条本地字幕"
/// (3.x's), so a narrow field (the portrait fullscreen's) is not cut short.
String localComposerHint(BuildContext context, TextStyle? style, double width) {
  final long = i18n('local_message_hint');
  final painter = TextPainter(
    text: TextSpan(text: long, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final fits = painter.width <= width;
  painter.dispose();
  return fits ? long : i18n('local_message_hint_short');
}

/// The composer's star: opens the local danmaku style (U.2k #1).
class _StarButton extends StatelessWidget {
  const new({required this.color, required this.size, required this.width, this.shadows});

  final Color color;
  final double size;
  final double width;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: IconButton(
      key: const ValueKey('local-composer-style'),
      tooltip: i18n('local_danmaku_style'),
      onPressed: () => openLocalDanmakuStyle(context),
      icon: Icon(AppIcons.localStyle, size: size, color: color, shadows: shadows),
    ),
  );
}

/// The light blue of a field on the picture while typing (U.2k c13): the
/// dark theme's primary colour of the user's theme colour, whatever the
/// page's brightness.
Color localVideoFocusColor(ColorScheme scheme) {
  if (scheme.brightness == Brightness.dark) return scheme.primary;
  return _darkPrimary[scheme.primary] ??= ColorScheme.fromSeed(
    seedColor: scheme.primary,
    brightness: Brightness.dark,
  ).primary;
}

final Map<Color, Color> _darkPrimary = {};

/// U.2k #27: the narrow fullscreen bar's star button; its row opens above
/// the bar with the keyboard up, and closes when a message is sent or the
/// user taps elsewhere.
class _LocalComposerStar extends StatefulWidget {
  const new({required this.session, this.onHold});

  final LocalRoomSession session;
  final ValueChanged<bool>? onHold;

  @override
  State<_LocalComposerStar> createState() => _LocalComposerStarState();
}

/// Opens the composer's row over [context]'s page until a message is sent or
/// the user taps elsewhere: on the picture above the bar
/// ([LocalComposerPlace.video]), or as the chat list's bar along the bottom
/// ([LocalComposerPlace.chat]).
Future<void> _showComposerRow(BuildContext context, LocalRoomSession session, LocalComposerPlace place) {
  final panels = RoomPanelScope.maybeOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: OnVideoColors.clear,
    transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, _, _) =>
        _ComposerRow(session: session, panels: panels, place: place, onSent: () => Navigator.of(dialogContext).pop()),
  );
}

class _LocalComposerStarState extends State<_LocalComposerStar> {
  bool _open = false;

  Future<void> _openRow() async {
    setState(() => _open = true);
    widget.onHold?.call(true);
    await _showComposerRow(context, widget.session, LocalComposerPlace.video);
    if (!mounted) return;
    setState(() => _open = false);
    widget.onHold?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focus = localVideoFocusColor(scheme);
    return Center(
      child: Tooltip(
        message: i18n('local_send_message'),
        child: Material(
          key: const ValueKey('local-composer-star'),
          color: _open ? focus.withValues(alpha: 0.35) : OnVideoColors.dim,
          shape: CircleBorder(side: BorderSide(color: _open ? focus : OnVideoColors.fieldOutline)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(_openRow()),
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(
                AppIcons.localStyle,
                size: 18,
                color: OnVideoColors.foreground,
                shadows: OnVideoColors.shadows,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row of the narrow screen: above the bar, or on the keyboard when it
/// is up (iOS too); from the chat list's star (A07.17 c3), the chat list's
/// bar along the bottom, on the keyboard when it is up.
class _ComposerRow extends StatelessWidget {
  const new({required this.session, required this.panels, required this.onSent, required this.place});

  final LocalRoomSession session;
  final RoomPanelController? panels;
  final VoidCallback onSent;
  final LocalComposerPlace place;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final composer = LocalDanmakuComposer(
      key: const ValueKey('local-composer-row'),
      place: place,
      session: session,
      autofocus: true,
      onSent: onSent,
      maxWidth: 520,
    );
    final row = Material(
      type: MaterialType.transparency,
      // The star inside the row still reaches the room's panels.
      child: panels == null ? composer : RoomPanelScope(notifier: panels!, child: composer),
    );
    if (place == LocalComposerPlace.chat) {
      return Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: media.viewInsets.bottom,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: SafeArea(top: false, child: row),
            ),
          ),
        ],
      );
    }
    final bottom = math.max(media.viewInsets.bottom + 8, media.padding.bottom + 64);
    return Stack(
      children: [
        Positioned(
          left: 12,
          right: 12,
          bottom: bottom,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: row),
          ),
        ),
      ],
    );
  }
}

/// A07.17 c3: the composer folded into a star at the lower right of the
/// chat list (the portrait room's panel, where its bar left two lines of
/// chat); a tap opens the composer's bar along the bottom with the
/// keyboard. Nothing while the local interaction is off or outside a room.
class LocalComposerChatStar extends ConsumerWidget {
  /// Creates the star.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = LocalRoomScope.maybeOf(context);
    if (session == null || !localInteractionAvailable(ref)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      key: const ValueKey('local-composer-chat-star'),
      tooltip: i18n('local_send_message'),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        // 40 to see, 48 to tap on every platform (A05.1).
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.primary,
      ),
      onPressed: () => unawaited(_showComposerRow(context, session, LocalComposerPlace.chat)),
      icon: const Icon(AppIcons.localStyle, size: 20),
    );
  }
}

/// Whether the room's danmaku fly over the picture now (`enableDanmakuDisplay`
/// and not `hideDanmaku`, 3.x's condition for local danmaku too).
bool localOverlayShown(SettingsStore settings) =>
    settings.get(Settings.enableDanmakuDisplay) && !settings.get(Settings.hideDanmaku);

/// The composer under the chat list of [child] (the list's tab, U.2k-a), or
/// with [collapsed] its star at the list's lower right
/// ([LocalComposerChatStar], A07.17 c3: the portrait room's panel).
class LocalComposerBelow extends StatelessWidget {
  /// Creates the column.
  const new({required this.child, this.collapsed = false, super.key});

  /// The chat list.
  final Widget child;

  /// The composer is a star on the list instead of a bar under it.
  final bool collapsed;

  /// How far the star pushes the list's own lower-right button (the new
  /// messages) to the left.
  static const double starInset = 52;

  @override
  Widget build(BuildContext context) => collapsed
      ? Stack(
          fit: StackFit.expand,
          children: [
            child,
            // 12 from the corner to the star; its tap area reaches 4 further.
            const Positioned(right: 8, bottom: 8, child: LocalComposerChatStar()),
          ],
        )
      : Column(
          children: [
            Expanded(child: child),
            const LocalDanmakuComposer(),
          ],
        );
}
