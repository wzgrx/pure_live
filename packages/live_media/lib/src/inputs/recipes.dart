import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/input.dart';
import 'package:live_media/src/relay/hls_relay.dart';
import 'package:live_media/src/relay/loopback_relay.dart';
import 'package:live_net/live_net.dart';

/// The relay recipe of a Bigo playlist: every segment of a protected media
/// playlist gets its first 376 bytes restored ([BigoHlsProtection]); an
/// unprotected playlist passes as it is. A protection tag without a usable
/// seed fails that playlist (the engine retries) rather than passing
/// scrambled segments.
HlsRelayRecipe bigoRelayRecipe() => HlsRelayRecipe(
  restore: (playlist) {
    final seed = BigoHlsProtection.seed(playlist);
    if (seed == null) return null;
    return (segment) => BigoHlsProtection.transform(segment, seed);
  },
);

/// The relay recipe of a niconico grant: each request carries the cookies
/// of its path at that moment (`NiconicoGrant.cookieHeaderFor`), and with
/// a [resolution] the master is reduced to the one exact variant (3.x's
/// `HlsMasterSelection`: `RESOLUTION`, and `BANDWIDTH` when given; zero or
/// several matches fail the master).
HlsRelayRecipe niconicoRelayRecipe(
  NiconicoGrant Function() grant, {
  String? resolution,
  int? bandwidth,
  DateTime Function()? now,
}) => HlsRelayRecipe(
  cookies: (url) => grant().cookieHeaderFor(url, now: now?.call()),
  master: resolution == null
      ? null
      : (source, text) {
          final variants = HlsMasterPlaylist.parse(source, text).variants
              .where(
                (variant) =>
                    variant.attributes['RESOLUTION'] == resolution &&
                    (bandwidth == null || variant.attributes['BANDWIDTH'] == '$bandwidth'),
              )
              .toList();
          if (variants.length != 1) throw const FormatException('niconico variant is not exactly one');
          return HlsMasterSelection.fromMaster(text, source: source, video: variants.single.uri).rewrite(source, text);
        },
);

final class _Owned implements OwnedInput {
  new(this.relay, {this._usable, this._release});

  @override
  final RelayInput relay;
  final bool Function()? _usable;
  final Future<void> Function()? _release;
  Future<void>? _closing;

  @override
  bool get isUsable => _closing == null && !relay.isClosed && (_usable?.call() ?? true);

  @override
  Future<void> close() => _closing ??= Future.wait([relay.close(), ?_release?.call()]);
}

void _checkCancelled(String site, CancelToken? cancel) {
  if (cancel?.isCancelled ?? false) throw TransportFailure(site, TransportReason.cancelled);
}

/// Bigo (3.x's `BigoPlaybackInput`): a fresh studio answer per open
/// ([BigoSite.resolveInput]), relayed with [bigoRelayRecipe].
final class BigoRecipeOpener implements RecipeOpener {
  /// Creates the opener.
  const new(this.site);

  /// The platform adapter.
  final BigoSite site;

  @override
  bool handles(LiveInputRecipe recipe) => recipe is BigoInputRecipe;

  @override
  Future<OwnedInput> open(LiveInputRecipe recipe, LoopbackRelay relay, {CancelToken? cancel}) async {
    final line = await site.resolveInput(recipe as BigoInputRecipe, cancel: cancel);
    _checkCancelled(site.id, cancel);
    return _Owned(relay.openHls(line, site: site.id, recipe: bigoRelayRecipe()));
  }
}

/// FC2 (3.x's `Fc2PlaybackInput`): a control of its own, held while the
/// playlist is played ([Fc2LiveSite.openControl]); the input stops being
/// usable when the control ends. A control already opened (the quality
/// probe's, notes "FC2 control sharing") can be handed over with [adopt].
final class Fc2RecipeOpener implements RecipeOpener {
  /// Creates the opener.
  new(this.site);

  /// The platform adapter.
  final Fc2LiveSite site;

  final Map<String, Fc2LiveControl> _adopted = {};

  /// Lets the next open of [control]'s channel and quality use it instead of
  /// opening another; the opener then owns it.
  void adopt(Fc2LiveControl control) {
    final key = '${control.channelId}:${control.requestedQuality}';
    final previous = _adopted[key];
    _adopted[key] = control;
    if (previous != null && !identical(previous, control)) unawaited(previous.close());
  }

  @override
  bool handles(LiveInputRecipe recipe) => recipe is Fc2LiveInputRecipe;

  @override
  Future<OwnedInput> open(LiveInputRecipe recipe, LoopbackRelay relay, {CancelToken? cancel}) async {
    final fc2 = recipe as Fc2LiveInputRecipe;
    final adopted = _adopted.remove('${fc2.channelId}:${fc2.quality}');
    final control = adopted != null && !adopted.isClosed
        ? adopted
        : await site.openControl(fc2.channelId, cancel: cancel, quality: fc2.quality);
    try {
      _checkCancelled(site.id, cancel);
      final line = LivePlayLine(
        control.playlist.toString(),
        headers: control.mediaHeaders,
        format: StreamFormat.hls,
        lineId: control.playlist.host,
      );
      return _Owned(
        relay.openHls(line, site: site.id),
        usable: () => !control.isClosed,
        release: control.close,
      );
    } on Object {
      await control.close();
      rethrow;
    }
  }
}

/// niconico (3.x's `NiconicoPlaybackInput`): the watch page and a seat of
/// its own per open ([NiconicoSite.openSeat]), the master with the seat's
/// per-path cookies ([niconicoRelayRecipe]). A grant that moves to another
/// master, or the seat ending, ends the input (3.x).
final class NiconicoRecipeOpener implements RecipeOpener {
  /// Creates the opener.
  const new(this.site);

  /// The platform adapter.
  final NiconicoSite site;

  @override
  bool handles(LiveInputRecipe recipe) => recipe is NiconicoInputRecipe;

  @override
  Future<OwnedInput> open(LiveInputRecipe recipe, LoopbackRelay relay, {CancelToken? cancel}) async {
    final nico = recipe as NiconicoInputRecipe;
    final seat = await site.openSeat(nico.programId, cancel: cancel);
    StreamSubscription<NiconicoGrant>? moves;
    try {
      _checkCancelled(site.id, cancel);
      final source = seat.current.uri;
      var moved = false;
      moves = seat.changes.listen((grant) => moved = moved || grant.uri != source);
      final input = relay.openHls(
        LivePlayLine(source.toString(), format: StreamFormat.hls, lineId: source.host),
        site: site.id,
        recipe: niconicoRelayRecipe(() => seat.current, resolution: nico.resolution, bandwidth: nico.bandwidth),
      );
      final subscription = moves;
      return _Owned(
        input,
        usable: () => !moved && !seat.isClosed,
        release: () async {
          await subscription.cancel();
          await seat.close();
        },
      );
    } on Object {
      await moves?.cancel();
      await seat.close();
      rethrow;
    }
  }
}
