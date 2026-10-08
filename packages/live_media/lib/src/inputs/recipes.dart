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

/// The FC2 controls a platform's quality probes handed over
/// ([Fc2LiveSite.probeControl]; UPGRADES 26-2, E06.2 c6), one per channel: an
/// open of that channel takes it ([take]) instead of taking a second grant
/// and socket. A control nobody takes is closed after [unclaimedLifetime]
/// (a room left or switched before it played, a toolbox lookup), so a
/// probe never leaves a control seat behind for long; a newer control of
/// the same channel replaces it at once.
final class Fc2ControlPool {
  /// Creates an empty pool; [timer] is injectable for tests.
  new({this.unclaimedLifetime = const Duration(seconds: 20), Timer Function(Duration, void Function())? timer})
    : _timer = timer ?? Timer.new;

  /// The pool of [site]'s probes, made on first use: what the app's
  /// `probeControl` of [site] fills and every [Fc2RecipeOpener] of [site]
  /// (playback, recording) takes from.
  factory of(Fc2LiveSite site) => _pools[site] ??= Fc2ControlPool();

  static final Expando<Fc2ControlPool> _pools = Expando('FC2 control pools');

  /// How long a control waits for an open of its channel.
  final Duration unclaimedLifetime;

  final Timer Function(Duration, void Function()) _timer;
  final Map<String, ({Fc2LiveControl control, Timer expiry})> _held = {};

  /// Controls waiting (tests).
  int get length => _held.length;

  /// Keeps [control] for the next open of its channel; the pool owns it
  /// until then. Any quality plays from it: the probe opened it for `auto`,
  /// and its playlists hold every tier ([Fc2LiveApi.playlistFor]).
  void adopt(Fc2LiveControl control) {
    final channel = control.channelId;
    final previous = _held.remove(channel);
    previous?.expiry.cancel();
    if (previous != null && !identical(previous.control, control)) unawaited(previous.control.close());
    if (control.isClosed) return;
    late final Timer expiry;
    expiry = _timer(unclaimedLifetime, () {
      if (!identical(_held[channel]?.expiry, expiry)) return;
      _held.remove(channel);
      unawaited(control.close());
    });
    _held[channel] = (control: control, expiry: expiry);
    // A control that ends while it waits (the grant expired, the socket
    // dropped) leaves at once.
    unawaited(
      control.done.then((_) {
        if (!identical(_held[channel]?.control, control)) return;
        _held.remove(channel)?.expiry.cancel();
      }),
    );
  }

  /// The control kept for [channelId], now the caller's; null when there
  /// is none or it has ended meanwhile.
  Fc2LiveControl? take(String channelId) {
    final held = _held.remove(channelId);
    if (held == null) return null;
    held.expiry.cancel();
    return held.control.isClosed ? null : held.control;
  }

  /// Closes every control kept.
  Future<void> close() async {
    final held = _held.values.toList();
    _held.clear();
    for (final entry in held) {
      entry.expiry.cancel();
    }
    await Future.wait([for (final entry in held) entry.control.close()]);
  }
}

/// FC2 (3.x's `Fc2PlaybackInput`): a control held while the playlist is
/// played; the input stops being usable when the control ends. The
/// control is the one the quality probe handed to [pool] for the channel
/// when there is one (notes "FC2 control sharing"), else a control of its
/// own ([Fc2LiveSite.openControl]).
final class Fc2RecipeOpener implements RecipeOpener {
  /// Creates the opener; [pool] defaults to [site]'s ([Fc2ControlPool.of]).
  new(this.site, {Fc2ControlPool? pool}) : pool = pool ?? Fc2ControlPool.of(site);

  /// The platform adapter.
  final Fc2LiveSite site;

  /// Where the probes' controls wait for an open of their channel.
  final Fc2ControlPool pool;

  /// Lets the next open of [control]'s channel use it, whatever the quality
  /// ([Fc2ControlPool.adopt]).
  void adopt(Fc2LiveControl control) => pool.adopt(control);

  @override
  bool handles(LiveInputRecipe recipe) => recipe is Fc2LiveInputRecipe;

  @override
  Future<OwnedInput> open(LiveInputRecipe recipe, LoopbackRelay relay, {CancelToken? cancel}) async {
    final fc2 = recipe as Fc2LiveInputRecipe;
    final control =
        pool.take(fc2.channelId) ?? await site.openControl(fc2.channelId, cancel: cancel, quality: fc2.quality);
    try {
      _checkCancelled(site.id, cancel);
      // A probe's control is `auto`: the recipe's tier is read from its
      // playlists (the same answer as a control opened for that tier).
      final playlist = Fc2LiveApi.playlistFor(control.playlists, fc2.quality)?.url ?? control.playlist;
      final line = LivePlayLine(
        playlist.toString(),
        headers: control.mediaHeaders,
        format: StreamFormat.hls,
        lineId: playlist.host,
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
