# CC catalogue contract fixtures

These are reduced public configuration responses captured on 2026-09-07 at
23:42:16 UTC, before the separate Dashen browser attempt was denied. They are
parser inputs, not proof of browser or native application acceptance.

- `dashen-games.json`: GET
  `https://inf.ds.163.com/v1/web/game-center/basic/base-info-list/by-type?gameType=NETEASE`.
  Retains the response code and 106 appKey/name/icon records. Original SHA-256:
  `0f0553e29f695822fef83d2937b6259ef4b891e606d41cca5c67ebf1b2a7bad5`.
- `dashen-live-config.json`: POST
  `https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig`, JSON body
  `{"id":"67b32cdd1801fc391a6c2657"}`. Retains the response code, configuration
  identity/visibility and the live-entry group, including all 23 entries in
  response order. Removes unrelated configuration, timestamps and weights.
  Original SHA-256:
  `d8d86c33395ea8b8008827b3f599a351f163326991103e93d363f1ccda5bd4aa`.

Only 20 entries are category paths. Three are official room paths, two of which
have independently observed event redirects. Do not use the 106 metadata
records, legacy top navigation, or a room ID as a substitute category catalogue.
No cookies, account data, stream addresses or authentication material are included.

See `docs/CC_MIGRATION_AUDIT_2026_09_08.md` and
`docs/CC_CATALOG_INTEGRATION_AUDIT_2026_09_08.md` from the repository root.
