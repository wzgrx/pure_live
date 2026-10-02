# U.2a2 录制按钮和录制状态图标：设计（第 1 版）

- 状态：按建议定稿（2026-10-02；用户已授权“所有决定你选择”，待选 X1～X3 按建议 A 做，X4 交维护者），开发完成（[记录](../../../4.0.x/records/B04.md)）
- 范围：录制的图形和颜色——直播间顶栏的录制按钮、画面上的录制角标、全屏顶栏的录制按钮、录制面板和录制中心的状态卡头、Android 录制通知小图标；位置、点法、面板和录制中心的布局不变
- 来源：用户的问题 02（“录制的按钮图标……现在这个看起来像在录制……让人从图标就可以明显看出来”）；审查报告 A-02（[docs/4.0.x/audit-2026-10-02.md](../../../4.0.x/audit-2026-10-02.md)）；云端任务 [B04](../../../4.0.x/tasks/B04.md)
- 修订：[U.2a](../U.2a/README.md) 改动 13（录制三态）；[U.2f](../U.2f/README.md) 录制面板和 [U.7a](../U.7a/README.md) 录制中心的状态卡只换卡片头图标
- 评审页：本机 `~/ref/design/compare/U.2a2.html`（`python3 tools/ui/mock/page.py docs/ui/compare/U.2a2/page.json`）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：v3 按 `v3.2.11` 代码还原；“现在”是 4.0.0；画面和头像是示意图片

## 界面清点表

| 编号 | 界面 | 从哪里看到 | 形态 | 状态 |
|---|---|---|---|---|
| U.2a2-a | 直播间顶栏的录制按钮（`LP/buttons/record_button.dart`） | 竖屏直播间顶栏、平板顶栏 | 普通、窄顶栏（`compact`） | 七种（下表） |
| U.2a2-b | 全屏顶栏的录制按钮（同一个组件，`onVideo`） | 横屏全屏、竖屏全屏第一行 | 横屏录制中加 `mm:ss` | 七种 |
| U.2a2-c | 画面上的录制角标（`LP/player/recording_badge.dart`） | 竖屏画面标题前；全屏控制栏下面；控制栏隐藏时左上角；小窗 | 完整、紧凑 | 录制中、重连中、合成中 |
| U.2a2-d | 录制面板和录制中心的状态卡头（`shared/record/record_status_card.dart`） | 直播间录制面板（U.2f）；录制中心卡片（U.7a） | 完整、紧凑 | 九种卡片状态 |
| U.2a2-e | Android 录制通知小图标（`res/drawable/ic_stat_recording.xml`） | 状态栏、通知栏 | 单色 | 前台通知、“录制已停止”提醒共用 |

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

v3 未录本来就是中性色空心圈；4.0.0 的 U.2a 改动 13 把中心点改成了红色，才出现“没在录也像在录”。

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
- X4 “录制已停止”提醒的小图标、准备中和合成中的前台通知文字：A（建议）另做“!”小图标、通知按状态写字（要改 `RecorderForegroundService.kt` 和 `app/recording_notice.dart`，超出 B04 范围，交维护者）；B 维持现状。
