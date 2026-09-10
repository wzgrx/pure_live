# Weibo metadata fixtures

Captured 2026-09-10 from the official anonymous PC recommendation and room-detail endpoints, through DIRECT HTTP. These are sanitized contract fixtures, not playable samples.

- `recommend.json`: first two rows of an actual 9-row recommendation snapshot requested with count=10. Broadcast IDs, UIDs, names and images replaced. No invented pagination or viewer counts.
- `live-detail.json`: actual status=1/watch_limit=0/play_switch=1 response, retaining field types and dimensions. Both HLS-labelled and FLV-labelled fields contained the same FLV URL; replaced with an inert example.test URL. Identity, post ID, title and images replaced; image signatures removed.
- `detail.json`: actual missing-user response for an older official indexed watch link. This is an API error, not confirmed offline status.

Status=3, unusual state, disabled playback and restricted/trial branches in the tests are synthetic mutations guided by the official player bundle. They are not captured current examples of those branches. No personal session, media credentials or raw HTTP captures are committed.
