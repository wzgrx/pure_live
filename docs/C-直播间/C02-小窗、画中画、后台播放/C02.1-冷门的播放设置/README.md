# C02.1 冷门的播放设置

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（下面“档位：可以以后”是当时旧任务表的写法）
- 类型：功能
- 旧编号：F.1d、T05j.2
- 相关：决定 D-018（3.x 的设置键不变）；依赖 A11.3、G04.1；真机核对原来归 [C01.3](../../C01-进房和房间逻辑/C01.3-直播间功能余项/README.md)（2026-10-03 按 D-029 改“不做”）
- 档位：可以以后；规模：中
- 功能点：F-ROOM-21、F-PORT-05、F-PORT-06、F-MINI-04、F-APP-17、F-ROOM-25（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 涉及代码：`features/live_play/`（`live_play_page.dart`、`logic/room_runtime.dart`、新 `logic/player_standby.dart`、`logic/mini_window.dart`、`mini/`、`player/`）、`app/app.dart`；设置行已在 `features/settings/settings_catalog.dart`（A11.3）
- 依赖：A11.3（已完成）
- 来源：I01.3（`useHardStopOnExit`）、J01.1（小窗弹幕预览）、C01.2 第 4 项、M13.17 任务说明第 5、8、9 项
- 评审页：X1 用户已定 A；其余只把 v3 的行为补回来
- 记录：[record.md](record.md)

## v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 功能点 | 行为 | 位置 |
|---|---|---|
| F-ROOM-21 | 离开直播间：“播放器强制销毁”开 → 立即销毁；关（默认）→ 停播但留着播放器，45 秒内进下一个直播间直接用，过后才销毁 | `player/core/player_manager.dart:3640-3646`、`:3654-3681`；设置 `common/services/settings/player_settings_controller.dart:52`、`modules/settings/pages/player_kernel_settings_page.dart:97-102` |
| F-PORT-05 | 小窗（画中画、应用内悬浮窗）的比例：横屏 16:9；竖屏且“小窗跟随真实画面比例”开 → 真实比例，关 → 固定 9:16 | `player/core/portrait_stream_support.dart:770-778`；用在 `player_manager.dart:812-818`、`:1063`、`:2843`、`:3010` |
| F-PORT-06 | “显示识别状态”开时画面左上角一块半透明的字：宽×高、比例、方向、手动覆盖，第二行依据、置信度、稳定次数、时间 | `modules/live_play/widgets/video_player/video_controller_panel.dart:704-745` |
| F-MINI-04 | 小窗弹幕设置页顶部的实时预览 | `modules/settings/pages/pip_danmaku_settings_page.dart:28-151`、`:501-678` |
| F-APP-17 | 系统内存紧张：清图片缓存和正在用的图片记录 | `common/global/platform/desktop_manager.dart:774-781` |
| F-ROOM-25 | 键盘的播放、暂停、播放/暂停键 | `modules/live_play/widgets/keyboard/video_keyboard.dart:56-59` |

## v4 现在

- F-ROOM-21：设置行在（`settings_catalog.dart:1234-1240`），没人读。每个直播间新建一个 `PlaybackSession`（`live_play_page.dart:158`），离开时连播放器一起释放（`:290-305`、`logic/room_runtime.dart:55-63`）。`PlaybackSession.stop()` 本来就会把播放器留 45 秒（`packages/live_player/lib/src/session.dart:331-352`），只是没人复用。
- F-PORT-05：`portraitPipFollowSource` 只有设置行（`settings_catalog.dart:973-980`），小窗总按真实比例（`logic/mini_window.dart:70-73`、`mini/floating_window.dart:136-140`、`mini/room_mini_window.dart:102-105`、`:131-138`、`:270-279`）。
- F-PORT-06：`showPortraitDiagnostics` 只有设置行（`settings_catalog.dart:1006-1013`），画面上没有。
- F-MINI-04：**已由 A11.3 做完**：`PipDanmakuPreviewBinding`（`features/settings/playback_tiles.dart:645`、`:672`、`:690-713`）、`packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart`，测试在 `settings_playback_test.dart` 和 `live_ui` 的 `settings_playback_widgets_test.dart`。清点写成“缺失”是在 A11.3 合并前。
- F-APP-17：Flutter 自己在内存紧张时清图片缓存（`flutter/lib/src/painting/binding.dart:158-161`），但不清“正在用的图片”记录；应用没有自己的处理。
- F-ROOM-25：空格、方向键、R、F、Esc 有（`live_play_page.dart:515-527`），媒体键没有。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | “播放器强制销毁”开关不起作用，关着也每次离开都销毁 | v4 改成每个直播间一个会话（C01.1），没有留给下一个直播间的地方 |
| P2 | 关掉“小窗跟随真实画面比例”没用 | 搬小窗（A07.8）时没接设置 |
| P3 | 打开“显示识别状态”画面上什么都没有 | 竖屏识别搬到 `live_player` 时只留了宽高，诊断没搬 |
| P4 | 内存紧张时少清一项 | 应用没接 `didHaveMemoryPressure` |
| P5 | 外接键盘的媒体键没用 | 搬快捷键（C01.2）时漏了 |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 新 `PlayerStandby`（跟着应用的 provider，一次只留一个）：离开直播间且不转应用内小窗时，设置“关”→ 房间的其他部分照常释放，播放会话 `stop()`（播放器留 45 秒）后放进来；下一个直播间打开时，播放器配置（解码、输出驱动等）没变就直接用，变了就释放旧的再新建。设置“开”→ 和现在一样立即释放 | P1、X1 |
| c2 | 补上 | 小窗比例：竖屏画面在“跟随”关时固定 9:16（应用内悬浮窗、画中画进入和自动画中画、桌面小窗），开时照旧按真实比例 | P2 |
| c3 | 补上 | “显示识别状态”开时画面左上角显示：宽×高、比例、方向（竖屏 / 横屏 / 近方形 / 等待尺寸）、手动覆盖（自动识别 / 强制竖屏 / 强制横屏），第二行依据（解码尺寸 / 平台预判，G04.1）。v4 没有置信度、稳定次数，不显示 | P3 |
| c4 | 保留 | 小窗弹幕预览：A11.3 已做完，只核对；清点那一行改成完成 | — |
| c5 | 补上 | `app/app.dart` 接 `didHaveMemoryPressure`：清图片缓存和正在用的图片记录（照 v3） | P4 |
| c6 | 补上 | 直播间加媒体键：播放 → 继续，暂停 → 暂停，播放/暂停 → 切换 | P5 |

