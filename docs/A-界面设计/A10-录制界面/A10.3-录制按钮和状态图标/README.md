# A10.3 录制按钮和录制状态图标：设计（第 1 版，按建议定稿，已开发，待真机）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：录制的图形和颜色——直播间顶栏的录制按钮、画面上的录制角标、全屏顶栏的录制按钮、录制面板和录制中心的状态卡头、Android 录制通知小图标；位置、点法、面板和录制中心的布局不变
- 来源：用户的问题 02（“录制的按钮图标……现在这个看起来像在录制……让人从图标就可以明显看出来”）；审查报告 A-02（[docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；云端任务 [A10.3](brief.md)
- 修订：[A07.1](../../A07-直播间界面/A07.1-竖屏普通布局/README.md) 改动 13（录制三态）；[A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md) 录制面板和 [A10.1](../A10.1-录制中心/README.md) 录制中心的状态卡只换卡片头图标
- 旧编号：U.2a2、B04、T08b.3（见 [MAPPING.md](../../../MAPPING.md)）；相关决定 D-003（X1～X3 按建议 A）；记录 [record.md](record.md)，真机验证 [verify.md](verify.md)
- 评审页：本机 `~/ref/design/compare/U.2a2.html`（`python3 tools/ui/mock/page.py docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/page.json`）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原；“现在”是 4.0.0；画面和头像是示意图片

## 界面清点表

| 编号 | 界面 | 从哪里看到 | 形态 | 状态 |
|---|---|---|---|---|
| A10.3-a | 直播间顶栏的录制按钮（`LP/buttons/record_button.dart`） | 竖屏直播间顶栏、平板顶栏 | 普通、窄顶栏（`compact`） | 七种（下表） |
| A10.3-b | 全屏顶栏的录制按钮（同一个组件，`onVideo`） | 横屏全屏、竖屏全屏第一行 | 横屏录制中加 `mm:ss` | 七种 |
| A10.3-c | 画面上的录制角标（`LP/player/recording_badge.dart`） | 竖屏画面标题前；全屏控制栏下面；控制栏隐藏时左上角；小窗 | 完整、紧凑 | 录制中、重连中、合成中 |
| A10.3-d | 录制面板和录制中心的状态卡头（`shared/record/record_status_card.dart`） | 直播间录制面板（A07.6）；录制中心卡片（A10.1） | 完整、紧凑 | 九种卡片状态 |
| A10.3-e | Android 录制通知小图标（`res/drawable/ic_stat_recording.xml`） | 状态栏、通知栏 | 单色 | 前台通知、“录制已停止”提醒共用 |

### 七种状态从哪里来

按录制任务的 `task.status`（经 `recordCardState`，和状态卡同一个映射），不再用 `RecordStatus.isActive` 二分：

| 图形状态 | 任务状态 | 顶栏提示文字 | 画面角标 |
|---|---|---|---|
| 未录 | 没有任务、`stopped`、`completed`（卡片“已保存”） | 录制 | 无 |
| 等待开播 | `waitingLive`；`queued` 且名额已满（卡片“排队中”） | 自动录 / 排队中 | 无 |
| 准备中 | `preparing`；`queued` 且有空位（录制器的启动间隔） | 准备中 | 无 |
| 录制中 | `running` | 录制中 | 红底“● 录制中 12:34” |
| 重连中 | `reconnecting` | 重连中 | 深色底“重连中 12:34” |
| 合成中 | `processing` | 合成中 | 深色底“合成中 45%” |
| 失败 | `failed` | 录制失败 | 无 |

## v3 的样子

`lib/modules/live_play/widgets/button/record_action_button.dart:40-104`、`record_action_content.dart`：手机上是 48×48、圆角 12 的实心按钮，图标 18。

| 状态 | 图标 | 颜色 | 底色 | 提示 |
|---|---|---|---|---|
| 没有任务 | `Remix.record_circle_line`（空心圈加圆点） | onSurfaceVariant | surfaceContainerHighest | 录制 |
| 有任务（已监控） | `Remix.checkbox_circle_fill` | primary | primary 10% | 已监控 |
| 录制中、重连中、准备中 | `Remix.record_circle_fill` | `Colors.redAccent` | 红 12% | 录制中 |

v3 未录本来就是中性色空心圈；4.0.0 的 A07.1 改动 13 把中心点改成了红色，才出现“没在录也像在录”。

## 现在（4.0.0）的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 未录是灰圈里一个红色实心点，红点就是“在录”的信号 | `packages/live_ui/lib/src/widgets/record_glyph.dart:78-96` |
| P2 | 顶栏按钮、画面角标按 `RecordStatus.isActive` 二分：准备中、重连中、合成 MP4 时也是红底闪烁和“● 录制中” | `LP/buttons/record_button.dart:75`、`LP/player/recording_badge.dart:59` |
| P3 | 失败在顶栏和未录一样 | `record_button.dart:126-132` |
| P4 | 状态卡每种状态一个不相干的图标，和顶栏对不上 | `shared/record/record_status_card.dart:258-460` |
| P5 | 录制通知小图标是圆环圆点，和“未录”同形 | `android/app/src/main/res/drawable/ic_stat_recording.xml` |
| P6 | 录制中白点 0.9 秒一闪，比呼吸更打扰 | `record_glyph.dart:52-64` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 一个图形七种状态；红色只给录制中；角标按状态写；横屏顶栏加时间；状态卡、通知同一组 | 用户已授权按建议 A 做，未单独评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：直播间顶栏](page/02-对比-直播间顶栏.jpg)
- [一个图标、七种状态](page/03-一个图标-七种状态.jpg)
- [在各处的样子](page/04-在各处的样子.jpg)
- [直播间（竖屏）](page/05-直播间-竖屏.jpg)
- [全屏（手机横屏）](page/06-全屏-手机横屏-852-393.jpg)
- [录制面板的状态卡和录制中心](page/07-录制面板的状态卡和录制中心.jpg)
- [通知小图标](page/08-通知小图标.jpg)
- [深色](page/09-深色.jpg)
- [现在的问题](page/10-现在的问题.jpg)
- [改了什么](page/11-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/12-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/13-各客户端.jpg)
- [需要你选的](page/14-需要你选的.jpg)
- [性能要点](page/15-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-appbar.jpg](v3-appbar.jpg) | v3 顶栏的三种样子 |
| [v4-current.jpg](v4-current.jpg) | 现在（4.0.0）七种状态的顶栏和角标，问题标红 |
| [v4-appbar.jpg](v4-appbar.jpg)、[v4-appbar-dark.jpg](v4-appbar-dark.jpg) | 新设计：顶栏七种状态和窄顶栏 |
| [v4-glyphs.jpg](v4-glyphs.jpg)、[v4-glyphs-dark.jpg](v4-glyphs-dark.jpg) | 图形规格：亮背景、画面上、放大 4 倍；呼吸三帧；画面角标 |
| [v4-matrix.jpg](v4-matrix.jpg) | 七种状态 × 顶栏、画面角标、全屏顶栏、状态卡、通知 |
| [v4-room-idle.jpg](v4-room-idle.jpg)、[v4-room-recording.jpg](v4-room-recording.jpg)、[v4-room-recording-n.jpg](v4-room-recording-n.jpg)、[v4-room-recording-dark.jpg](v4-room-recording-dark.jpg)、[v4-room-processing.jpg](v4-room-processing.jpg) | 竖屏直播间：没在录 / 录制中（编号图、深色）/ 停止后合成中 |
| [v4-land-recording.jpg](v4-land-recording.jpg)、[v4-land-recording-n.jpg](v4-land-recording-n.jpg)、[v4-land-reconnecting.jpg](v4-land-reconnecting.jpg)、[v4-land-reconnecting-n.jpg](v4-land-reconnecting-n.jpg)、[v4-land-hidden.jpg](v4-land-hidden.jpg) | 横屏全屏：录制中（按钮带时间）/ 重连中 / 控制栏隐藏 |
| [v4-cards.jpg](v4-cards.jpg)、[v4-cards-dark.jpg](v4-cards-dark.jpg) | 录制面板九种状态卡 |
| [v4-centre.jpg](v4-centre.jpg) | 录制中心紧凑卡片 |
| [v4-notify.jpg](v4-notify.jpg) | 状态栏和通知：现在 / 新 / 建议的“录制已停止” |

