# A08.4 画面弹幕点按和长按：复制、屏蔽此用户、屏蔽关键词

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02；记录写明 K90 没验证，见“验证”）；当时定的档位“应该”、规模中
- 类型：功能（界面照已确认的 A07.6“长按弹幕”面板，不另出图）
- 来源：C01.2“留给后续”第 5 项；旧的模块重构任务说明 M13.17（没有进登记表）第 3 项；`~/ref/notes/m13_notes.md`“tap/long-press on flying danmaku”
- 旧编号：F.2b、T06c.3（见 [MAPPING.md](../../../MAPPING.md)）
- 功能点：F-DM-13（见 [inventory/FEATURES.md](../../../inventory/FEATURES.md)）
- 相关：和 [D03.1](../../../D-弹幕/D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/README.md) 的 c9（弹幕层的命中和停住）一起开发；依赖 [D05.1](../../../D-弹幕/D05-弹幕设置生效/D05.1-弹幕设置生效/README.md)；面板是 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md) 的“长按弹幕”（后来由 A07.12 改成 `RoomMessagePanel`、A07.11 c8 加了关键词第二页）；相关提议 V01.3（按住弹幕让它停住，松手继续）；[specs/UI.md](../../../specs/UI.md) 附录 A 第 2、6 条
- 记录：[record.md](record.md)

## 目标

3.x 里点按或长按画面上飘过的弹幕，会停住弹幕并打开和弹幕列表长按同样的菜单（复制、屏蔽此用户、屏蔽关键词）；4.x 换成自己画的弹幕层后这个功能没了（设置里两个开关还在，但没人读）。做完后：设置“点按 / 长按”开着时，点中或长按中画面上的一条弹幕，弹幕层停住、打开同一个面板，面板关了继续飞；没点中照常显示或隐藏控制层、双击全屏；控制条显示时上下控制条范围内的点击不算弹幕（附录 A 第 2 条）。

## 3.x 和现状

### 3.x 的行为（`~/ref/v3ref`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 每条弹幕按设置带上点按、长按回调（开关关着就没有） | `modules/live_play/widgets/video_player/video_controller.dart:217-220` |
| 画面手势层先挡掉上下控制条范围内的点（控制条显示时），再把点的位置转给弹幕层；命中就不再显示 / 隐藏控制层 | `video_controller_panel.dart:69-84`、`:196-245`；`video_controller.dart:258-263`、`:984-995` |
| 命中后弹幕层暂停，打开“长按弹幕”面板（复制、屏蔽此用户、屏蔽关键词），面板关了继续；长按后 1 秒内的点按不再开第二次 | `video_controller.dart:132-149` |

### 开工时 v4 的样子

- 设置开关有（`enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction`，默认开，同 v3），只有设置面板读（`shared/danmaku/danmaku_settings_content.dart:197-213`）。
- 弹幕层整层 `IgnorePointer`，不记位置（`danmaku_overlay.dart:370`）；画面的点按只切换控制层（`player_view.dart:240-251`、`:389-393`）。
- 弹幕列表的长按面板已有（`features/live_play/danmaku/chat_list.dart:173-195`、`:521`）。

### 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 点、长按画面弹幕没反应 | 弹幕层换成自己的画法（I01.2）时没做命中检测，画面手势层也不问弹幕层 |
| P2 | 面板打开时弹幕照飞 | 弹幕层没有“暂停”（D03.1 V9、V10） |

### 对照（现在的代码，2026-10-03 核对）

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 设置开关 | `enableDanmakuTapInteraction`、`enableDanmakuLongPressInteraction` 默认开，每条弹幕按开关带回调（`lib/modules/live_play/widgets/video_player/video_controller.dart:217-220`） | 同名设置（默认开），在 `apps/pure_live/lib/features/live_play/player/player_view.dart:416-421` 读；长按手势只在长按开关开着时挂上（`:658-665`） | 照 3.x（做到） |
| 命中 | 弹幕层 `triggerItemAt`，手势层把点的位置转给弹幕层（`video_controller.dart:258-263`、`:984-995`） | `DanmakuOverlayState.messageAt`（`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:292`，按这一帧的位置、四周放宽 4、叠着时取后进来的）；`_danmakuAt`（`player_view.dart:416-439`） | 照 3.x，点按在按下的那一刻问（做到） |
| 控制条范围 | `shouldHandleVideoSurfaceTap`（`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:75`，用在 `:205`、`:235`） | `danmakuTapAllowed`（`player_view.dart:830`），条高按三种排布（内嵌、横屏、竖屏全屏，`:427-433`）；锁定时不问（`:417`） | 照 3.x（做到） |
| 打开什么 | 暂停弹幕 → `DanmakuMessageActions.show`（模态底部面板）→ 关了 `resume`（`video_controller.dart:132-149`） | `_openMessage`（`player_view.dart:443-450`）：弹幕层 `held` 置真 → `showRoomMessageActions`（`features/live_play/danmaku/message_panel.dart:20`）→ 关了恢复 | 和列表长按同一个面板（做到） |
| 长按后的点按 | 长按后 1 秒内的点按不再开第二次（`video_controller.dart:132-149`） | 不需要：手势竞争里长按赢了就不会再有点按 | — |

