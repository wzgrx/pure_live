# live_ui

Design system of Pure Live v4 (`spec/design/principles.md`): theme tokens,
window classes, adaptive navigation, shared components, and the on-video
danmaku layer. Flutter only; it depends on no other `live_*` package
(`tools/gate/check_deps.py`), so the app maps its models to the small input
types here.

## Danmaku layer (`src/danmaku/`)

Behaviour follows `spec/modules/danmaku.md` §5 (REN-1 to REN-9) and the
budgets of PLAN §10; rule ids are quoted in the code.

### Using it

```dart
// One controller per surface (room, PiP/mini window, focused multiview cell).
final danmaku = DanmakuController(
  style: DanmakuStyle(
    fontSize: settings.get(Settings.danmakuFontSize),
    fontWeight: settings.get(Settings.danmakuFontWeight),
    opacity: settings.get(Settings.danmakuOpacity),
    speed: settings.get(Settings.danmakuSpeed),          // logical px/s
    area: settings.get(Settings.danmakuArea),
    topMargin: settings.get(Settings.danmakuTopArea),
    bottomMargin: settings.get(Settings.danmakuBottomArea),
    stroke: settings.get(Settings.danmakuStroke),
    strokeWidth: settings.get(Settings.danmakuStrokeWidth),
    noEmoji: settings.get(Settings.danmakuNoEmoji),
  ),
  budget: const DanmakuBudget().withFps(resolvedFps),   // null follows the display
);

// Above the video, below the controls.
Stack(children: [video, Positioned.fill(child: DanmakuView(controller: danmaku)), controls]);

// Each batch of the chat pipeline (only chat, and only while playing: REN-7).
danmaku.addAll(batch.chats.map((m) => DanmakuItem(m.text, color: m.color, data: m)));
danmaku.add(DanmakuItem(echo.text, isLocal: true));     // own echo: never dropped

danmaku.pause(#video);  danmaku.resume(#video);         // positions freeze
danmaku.pause(#menu);   danmaku.resume(#menu);          // REN-8 action menu; reasons stack
danmaku.style = danmaku.style.copyWith(opacity: 0.6);   // applies on screen, also while paused
danmaku.budget = const DanmakuBudget.pip();             // when the surface shrinks
danmaku.clear();                                        // room change, danmaku off

// Tap/long-press on the video: the layer never takes pointers.
final hit = danmaku.itemAtGlobal(details.globalPosition); // hit?.item.data is the chat message
```

`DanmakuStyle.pip()` and `DanmakuBudget.pip()` hold the REN-6 PiP defaults
(font 12, area 50%, 90 px/s; 6 on screen, one per 350 ms, 30 fps). The
automatic frame-rate policy (REN-3) lives in the app, which knows the refresh
mode; it passes the result as `DanmakuBudget.fps`.

### How it works

- **One render box, one canvas** (REN-1). `DanmakuView` builds a leaf
  `RenderBox` that is its own repaint boundary, so neither the video nor the
  controls repaint with it. Scrolling items are drawn first, then top and
  bottom items. Everything is clipped to the view with a hard-edged rectangle,
  so a video narrower than the window does not leak text onto the chat
  panel. The box never hit-tests and never takes focus (KEY-1).
- **Engine and controller.** `DanmakuEngine` (internal) holds the queues,
  lanes, on-screen items and the text cache, and gets time only through
  `step(seconds)`. Tests and the benchmark drive it with simulated frames.
  `DanmakuController` connects it to a `Ticker` that the view provides.
- **Time, not frames** (REN-2). Motion is `speed × elapsed` in logical px/s,
  the same in every orientation and on desktop (REN-5). `DanmakuFrameClock`
  follows the display, or skips vsyncs with an accumulator below the display
  rate. One step covers at most three frame intervals, so a stall slows the
  layer for a moment instead of making it jump.
- **No idle work** (REN-2, REG-DANMAKU-011). The ticker runs only while
  something is on screen or waiting, and not while paused. A frame that
  changes nothing is not repainted. When the view is unmounted the ticker
  stops and every laid-out text is freed at once (REN-9). Moving the view with
  a `GlobalKey` keeps the items. A new view given the same controller takes
  over from the old one.
