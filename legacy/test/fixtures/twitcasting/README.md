# TwitCasting contract fixtures

Derived from public website/API responses observed on 2026-09-07, starting 10:33 UTC, via the local Clash proxy. Raw responses stay in ignored `local-artifacts/twitcasting-20260907/`.

- `directory.json`: one normalized public movie from `frontendapi.twitcasting.tv/top/category?id=&count=60`. Preserve flag types and `current_viewer_count=2260`; replace public channel/title/images and normalize movie ID to 42. The actual sample had 54 rows; its single null current count belonged to an excluded group broadcast.
- `room.html`: only the metadata and profile selectors needed to establish channel identity and presentation. No scripts, anonymous CSRF or session state copied.
- `categories.html`: representative real top-bar category keys and the DOM contract from the homepage, not an invented complete taxonomy.
- `live-stream.json`: normalized movie 42 with observed high/medium/low path shapes. CDN host replaced with `edge.twitcasting.tv`; no credentials or media bytes.
- `offline-stream.json`: explicit `movie.live=false` with deliberately stale HLS for a DIFFERENT movie, matching the observed offline response. Movie IDs normalized to 41/900. Stale playback URLs must be ignored.

Reference contract: [biliup TwitCasting at 906e0f6f](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/twitcasting.rs). Dart implementation is independent; reference download/error defaults are not copied.
