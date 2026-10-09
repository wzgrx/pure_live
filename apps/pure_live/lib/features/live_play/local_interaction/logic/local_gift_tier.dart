import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';

/// The three effects of a local gift (D08.5 c1), by the price of one (not
/// by the platform, not by a combo's total, so a banner keeps its tier
/// while its count goes up):
///
/// - [small] (below [LocalCatalog.giftTierMedium]): one line flies over the
///   top of the picture from right to left;
/// - [medium] (up to [LocalCatalog.giftTierBig]): the banner in the middle,
///   as before D08.5;
/// - [big] (from [LocalCatalog.giftTierBig], or a gift marked big): the
///   bigger banner, with a vehicle (a rocket, a jet, a meteor) crossing the
///   picture behind it for 2.6 s.
///
/// [duration] is how long the effect holds the gift layer (the banner
/// queue's time, D08.4): the line needs 4 s to cross a landscape picture
/// slowly enough to read in the middle; the vehicle's banner stays 4 s, so
/// it is still up 1.4 s after the vehicle left.
enum LocalGiftTier {
  /// The line over the top of the picture.
  small(Duration(seconds: 4)),

  /// The banner (3.x's 3 s).
  medium(Duration(seconds: 3)),

  /// The bigger banner and a vehicle.
  big(Duration(seconds: 4));

  new(this.duration);

  /// How long the effect holds the gift layer.
  final Duration duration;

  /// The tier of a gift costing [price] each, marked [big] or not. An
  /// unknown price (0: a message from before D08.4 carried none) keeps the
  /// banner it had.
  static LocalGiftTier of({required int price, bool big = false}) {
    if (big || price >= LocalCatalog.giftTierBig) return LocalGiftTier.big;
    if (price >= LocalCatalog.giftTierMedium || price <= 0) return medium;
    return small;
  }

  /// The tier of [gift].
  static LocalGiftTier ofGift(LocalGift gift) => of(price: gift.price, big: gift.big);
}

/// Which local gifts show their effect (D08.5 c2, "显示本地礼物特效"):
/// [all], [bigOnly] or none ([off]); the others only join the chat list.
enum LocalGiftEffectLevel {
  /// Every gift (the switch on, as before D08.5).
  all('all'),

  /// Only the [LocalGiftTier.big] gifts.
  bigOnly('bigOnly'),

  /// None (the switch off).
  off('off');

  new(this.id);

  /// The stored value (`localInteraction.giftEffectLevel`).
  final String id;

  /// The level stored as [id]; [all] for anything else.
  static LocalGiftEffectLevel parse(String id) => switch (id) {
    'bigOnly' => bigOnly,
    'off' => off,
    _ => all,
  };

  /// Whether a gift of [tier] shows its effect.
  bool shows(LocalGiftTier tier) => switch (this) {
    all => true,
    bigOnly => tier == LocalGiftTier.big,
    off => false,
  };
}
