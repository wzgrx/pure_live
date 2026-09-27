# Pure Live v4 repository guidance

Pure Live is being rewritten as v4 on `master`. The 3.x app is archived in `legacy/` (ADR 0016): it is not built, not a workspace member and not maintained. Read it only when a spec points to it.

## Sources of truth

- Rules and accepted decisions: [spec/constitution.md](spec/constitution.md). Behaviour: `spec/` (product, sites, modules, design). When code and spec disagree, fix the spec first.
- Plan: [docs/rewrite/PLAN.md](docs/rewrite/PLAN.md). Progress: [docs/rewrite/STATUS.md](docs/rewrite/STATUS.md). Decisions: [docs/adr/](docs/adr/README.md); write a new ADR for every lasting choice.

## Layout

- `packages/`: `live_core` (models, adapters; pure Dart), `live_net` (HTTP; pure Dart), `live_danmaku` (chat protocols; pure Dart), `live_media` (engine interface, relay, playback session; pure Dart), `live_player` (media_kit binding; Flutter), `live_store` (drift storage; pure Dart), `live_ui` (design system; Flutter).
- `apps/pure_live`: the v4 app (package `pure_live_app`, Android id `com.mystyle.purelive.next` for previews).
- `tools/`: `live_cli` (probes, fixture capture), `check_latest`, `gate`.
- `fixtures/`: redacted platform samples (ADR 0009). `third_party/`: the media_kit fork (ADR 0002).
- Root `assets/version.json` and `assets/releases.json` serve installed 3.x apps' update check; change them only with a published release.

## Working rules

- Dependency direction is enforced by `tools/gate/check_deps.py`; pure-Dart packages never import Flutter.
- Toolchain and dependencies: latest official stable, pinned in `toolchain.env` and `pubspec.lock` (one lock at the root).
- Code style: very_good_analysis, page width 120, public API docs, Dart 3.13 primary constructors (`new(...)`). Tests next to every behaviour; test doubles follow the real library's event order.
- Gate: `bash tools/gate/gate.sh` while working, `bash tools/gate/gate.sh --all` before every push. Builds and gates run on the local machines (WSL for Android, Windows for Windows); GitHub Actions is manual only (ADR 0014).
- `master` is the only branch. Commit small verified steps and push them; never force-push. Bump versions only with a published release.
- Secrets and signing keys stay out of Git. Cookies are stored encrypted and never logged.
- Phone and device work needs the user's current explicit request and the shared-device lease (see `legacy/docs/ANDROID_DEVICE_TEST_ROTATION.md`); check the foreground app before every input.
- Report progress and results to the user in Chinese.
