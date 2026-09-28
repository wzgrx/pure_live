# live_ui

Design system of Pure Live v4 (`spec/design/principles.md`): theme tokens,
window classes, adaptive navigation, shared components, and the on-video
danmaku layer. Flutter only; it depends on no other `live_*` package
(`tools/gate/check_deps.py`), so the app maps its models to the small input
types here.

## Icons (`src/icons/`)

Principles §2.6: every icon is Material Symbols Rounded, a variable font
(`material_symbols_icons`, Apache-2.0), and the app names icons only by
meaning.

```dart
LiveIcon(LiveIcons.refresh)                        // an action
LiveIcon(LiveIcons.danmaku, filled: danmakuOn)     // a toggle: same glyph, fill 0 or 1
IconButton(isSelected: muted, icon: const LiveIcon(LiveIcons.mute),
    selectedIcon: const LiveIcon(LiveIcons.mute, filled: true), onPressed: toggle)
VideoControlIcons(size: VideoControlIcons.sizeFor(context, fullscreen: full), child: bar)
```

- **`LiveIcons`** is the whole set, one value per meaning (table below). The
  app never writes `Icons.*` or `Symbols.*`; a test in the app scans `lib/`
  for them.
- **`LiveIcon`** sets the axes. FILL 0, or 1 when `filled` (the current
  destination, danmaku on, followed, muted); a toggle never swaps glyphs.
  Weight and grade come from the nearest `IconTheme`: the theme gives weight
  400 and grade 0 on light, -25 on dark and pure black (`iconAxes`); a
  component that replaces the icon theme without them (the navigation rail)
  falls back to the theme's. The optical size is the size shown, clamped to
  20–48.
- **Sizes**: lists and toolbars 24 (`Sizes.iconMd`), dense information 20
  (`iconDense`), an icon beside a button's or chip's label 20 (the theme sets
  it; Material's 18 is below the smallest optical size), a state in the
  middle of a picture or a message view 40 or 48 (`iconXl`, `iconXxl`). An
  icon inside a text badge takes the text's size (the audience on a cover,
  12). TV: 32 (`iconLg`), 24 beside a label.
- **Controls on a picture**: `VideoControlIcons` gives weight 500 and grade 0
  in every theme (the controls look the same in every theme), white, 24 dp in
  compact and medium windows and 32 dp from the expanded width class on and
  in fullscreen (`sizeFor`).
- **Drawn glyphs**: where Symbols has none (弹幕), `drawn_glyphs.dart` draws
  one on the 24 dp grid, with the frame, corners and 2 dp stroke of Rounded,
  in both fill states. `symbolStroke` gives the stroke Symbols has at the
  same weight, grade and optical size (measured from the font), so a drawn
  glyph sits in a row of font glyphs at the same weight.
- **Framework icons**: the theme's `ActionIconThemeData` makes Material's own
  back, close and drawer buttons show `LiveIcon`s, and the segmented button's
  check is `LiveIcons.check`. `CheckedMenuItem` replaces
  `CheckedPopupMenuItem` (its check is fixed to Material Icons). Popup menu
  buttons get `LiveIcons.more`, expansion tiles a `LiveIcon` arrow and
  reorderable lists their own handles, since Material's defaults are
  Material Icons glyphs. The app screenshot tests fail when any Material
  Icons glyph is drawn.
