import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// What to tell the user about a failure: the UI decides by type, never by
/// message text (ADR 0010, rule 6; principles rule 3).
({String title, String message, bool retryable}) describeError(Object error) => switch (error) {
  NotFound(site: 'iptv') => (title: t.errors.channelMissing, message: t.errors.channelMissingDetail, retryable: false),
  NotFound() => (title: t.errors.roomMissing, message: t.errors.roomMissingDetail, retryable: false),
  NeedsLogin() => (title: t.errors.needsLogin, message: t.errors.needsLoginDetail, retryable: false),
  RateLimited() => (title: t.errors.rateLimited, message: t.errors.rateLimitedDetail, retryable: true),
  RiskControl() => (title: t.errors.riskControl, message: t.errors.riskControlDetail, retryable: true),
  RegionBlocked() => (title: t.errors.regionBlocked, message: t.errors.regionBlockedDetail, retryable: false),
  StreamUnavailable() => (title: t.errors.noStream, message: t.errors.noStreamDetail, retryable: true),
  UnsupportedLink() => (title: t.errors.unsupportedLink, message: t.errors.unsupportedLinkDetail, retryable: false),
  ApiChanged() => (title: t.errors.apiChanged, message: t.errors.apiChangedDetail, retryable: true),
  NetworkFailure() || TransportFailure() => (title: t.errors.network, message: t.errors.networkDetail, retryable: true),
  // F-FAV-08: follows and history of other platforms stay; they just cannot open.
  PlatformUnsupported(:final platform) => (
    title: t.errors.platformUnsupported,
    message: t.errors.platformUnsupportedDetail(name: platformName(platform)),
    retryable: false,
  ),
  _ => (title: t.errors.generic, message: '$error', retryable: true),
};