## 需要选的

- X1 “退出时销毁播放器”：用户已定 **A**——保留开关，“关”时离开直播间把播放器留给下一个直播间。
- 只在“离开直播间”时留；应用内悬浮窗关掉（✕、打开多画面、换房间）时照旧释放（悬浮窗本身就是在留播放器）。

## 测试和验证

- 离开直播间：设置关 → 播放器没释放，下一个直播间用同一个；设置开 → 立即释放；配置变了 → 换新的。
- 小窗比例：竖屏、跟随关 → 9:16；开 → 真实比例。
- 识别状态：开时有，关时没有；显示依据。
- 内存紧张：正在用的图片记录清空。
- 媒体键：暂停、继续、切换。
- K90：TASKS 第 5 节 5.1 第 8、11、12 条；退出直播间再进另一个，看起播是否更快、45 秒后内存回落。

## 风险和性能

- c1：离开后最多 45 秒多留一个播放器（v3 默认就是这样）；不加常驻定时器（用会话自己的 45 秒计时）。
- 3.x 的键 `useHardStopOnExit`、`portraitPipFollowSource`、`showPortraitDiagnostics` 不变；没有新设置。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比；F-MINI-04 已由 A11.3 做完，清点那一行改成完成 |
| 2026-10-02 | 开发完成（c1～c6），待 K90 验证 |

## 结果

- 提交：代码 `df6e2cf2a`（`feat(live_play): portrait hint, Kuaishou app link, switcher refresh, back, player standby (F.1b-F.1d)`），合并 `d53df6d71`（2026-10-02）；登记表写的 `7b37e6f5f` 是记录的提交。逐条见 [record.md](record.md)。
- c1～c6 都做到。偏差：c3 不显示 3.x 的置信度、稳定次数、时间（4.x 的竖屏识别没有这些）。
- 现在的位置（`apps/pure_live/lib/` 下）：`features/live_play/logic/player_standby.dart`（c1，页面里 `live_play_page.dart:228` 取、`:491-496` 留）；`features/live_play/logic/mini_window.dart:83` 的 `miniPictureSize`（c2，用在 `mini/room_mini_window.dart:106`、`mini/floating_window.dart:125`）；`features/live_play/player/portrait_diagnostics.dart`（c3，`player/player_view.dart:557`、`:711`）；`features/settings/playback_tiles.dart:690`（c4，A11.3 做的）；`app/app.dart:116`、`:261` 的 `releaseImageMemory`（c5）；`features/live_play/live_play_page.dart:750-753` 的媒体键（c6）。
- 默认行为变了：离开直播间（不转小窗）原来立即释放播放器，现在照 3.x 默认留 45 秒。记录里说的“换房间时新页面先建好、旧页面后关，这一种不复用”已经过时：A07.13 之后换房间在同一个页面里进行，直接接着用同一个会话（`_switchRoom`，`live_play_page.dart:360`），不经过 `PlayerStandby`。
- 测试：新增 `apps/pure_live/test/features/live_play/room_extras_test.dart` 的“F.1d”组 7 个；`live_play_mini_window_test.dart` 改了 2 处断言（离开后 45 秒才释放）。没有新设置，新翻译键 `portrait_evidence_decoder`、`portrait_evidence_platform`。

## 验证

- 自动测试：`room_extras_test.dart` 的“F.1d”组（c1 留给下一个房间 / 开关打开立即释放 / 配置变了换新的；c2 两个；c3 两个；c5；c6）。
- 真机：登记表是“完成”，但记录里“要在 K90 上看的”四项（播放器复用和 45 秒后内存回落、竖屏画面进画中画和应用内小窗的比例、识别状态的“平台预判 / 解码尺寸”、外接键盘媒体键）都**没有真机结果**。原来归 C01.3 的真机步骤；C01.3 按 D-029 改“不做”后，V03.3 把这几个功能点（F-ROOM-21、F-PORT-05、F-PORT-06、F-ROOM-25）判为“完成”（关键部分不靠原生和系统服务，组件测试覆盖了行为），没有专门的真机任务。日常回归照 [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 8 条（竖屏主播）、第 11、12 条（画中画和应用内小窗的比例）看；播放器复用要看时：退出直播间 45 秒内进另一个，起播比第一次快，`adb shell dumpsys meminfo com.mystyle.purelive.v4dev` 45 秒后回落。

## 留下的问题

- 真机没看（上面），没有专门的任务（D-029）；回归发现问题时在 C02 开新任务。
- 多画面（`features/multiview/`）和电视的直播间不经过 `PlayerStandby`，各自离开时立即释放（`PlayerStandby` 只有直播间页面在用）；要不要也留给下一个房间不在本任务范围。