- **Lanes** (REN-5). Lane height is font size × 1.55, kept within 24–64. The
  count is the height between the insets (safe area plus margins), times the
  area share applied exactly once (REG-DANMAKU-010), divided by the lane
  height. Every scrolling item moves at the same speed, so an item can never
  catch the one ahead of it. A lane is free once its last item has fully
  entered, plus one character of gap. New items take the topmost free lane.
  Top items stack down from the top. Bottom items stack up from the bottom
  of the area, so a reduced area keeps the lower part of the picture clear.
  Fixed items are centered and hold their lane until they expire (4 s by
  default).
- **Resizing** (fullscreen, rotation, window drag). Lanes are recomputed.
  Scrolling items keep their x and lane and continue moving from there.
  Fixed items re-center. Items in lanes that no longer exist finish their run.
- **Budget** (REN-4). Adding an item costs nothing beyond a queue entry:
  text is laid out only when an item is admitted to the screen. Admissions
  use a token bucket: on average one per `emitInterval` (50 ms), and never
  more than `maxEmitPerFrame` (2) in a frame. At most `maxVisible` (48)
  items are on screen. At most `maxPending` (120) wait; beyond that the
  oldest is dropped, and an item that waits over 5 s is dropped too. A batch
  larger than the queue is sampled evenly across its whole span (SMP-2). The
  result: under load the density drops, never the frame rate. `isLocal`
  items bypass all of this, jump the queue, and take the roomiest lane when
  none is free.
- **Text** (principles §7 item 10). Each distinct text and color is laid out
  once into `ui.Paragraph`s: the fill and, when enabled, a stroke outline.
  The outline is light for dark text. These paragraphs are drawn every frame.
  Identical texts ("666") share one layout through an LRU cache of
  `glyphCacheSize` (96). Cached layouts are reference counted, so a layout
  evicted while still on screen is freed only when its last item leaves.
  Opacity goes into the color's alpha; there is no opacity layer and no blur.
- **Style changes** apply to items already on screen (principle 3), also
  while paused. A change that affects glyphs clears the cache and lays out
  the on-screen items again in the next frame; this is the one case that
  exceeds the per-frame layout cap, and only the user can trigger it. Speed
  changes apply to moving items at once.
- **No-emoji mode.** Strips Unicode pictographs together with their
  modifiers, joiners, flags and keycaps; an emoji-only message is not shown.
  Platform image emoticons (`[doge]`) are still text here (spec §8 item 6).

### Tests

- `test/danmaku/danmaku_lanes_test.dart`: lane math, collision freedom,
  fixed lanes, even sampling.
- `test/danmaku/danmaku_text_test.dart`: display text and emoji stripping,
  glyph metrics, cache eviction and reference counting.
- `test/danmaku/danmaku_engine_test.dart`: fps-independent motion, the frame
  clock, collisions and area bounds, fixed items, every budget rule, local
  items, style and geometry changes, hit testing, release.
- `test/danmaku/danmaku_view_test.dart`: widget tests for painting, the
  ticker stopping when empty (no idle frames or paints), elapsed-time motion,
  a lower fps, pause with stacked reasons, a restyle while paused, resize,
  safe area, pointer pass-through with `itemAtGlobal`, unmount, `GlobalKey`
  moves, a controller swap, and clear.
- `test/danmaku/danmaku_benchmark_test.dart`: 2000 items over 60 simulated
  seconds, 200 items/s at 120 fps, and the PiP budget. On every frame it
  asserts layouts ≤ admissions ≤ 2 and the on-screen and waiting caps, and it
  prints frame-time percentiles. On-device frame budgets (≤ 3 ms of main
  thread per frame, P90 ≤ 8 ms) belong to the K90 performance suite.

### Open points

- REN-8's "ignore a tap within 1 s of a long press" and the menu belong to
  the app's gesture layer. This package provides `itemAt` /
  `itemAtGlobal` and pause reasons.
- Per-item font size or stroke for local messages (spec §1) is not
  supported: every item uses the surface style.
- A raster (`Image`) cache per glyph would make each frame's raster work a
  textured quad per item. Add it only if the K90 suite shows paragraph
  drawing as the cost.
