# live_player

The Flutter half of Pure Live v4 playback (ADR 0015). It binds
`live_media`'s `PlayerEngine` to mpv through the self-maintained media_kit
fork in `third_party/` (ADR 0002) and provides the single video surface. mpv
is the only engine on every platform (ADR 0006). Native libraries come from
media_kit's build hook (`third_party/media_kit/hook/native_bundles.json`);
there are no `media_kit_libs_*` packages.

## API

- `MpvEngine.create({MpvEngineConfig config})` creates a media_kit `Player`
  and `VideoController` and applies the live property set.
  `mpvEngineFactory(config)` is the `EngineFactory` to hand to
  `PlaybackSession`.
- `MpvEngineConfig`: hardware decoding (default `auto-safe`),
  Android compatibility mode (`mediacodec_embed` + `mediacodec`, SURF-6), low
  latency, `httpProxy` for CDN URLs, `audioOutput`.
- `LiveVideoView(session:, fit:, occluded:, background:)` is the one video
  surface per session (SURF-5): move it between layouts with a `GlobalKey`,
  since a second view of the same session fails an assertion in debug builds.
  Fit is `VideoFit.contain`, `cover` or `fill`. The view is black with sharp
  corners.
- `PlaybackStateNotifier(session)` is a `ValueListenable<PlaybackState>` for
  simple widgets.
- `MediaKitEventMapper` and `videoOutputSize` are public for tests and
  multiview sizing.

```dart
final session = PlaybackSession(engine: mpvEngineFactory());
await session.open(PlaybackRequest.room(site as StreamSource, detail));
// build:
LiveVideoView(key: videoKey, session: session, fit: VideoFit.contain);
// quality/line menus: session.state.qualities / lines, then
await session.selectQuality(q);
await session.selectLine(lineId);
// leaving the room:
await session.close();      // soft stop; engine released after 45 s idle
await session.dispose();    // when the player itself goes away
```

`main()` must have a Flutter binding before the first open;
`MpvEngine.create` calls `MediaKit.ensureInitialized()`.

## mpv options

Applied once per player (`MpvEngineConfig.liveProperties`, spec PERF-3,
PERF-4):

| Property | Value | Why |
|---|---|---|
| `demuxer-lavf-probesize` | 2 MiB (512 KiB low latency) | short probe for live FLV/HLS |
| `demuxer-lavf-analyzeduration` | 2 s (1 s) | first frame sooner |
| `network-timeout` | 15 s | a dead connection ends as `completed` (EVT-15) |
| `hwdec-software-fallback` | 1 | leave a failing hardware decoder after one frame |
| `force-seekable` | yes | the demuxer cache stays usable on live input |
| `cache` / `cache-on-disk` | yes / no | memory only |
| `cache-secs` | 6 s (2 s) | bounded readahead |
| `demuxer-max-bytes` / `-back-bytes` | 32 MiB / 4 MiB | memory stays flat over hours |
| `demuxer-readahead-secs` | 2 s (1 s) | |
| `protocol_whitelist` | http(s), tls, tcp, httpproxy, … | |

Set per open: `http-proxy` (empty for loopback relay inputs, SRC-3, otherwise
`MpvEngineConfig.httpProxy`) and `hwdec` (`no` for the session's software
retry, REC-1 step 4). Request headers (User-Agent, Referer, Cookie) travel
with the media through media_kit's `on_load` hook as `http-header-fields`.
The low-latency values are provisional until they are measured on devices
(spec §12 item 6).

## Events

`MediaKitEventMapper` turns media_kit's `playing`, `completed`, `buffering`,
`position`, `duration`, `tracks`, `videoParams` and error-level `log` streams,
plus the patched `frameRevision` on Windows, into one `EngineEvent` stream in
arrival order. That is the order the `fixtures/player` traces record, since
media_kit adds each mpv event in its own turn. A burst of adds across its
separate broadcast controllers would be delivered round-robin, so tests feed
one event per turn.

## Platform notes

- Android: audio-only mode goes through the patched
  `VideoController.setVideoOutputEnabled` (the controller owns `vid` and the
  Surface). `vid=auto` is never re-sent after an open (EVT-9). An occluded
  view stays mounted offstage (SURF-4).
- Windows: frame progress feeds the frame watchdog. An occluded view drops
  the texture and forces the output size when it comes back (SURF-1). The
  native output follows the displayed size, debounced 180 ms (PERF-1; also
  on Linux and macOS).
- Disposal waits for media_kit's release, which runs the fork's Windows
  teardown order (SURF-2).

## Tests

`flutter test` covers the event mapping with fake media_kit streams, the
property set, output sizing and the view's single-surface rule. They need no
libmpv. Real playback is verified on devices.