## 图形规格（24 的盒子，按尺寸缩放）

| 状态 | 画法 | 颜色 | 动效 |
|---|---|---|---|
| 未录 | 半径 9、线宽 2 的圆环（外径 20）+ 半径 3.5 的中心圆点 | 旁边图标的颜色（`IconTheme`；画面上白色） | 静止 |
| 等待开播 | 未录的圆环，右下角（18.8, 18.8）挖空半径 6，放半径 4.3、线宽 1.5 的小钟 | 同未录 | 静止 |
| 准备中 | 28% 透明的圆环上画 1/4 段弧 + 中心圆点 | 同未录 | 1.2 秒一圈；减少动态效果时停住 |
| 录制中 | 半径 10 的红色实心圆 + 7.5 的白色圆角方块（圆角 1.8）+ 半径 10～12 的红色光晕 | `LiveSemanticColors.recording` / `onRecording` | 光晕透明度 15%↔45%，2.4 秒一呼一吸；减少动态效果时常亮 30% |
| 重连中 | 8 段虚线圆环 + 中心圆点 | `LiveSemanticColors.warning`（画面上用深色主题的琥珀色） | 静止 |
| 合成中 | 淡圆环上从 12 点顺时针画合成进度 + 中心圆点；没有进度时同准备中 | 同未录 | 跟进度 |
| 失败 | 未录的圆环，右下角挖空放半径 5 的错误色圆和“!” | 圆环同未录；徽标 `error` / `onError`（画面上用 `OnVideoColors.error`） | 静止 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 未录：单色圆环 + 中心圆点，和旁边图标同色，没有红色 | P1 |
| c2 | 修改 | 录制中：红色实心圆 + 白色圆角方块，外圈慢慢呼吸；减少动态效果时常亮 | P6 |
| c3 | 增强 | 等待开播：圆环右下角小钟；顶栏仍是“自动录”胶囊，窄顶栏、画面上只放图标 | — |
| c4 | 修改 | 准备中、合成中：中性色环形进度，不再红色 | P2 |
| c5 | 修改 | 重连中：琥珀色虚线圆环 | P2 |
| c6 | 增强 | 失败：圆环右下角错误色“!” | P3 |
| c7 | 修改 | 画面角标按状态写“录制中 / 重连中 / 合成中”；准备中、未录不显示 | P2 |
| c8 | 增强 | 横屏全屏顶栏录制中时按钮右边加 `mm:ss`，这时控制栏下面不再重复录制中的角标 | — |
| c9 | 修改 | 状态卡头换成同一组图形；排队中用小钟；已保存保持绿色勾 | P4 |
| c10 | 修改 | Android 录制通知小图标换成录制中的形状（单色） | P5 |
| c11 | 保留 | 位置、点按打开录制面板、“自动录”胶囊、提示文字、面板和录制中心布局 | — |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 录制按钮 | 点一下打开录制面板；图形就是当前状态，长按看提示文字 |
| 2 | 画面角标 | 录制中、重连中、合成中出现；点一下打开录制面板；控制栏隐藏时缩成图标和时间，不能点 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机竖屏 | 顶栏录制按钮；画面标题前的角标 |
| Android 手机横屏全屏 | 顶栏录制按钮，录制中右边加时间；控制栏下面的角标只在重连中、合成中出现 |
| Android 竖屏全屏 | 顶栏第一行只放图标；时间在控制栏下面的角标里 |
| Android 平板 | 同一个按钮和角标 |
| 小窗 | 只有紧凑角标 |
| 电视、Windows、Linux、苹果平台 | 这一轮只做 Android；同一个组件 |

