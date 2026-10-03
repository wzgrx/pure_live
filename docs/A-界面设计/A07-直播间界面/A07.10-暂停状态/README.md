# A07.10 暂停状态：中间 ▶、控制层常显、“暂停时的弹幕”设置、重连误报、锁定后能解锁

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（暂停时的界面行为；没有新的设计稿，照已确认的规则和任务书做）
- 来源：用户 2026-10-02 的问题 01（暂停图标）、05（暂停时弹幕）、07（点画面恢复播放），见 [V02.2](../../../V-需求和反馈/V02-用户反馈和issue/README.md)；审查报告 A-01、A-05、A-07、B-2、B-4、B-9（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；维护者补充：YY 直播间刚开始播放就显示“正在重连（第 1 次）”
- 旧编号：B02、T05f.1
- 相关：D-012（暂停后单击画面只显示或隐藏控制层，不继续播放；暂停时控制层不自动隐藏）；基础提交 `f24ca8540`（中间改 ▶ 可点、点画面不再继续播放）；[specs/UI.md](../../../specs/UI.md) 附录 A 第 1 条（已按本任务改写）；同一批文件的 A07.11、A07.12、A07.13 排在它后面

## 目标

暂停时用户一眼看出是暂停、知道怎么继续，并且不会被误导：

- 暂停后控制层一直显示（不再 4 秒后隐藏），画面中间是看得清的 ▶（64 圆形 45% 黑底），点 ▶ 继续；点画面只显示或收起控制层，从不继续播放。
- 暂停时弹幕怎么动由新设置“暂停时的弹幕”决定（随视频暂停 / 继续飘过），主画面、应用内小窗和画中画、多画面三处一致。
- 暂停后继续、播放器自己缓冲一下，都不再显示“正在重连（第 N 次）”；只有真的掉线恢复时才显示，次数准确。
- 全屏锁定后房间下播或出错，仍能解锁。
- 纯音频暂停时也有 ▶ 和“纯音频已暂停”。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 暂停时点画面 | 暂停或缓冲时点画面会**继续播放**（`modules/live_play/widgets/video_player/video_controller_panel.dart:225-231`） | 只显示或收起控制层（`apps/pure_live/lib/features/live_play/player/player_view.dart:333-386` 的 `_onTap`、`_tapControls`） | 不继续播放（D-012） |
| 暂停时控制层 | 4 秒后照样隐藏（`video_controller.dart:320` 的 `_controllerHideDelay`、`:864-891`） | 暂停时不计时隐藏，通知栏、耳机暂停也显示（`player_view.dart:292-305` 的 `_onPlayback`、`:312-319` 的 `_scheduleHide`） | 常显，点画面可收起 |
| 中间的 ▶ | 没有中间按钮（下栏的播放键 `video_controller_panel.dart:1752-1777`） | `packages/live_ui/lib/src/widgets/video_centre_button.dart:20` 的 `VideoCentreButton`（64，`:8`）；直播间 `player/player_status.dart:254`（`picture-paused-play`）、缓冲 `:264`（`picture-buffering`）；应用内小窗 `mini/mini_player.dart:317-321`（58，`miniCentreSize` `:28`） | 圆底 ▶，缓冲时同一个圆底转圈 |
| 暂停时的弹幕 | 不在播时不再发新的平台弹幕，本地弹幕照发（`video_controller.dart:179-183`）；没有设置 | 设置 `danmakuPausedBehavior`（`packages/live_store/lib/src/settings/settings.dart:469`）；`danmakuRunning`（`apps/pure_live/lib/shared/danmaku/danmaku_settings.dart:44`）；主画面 `player_view.dart:484`、小窗和画中画 `mini/compact_danmaku.dart:51`、`:82`、多画面 `features/multiview/multiview_page.dart:882` | 三处同一规则 |
| 重连提示 | 断流时没有任何提示（A07.7 S11） | 会话报告恢复次数 `packages/live_player/lib/src/state.dart:119` 的 `recovery`、`session.dart:160` 的 `_recoveries`；`features/live_play/logic/reconnect_watch.dart:16` 只照抄 | 只在真的恢复时显示，次数准确 |
| 锁定 | 锁按钮只在控制层显示时出现（`video_controller_panel.dart:1018`） | 只要锁着就有解锁按钮（`player_view.dart:775`：`lockable && (controls \|\| _locked)`） | 任何状态都能解锁 |
| 纯音频暂停 | 纯音频画面不分播放和暂停 | `logic/room_status.dart:247-248` 先判断暂停再判断纯音频；`player_status.dart:333` 的 `AudioOnlyCover(paused:)` | ▶ + “纯音频已暂停” |

## 结果

- 改动清单（逐条见 [record.md](record.md)）：
  - c1 暂停时控制层不自动隐藏；变成暂停时（播放键、通知栏、耳机都算）显示并停掉计时，继续后照常 4 秒隐藏。**做了一个选择**：暂停时控制层显示着，点画面会把它收起（▶ 还在），再点显示；否则加上常显后就再也收不起来、看不到干净的暂停画面。桌面照旧只显示。
  - c2 共用组件 `VideoCentreButton`（`live_ui`，只加）：45% 黑圆底、白 ▶，`busy` 时同一个圆底换成“加载样式”的转圈、不接点击；直播间 64、应用内小窗 58（尺寸参数不同）；系统画中画没有中间按钮，缓冲照旧小转圈；纯音频暂停（B-9）显示 ▶ 和“纯音频已暂停”。
  - c3 设置“暂停时的弹幕”（`pause` 默认随视频暂停 / `continue` 继续飘过），放在弹幕设置“显示范围”组最后（`shared/danmaku/danmaku_settings_content.dart:117`，直播间面板、弹幕设置标签、设置页、多画面面板都是这个组件）；`danmakuRunning`：播放中飞；暂停时只有“继续飘过”才飞；打开、缓冲、失败时都停；小窗暂停时清掉待发队列、不再收新的平台弹幕；自己发的本地弹幕暂停时也飞。
  - c4 按维护者补充从根上改：`PlaybackState` 加 `recovery`、`recovering`，只有会话的 `_recover`、重试轮次和它们里面的换线、换引擎、换软解时为真，播放起来、暂停、停止、报错、用户自己打开 / 换线 / 重试时清零，稳定播放 30 秒后从 1 重新数；`ReconnectWatch` 只照抄会话，删掉了 `expectReopen`；普通缓冲在画面中间只转圈。
  - c5 锁按钮条件改成只要锁着就显示；没有做“离开播放自动解锁”。
