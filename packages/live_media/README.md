# live_media

Playback core of Pure Live v4, in pure Dart (ADR 0015): the player engine
contract, the loopback relay that splices leased FLV streams, and the playback
session state machine. Behaviour follows `spec/modules/playback.md`; section
and rule ids (SES-3, EVT-14, REC-2…) are quoted in the code.

`live_player` implements the engine with media_kit/mpv; `tools/live_cli`
uses the relay directly (`live_cli lease`).

## Engine contract (`src/engine/`)

- `PlayerEngine`: `open(EngineMedia)`, `play`, `pause`, `stop`, `setVolume`,
  `setAudioOnly`, `dispose`, and one broadcast `events` stream of sealed
  `EngineEvent`s: `EnginePlaying`, `EngineCompleted`, `EngineBuffering`,
  `EnginePosition`, `EngineDuration`, `EngineVideoSize`, `EngineTracks`,
  `EngineFrame` (only with `EngineCapabilities.frameProgress`) and
  `EngineError` (error-level mpv diagnostics that pass
  `isActionableDiagnostic`, EVT-7).
- Events come in media_kit's real order. The recorded traces in
  `fixtures/player/` are the contract; `test/engine_contract_test.dart`
  asserts EVT-13 to EVT-19 on them. The known trap: at the end of a stream
  `playing=false` arrives before `completed=true` (EVT-1, EVT-14).
- `classifyDiagnostic` maps a diagnostic to a `DiagnosticKind` (EVT-12):
  lifecycle, video output, decoder init, transport and open failures are
  terminal at once; runtime decoder/source problems are watched for 1.2 s.
- `FakeEngine` (`package:live_media/testing.dart`) replays a recorded
  `EngineTrace` as commands arrive, or emits the recorded sequences through
  scenario helpers (`startStreaming`, `endOfStream`, `networkTimeout`,
  `failNextOpen`…). It never invents an order.

## Relay (`src/relay/`)

- `SourcePipeline.open(line, site:, renew:)` picks the pipeline (SRC-2):
  `splice` for an FLV line whose `Lease.cutsConnection` is true (Douyu
  `expire`), `direct` for everything else. Codec-12 HEVC rewriting and the
  HLS relay are not built: v4 libmpv ships FFmpeg 9 on Android/Linux (the
  Windows build is unconfirmed) and no v4 platform produces an HLS query
  policy (spec §12 items 1–2).
- `LoopbackRelay` binds 127.0.0.1 only and serves each input on a random
  24-character path that stops working when the input closes (SRC-4).
  Upstream requests use `dart:io` with TLS verification, the line's headers,
  the `ProxyPolicy` route and a 15 s read idle timeout. The downstream
  response is unbuffered (`bufferOutput = false`); a buffered dart:io response
  holds the body until close even after `flush()`.
- `FlvSplicer` (SRC-5) keeps one output timeline across renewals:
  1. At `lease.refreshAt` it calls the renewer (the app passes
     `StreamSource.streams` for the same quality and line) and connects the
     new URL while the old connection keeps being forwarded.
  2. Once the new connection is scanning, the old stream is held just
     before its next keyframe (at most 10 s). Both connections sit at the
     live edge, so otherwise the old one usually delivers the shared keyframe
     first and the switch slips a GOP or past the cut; the real-socket test
     caught this.
  3. The switch point is the first new keyframe beyond the delivered video
     timestamp. Old tags are forwarded up to it and the new connection takes
     over from it: no gap, no repeat. Video/audio configurations are re-sent
     only when they change; script tags are not repeated.
  4. A new connection more than 60 s off the delivered timeline is shifted to
     continue it. If the old connection ends first, the splicer renews at once
     and skips at most one GOP. A failed renewal keeps the old connection and
     retries every 10 s; if the old one ends with no successor, the output
     ends and the session's recovery takes over.

## Session (`src/session/`)

`PlaybackSession` covers spec §1–§3 and §5–§8:

- Native commands run one at a time; every user command bumps the intent
  revision at once, and queued or in-flight work that sees a newer revision
  gives up (SES-2, INT-5, REC-4). The engine is created on the first open,
  soft-stopped on close and released 45 s later (SES-1, SES-7).
- Each open, refresh, line switch or rebuild is a new source generation with
  a reset engine mirror (EVT-10). Errors arriving while an open is in flight
  are held and handled afterwards (EVT-5); the same text is reported once per
  2 s within a generation (EVT-6).
- Watchdogs (§5): open 18 s, buffering 12 s with one deadline per episode
  (EVT-3), unexpected pause 350 ms → play() → 5 s, frame stall 10 s (only
  with frame progress, visible, not audio-only), unexpected `completed` on a
  live stream right away.
- Recovery (REC-1): refresh (twice; the second moves to the next line and
  the first may use an unexpired prefetch), line switch, one same-engine
  rebuild, one software-decoding retry per URL, backoff 750 ms and 2 s, then
  a terminal error. A round ends after 30 s of healthy play; at most 2 rounds
  may start in 3 minutes (REC-2). Quality and line survive refreshes (REC-3).
  A resolve that says the room is offline (`SiteError` not transient) ends at
  once.
- Failure classes: `liveCompleted` and `bufferingStall` count as both
  transport and stall failures. EVT-15/EVT-16 show that both are how
  network cuts look, so refresh, line switch and backoff apply as well as
  the rebuild the spec lists for stalls.
- Leases (SRC-6): a relayed input renews itself. A lease that does not cut
  the connection is only prefetched at `refreshAt` (off the serial queue,
  retried after 10 s) and used by the next refresh.
- Audio only (§7): switched in place with the last request winning. A switch
  still running after 5 s is rolled back, reported in
  `PlaybackState.notice`, and does not enter recovery.
- Geometry (§8): `GeometryTracker` merges sizes in fixed 120 ms windows and
  commits after 3 samples or 500 ms, with hysteresis.

Not covered yet: the first-frame-fenced handover for leases of unknown kind
(no v4 platform produces one), candidate players for rebuilds, background
policy timing (INT-3, app level), PiP and the mini window (§9, app level),
and multiview scheduling (PERF-5).

## Driving a session

```dart
final session = PlaybackSession(engine: () => MpvEngine.create());   // live_player
await session.open(PlaybackRequest.room(douyu, detail));               // StreamSource + RoomDetail
session.states.listen(render);                                         // PlaybackState
await session.selectQuality(quality);
await session.selectLine('hs-h5');
final token = session.suspend(SuspendReason.background);
session.resume(token);
await session.close();                                                 // soft stop; released after 45 s
await session.dispose();
```

## Tests

`dart test` runs the FLV framer, the splicer on synthetic streams under a
fake clock, the relay over real loopback sockets, the recorded-trace
contract and the session scenarios under `fake_async`. The real-network
check is `dart run tools/live_cli/bin/live_cli.dart lease douyu <room>`.
