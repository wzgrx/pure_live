import 'package:live_cli/src/fixture/scrub.dart';

const ScrubRule _secret = ScrubRule.secret;

/// Picarto: spec/sites/picarto.md §11 "需要脱敏的字段".
///
/// Channels (ids, names, titles, avatars, descriptions, social links) are
/// public and stay (ADR 0009 rule 4). Explore rows carry the IP address of
/// the channel's ingest origin (`origin`, not the load balancer's edge name
/// under `getLoadBalancerUrl`), and the chat JWT is a signed token: both
/// replaced.
const ScrubRules picartoRules = ScrubRules(
  jsonPaths: {r'$.data[*].origin': _secret, r'$.data.generateJwtToken.key': _secret},
);