## 待选和决定

- X1 横屏全屏录制中时间放哪：A（已做）按钮右边加时间，控制栏下面不重复；B 只在角标里。
- X2 排队中（名额满）的图形：A（已做）同等待开播的小钟；B 同准备中转圈。
- X3 失败在顶栏：A（已做）圆环右下角“!”；B 同未录。
- X4 “录制已停止”提醒的小图标、准备中和合成中的前台通知文字：A（建议）另做“!”小图标、通知按状态写字（要改 `RecorderForegroundService.kt` 和 `app/recording_notice.dart`，超出 A10.3 范围，交维护者）；B 维持现状。

## 实现和验证

**定稿**：用户授权“所有决定你选择”（D-003），X1～X3 按建议 A 做（横屏录制中时间在按钮右边、排队中用小钟、失败圆环右下角“!”），没有单独评审；X4（“录制已停止”提醒另做小图标、准备中和合成中的通知按状态写字）超出本任务可改范围，维护者随后按建议 A 补做，登记为 H05.1（提交 `79ecb5d2b`，待真机）。

**实现**（详见 [record.md](record.md)；2026-10-02，提交 `82f3a60b7`“feat(live_ui): record glyph in seven states, red only while recording”、`5bab804b0`“feat(record): room bar, marks, cards and notification follow the task state”，合并 `40086fafa`“Merge B04: record glyphs by status, idle without red”；登记表记的是 `2e6c6f5ab`（记录））

