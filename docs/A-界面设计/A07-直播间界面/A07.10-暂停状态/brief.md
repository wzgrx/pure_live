# A07.10 暂停状态：任务书

> 代码已在 2026-10-02 合并（`5dc1d84b8`），登记表状态“待真机”。这份任务书保留原来交给执行者的全部要求（旧编号 B02 的任务单，下面“方案和阶段”的阶段 1），并写清剩下的事：阶段 2 真机验证和维护者要定的几处。接手的人只读这一页和下面列的文件就能开工。

## 背景

- 来源：用户 2026-10-02 的问题 01（暂停后中间的图标看不清）、05（暂停时弹幕照飞）、07（暂停后随手点画面又开始播放）；审查报告 A-01、A-05、A-07、B-2、B-4、B-9（`docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md`）；维护者补充：YY 直播间刚开始播放就显示“正在重连（第 1 次）”。
- 现象（修之前）：暂停后控制层 4 秒就隐藏，中间的 ▶ 没有底色、亮画面上看不清；应用内小窗、系统画中画、多画面的弹幕暂停时照飞；暂停 10 秒再继续，画面中间出“正在重连（第 1 次）”；全屏锁定后房间下播或断网，锁按钮跟着顶栏消失，没法解锁；纯音频暂停时还写“纯音频播放中”。
- 为什么做：第一档（用户的问题）；D-012 定了“暂停后单击画面只显示或隐藏控制层，不继续播放；暂停时控制层不自动隐藏”。
- 已经做过的：`f24ca8540`（中间改 ▶ 可点、点画面不再继续播放，附录 A 第 1 条已改）。本任务在它上面做，不回退。
- 原任务单的约定：规模中；出设计：不用（照已确认的设计和本任务单）；和 A07.13、A07.12、A07.11 改同一批文件，不要同时开；可以和 D02.1、A02.3、A10.3、D01.32、E06.2 同时做。

## 目标和验收

1. 暂停后控制层常显（不再 4 秒隐藏）；用通知栏、耳机暂停也一样；继续播放后照常 4 秒隐藏。点画面只显示或收起控制层，从不继续播放。
2. 中间 ▶ 是一个共用组件：64 圆形、45% 黑底（`OnVideoColors.button`）、白色 ▶；暂停期间一直显示；缓冲时同一个圆底换成转圈；直播间和应用内小窗（`features/live_play/mini/mini_player.dart`，不是系统画中画）用同一个组件；纯音频暂停时也显示，并写“纯音频已暂停”。
3. 新设置“暂停时的弹幕”：随视频暂停（默认）/ 继续飘过；主画面、应用内小窗和画中画、多画面三处都按它；小窗暂停时清掉待发队列。
4. 暂停后继续、播放器自己缓冲，都不显示“正在重连（第 N 次）”；只有真的掉线恢复时才显示，次数准确；YY 刚开始播放不误报。
5. 全屏锁定后房间下播或加载失败，锁按钮仍在（只要锁着就显示）。
6. 每条至少一个测试（含三处弹幕 × 两种设置）；门禁通过。
7. （阶段 2）在 K90 上照 `verify.md` 逐条通过，登记表改“完成”。

## 现状（读代码得出，写文件:行）

代码已合并，下面是现在实现这些行为的位置（`apps/pure_live/lib/features/live_play/` 省略前缀）：

- 控制层常显：`player/player_view.dart:292-305`（`_onPlayback`：变成暂停时显示控制层并停掉计时）、`:312-319`（`_scheduleHide`：暂停或菜单、面板开着时不计时）、`:371-386`（`_tapControls`：手机上播放中或暂停时点画面收起，其余显示）。
- 中间 ▶：`packages/live_ui/lib/src/widgets/video_centre_button.dart:20`（`VideoCentreButton`，`videoCentreButtonSize = 64` `:8`）；直播间 `player/player_status.dart:254`（键 `picture-paused-play`）、`:264`（`picture-buffering`）；应用内小窗 `mini/mini_player.dart:317-321`（`miniCentreSize = 58` `:28`）；纯音频 `player/player_status.dart:333` 的 `AudioOnlyCover(paused:)`；状态顺序 `logic/room_status.dart:247-253`（暂停先于纯音频，缓冲 `pictureBuffering` `:179`）。
- 暂停时的弹幕：设置 `packages/live_store/lib/src/settings/settings.dart:469`（`danmakuPausedBehavior`）；规则 `apps/pure_live/lib/shared/danmaku/danmaku_settings.dart:44`（`danmakuRunning`）；设置行 `apps/pure_live/lib/shared/danmaku/danmaku_settings_content.dart:117`；主画面 `player/player_view.dart:484`；小窗和画中画 `mini/compact_danmaku.dart:51`、`:82`；多画面 `apps/pure_live/lib/features/multiview/multiview_page.dart:882`。
- 重连：`packages/live_player/lib/src/state.dart:119`（`PlaybackState.recovery`）、`packages/live_player/lib/src/session.dart:160`（`_recoveries`）；`logic/reconnect_watch.dart:16`（`ReconnectWatch` 照抄会话）。
- 锁定：`player/player_view.dart:775`（`lockable && (controls || _locked)`）、`:404-407`（`_toggleLock`）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart`：`:201-232` 单击：播放中第二次点隐藏，暂停或缓冲时**继续播放**（`:225-231`，这是本任务和 D-012 改掉的）；`:1009-1043` 锁按钮只在控制层显示时出现（`:1018`）；`:1752-1777` 下栏播放键（没有画面中间的按钮）。
- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller.dart`：`:320` 控制层 4 秒隐藏，`:864-891` 不看是否暂停；`:179-183` 不在播时不再发新的平台弹幕，本地弹幕照发。
- 要保留的：单击显示或隐藏、双击全屏、锁定锁住所有手势（附录 A 第 1、3、4 条）；本地弹幕暂停时也能发；下栏的播放键照旧。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 10 节真机、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.4 节（输入方式）、第 8.1 节（画面上的颜色）、附录 A 第 1 条。
3. 本文件夹的 `README.md`、`record.md`、`verify.md`；`docs/A-界面设计/A07-直播间界面/README.md`（直播间的结构）；`docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md` 的 A-01、A-05、A-07、B-2、B-4、B-9。

