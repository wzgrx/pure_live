# Bigo public metadata fixtures

Source: anonymous requests through the configured local Clash proxy on 2026-09-09.
`directory.json` retains the observed nested `code → data.resCode → data.data`
envelope and int64 broadcast representation; values, names and images are replaced.
`studio-login.json` retains the observed `needLogin=true`, `alive=0`, empty media,
empty `siteId` and separately populated `clientBigoId` shape. The public requested
alias and returned canonical alias can differ while `uid` still matches directory
`owner`.

The official player checks `needLogin` before interpreting `alive` or sources.
Tests setting gates false, paid/password flags, malformed fields or alive=1 are
synthetic boundary cases, not evidence of current anonymous media availability.
No live media contract, complete source list, recording or native playback is
claimed by these fixtures. API implementation is not yet registered as a LiveSite.
Raw responses, official JS and hashes stay in ignored local artifacts.

The public directory also returned null cover_m on 2 of 20 rows. A null cover remains unknown; a non-string non-null cover is malformed. The unit regression mutates only this optional field.
