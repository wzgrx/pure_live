# C01.3 直播间功能余项

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（现在的内容以核对和真机验证为主，另有一处读代码发现的问题要修，见“方案”）
- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 8 节。登记时（docs v0，2026-10-03）照抄了清点第 1 版（2026-10-02）统计表里直播间那一行的“6 项缺失、1 项有问题”
- 旧编号：T05a.4
- 相关：C02.1、C03.1、O05.1（已经做完这 7 项的代码）；O02.1（画中画复验，同一次真机做）；S02.5 第一阶段“直播间”；决定 D-012、D-018；任务书 [brief.md](brief.md)

## 目标

- 用户：直播间里 3.x 有的功能在 4.x 都能用、行为对；离开应用后，直播间不会自己在后台出声。
- 开发者：功能清点第 8 节说的和代码一致，不再显示“还缺 7 项”。

## 3.x 和现状

清点第 1 版里直播间的 6 项缺失是 F-ROOM-21、F-RT-05、F-RT-07、F-PORT-05、F-PORT-06、F-MINI-04，1 项有问题是 F-ROOM-13（另有 F-ROOM-25 部分、F-RT-01 没验证）。现在代码都在，但**没有一项有真机结果**：

| 编号 | 功能 | 3.x（`v3.2.11`） | 现在（文件:行） | 谁做的 | 真机 |
|---|---|---|---|---|---|
| F-ROOM-13 | 屏幕常亮（可关） | `modules/live_play/controllers/live_play_controller.dart:177`、`:252-260` | `packages/live_player/lib/src/screen_wake.dart`、`video_view.dart:79`；`features/live_play/player/player_view.dart:503-516`、`mini/floating_window.dart:187` | O05.1 | 没看（CHECKLIST 第 1 节第 7 条） |
| F-ROOM-21 | “播放器强制销毁”关时把播放器留给下一个房间 | `player/core/player_manager.dart:234`、`:3656-3686` | `logic/player_standby.dart`；`live_play_page.dart:228`、`:491-496` | C02.1 c1 | 没看 |
| F-ROOM-25 | 键盘媒体键 | `modules/live_play/widgets/keyboard/video_keyboard.dart:56-59` | `live_play_page.dart:750-753` | C02.1 c6 | 没看 |
| F-RT-05 | 快手 App 跳转 | `modules/live_play/services/room_external_opener.dart:193-200` | `buttons/room_menu_button.dart:55-83`（`kuaishouStreamId`、`kuaishouAppLink`） | C03.1 c1 | 没看（第 14 条） |
| F-RT-07 | 切换直播间里的刷新 | `modules/live_play/dialogs/play_other.dart:117-136` | `switch_room/room_switch_panel.dart:22`（`FollowsRefresher`）、`:409`（`_RefreshButton`）；`app/app.dart:86` | C03.1 c2（A07.13 改成面板） | 没看（第 14 条） |
| F-PORT-05 | 小窗跟随竖屏源的比例 | `player/core/portrait_stream_support.dart:770-778` | `logic/mini_window.dart:83`（`miniPictureSize`）；`mini/room_mini_window.dart:106-114`；`mini/floating_window.dart:125`、`:140` | C02.1 c2 | 没看（第 11、12 条） |
| F-PORT-06 | 竖屏诊断信息 | `modules/live_play/widgets/video_player/video_controller_panel.dart:704-745` | `player/portrait_diagnostics.dart`；`player/player_view.dart:557`、`:711` | C02.1 c3 | 没看（第 8 条） |
| F-MINI-04 | 小窗弹幕设置的实时预览 | `modules/settings/pages/pip_danmaku_settings_page.dart:28-151` | `features/settings/playback_tiles.dart:690`（`PipDanmakuPreviewBinding`）、`packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart` | A11.3（C02.1 c4 核对） | 没看 |
| F-RT-01 | 投屏（DLNA） | `modules/live_play/dialogs/live_dlna_dialog.dart`、`common/utils/live_url_tool.dart:405` | `dialogs/stream_dialogs.dart:290`（`CastDevices`）、`packages/live_cast` | C01.2、N02.1 | 没对真电视试（第 13 条） |

