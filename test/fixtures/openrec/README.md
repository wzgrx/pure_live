# OPENREC / mellow-fan v5 fixtures

Minimized from the 2026-09-08 UTC anonymous public API captures; see
[the contract audit](../../../docs/OPENREC_API_AUDIT_2026_09_09.md).

- `movie.json`: live movie fields, current/future end time, nullable media,
  three HLS source families, restriction flags and embedded channel identity.
- `channel-live.json`: channel envelope with its current broadcast.
- `channel-offline.json`: explicit `is_live=false`, empty current broadcast list.
- `directory.json` / `empty-page.json`: array envelopes; directory uses the
  minimized movie structure shared with the detail contract.

Public IDs, numeric IDs, names, titles, images and media paths are replaced.
`registered_user_id` intentionally remains a boolean. Source URLs are fixture
paths, not live playback links. No credentials or original profile text are kept.
Synthetic field mutations in tests exercise restrictions, schema damage,
multiple broadcasts and races; they do not claim those scenarios were observed
on the sample channel.

The service returned two rows for a request with `limit=1`; the API treats the
requested count only as a hint. Only an empty raw page ends pagination, not the
post-filter card count or a comparison with the requested limit.
