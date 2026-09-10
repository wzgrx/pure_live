# Niconico watch-page fixtures

Observed through the user's local Clash proxy on 2026-09-10. These minimal
projections retain the types of program/status, watch conditions and frontend
bootstrap from four current watch pages: allowed ON_AIR, region-gated ON_AIR,
region-gated RELEASED, and ENDED with canWatch=false. IDs, title, broadcaster and
WebSocket token/path are synthetic. No real tokens, cookies or personal data
are included. Login and malformed cases in tests are synthetic mutations.

The program ID identifies one broadcast, not its broadcaster. watchCount is a
platform cumulative count, not concurrent audience. A WebSocket bootstrap is
not a media URL: an owned heartbeat/seat connection and path-scoped media cookies
are required separately. Raw responses remain in ignored local artifacts.
