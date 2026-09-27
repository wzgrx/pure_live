# Claude Code guidance

[AGENTS.md](AGENTS.md) is the repository entrypoint.

- The v4 plan is approved and Claude makes the remaining choices: record each lasting one in `docs/adr/`, update `docs/rewrite/STATUS.md` as phases move, and follow `spec/constitution.md`.
- 3.x is archived in `legacy/` and never built (ADR 0014, ADR 0016).
- Build locally, never on GitHub Actions (its minutes are used up): Android in WSL, Windows on the Windows host. Run `tools/gate/gate.sh --all` before every push.
- WSL environment: `source ~/tools/purelive-env.sh` (Flutter 3.47.5, JDK 27, Android SDK with NDK 30; versions in `toolchain.env`). `ANDROID_USER_HOME` holds a copy of the Windows debug keystore so WSL builds overwrite-install Windows builds. One heavy task at a time (WSL: 15 cores, 125 GB RAM).
- `gh` defaults to the upstream repository; always pass `--repo wzgrx/pure_live`.
