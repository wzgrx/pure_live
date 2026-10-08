# A07.10 暂停状态：中间 ▶、控制层常显、暂停时的弹幕、重连误报、锁定后无法解锁

- 日期：2026-10-02
- 任务单：[tasks/B02.md](brief.md)；审查报告 A-01、A-05、A-07、B-2、B-4、B-9（[audit-2026-10-02.md](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）
- 基础：`f24ca8540`（中间 ▶ 可点、点画面不再继续播放），没有回退
- 维护者补充（c4）：YY 直播间刚开始播放就显示“正在重连（第 1 次）”。授权改 `packages/live_player`（只加字段和设置它的地方）
- 本地 worktree 任务：没有新建 `cloud/B02` 分支、没有推送和开 PR；没有改 Android 原生代码，不需要构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 暂停时控制层不自动隐藏；点画面只显示或隐藏控制层 | ✅（有一处选择） | `player_view.dart`：`_scheduleHide` 遇到暂停直接返回；订阅 `session.states`，变成暂停时（不管是播放键、通知栏还是耳机暂停的）显示控制层并停掉隐藏计时，继续播放后照常 4 秒隐藏。**选择**：暂停时控制层显示着，点画面会把它**隐藏**（▶ 还在），再点显示；`f24ca8540` 之后暂停时点画面只能“显示”，加上常显后就再也收不起来、看不到干净的暂停画面。点画面任何时候都不继续播放。桌面照旧只显示 |
| c2 | 中间 ▶ 做成共用组件：64dp 圆形 45% 黑底、白色 ▶、暂停期间一直显示、缓冲时转圈、直播间和应用内小窗共用、纯音频暂停也显示 | ✅ | 新组件 `VideoCentreButton`（`packages/live_ui/lib/src/widgets/video_centre_button.dart`，只添加）：`OnVideoColors.button`（45% 黑）圆底，白色 `AppIcons.play`；`busy` 时同一个圆底上换成“加载样式”的转圈、不接点击。直播间：暂停 → `picture-paused-play`（64dp，点它继续）；画面已经出来后的缓冲（继续播放后的缓冲、短暂卡顿）→ `picture-buffering`（同一个圆底转圈、不写字）。应用内小窗：中间的播放 / 暂停 / 重试都换成这个组件，缓冲时转圈且一直显示（小窗尺寸照 A07.8 保持 58dp）；系统画中画没有中间按钮，缓冲照旧小转圈。纯音频暂停（B-9）：`pictureStateOf` 先判断暂停再判断纯音频，封面中间是 ▶，下面写“纯音频已暂停” |
| c3 | 新设置“暂停时的弹幕”（随视频暂停 / 继续飘过），`danmakuRunning(status, setting)`，主画面、小窗和画中画、多画面三处都用 | ✅ | 设置 `danmakuPausedBehavior`（`pause` 默认 / `continue`）。放在弹幕设置“显示范围”组最后（共用组件 `danmaku_settings_content.dart`，直播间面板、直播间弹幕标签、设置页、多画面面板都是它；没有叫“显示”的组，最接近的是“显示范围”）。`danmakuRunning`（`shared/danmaku/danmaku_settings.dart`）：播放中飞；暂停时只有“继续飘过”才飞；打开、缓冲、失败时都停。主画面：`player_view.dart` 的 `running`。小窗和画中画：`compact_danmaku.dart` 订阅 `controller.session.states`，停的时候清掉待发队列、不再收新的平台弹幕，`DanmakuOverlay` 传 `running`。多画面：`multiview_page.dart` 用格子会话的播放状态。自己发的本地弹幕照旧暂停时也飞 |
| c4 | 暂停后继续播放不再显示“正在重连（第 N 次）” | ✅（按维护者补充从根上改） | 见下面“根因”。`PlaybackState` 加 `recovery`（第几次恢复，0 = 没在恢复）和 `recovering`；只有 `_recover`、重试轮次和它们里面的换线、换引擎、换软解时为真，播放起来、暂停、停止、报错、用户自己打开 / 换线 / 重试时清零，连续恢复的次数在稳定播放 30 秒（会话的恢复预算重置）后从 1 重新数。`ReconnectWatch` 只照抄会话说的，不再猜；删掉了 `expectReopen`（会话自己知道是用户换线）。普通缓冲在画面中间只转圈（c2 的同一个圆底），画面还没出来的新源照旧“正在连接直播流…” |
| c5 | 全屏锁定后房间下播或加载失败，锁按钮仍要显示 | ✅ | `player_view.dart`：锁按钮条件从 `lockable && controls` 改成 `lockable && (controls \|\| _locked)`，只要锁着就有解锁按钮（控制层因安静隐藏时点画面就出来）。没有做“离开播放自动解锁” |

## 根因

- **A-07 / c1**：`_scheduleHide` 不看是否暂停，4 秒后控制层照样隐藏。
- **A-01 / c2**：▶ 没有底色，画面亮时看不清；小窗暂停时用另一套图标（`miniPlay` 实心圆），两处不一致；画面上没有“缓冲中”的样子。
- **B-9**：`pictureStateOf` 先判断纯音频再判断暂停，纯音频暂停后仍是“纯音频播放中”、没有 ▶。
- **A-05 / c3**：只有主画面传了 `running`；`compact_danmaku.dart`（应用内小窗和系统画中画共用）和多画面的 `DanmakuOverlay` 没传，默认 `true`，暂停时照飞；也没有设置项。
- **B-2 和 YY 进房误报 / c4**：`ReconnectWatch` 靠猜：只要“播放过、后来变成 buffering / opening、又没调用 `expectReopen`”就算一次掉线。会话在三种完全不同的情况下发的都是同一个 `PlaybackStatus.buffering`：真的掉线后恢复（`session.dart` 的 `_recover`）、播放器自己缓冲一下（引擎的 `EngineBuffering`，YY 这类流刚开始常见）、暂停后继续（`resume()` 先发 buffering）。`ReconnectWatch` 分不出来，后两种都被当成“正在重连”，次数还累加。改成由会话自己在状态里说明正在恢复和第几次，界面只信它。
- **B-4 / c5**：锁按钮挂在 `pictureHasControls(stage)` 下面，房间离开 playing（下播、失败）时连同顶栏一起消失，`_locked` 仍为真，屏幕上没有任何办法解锁。

## 改了哪些文件

- `packages/live_player/lib/src/state.dart`：`PlaybackState.recovery`、`recovering`、`copyWith(recovery:)`。
- `packages/live_player/lib/src/session.dart`：`_recoveries` 计数；`_recover`、`_retryRound` 发出带次数的 buffering；`_openSource(recovering:)` 区分恢复步骤和用户操作；播放、暂停、停止、完成、报错时清零；`open` / `selectLine` / `retry` 和恢复预算重置时归零。
- `packages/live_store/lib/src/settings/settings.dart`：`danmakuPausedBehavior`。
- `packages/live_ui/lib/src/widgets/video_centre_button.dart`（新）、`packages/live_ui/lib/live_ui.dart`（导出）。
- `apps/pure_live/lib/features/live_play/logic/reconnect_watch.dart`：改成照会话的 `recovery`。
- `apps/pure_live/lib/features/live_play/logic/room_status.dart`：新状态 `buffering`、`pictureBuffering()`；暂停排在纯音频前面。
- `apps/pure_live/lib/features/live_play/player/player_status.dart`：▶ 和缓冲用 `VideoCentreButton`；“加载较慢”的计时不算画面已出来后的缓冲；`AudioOnlyCover(paused:)`；去掉 `expectReopen`。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`：c1、c3（主画面）、c5、纯音频暂停；去掉 `onReopen: expectReopen`。
- `apps/pure_live/lib/features/live_play/mini/mini_player.dart`：中间按钮换成共用组件，缓冲时转圈。
- `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart`：c3（小窗和画中画）。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：`ReconnectWatch(session.states)`，信息行不再传 `onReopen`（两行）。
- `apps/pure_live/lib/features/multiview/multiview_page.dart`：c3（多画面）。
- `apps/pure_live/lib/shared/danmaku/danmaku_settings.dart`：`DanmakuPausedBehavior`、`danmakuRunning`。
- `apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart`：“暂停时的弹幕”一行。
- `apps/pure_live/assets/translations/zh.json`、`en.json`：6 个新键。
- 测试：`packages/live_player/test/session_test.dart`、`packages/live_store/test/stores_test.dart`、`packages/live_ui/test/widgets_test.dart`、`apps/pure_live/test/features/live_play/`（`live_play_layouts_test`、`live_play_mini_window_test`、`live_play_page_test`、`live_play_popups_test`、`live_play_room_test`、`live_play_states_test`、`live_play_support`）、`apps/pure_live/test/features/multiview/multiview_page_test.dart`、`apps/pure_live/test/shared/danmaku_overlay_test.dart`。

## 新设置和翻译键

- `danmakuPausedBehavior`（`danmaku` 节，字符串，默认 `pause` = 随视频暂停；`continue` = 继续飘过；其他值回到默认；随备份）。3.x 没有这个键，3.x 的设置都没动。
- 翻译键（中英都加，按键名排序）：`danmaku_paused_behavior`（暂停时的弹幕）、`danmaku_paused_behavior_desc`（视频暂停后，弹幕跟着停住还是照常飘过）、`danmaku_paused_pause`（随视频暂停）、`danmaku_paused_fly`（继续飘过）、`live_play_audio_only_paused`（纯音频已暂停）、`live_play_buffering`（缓冲中，转圈的读屏文字）。

## 测试

新增 10 个，改写或扩充 6 个（每条 c 至少一个；三处弹幕 × 两种设置都有）：

- c1：`live_play_layouts_test` “paused: …”（改写：10 秒后控制层还在、点画面隐藏 / 显示、不继续、▶ 继续后照常隐藏）；新增 “A07.10 c1: a pause from elsewhere …”（通知栏 / 耳机暂停也显示并保持）。
- c2：`live_ui` 新增 `VideoCentreButton` 测试（64dp、45% 黑底、白 ▶、忙时转圈不接点击）；上面的 layouts 测试查 ▶ 的圆底和缓冲转圈；`live_play_mini_window_test` c2、c8（改写：小窗用同一个组件，缓冲时转圈且一直显示）；`live_play_states_test` 新增 “A07.10: paused shows the play mark, over audio only too (B-9) …”。
- c3：`danmaku_overlay_test` 新增 `danmakuRunning`；主画面 `live_play_page_test` “D05.1, D03.1 c10”（扩充：改成继续飘过后暂停照飞、改回停住）；小窗 `live_play_mini_window_test` 新增 “A07.10 c3”（默认停住、暂停期间的不排队、继续飘过后照飞）；多画面 `multiview_page_test` 新增 “A07.10 c3”；设置行 `live_play_popups_test`（扩充：在“显示范围”里、默认随视频暂停、点了立即生效）；`stores_test` 新增默认值和取值范围。
- c4：`session_test` 新增两个（会话只在恢复时带次数；缓冲、继续播放、用户换线都不是恢复；重试轮次也算一次；报错结束恢复）；`live_play_room_test` 的 `ReconnectWatch`（改写：缓冲和暂停后继续都不算，只照会话的次数）和 E3（改写：用真的掉线驱动“正在重连（第 1 次）”）；`live_play_states_test` 的单元测试也查了“画面已出来的缓冲只转圈”。
- c5：`live_play_states_test` 新增 “B-4: locked in fullscreen, the unlock button stays …”（改之前失败：找不到解锁按钮）。

跑过的：`apps/pure_live` 的 `flutter analyze`（无问题）和全部 `flutter test`（747 个通过）；`packages/live_player` `flutter analyze`、`flutter test`（36 个通过）；`packages/live_ui` `flutter analyze`、`flutter test`（100 个通过）；`packages/live_store` `dart analyze`、`dart test`（45 个通过）；四个包 `dart format` 无改动；根目录 `python3 tools/gate/check_ui_structure.py` 通过（没有新的直接颜色和图标）、`check_deps.py` 0 错误。没有跑完整门禁。

## 要在 K90 上看的（Redmi K90 Pro Max，Android 17，120 Hz）

1. 进一个正常直播间，点暂停：中间是黑色半透明圆底上的白色 ▶，亮画面上也看得清；等 10 秒，控制层还在。点画面空白处：控制层收起、▶ 还在；再点：控制层回来。点 ▶：变成同一个圆底上的转圈，随后消失、继续播放，控制层 4 秒后照常隐藏。
2. 横屏全屏重复第 1 条。用通知栏的暂停或耳机按键暂停：控制层自己出来并保持。
3. 弹幕多的房间暂停：默认弹幕停住、不再进新的。到“设置 → 弹幕”或直播间“弹幕设置”的“显示范围”最后一行把“暂停时的弹幕”改成“继续飘过”：暂停后弹幕照飞。改回“随视频暂停”。
4. 离开直播间成应用内悬浮小窗：点中间暂停，小窗弹幕停住；改成“继续飘过”后照飞。系统画中画里用系统的暂停键，同样。多画面里暂停选中的格子（开着弹幕），同样。
5. 暂停 10 秒以上再继续：不出现“正在重连”；画面中间只短暂转圈。
6. 进一个 YY 直播间（维护者报的情况）：刚开始不再出现“正在重连（第 1 次）”，最多在画面中间转圈或“正在连接直播流…”。
7. 播放中断网几秒（或开关飞行模式）：出现“正在重连（第 1 次）”和“换线路”，恢复后消失；再断一次是“第 2 次”。
8. 全屏点锁，然后让房间失败（断网到出现“播放已中断”，或等房间下播）：右侧的锁按钮还在（控制层收起时点一下画面就出来），点它解锁后顶栏回来，能退出全屏。
9. 开纯音频再暂停：封面中间是 ▶，下面写“纯音频已暂停”；继续后回到耳机和“纯音频播放中”。

## 需要维护者决定的

- **暂停时点画面会收起控制层**（c1 的选择，理由见上）。如果要“暂停时点画面只显示、不收起”，把 `_onTap` 里的 `status == PlaybackStatus.paused` 去掉即可。`docs/specs/UI.md` 附录 A 第 1 条还写着“暂停中 → 只显示控制层”，本任务不能改那个文件，请合并时顺手改成“暂停中 → 控制层常显，点画面显示或收起，不继续播放”。
- **“显示”组**：弹幕设置里没有叫“显示”的组，放在了“显示范围”的最后一行。
- **小窗中间按钮的大小**：直播间 64dp；应用内小窗照 A07.8 保持 58dp（同一个组件，只是尺寸参数），小窗最矮 124，64 也放得下，要统一成 64 改 `miniCentreSize` 一处。
- **画面已出来后的缓冲不再走“加载较慢”**：以前播放中卡住 8 秒会出“比平时慢，可以换一条线路试试”；现在只转圈，12 秒后由会话的缓冲看门狗转成恢复，出“正在重连（第 1 次）”和“换线路”。画面还没出来的新源照旧 8 秒后提示“加载较慢”。
- **长时间暂停后继续**：输入已经不能用时 `resume()` 走 `retry()`，会显示“正在连接直播流…”（不是重连，也不是 ▶ 转圈），这是重新打开流。
- 可以以后清理的：`onReopen` 参数（`RoomInfoBar`、`StreamPickers`、`PlayerBarActions`）现在没人传；`AppIcons.pausedOverlay`、`miniPlay`、`miniPause` 不再使用（`live_ui` 本任务只能添加）。这些在 `buttons/`、`player/` 下，和 A02.3、A10.3 同时改容易冲突，所以没动。

## 可能和别的任务冲突的文件

- `player/player_view.dart`、`player/player_status.dart`（A10.3 改 `player/`；A07.13、A07.12、A07.11 按顺序在 A07.10 之后）。
- `mini/mini_player.dart`、`mini/compact_danmaku.dart`、`logic/room_status.dart`、`logic/reconnect_watch.dart`、`live_play_page.dart`（两行，E06.2 可能也改 `features/live_play/`）。
- `shared/danmaku/danmaku_settings_content.dart`、`danmaku_settings.dart`（D02.1 改 `shared/danmaku/` 的屏蔽管理；A08.5 的设置弹幕页）。
- `packages/live_store/lib/src/settings/settings.dart`（D02.1 加 meta 键）、`packages/live_ui/lib/live_ui.dart` 导出列表（A02.3、A10.3 也在 `live_ui` 加东西）、`packages/live_player/lib/src/session.dart`（R02.2 若改帧率声明）。
- 翻译文件 `zh.json`、`en.json`（几乎每个任务都加键，按键名排序，合并时一般只是相邻行）。
- 测试：`live_play_support.dart`（`FakeEngine.onOpen`）、`live_play_mini_window_test.dart`（`_App.danmakus`）。

## K90 复查（2026-10-08，master ce7640a5b）

- 第 1 条（竖屏，哔哩哔哩）：暂停后中间是深色半透明圆底上的白 ▶，10 秒后控制层还在 ✓；点 ▶ 继续播放 ✓。
- 第 5 条：暂停 10 秒以上再继续，没出现“正在重连”，日志里没有 `playback: recovering` ✓。
- 第 9 条：纯音频时暂停，封面中间写“纯音频已暂停”；继续后回到“纯音频播放中” ✓。
- 第 7 条见 G02.3 的 K90 复查（断网出“正在重连”，恢复后自己接上）✓。
- 第 2～4、6、8 条没看（横屏全屏、通知栏暂停、“暂停时的弹幕”、小窗和多画面、YY 起播、全屏锁定后失败）。

## K90 复查（2026-10-08 晚，提交 `9e84b6f7b`）

- 第 2 条：横屏全屏暂停，中间 ▶，10 秒后控制层还在 ✓；点 ▶ 继续后 4 秒隐藏 ✓；用媒体键暂停（`cmd media_session dispatch pause`，和耳机键、通知栏走同一个媒体会话）控制层自己出来并保持 ✓。
- 第 3 条：默认“随视频暂停”，暂停后隔 2 秒两张截图弹幕位置不变 ✓；改成“继续飘过”后暂停照飞 ✓；已改回。
- 第 4 条（部分）：系统画中画里媒体键暂停，画面停住 ✓；画中画默认不显示弹幕（“小窗显示弹幕”关着），小窗和多画面没看。
- 第 6 条：进 YY 直播间，连续截图是“正在进入直播间…”→“正在连接直播流…”，没有“正在重连”，日志里没有 recovering ✓。
- 还剩：第 4 条的小窗、多画面和画中画弹幕；第 8 条（全屏锁定后让房间失败）。