（`features/live_play/` 下的路径省略了 `apps/pure_live/lib/features/live_play/`。）

清点表本身也要改：第 8 节统计行仍是“46、35、1、6、1、2、1”；上面前 8 行的“依据”还是做之前的写法（“没人读”“没有快手分支”“`room_switcher.dart` 没有刷新”）；F-ROOM-25 的“Android”列写成了“完成（…）”、“v4 现状”列写成“部分”，两列填反；F-ROOM-21 的备注“要不要保留这个开关需要用户定”已经定了（C02.1 的 X1 = A）；F-RT-06 的依据 `features/live_play/dialogs/room_switcher.dart` 已不存在（A07.13 换成 `switch_room/room_switch_panel.dart`）；第 2 节 F-AND-08 的依据“Dart 侧没有调用”也过时（C03.1 接上了）。

读代码时另外发现一处 4.x 新有的问题（3.x 没有定时刷新，所以没有这个问题）：

| 问题 | 位置 | 根因 |
|---|---|---|
| 在未开播的直播间里离开应用（按 Home、锁屏），主播开播后手机在后台直接出声，通知栏也没有媒体通知可以停 | `logic/room_controller.dart:325-327`（定时刷新在后台照跑）、`:775-777`（不在播而现在能播 → `load()`）；`logic/background_playback.dart:472-490`（`onHidden` 只在离开那一刻决定是否暂停）、`:431-438`（后台时不显示通知） | 定时刷新（B-24）只考虑了前台；后台策略没有处理“离开以后才开始的播放” |

## 方案

- c1 **清点表更正**：改 `docs/inventory/FEATURES.md` 第 8 节上面列的 9 行和统计表第 8 行、合计行，第 2 节 F-AND-08 的依据；“依据”写现在的文件和任务。
- c2 **真机核对**：上表 9 项逐条在 K90 上看，结果写 `verify.md`；不通过的开到对应组（例如投屏到 N02，快手跳转到 C03）。
- c3 **后台不自动出声**（建议 A，要维护者确认）：
  - A（建议）：`RoomBackgroundPolicy` 记住离开时是否在播；离开以后会话才开始打开或播放的（定时刷新开播、其他自动开始），立即暂停并记为“我们暂停的”，回到前台时继续。开着“后台播放”也一样：后台只继续离开时已经在播的（离开时没在播，通知也没显示，出声了用户没法从通知栏停）。
  - B：`LiveRoomController` 多一个“现在在后台”的回调，后台时 `refreshDetail` 只更新状态不 `load()`，回到前台再 `load()`。不开流，最省流量，但控制器要知道前后台，其他自动开始的路径（以后加的）还要各自处理。
  - 两种都保留前台“开播自动播放”（B-24）的行为不变。

## 验证

- 自动测试：c3 先在 `apps/pure_live/test/features/live_play/live_play_more_test.dart` 写一个改之前会失败的测试（未开播的房间、离开应用、平台变成开播、刷新后会话不在播；回来后在播）。c1 用 `python3 tools/docs/docs.py --check`。
- 真机：照 [brief.md](brief.md) 的“真机验证”在 K90 上看，结果写 `verify.md`；还没做（待真机）。

## 留下的问题

- 登记表的标题还是“6 项缺失、1 项有问题”，和现在的内容不符，建议维护者改成“直播间功能余项：清点第 8 节的真机核对、清点表更正、后台开播不出声”，类型可改成验证。
- C02.1、C03.1、O05.1 在登记表里是“完成”，但记录里“要在 K90 上看的”没有真机结果（[PROCESS.md](../../../PROCESS.md) 第 3.2 节：完成必须有真机结果）；本任务的 c2 做完后它们才算真的完成。