- **Release size**: `flutter build` shrinks icon fonts to the glyphs the
  code names (icon tree shaking). The package references its Outlined and
  Sharp fonts once so that they shrink to a few kilobytes too. Flutter's
  subsetter once dropped the filled forms of variable icons
  (flutter/flutter#183381); `test/icon_subset_test.dart` runs the SDK's own
  `font-subset` on every glyph here and compares fill 0/1, grade 0/-25 and
  weight 400/500 against the whole font. Should it fail after an SDK update,
  building with `--no-tree-shake-icons` is the way out, at the price of the
  whole fonts: Rounded 15.1 MB, Outlined 10.6 MB, Sharp 8.8 MB and Material
  Icons 1.6 MB (36.2 MB, 16.2 MB deflated in an APK).

### Tests

- `test/live_icon_test.dart`: the axes in light, dark, pure black, TV, on the
  controls and inside the navigation rail; the optical size at every size;
  Material's back button; the stroke model against the font; the catalog
  (Rounded glyphs only, and this table in sync); the drawn glyph's geometry;
  goldens `goldens/icon_axes.png` (fill 0 and 1, grade 0 and -25, sizes, the
  controls) and `goldens/icon_catalog.png` (every icon, light and dark).
- `test/icon_subset_test.dart`: the release subsetter, above.

### The icons

The meaning column is the doc comment of each value. Glyph names are
Material Symbols names; the Rounded style is used throughout.

| Name | Glyph | Meaning |
|---|---|---|
| `follows` | `favorite` | 关注 tab; filled when current. |
| `discover` | `explore` | 发现 tab. |
| `search` | `search` | 搜索 tab and search fields; its fill is a plain magnifier. |
| `me` | `person` | 我的 tab. |
| `railExpand` | `menu` | Expands the navigation rail. |
| `railCollapse` | `menu_open` | Collapses the navigation rail. |
| `back` | `arrow_back` | Back. |
| `close` | `close` | Close, cancel, remove an entry. |
| `more` | `more_vert` | More actions. |
| `subpage` | `chevron_right` | A row that opens a page. |
| `expand` | `expand_more` | Shows more rows. |
| `collapse` | `expand_less` | Shows fewer rows. |
| `add` | `add` | Add. |
| `addEntry` | `add_circle` | An empty place to add something (a multi-view cell, a guide source). |
| `edit` | `edit` | Edit. |
| `delete` | `delete` | Delete. |
| `clearAll` | `delete_sweep` | Clear a whole list. |
| `check` | `check` | The chosen entry of a list. |
| `refresh` | `refresh` | Refresh. |
| `replay` | `replay` | Try again, watch back a programme. |
| `restore` | `restore` | Restore a backup, reset to the default. |
| `sort` | `sort` | Sort. |
| `selectAll` | `select_all` | Select everything shown. |
| `multiSelect` | `checklist` | Start multi-select. |
| `reorder` | `drag_handle` | Drag to reorder. |
| `copy` | `content_copy` | Copy. |
| `paste` | `content_paste` | Paste. |
| `share` | `share` | Share. |
| `link` | `link` | A link. |
| `linkOff` | `link_off` | A link that cannot be used. |
| `openSite` | `open_in_new` | Open the platform's site. |
| `openInApp` | `open_in_phone` | Open in the platform's app. |
| `newWindow` | `open_in_browser` | Open in a new window. |
| `download` | `download` | Download, export. |
| `importFile` | `upload_file` | Import a file. |
| `upload` | `cloud_upload` | Upload to a server. |
| `send` | `send` | Send. |
| `receive` | `download_for_offline` | Receive from another device. |
| `parentFolder` | `arrow_upward` | The folder above. |
| `folder` | `folder` | A folder, a follows group. |
| `folderOpen` | `folder_open` | Pick a folder. |
| `file` | `description` | A file. |
| `inbox` | `inbox` | Nothing here. |
| `history` | `history` | History. |
| `noResults` | `search_off` | Nothing found. |
| `webSearch` | `travel_explore` | Search the web. |
| `web` | `public` | A web page, a web login. |
| `webUnavailable` | `public_off` | Web pages cannot be shown here. |
| `voice` | `mic` | Voice input. |
| `showPassword` | `visibility` | Show the password; filled while it shows. |
| `key` | `vpn_key` | A key or password. |
| `qrCode` | `qr_code_2` | A QR code. |
| `help` | `help` | Help. |
| `info` | `info` | Information, 关于. |
| `tip` | `lightbulb` | A tip. |
| `error` | `error` | An error; filled on a status list. |
| `warning` | `warning` | A warning. |
| `success` | `check_circle` | Done, working; filled on a status list and for the chosen device. |
| `block` | `block` | Block a keyword. |
| `blockUser` | `person_off` | Block a user. |
| `savePreset` | `bookmark_add` | Save the danmaku settings as a preset. |
| `presets` | `bookmark` | Danmaku presets. |
| `follow` | `favorite` | Follow; filled when followed. |
| `unfollow` | `heart_broken` | Unfollow. |
| `star` | `star` | Star an area, the default platform; filled when starred. |
| `audience` | `person` | The audience of a room. |
| `multiview` | `grid_view` | 多画面, its layouts. |
| `roomList` | `format_list_bulleted` | A list of rooms. |
| `gift` | `card_giftcard` | A gift in the chat. |
| `scrollToLatest` | `arrow_downward` | Jump to the newest chat. |
| `play` | `play_arrow` | Play. |
| `pause` | `pause` | Pause. |
| `paused` | `pause_circle` | A paused picture. |
| `stop` | `stop` | Stop. |
| `danmaku` | drawn (`danmakuGlyph`) | 弹幕 on or off: filled when on. Drawn: Symbols has no danmaku glyph, and `subtitles` means captions. |
| `tune` | `tune` | Danmaku settings, the 通用 settings. |
| `quality` | `high_quality` | Quality and line. |
| `line` | `alt_route` | Line (CDN). |
| `volume` | `volume_up` | Volume. |
| `volumeDown` | `volume_down` | The low end of a volume slider. |
| `mute` | `volume_off` | Mute; filled while muted. |
| `fullscreen` | `fullscreen` | Enter fullscreen. |
| `fullscreenExit` | `fullscreen_exit` | Leave fullscreen. |
| `expandView` | `open_in_full` | Show larger (immersive multi-view, the room from the mini player). |
| `collapseView` | `close_fullscreen` | Show smaller (leave immersive multi-view or picture-in-picture). |
| `pip` | `picture_in_picture_alt` | Picture-in-picture. |
| `cast` | `cast` | Cast. |
| `casting` | `cast_connected` | Casting to a device. |
| `audioOnly` | `headphones` | Audio only; filled when on. |
| `chat` | `chat_bubble` | The chat over the fullscreen picture; filled when shown. |
| `chatPanel` | `view_sidebar` | The chat panel beside the picture; filled when shown. |
| `theater` | `crop_7_5` | Theatre mode; filled when on. |
| `lock` | `lock` | Lock the controls; filled while locked. |
| `switchRoom` | `swap_horiz` | Switch to another room. |
| `roomStep` | `swap_vert` | Switched to the room above or below. |
| `swipeRooms` | `swipe_vertical` | Swipe up or down to switch rooms. |
| `firstRoom` | `vertical_align_top` | The first room of the list. |
| `lastRoom` | `vertical_align_bottom` | The last room of the list. |
| `aspect` | `aspect_ratio` | Aspect ratio. |
| `orientation` | `screen_rotation_alt` | Orientation. |
| `rotate` | `screen_rotation` | Turn to landscape. |
| `fitPicture` | `fit_screen` | Show the whole picture. |
| `fillScreen` | `crop_portrait` | Fill the screen with the picture. |
| `brightness` | `brightness_medium` | Brightness. |
| `sleepTimer` | `bedtime` | Sleep timer. |
| `quit` | `exit_to_app` | Quit the app. |
| `screenshot` | `photo_camera` | Screenshot. |
| `shortcuts` | `keyboard` | Keyboard shortcuts. |
| `batteryFull` | `battery_full` | A full battery. |
| `batteryHigh` | `battery_5_bar` | A battery above 60%. |
| `batteryHalf` | `battery_3_bar` | A battery above 35%. |
| `batteryLow` | `battery_2_bar` | A battery above 15%. |
| `batteryAlert` | `battery_alert` | An almost empty battery. |
| `batteryCharging` | `battery_charging_full` | A charging battery. |
| `noPicture` | `tv_off` | A screen that shows nothing (the room is offline, no device found). |
| `offline` | `wifi_off` | No network. |
| `record` | `fiber_manual_record` | Record; filled while recording or booked. |
| `recording` | `radio_button_checked` | 录制, the settings group. |
| `schedule` | `schedule` | Waits for the room to go live; a time. |
| `stopTask` | `stop_circle` | Stop a task. |
| `recordingCenter` | `video_library` | The recording center. |
| `liveTv` | `live_tv` | IPTV, a channel on air. |
| `guide` | `event_note` | The programme guide. |
| `noProgrammes` | `event_busy` | No programmes. |
| `addPlaylist` | `playlist_add` | Add a playlist. |
| `sync` | `sync` | Synchronise. |
| `settings` | `settings` | Settings. |
| `appearance` | `palette` | 外观. |
| `playback` | `play_circle` | 播放. |
| `accounts` | `account_circle` | 账号. |
| `network` | `lan` | 网络. |
| `data` | `cloud_sync` | 数据与同步. |
| `tvMode` | `tv` | TV mode. |
| `alerts` | `notifications` | Live alerts; filled when on. |
| `backup` | `save` | Back up. |
| `cloud` | `cloud` | WebDAV, a playlist from the network. |
| `cloudOff` | `cloud_off` | No WebDAV account. |
| `testConnection` | `wifi_tethering` | Test a connection. |
| `lanSync` | `devices_other` | LAN sync, other devices. |
| `diagnostics` | `medical_information` | Diagnostics. |
| `debugLog` | `bug_report` | Debug logging. |
| `platformStatus` | `monitor_heart` | Platform status. |
| `clearCache` | `cleaning_services` | Clear the cache. |
| `sourceCode` | `code` | Source code. |
| `feedback` | `feedback` | Feedback. |
| `changelog` | `history_edu` | Changelog. |
| `licenses` | `gavel` | Licences. |
| `update` | `system_update` | Check for updates. |
| `newRelease` | `new_releases` | A new release. |
| `verified` | `verified` | Verify a download. |

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
