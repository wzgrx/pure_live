import 'package:flutter/material.dart';
import 'package:live_ui/src/avatar.dart';
import 'package:live_ui/src/badges.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/text_scale.dart';
import 'package:live_ui/src/tv/focus_frame.dart';
import 'package:live_ui/src/tv/tv_scope.dart';
import 'package:live_ui/src/ui_text.dart';

/// Card density (principles §4.3).
enum CardDensity {
  /// Streamer name and title on two lines.
  standard,

  /// "Streamer · title" on one line.
  compact;

  /// The density a card is laid out with at [scaler]: from 1.5× text a
  /// compact card takes the standard two lines (streamer, then title), where
  /// one line of "streamer · title" would leave only an ellipsis of the
  /// title. Grids size their cells with the same answer.
  CardDensity shownAt(TextScaler scaler) =>
      this == compact && scaler.scale(_probe) >= _probe * _twoLinesFrom ? standard : this;

  static const double _probe = 14;
  static const double _twoLinesFrom = 1.5;
}

/// A live room card: 16:9 cover with platform logo, live badge and audience,
/// then the streamer and title (principles §4.3).
///
/// The cover is an [ImageProvider] so the app decides caching and decode size.
class RoomCardView extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.platformId,
    required this.anchorName,
    required this.title,
    required this.isLive,
    this.cover,
    this.audience,
    this.liveFor,
    this.recording = false,
    this.density = CardDensity.standard,
    this.onTap,
    this.onMenu,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
    super.key,
  });

  /// Platform id for the logo (`douyu`).
  final String platformId;

  /// Streamer's name.
  final String anchorName;

  /// Broadcast title.
  final String title;

  /// Whether the room is live now.
  final bool isLive;

  /// Cover image. While it loads the cover is a plain surfaceContainerHighest
  /// block; without a cover or when it fails, the block carries the 24 dp
  /// platform logo in the middle (principles §3.4).
  final ImageProvider? cover;

  /// Formatted audience figure (`355.1万`), shown bottom right.
  final String? audience;

  /// Formatted live duration (`01:24`), shown next to the live badge.
  final String? liveFor;

  /// Whether the recorder is saving this room: "录制中" top right
  /// (spec/product.md F-FAV-01).
  final bool recording;

  /// Text density.
  final CardDensity density;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card menu: long press on touch, right click on desktop, long
  /// OK or the menu key on a remote (principles §4.2).
  final VoidCallback? onMenu;

  /// The card's focus node; grids keep one per card (TV focus memory).
  final FocusNode? focusNode;

  /// Keys other than OK and menu while the card has focus (grid moves).
  final FocusOnKeyEventCallback? onKeyEvent;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final words = LiveUiText.current;
    final density = this.density.shownAt(MediaQuery.textScalerOf(context));
    final label = [
      anchorName,
      if (isLive) words.liveNow else words.offline,
      if (recording) words.recording,
      title,
    ].join(words.separator);
    // The frame is the card's only focus target: keyboard and remote focus
    // draw its ring (and grow the card on TV), OK opens, long OK is the menu.
    return FocusFrame(
      focusNode: focusNode,
      onActivate: onTap,
      onMenu: onMenu,
      onKeyEvent: onKeyEvent,
      onFocusChange: onFocusChange,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onSecondaryTap: onMenu,
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap,
            onLongPress: onMenu,
            borderRadius: BorderRadius.circular(Radii.r2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: RoomCover(
                    cover: cover,
                    platformId: platformId,
                    // principles §3.4: 24 dp on TV, 16 elsewhere.
                    cornerLogo: TvScope.of(context).enabled ? Sizes.logoLarge : Sizes.logoSmall,
                    children: [
                      // Badges on the cover grow at most 1.3× (principles
                      // §2.3), so large text never buries the picture.
                      Positioned.fill(
                        child: OnVideoTextScale(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (recording)
                                const Positioned(right: Space.s1 + 2, top: Space.s1 + 2, child: RecordingBadge()),
                              // One row, so large text shortens the badge
                              // instead of drawing it under the audience.
                              if (isLive || audience != null)
                                Positioned(
                                  left: Space.s1 + 2,
                                  right: Space.s1 + 2,
                                  bottom: Space.s1 + 2,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: AlignmentDirectional.bottomStart,
                                          child: isLive ? LiveBadge(duration: liveFor) : null,
                                        ),
                                      ),
                                      if (audience != null) ...[const SizedBox(width: Space.s1), CoverLabel(audience!)],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s1, Space.s2, Space.s1, Space.s1),
                  child: density == CardDensity.standard
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(anchorName, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              title,
                              style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: anchorName, style: text.titleSmall),
                              TextSpan(
                                text: ' · $title',
                                style: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row for an offline followed streamer: avatar, name, last live time; no
/// cover is loaded (principles §4.1).
class OfflineRoomRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.platformId,
    required this.anchorName,
    this.seed,
    this.avatar,
    this.subtitle,
    this.tag,
    this.recording = false,
    this.onTap,
    this.onMenu,
    super.key,
  });

  /// Platform id for the logo.
  final String platformId;

  /// Streamer's name.
  final String anchorName;

  /// Picks the initial's tone ([InitialAvatar.seed]): the room key; the
  /// platform and name when null.
  final String? seed;

  /// Avatar image.
  final ImageProvider? avatar;

  /// Secondary line (`上次开播 3 小时前`).
  final String? subtitle;

  /// A state label after the name (`未支持`, `状态未知`).
  final String? tag;

  /// Whether the recorder is saving this room (F-FAV-01).
  final bool recording;

  /// Opens the room.
  final VoidCallback? onTap;

  /// Opens the card menu (long press, right click, long OK, menu key).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    // One focus target with the card's remote keys; the row keeps its fill.
    return FocusFrame(
      onActivate: onTap,
      onMenu: onMenu,
      grow: false,
      ringInside: true,
      radius: 0,
      child: GestureDetector(
        onSecondaryTap: onMenu,
        child: ExcludeFocus(
          child: ListTile(
            onTap: onTap,
            onLongPress: onMenu,
            leading: InitialAvatar(name: anchorName, seed: seed ?? '$platformId:$anchorName', image: avatar),
            title: Row(
              children: [
                Flexible(child: Text(anchorName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (tag != null) ...[const SizedBox(width: Space.s2), StatusTag(tag!)],
                if (recording) ...[const SizedBox(width: Space.s2), const StatusTag.recording()],
              ],
            ),
            subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 1),
            trailing: PlatformLogo(platformId: platformId, size: Sizes.logoMedium),
          ),
        ),
      ),
    );
  }
}

/// A 16:9 cover without a clip layer (principles §7.11): the image fills a
/// decoration with r2 corners and the platform logo sits top left
/// (principles §4.3). While the first image loads the block is plain
/// surfaceContainerHighest, with no spinner; with no cover, or when it
/// fails, the 24 dp logo moves to the middle of the block instead
/// (principles §3.4), so the card never shows the same logo twice. A new
/// [cover] (a refreshed live cover) replaces the old one only once it has
/// loaded, so the card never flashes back to the placeholder.
class RoomCover extends StatefulWidget {
  /// Creates the cover.
  const new({
    required this.cover,
    required this.platformId,
    this.cornerLogo = Sizes.logoSmall,
    this.children = const [],
    super.key,
  });

  /// The image; null for none.
  final ImageProvider? cover;

  /// Platform of the logo.
  final String platformId;

  /// Size of the top-left logo over a picture.
  final double cornerLogo;

  /// Marks drawn on top (badges, logo, audience), usually [Positioned].
  final List<Widget> children;

  @override
  State<RoomCover> createState() => _RoomCoverState();
}

class _RoomCoverState extends State<RoomCover> {
  /// The image the decoration paints; null until one has loaded.
  ImageProvider? _shown;

  /// The image being resolved, and its stream and listener.
  ImageProvider? _pending;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// The latest image failed and nothing was shown before it.
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(RoomCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cover != oldWidget.cover) _resolve();
  }

  void _resolve() {
    final cover = widget.cover;
    if (cover == null) {
      _stopListening();
      _pending = null;
      _shown = null;
      _failed = false;
      return;
    }
    if (cover == _pending || cover == _shown) return;
    _stopListening();
    _pending = cover;
    final stream = cover.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (image, _) {
        // Only the signal is needed; the decoration holds its own handle.
        image.dispose();
        if (!mounted || _pending != cover) return;
        setState(() {
          _shown = cover;
          _pending = null;
          _failed = false;
        });
        _stopListening();
      },
      onError: (_, _) {
        if (!mounted || _pending != cover) return;
        // A failed refresh keeps the picture that was there.
        setState(() {
          _pending = null;
          _failed = _shown == null;
        });
        _stopListening();
      },
    );
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final placeholder = widget.cover == null || (_failed && shown == null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.r2),
        image: shown == null ? null : DecorationImage(image: shown, fit: BoxFit.cover, onError: (_, _) {}),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (placeholder)
            Center(
              child: PlatformLogo(platformId: widget.platformId, size: Sizes.logoLarge),
            )
          else
            Positioned(
              left: Space.s1 + 2,
              top: Space.s1 + 2,
              child: PlatformLogo(platformId: widget.platformId, size: widget.cornerLogo),
            ),
          ...widget.children,
        ],
      ),
    );
  }
}
