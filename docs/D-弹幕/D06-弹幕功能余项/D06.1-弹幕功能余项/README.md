# D06.1 弹幕功能余项：功能清点里弹幕部分的 3 项缺失、2 项有问题

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为**不做**；登记时规模中）
- 类型：功能
- 来源：2026-10-02 功能清点（[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 9 节“弹幕”）：176 个 Android 功能点里弹幕部分有 3 项缺失、2 项有问题，当时开这个任务收拢
- 旧编号：T06c.4
- 相关：决定 D-029（改“不做”的依据）；核对报告 [V03.3 功能清点和已批准升级核对](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)；做完这 5 项的任务 [D05.1](../../D05-弹幕设置生效/D05.1-弹幕设置生效/README.md)、[D03.2](../../D03-飞行弹幕引擎/D03.2-飞行弹幕里的表情图片/README.md)、[A08.4](../../../A-界面设计/A08-弹幕界面/A08.4-画面弹幕点按和长按/README.md)；同时关掉的同类任务 C01.3、Q04.1

## 是什么

功能清点（2026-10-02）把 3.x 的弹幕功能点逐项对照 4.0.0，下面 5 项不是“完成”，开了这个任务一起补：

| 功能点 | 当时的状态 | 3.x（`git show v3.2.11:lib/...`） | 当时 4.x 的问题 |
|---|---|---|---|
| F-DM-04 弹幕帧率（跟随屏幕或固定） | 有问题 | `modules/live_play/widgets/video_player/video_controller.dart:90` | 设置只改面板上的数字，主画面的弹幕层没收到 `fps`，每个刷新周期都画 |
| F-DM-05 弹幕字体 | 缺失 | `video_controller.dart:91` | `DanmakuLook` 没有字体字段 |
| F-DM-06 纯文字模式（不显示表情） | 有问题 | `video_controller.dart:76` | 弹幕层没有表情图，也就没有“去掉表情”这一步 |
| F-DM-13 画面上的弹幕点按、长按（复制、屏蔽此用户、屏蔽关键词） | 缺失 | `video_controller.dart:132` | 弹幕层整层 `IgnorePointer`，设置里两个开关没人读 |
| F-DM-16 飞行弹幕里的表情图片 | 缺失 | `core/emoji/models/unified_emoji_model.dart:4` | 表情只在聊天列表是图片，飞行弹幕是代码原文 |

## 为什么不做

这 5 项在登记本任务的同一天已经由别的任务做完（和飞行弹幕层重写 D03.1 一起，代码提交 `0451ac8c6`，合并 `1071b4e25`，2026-10-02），本任务没有剩下要做的：

| 功能点 | 由谁做完 | 现在的代码 |
|---|---|---|
| F-DM-04 | D05.1 c1 | `apps/pure_live/lib/features/live_play/player/player_view.dart:475`（`resolvedDanmakuFps`）、`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:130`（`danmakuFrameDivisor`） |
| F-DM-05 | D05.1 c2 | `apps/pure_live/lib/shared/danmaku/danmaku_settings.dart:25` |
| F-DM-06 | D05.1 c3 | `danmaku_settings.dart:26`（`textOnly`）、`danmaku_overlay.dart:373`（`_segments`） |
| F-DM-13 | A08.4 | `danmaku_overlay.dart:292`（`messageAt`）、`player_view.dart:416-450`（`_danmakuAt`、`_openMessage`） |
| F-DM-16 | D03.2（随 D03.1 c1、c8） | `danmaku_overlay.dart:585`（`_record` 画表情图）、`:861`（`_EmoteImages`） |

2026-10-03 的 V03.3 核对把这 5 项在功能清点里改成“完成”，本任务按 D-029 改“不做”（不再单独做，去向写在登记表的 `note`）。

## 真机验证的去向

“完成”的依据要有真机结果（D-029 的口径）。5 项里：

- F-DM-16：[S02.2 冒烟](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)（2026-10-02）看到飞行弹幕带表情图，有结果。
- F-DM-04、F-DM-05、F-DM-06：[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 3 条，**还没有结果**；建议和 [D04.1 的真机验证](../../D04-数据流和性能/D04.1-弹幕性能和可读性/verify.md)同一轮看（见 [D05 子分类](../../D05-弹幕设置生效/README.md)“路线”）。
- F-DM-13：CHECKLIST 第 2 节第 6 条，**还没有结果**（A08.4 的记录写明 K90 没验证）。

## 以后在什么条件下重新考虑

- 本任务不会再打开：要补的点已经做完。
- 真机看出这 5 项有问题时，在对应的子分类开**新任务**（帧率、字体、纯文字归 D05，表情图归 D03，点按长按归 A08），不复用本编号。
- 功能清点以后再发现弹幕部分的缺失或问题（例如本轮核对发现的：小窗不用弹幕字体、不画自带表情图，见 [D03](../../D03-飞行弹幕引擎/README.md)、[D05](../../D05-弹幕设置生效/README.md) 的已知问题），同样在 D06 或对应子分类登记新任务。