| 编号 | 做到 | 现在的代码 |
|---|---|---|
| c1 | ✅ | `packages/live_ui/lib/src/widgets/record_glyph.dart`：`RecordGlyphState.idle`（`:10` 起七个值）由 `RecordGlyphPainter`（`:154`）画半径 9、线宽 2 的圆环 + 半径 3.5 的圆点（`:235`），颜色取 `IconTheme`（`:200-203`，画面上白色）；`shared/record/record_look.dart:13`：没有任务、已保存、停止都映射成未录 |
| c2 | ✅ | 录制中（`record_glyph.dart:279-289`）：`LiveSemanticColors.recording` 红圆 + `onRecording` 白色圆角方块（`:204`）；光晕 15%↔45% 呼吸 2.4 秒（`breath` `:64`、`:82`）；减少动态效果时不启动动画（`:80`），常亮 30%（`packages/live_ui/lib/src/theme/live_colors.dart:180` 的 `recordingHalo`） |
| c3 | ✅ | 等待开播（`record_glyph.dart:238-266`）：右下角挖空（`saveLayer` + `BlendMode.clear` `:240-244`）放小钟；排队中名额满时也用它（`record_look.dart:15`，X2 A）；直播间顶栏仍是“自动录”胶囊，图标换成新图形（`apps/pure_live/lib/features/live_play/buttons/record_button.dart:111-139`），窄顶栏、画面上只放图标 |
| c4 | ✅ | 准备中、合成中（`record_glyph.dart:267-278`）：28% 透明的圆环上画弧 + 圆点，颜色同未录；准备中 1/4 段弧 1.2 秒一圈（`turn` `:67`、`:83`），合成中按进度从 12 点顺时针画（`recordJoinProgress` `record_look.dart:55`），没有进度时同准备中转圈（`:84`） |
| c5 | ✅ | 重连中（`record_glyph.dart:290-297`）：8 段虚线 + 圆点，`LiveSemanticColors.warning`（画面上用深色主题的琥珀色，`:205`） |
| c6 | ✅ | 失败（同 `:238-266` 的挖空）：右下角半径 5 的错误色圆和“!”（`:206`；画面上用 `OnVideoColors.error` / `onError`，`live_colors.dart:104`）；顶栏提示“录制失败”（`record_look.dart:33`） |
| c7 | ✅（偏差 3） | 角标 `RecordingBadge`（`record_glyph.dart:328`）：录制中红底“录制中 12:34”，重连中、合成中黑 60% 底加 14 的小图形“重连中 12:34”“合成中 45%”，紧凑形只剩图形和数字；`recordBadgeState`（`record_look.dart:39`）只认 running / reconnecting / processing，准备中不显示；直播间里的 `RoomRecordingBadge`（`apps/pure_live/lib/features/live_play/player/recording_badge.dart:18`，计时器只在录制中、重连中跑） |
| c8 | ✅（偏差 4） | 横屏全屏顶栏 `_roomActions(landscape: true, time: true)`（`features/live_play/player/player_controls.dart:294`、`:372`）→ `RecordButton(showTime:)` 录制中时按钮右边 `mm:ss`（`record_button.dart:140-165`，`_RecordTime` `:178` 每秒只重画这段字）；全屏控制栏下面的角标 `showsRecording: arrangement != landscape || 网络电视`（`player_view.dart:734-736`：横屏全屏录制中不重复；网络电视的全屏顶栏没有录制按钮 `player_controls.dart:367`，所以照常显示）；控制栏隐藏时左上角紧凑角标照旧（`player_view.dart:724`） |
| c9 | ✅（偏差 1） | 状态卡卡片头（`apps/pure_live/lib/shared/record/record_status_card.dart:265`，20 号，琥珀色只给排队和重连 `:264`）：同一组图形，合成中按百分比重画（`:410-420`），已保存仍是绿色勾 `AppIcons.recordSaved`（`:458`）；录制中心用的是同一张卡，自动跟着变 |
| c10 | ✅（偏差 2） | `apps/pure_live/android/app/src/main/res/drawable/ic_stat_recording.xml`：实心圆挖出圆角方块（`evenOdd`，白色），`RecorderForegroundService.kt:331` 使用；“录制已停止”提醒后来由 H05.1 换成 `ic_stat_record_stopped.xml`（`:135`） |
| c11 | ✅ | 按钮位置（竖屏顶栏 `features/live_play/layout/room_header.dart:106`）、点按打开录制面板（`record_button.dart:86`）、“自动录”胶囊、面板和录制中心的布局都没动 |

