# TTing/FLEX response fixtures

Derived from the anonymous official responses recorded on 2026-09-09 in
`docs/TTING_PUBLIC_CONTRACT_AUDIT_2026_09_09.md`:

- `profile.json`: `/api/channels/{channelId}/profile`.
- `stream.json`: `/api/channels/{channelId}/stream?option=all`, NCP family.
- `directory.json`: one card from `/api/channels/live-list-main?includeAdult=false&liveOption=total`.

Channel/owner/broadcast IDs are replaced by 101/202/303; names, titles and image
addresses are synthetic. Signed media URLs use a fixture NCP subdomain and a
non-working `hmac=fixture`; the expiry is fixed for deterministic clock tests.
The tests preserve the observed flag types, nesting and four resolutions.
Directory owner has no numeric ID in the observed response; the parser must
obtain that identity from profile rather than inventing it from the card.
Unrelated profile/account/presentation fields are omitted.

The later public sample used NCP low-latency (`ncp_llh`). Its source-family
contract and rejection of mismatched families are represented by a test
transformation of the same structural fixture; original responses and HLS
master/media lists remain in ignored local artifacts, not checked in with
temporary signed URLs. Neither fixture nor successful parsing proves native
decoding or a completed recording.