## 结果

- 改动清单（开发前定的，全部做到）：

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | 弹幕层给出“这个点上是哪条”（按这一帧的位置，照 D03.1 的 c9） | P1 |
| c2 | 补上 | 画面的点按、长按：控制条显示时上下控制条范围不问（照 v3）；开了哪个手势哪个才问弹幕层；没命中照原来（显示 / 隐藏控制层、双击全屏） | P1 |
| c3 | 保留 | 面板用 A07.6 的“长按弹幕”（`showChatMessageActions`），复制、屏蔽此用户、屏蔽关键词和列表长按同一套 | P1 |
| c4 | 补上 | 面板打开期间弹幕层暂停，关了继续（照 D03.1 的 c9） | P2 |

面板留在 `chat_list.dart`，直播间的画面和列表共用一个入口；多画面不在本任务的目录（`features/multiview/`），以后要用时再挪到 `shared/danmaku/`。

- 实际做的（详见 [record.md](record.md)）：
  - c1 `DanmakuOverlayState.messageAt`（现在 `shared/danmaku/danmaku_overlay.dart:292`），还有测试用的 `rectOf`（`:283`）。
  - c2 画面的点按、长按先问弹幕层：开关开着才问；控制条显示时上下控制条范围不问；锁定时不问；没命中照原来（显示 / 隐藏控制层、双击全屏）。点按在按下的那一刻就问（`onTapDown`，`player_view.dart:653-656`；双击要等 0.3 秒，弹幕已经走开），比 3.x 准。
  - c3 面板：当时在 `chat_list.dart` 加了顶层 `showRoomMessageActions`，列表长按和画面弹幕共用；后来 A07.12 把面板挪到 `features/live_play/danmaku/message_panel.dart`（`RoomMessagePanel` `:50`），名字不变。旧 README 写的 `showChatMessageActions` 已经没有了。
  - c4 弹幕层 `held`：整层停住，新弹幕不进，面板关了继续（`player_view.dart:485`）。
  - 没做的：面板没有挪到 `shared/danmaku/`（多画面不在当时的目录，直播间里放在 `danmaku/` 就够；多画面要用时再挪）。
- 根因：I01.2 换成自己的画法时弹幕层整层 `IgnorePointer`、不记位置（现在仍是 `IgnorePointer`，`danmaku_overlay.dart:673`，命中改由手势层来问），画面手势层也不知道有弹幕可点；设置面板的两个开关（A07.6）没人读。
- 没有新设置。
- 提交：代码 `0451ac8c6`（`feat(danmaku): U.2h flying layer, F.2a settings, F.2b tap and long press, F.1a keep-on`）；合并 `1071b4e25`（2026-10-02）；登记表写的是记录提交 `b8462638a`（和 D03.1、D05.1 同一个）。
- 开发前的“需要选的”：无。

## 性能任务：测量

不是性能任务。开发前的约束（原“风险和性能”）：

- 命中检测只在点按时算一次（遍历屏上最多 48 条），平时没有开销。
- 长按手势只在长按开关开着时挂上，免得影响画面的拖动。

## 验证

- 自动测试：`apps/pure_live/test/features/live_play/live_play_page_test.dart` 2 个：点一条飞着的弹幕出面板三项、弹幕停住、关了继续，长按出同一个面板；点按开关关时只切换控制层，另测控制条范围不命中。弹幕层的命中和停住在 `apps/pure_live/test/shared/danmaku_overlay_test.dart`（D03.1）。开发前列的测试项（原“测试和验证”）：弹幕层按位置命中；开关关时点弹幕只切换控制层；命中后出面板三项、弹幕层暂停、关了继续；控制条范围不命中。
- 真机：**没验证**。记录“没验证的”写的是“K90：真机上点小字弹幕好不好点中”，对应 [CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 6 条（“打开设置里的‘点按 / 长按’，在画面上点或长按一条飞过的弹幕 → 出现同样的三项”）。登记表却是“完成”（见[子分类页](../README.md)“已知问题”和本单元报告的建议）。

## 留下的问题

- 真机上点小字弹幕好不好点中（放宽 4 像素够不够）：待 K90；不够时调 `messageAt` 的放宽值。
- 多画面里的弹幕不能点（面板在 `features/live_play/`，多画面在 `features/multiview/`）：没有任务；多画面要用时把面板挪到 `shared/danmaku/`。
- “按住弹幕让它停住，松手继续”是另一个提议：V01.3（第三档）。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比，和 D03.1 一起开发 |
| 2026-10-02 | 开发完成（和 D03.1 的 c9 一起），待 K90 验证 |
| 2026-10-03 | 文档 v2：按功能说明模板重排，补上现在的文件:行和提交 |