- 根因（记录）：①`record_glyph.dart` 的“未录”是灰圈里一个红色实心点（A07.1 改动 13 加的），红点本身就是“正在录”；②顶栏按钮和画面角标用 `RecordStatus.isActive` 二分，准备中、重连中、合成 MP4 时也是红底闪烁和“● 录制中”，失败落到“未录”分支；③状态卡每种状态一个不相干的图标，通知小图标是圆环圆点、和“未录”同形。
- 偏差（记录）：①状态卡的等待开播、准备中、合成中图标从主色改成中性色（设计要求“中性色”；已保存的绿勾不变）；②通知只做了录制中的小图标，“录制已停止”和按状态写字超出范围（X4，后来 H05.1 补做）；③准备中不显示画面角标（通常几秒，顶栏的转圈已经说明）；④横屏全屏控制栏下面的角标在录制中时不再显示（按钮带时间，X1 A），重连中、合成中照旧。
- 新翻译键：`record_badge_reconnecting`（重连中）、`record_badge_processing`（合成中）；“录制中”用原有的 `recording`。没有新设置。`live_ui` 加颜色角色 `OnVideoColors.onError`，`recordingHalo` 改成光晕静止时的 30%。

**验证**

- 自动测试：新写 7 个、改 2 个、删 `live_ui` 旧的 3 个（闪烁白点、旧角标、白色圆环）。现在的位置：`packages/live_ui/test/design_system_test.dart` 4 个（`:301` 只有录制中有红色、`:362` 画面上的色调、`:377` 呼吸和转圈及减少动态效果、`:412` 角标三种状态）；`apps/pure_live/test/features/recorder/recorder_page_test.dart` 2 个（`:186` 顶栏七种状态、红色、提示、合成进度、横屏带时间和角标；`:288` 九种卡片状态到图形和角标的映射）；`recorder_centre_test.dart:434`（九张卡片头的图形）；改的是 `live_play_popups_test.dart`（横屏全屏点顶栏录制按钮、断言按钮带时间）和 `test/platform/system_surfaces_test.dart`（通知资源）。当时 `live_ui` 100 个、`apps/pure_live` 743 个全部通过，debug APK 构建通过（新通知图标能编译）。
- 真机：待真机，步骤见 [verify.md](verify.md)（从记录“要在 K90 上看的地方”八条和 c1～c10 整理，13 步，含 H05.1 的通知标题和“录制已停止”图标）。
- 留下的问题和去向：记录里说电视卡片 `tv/widgets/tv_room_card.dart` 也用 `isActive` 判断录制中——查过现在的代码，那里的 `isActive` 是跑马灯计时器，电视卡片不显示录制状态，不用改；和 A07.13 都改过顶栏按钮（`record_button.dart`、`player_controls.dart`），A07.13 已合并（待真机），没有冲突遗留；通知里的合并进度 → H05.3。