## 范围

- 可以改（阶段 1 当时的范围）：`apps/pure_live/lib/features/live_play/`、`apps/pure_live/lib/features/multiview/`（只接弹幕运行状态）、`apps/pure_live/lib/shared/danmaku/`、`packages/live_ui`（只添加）、`packages/live_store`（只添加设置）、`packages/live_player`（只加字段和设置它的地方，维护者授权）；对应测试；翻译文件。
- 阶段 2 只改本文件夹（`verify.md`、`verify/` 截图）和登记表。
- 不能改：其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；`docs/specs/UI.md`（附录 A 的改动由维护者做，已做）。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已完成，`5dc1d84b8`） | c1 暂停时控制层常显（`_scheduleHide` 遇到暂停直接返回）；c2 中间 ▶ 共用组件；c3 “暂停时的弹幕”设置和 `danmakuRunning(status, setting)`，三处都用；c4 暂停后继续不再显示重连（会话报告恢复次数）；c5 锁着就有解锁按钮 | 见“现状” | 每条有测试；门禁通过 |
| 2（待做） | 真机验证 | `verify.md`、`verify/`、`docs/tasks.toml`（状态改“完成”、写日期） | `verify.md` 每条通过；维护者对“留下的问题”里的选择表态 |

## 测试

- 已有（阶段 1）：见 `README.md`“验证”：`live_play_layouts_test.dart`、`live_play_mini_window_test.dart`、`live_play_states_test.dart`、`live_play_page_test.dart`、`live_play_popups_test.dart`、`live_play_room_test.dart`、`test/shared/danmaku_overlay_test.dart`、`test/features/multiview/multiview_page_test.dart`、`packages/live_player/test/session_test.dart`、`packages/live_ui/test/widgets_test.dart`、`packages/live_store/test/stores_test.dart`。B-4 的测试改之前会失败。
- 真机发现问题要修时：先写一个改之前会失败的测试；测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 正常直播间点暂停，等 10 秒；点画面空白处两次；点 ▶ | 中间是黑色半透明圆底上的白色 ▶，亮画面上看得清；10 秒后控制层还在；点画面收起、▶ 还在，再点回来；点 ▶ 变成同一个圆底上的转圈后继续播放，控制层 4 秒后隐藏 |
| 2. 横屏全屏重复第 1 条；用通知栏或耳机暂停 | 同上；控制层自己出来并保持 |
| 3. 弹幕多的房间暂停；把“暂停时的弹幕”改成“继续飘过”再暂停；改回 | 默认弹幕停住、不进新的；继续飘过时照飞 |
| 4. 应用内小窗、系统画中画、多画面里各暂停一次（开着弹幕） | 默认停住；改成继续飘过后照飞 |
| 5. 暂停 10 秒以上再继续；进一个 YY 直播间 | 不出现“正在重连”，最多短暂转圈或“正在连接直播流…” |
| 6. 播放中断网几秒再恢复，再断一次 | “正在重连（第 1 次）”和“换线路”，恢复后消失；第二次是“第 2 次” |
| 7. 全屏点锁，然后断网到“播放已中断”或等下播 | 右侧锁按钮还在（控制层收起时点一下画面就出来），点它解锁后能退出全屏 |
| 8. 开纯音频再暂停、再继续 | 封面中间 ▶，写“纯音频已暂停”；继续后回到耳机和“纯音频播放中” |

完整的表和结果栏在 `verify.md`。

## 风险和注意

- 真机上暂停和缓冲的状态来自 mpv 的事件，事件丢了时画面可能在动但状态一直是缓冲（G02.2 的问题），这时中间会一直转圈——看到这个现象记进 `verify.md` 并指向 G02.2，不在本任务修。
- 同一批文件（`player/player_view.dart`、`player/player_status.dart`、`mini/mini_player.dart`、`logic/room_status.dart`）A07.11～A07.13、A07.14、A07.15 也会改；真机发现问题要改代码时开新任务或在这些任务里一起改，避免冲突。
- 只点测试包 `com.mystyle.purelive.v4dev`；不碰 3.x（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 真机用的构建：master 上包含 `5dc1d84b8` 的提交（profile 或 debug，`com.mystyle.purelive.v4dev`）；在 `verify.md` 写清提交号。
- 要改代码时：分支 `ai/A07.10` 或本机工作区；提交信息以 `[A07.10]` 开头（英文）；不推 master。提交前改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`。真机验证做到一半时把已看的结果写进 `verify.md`。

## 报告（中文，简洁）

`verify.md` 每条的结果和截图；不通过的现象和根因线索（文件:行）；维护者对五处选择的决定；登记表改了什么。
