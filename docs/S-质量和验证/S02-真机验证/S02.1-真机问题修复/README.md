# S02.1 真机问题修复

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证（真机发现的问题集中修复）
- 来源：2026-10-01 两轮真机测试（K90，测试包；第一轮 `8df75a12a`，第二轮 `e62c995e4`）的记录 `~/ref/notes/m13_notes.md` 的“DEVICE TEST 2026-10-01”，加上协调员补充的 4 个直播间问题
- 旧编号：M13.16、T15b.1
- 相关：记录 [record.md](record.md)（逐条根因和改法）；后续复验 O02.1（画中画回来后控制条）；关联 A07.1（录制按钮）、A09.3（关注页标签）、A09.7（搜索）

## 目标

把界面重构前两轮真机测试里看到的 12 个问题逐个找到根因并修掉，每个修复都有改之前会失败的测试；修不了或不是应用的问题写清楚原因。

## 3.x 和现状

| # | 现象（真机） | 3.x | 修之前的 4.x（根因） | 修之后 |
|---|---|---|---|---|
| 1 | 关注页空状态“搜索直播”按钮是刷新图标 | 一样（`app_status_view.dart:474` 写死刷新图标） | `live_ui` 的 `AppStatusView` 按钮固定 `Icons.refresh_rounded` | `AppStatusView`、`EmptyView` 加 `buttonIcon`，七类页面的按钮配上对应图标 |
| 2 | 快手标题里的 U+FFFC 显示成“OBJ”方框 | 原样显示 | 各平台文字原样进模型 | `live_core` 的 `stripInvisiblePlaceholders`；`LiveRoom` 构造时、弹幕运行时统一清理（保留零宽空格等有含义的字符） |
| 3 | 卡片“已播 51 小时 49 分”、直播间“已开播 2 天”不一致 | — | 两个函数各一套规则 | 一个 `elapsedText`：不到 1 小时“N 分钟”，不到 24 小时“N 小时 M 分”，之后“N 天 M 小时” |
| 4 | 关注页“已开播 1”被截断变淡 | — | 三个标签挤在标题栏，默认内边距 16，360 宽时每个标签只剩约 66 像素 | 内边距 4、数字改小徽标、`FittedBox` 只缩小不截断 |
| 5 | YY 部分直播间标题栏没有分区名 | — | 预置表只覆盖有列表模块的分区 | `YyApi.bizAreaNames` 加 `zonghe` = 综合（只读探测 82 个在播详情得出） |
| 6 | 搜索“全部”时海外平台每次失败，红色横幅一长串 | 一样 | “全部”默认就是所有平台；失败横幅列全部名字 | 温和的说明卡、名字收起、新“搜索范围”（记住在 `search.allExcluded`） |
| 7 | 从直播间返回后约 2 秒内点平台标签没反应 | — | 返回时首页跟着跑 450 毫秒的转场，标签还在左边 80～100 像素处 | 直播间用 `CustomTransitionPage`，首页返回时不动 |
| 8 | 快手 `[笑哭]`、CHZZK、YouTube 表情显示成文字 | 3.x 有表情包 | 消息模型没有表情片段 | `LiveMessage.emotes`；四个平台解码；带上 3.x 的表情包（5 个平台、1350 张图） |
| a | 从画中画回来后控制条一直显示、按钮没反应 | 3.x 先切紧凑布局再进画中画 | 三种布局各建一个播放器，进出画中画整棵重建（真机没复现） | 播放器和视频视图用 `GlobalKey` 跨布局保持；回来时控制条重新计时、解锁、强制出一帧 |
| b | 控制条没有深色衬底，亮画面上白图标看不清 | — | 渐变 `black54`，只有栏高 | 70% 起、多延伸 28 像素，图标加阴影 |
| c | 标题栏录制按钮只是空心圆 | 3.x 未录是空心圆 | 窄栏只显示 `fiber_manual_record_outlined` | 录制图标、监控中加橙点、录制中红点加“录制中”（之后 A10.3 又重新设计） |
| d | 调过音量后画面左侧出现蓝色喇叭按钮 | — | 不是应用画的（应用的提示在画面中间） | 无代码改动；判断是 HyperOS 的系统音量指示，待截图确认 |

## 结果

- 每条一次提交（`bbc7aa6b0`、`aadad46ef`、`13e0f7f09`、`edb8531fb`、`dfcb14000`、`ef1380904`、`95c8b4da7`、`fffd28b31`、`bfcca456b`、`6e0be540b`、`f01c87861`），记录提交 `f4cb41c68`（2026-10-01）。改动范围：`apps/pure_live`；`packages/live_core`（文字清理、`LiveMessage` 只加字段、快手表情表、YY 预置表）；`packages/live_danmaku`（文字清理、表情片段）；`packages/live_ui`（状态视图按钮图标、`EmoteText` 本地图片）。
- 测试：`live_core` 3590 个通过（新增 4）、`live_danmaku` 1568 个（新增 7）、`live_ui` 39 个（新增 2）、应用 215 个（新增 10）；`flutter analyze` 无问题。
- 偏差：真机只读探测约 5 分钟（YY 82 个在播详情、快手房间页一次）；没有往手机装包。第 a 条是按代码推断的防御性修改，没在真机复现。
- 翻译键：新 `duration_minutes`、`duration_hours`、`duration_days`、`live_play_started`、`room_live`、`search_scope*`、`search_failures_*`、`search_proxy_settings`；删 `live_play_started_days/hours/minutes`、`room_live_hours/minutes`、`search_partial_failure`。

## 验证

- 自动测试：见上；每条对应的测试文件写在 [record.md](record.md) 各节（例如第 4 条 `favorite_test` 的 360 宽 12 个开播用例，修改前失败）。
- 真机：第 1～8 条在 2026-10-02 的 S02.2 冒烟里间接看过（关注页标签、表情图、搜索提示都正常）；第 a 条（画中画回来）没复验；第 d 条没截图确认。

## 留下的问题

| 内容 | 去向 |
|---|---|
| 画中画进出后控制条的真机复验 | [O02.1](../../../O-Android系统集成/O02-画中画/README.md) |
| 左侧蓝色喇叭的截图确认；如果是系统音量指示，要不要改成调播放器音量（改变 3.x 行为，要先问用户） | O02.1 同一次上机时截图；后来 A07.12 把房间音量和手势统一成系统媒体音量（审查 B-3） |
| 飞行弹幕里显示表情图片 | 后来已做（`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart` 的 `emotes` 参数，表情码飞成图片）；S02.2 冒烟看到“飞行弹幕带表情图” |
| CC 的表情包 | CC 弹幕接入时一起带上（D01 未接入） |
| 观察到的不稳定测试 `live_play_more_test` 的助眠用例 | 现在用 `until` 按条件等（`live_play_more_test.dart:77`），见 [S01](../../S01-自动测试/README.md) |
