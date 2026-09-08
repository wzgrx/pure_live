# Huajiao H5 response fixtures

Derived from anonymous official H5 responses captured on 2026-09-08. Raw files
and request/status/hash records remain in ignored local artifacts under
`local-artifacts/huajiao-public-20260908/`.

| Fixture | Raw source | Preserved contract |
| --- | --- | --- |
| directory.json | directory.body | Section feeds; integer identities; geographic point object; offset string; more boolean |
| broadcast.json | broadcast-info.body | Nested feed/author/live; empty title; public protocol; duplicate HLS plus distinct FLV; contradictory codec hints |
| empty-page.json | directory-page2.body | Empty rows with advancing offset and more=true |
| missing-broadcast.json | invalid-broadcast.body | Point-only feed with no author/type and null live |

Profiles, IDs, images, serials and signed media URLs are replaced by synthetic
values. Unused profile data is omitted. The zero-coordinate object in directory
is retained from the response; it is not a payment or access-control field.
Fixtures prove parsing, not live availability, native decoding or playback.