- 根因（核对过）：A-07 `_scheduleHide` 不看是否暂停；A-01 ▶ 没有底色、小窗暂停用另一套图标、画面上没有缓冲的样子；B-9 `pictureStateOf` 先判断纯音频；A-05 小窗和多画面的 `DanmakuOverlay` 没传 `running`（默认 `true`）、也没有设置；B-2 和 YY 误报：`ReconnectWatch` 靠猜，会话在掉线恢复、播放器自己缓冲、暂停后继续三种情况下发的都是同一个 `PlaybackStatus.buffering`；B-4 锁按钮挂在 `pictureHasControls(stage)` 下面，房间离开播放时连同顶栏一起消失。
- 提交：2026-10-02，合并提交 `5dc1d84b8`“Merge B02: paused state, the paused danmaku setting, recovery-only reconnect message, unlock always shown”；登记表记的是记录提交 `7cd3a0463`。授权改了 `packages/live_player`（只加字段和设置它的地方）。
- 新设置：`danmakuPausedBehavior`（`danmaku` 节，字符串，默认 `pause`，其他值回到默认，随备份；3.x 没有这个键）。
- 新翻译键：`danmaku_paused_behavior`、`danmaku_paused_behavior_desc`、`danmaku_paused_pause`、`danmaku_paused_fly`、`live_play_audio_only_paused`、`live_play_buffering`。
- 测试：新增 10 个、改写或扩充 6 个（每条 c 至少一个；三处弹幕 × 两种设置都有），见“验证”；当时 `apps/pure_live` 747 个、`live_player` 36 个、`live_ui` 100 个、`live_store` 45 个全部通过。

## 验证

- 自动测试：
  - c1：`apps/pure_live/test/features/live_play/live_play_layouts_test.dart`“paused: …”（10 秒后控制层还在、点画面收起 / 显示、不继续、▶ 继续后照常隐藏）、“A07.10 c1: a pause from elsewhere …”（通知栏、耳机暂停也显示并保持）。
  - c2：`packages/live_ui/test/widgets_test.dart` 的 `VideoCentreButton`（64、45% 黑底、白 ▶、忙时转圈不接点击）；`live_play_mini_window_test.dart` c2、c8（小窗同一个组件，缓冲时转圈且一直显示）；`live_play_states_test.dart`“A07.10: paused shows the play mark, over audio only too (B-9) …”。
  - c3：`apps/pure_live/test/shared/danmaku_overlay_test.dart` 的 `danmakuRunning`；主画面 `live_play_page_test.dart`“F.2a, U.2h c10 …”（改成继续飘过后暂停照飞、改回停住）；小窗 `live_play_mini_window_test.dart`“A07.10 c3”；多画面 `test/features/multiview/multiview_page_test.dart`“A07.10 c3”；设置行 `live_play_popups_test.dart`；`packages/live_store/test/stores_test.dart` 的默认值和取值范围。
  - c4：`packages/live_player/test/session_test.dart` 两个（只在恢复时带次数；缓冲、继续、用户换线不是恢复；重试轮次也算一次；报错结束恢复）；`live_play_room_test.dart` 的 `ReconnectWatch` 和 E3（用真的掉线驱动“正在重连（第 1 次）”）。
  - c5：`live_play_states_test.dart`“B-4: locked in fullscreen, the unlock button stays …”（改之前失败）。
- 真机：待真机，步骤见 [verify.md](verify.md)（从记录的“要在 K90 上看的”九条整理）。

## 留下的问题

- 需要维护者决定的（记录）：①暂停时点画面会收起控制层（c1 的选择；要“只显示、不收起”时去掉 `_onTap` 里对 `PlaybackStatus.paused` 的判断）；②“显示”组：弹幕设置里没有叫“显示”的组，放在了“显示范围”的最后一行；③应用内小窗中间按钮 58（直播间 64），要统一成 64 改 `miniCentreSize` 一处；④画面已出来后的缓冲不再走“加载较慢”，12 秒后由会话的缓冲看门狗转成恢复；⑤长时间暂停后继续时输入已不能用会走 `retry()`，显示“正在连接直播流…”。
- [specs/UI.md](../../../specs/UI.md) 附录 A 第 1 条已经改成“暂停时控制层不自动隐藏，画面中间一直有 ▶”（记录里请维护者合并时顺手改的，已改）。
- 可以以后清理的：`onReopen` 参数（`layout/room_info_bar.dart:32`、`buttons/stream_menu.dart:20`）没人传；`AppIcons.pausedOverlay`、`miniPlay`、`miniPause` 不再使用（见子分类 README 已知问题）。
- 缓冲状态的对账（画面在动但状态一直是缓冲）属于 G02.2。
