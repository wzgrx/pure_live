# D06 弹幕功能余项

功能清点、审查和真机验证里发现的、弹幕方面零散的缺失和小问题，放不进 D01～D05 某一个长期范围、又不值得各开一个子分类的，在这里登记成任务；做完的去向记在任务里。

## 范围

- 包括：
  - 功能清点（[inventory/FEATURES.md](../../inventory/FEATURES.md) 第 9 节“弹幕（DM）和本地互动（LOC）”）里弹幕功能点的余项：状态不是“完成”、又没有明确归属的。
  - 跨几个子分类的弹幕小问题（例如同时涉及协议参数和直播间刷新的、同时涉及弹幕层和小窗设置的），先在这里登记，评估后能归到 D01～D05 的就开到那里。
- 不包括（归哪里）：
  - 有明确归属的问题直接开到对应子分类：协议 D01、过滤 D02、弹幕层 D03、数据流 D04、设置生效 D05；界面 A08；直播间什么时候连、断 C01。
  - 3.x 没有的新功能（例如“按住弹幕让它停住”V01.3、“同屏最大条数可以设置”V01.4）→ [V01 新功能提议](../../V-需求和反馈/V01-新功能提议/README.md)（D-026）。
  - 真机验证本身 → S02（这里只登记看出问题后的修补）。

## 现状：做到哪、怎么工作的

- 唯一的任务 D06.1（功能清点里弹幕部分的 3 项缺失、2 项有问题）在 2026-10-03 按 D-029 改成“不做”：F-DM-04、F-DM-05、F-DM-06 由 D05.1 做完，F-DM-16 由 D03.2 做完，F-DM-13 由 A08.4 做完（V03.3 核对）。现在 D06 没有在做的任务。
- 功能清点第 9 节 17 个弹幕功能点（F-DM-01～F-DM-17）现在都是“完成”；其中有真机结果的只有 F-DM-01（K90 第一轮 5 个国内平台有弹幕）和 F-DM-16（S02.2 冒烟），其余 15 项的真机结果在 [CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 2 节第 1～7 条，结果栏都是空的。
- 本轮（2026-10-07 docs v2）读代码发现、还没有任务的弹幕余项（详见各子分类的“已知问题”）：

| 余项 | 位置 | 和 3.x 比 | 记在哪 |
|---|---|---|---|
| 应用内小窗和画中画的弹幕不用弹幕字体、不画应用自带的表情图，“纯文字”只去掉消息自带的表情代码 | `apps/pure_live/lib/features/live_play/mini/compact_danmaku.dart:105`、`:190`、`:204-213` | 3.x 小窗用弹幕字体和同一个表情图集（`git show v3.2.11:lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart:35`、`:62`、`:86`），**比 3.x 少** | [D03](../D03-飞行弹幕引擎/README.md)、[D05](../D05-弹幕设置生效/README.md) |
| 主播换场后弹幕参数变了（TwitCasting、克拉克拉、SHOWROOM），直播间刷新不重连，弹幕停在旧的一场；“YouTube 显示全部聊天”改了要重新进房 | `apps/pure_live/lib/features/live_play/logic/room_controller.dart:785`；`apps/pure_live/lib/app/platforms.dart:227` | 3.x 这几个平台没有弹幕 | [D01](../D01-平台弹幕协议/README.md) |
| AcFun 付费直播提示“弹幕服务器连接失败”，应该是“没有弹幕” | `packages/live_danmaku/lib/src/connection_base.dart:55` | 3.x AcFun 没有弹幕 | D01 |
| 长按弹幕面板不显示等级（3.x 显示 `Lv.N`） | `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart:112-150` | **比 3.x 少**（`danmaku_message_actions.dart:19`） | D01（需要维护者决定，界面归 A08） |
| 多画面弹幕不跟帧率设置 | `apps/pure_live/lib/features/multiview/multiview_page.dart:878` | 比 3.x 少 | 已有任务 N01.2 |

## 代码地图

无：D06 没有自己的代码，余项的代码在各子分类的代码地图里（D01 `packages/live_danmaku/lib/src/sites/`、D03 `shared/danmaku/danmaku_overlay.dart`、D05 `shared/danmaku/danmaku_settings.dart` 和 `features/live_play/mini/compact_danmaku.dart`）。

测试：无（各余项的测试在对应子分类）。

## 3.x 基线

- 弹幕功能点的 3.x 位置都在 [inventory/FEATURES.md](../../inventory/FEATURES.md) 第 9 节的“3.x 位置”一列（例如 F-DM-04 `lib/modules/live_play/widgets/video_player/video_controller.dart:90`、F-DM-13 `:132`、F-DM-16 `lib/core/emoji/models/unified_emoji_model.dart:4`）。
- 小窗弹幕：`git show v3.2.11:lib/modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart`（94 行）；长按面板：`lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart`（125 行，第一行“用户名: 内容”和“Lv.N”）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 上表的余项都还没有登记任务 | 见上表 | 比 3.x 少的两项（小窗字体和表情、长按面板等级）会被当作已经“完成” | 写进本单元报告，请维护者决定开在 D06 还是对应子分类 |
| 功能清点里 15 个弹幕功能点标“完成”但没有真机结果 | CHECKLIST 第 2 节 | 和 D-029 的口径（“完成”要有 K90 结果或关键部分不靠原生和系统服务）有出入：这些都是纯 Dart 逻辑，按 D-029 可以算完成，但界面效果没人看过 | 建议和 D02.1、D04.1 的真机验证同一轮补看 |
| 功能清点 F-DM-10、F-DM-12 的“4.x 位置”过时：写的是 `app/platforms.dart:184`、`chat_list.dart:521`，现在是 `platforms.dart:204-208`、`features/live_play/danmaku/message_panel.dart` | [inventory/FEATURES.md](../../inventory/FEATURES.md) 第 9 节 | 按清点找代码会找错 | inventory 不归本组；写进本单元报告 |

## 相关决定和规范

- D-029：功能清点余项任务 C01.3、D06.1、Q04.1 不再单独做；功能点改“完成”要有 K90 结果或关键部分不靠原生和系统服务。
- D-026：3.x 没有的新功能先在 V01 提议，不在 D06 直接开任务。
- [PROCESS.md](../../PROCESS.md) 第 6 节（新功能和需求）、第 12 节（季度复查长期没动的任务）。

## 测试和验证

- 自动测试：无（见各子分类）。
- 真机：CHECKLIST 第 2 节第 1～8 条是弹幕功能点的真机步骤；D06.1 关掉后，F-DM-04～06 的真机结果由 D05 跟进，F-DM-13 由 A08.4 跟进。

## 路线

1. 维护者对上表的余项表态：开新任务（建议“小窗和画中画的弹幕字体和表情图”开在 D05 或 D03，“换场后弹幕参数变了要重连”开在 C01 或 D01，“长按面板的等级”先定要不要），或写明不做。
2. 以后功能清点、审查、真机验证发现的弹幕零散问题，先在这里登记，评估后能归到 D01～D05 的就开到那里；新功能进 V01。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：—
- 进度：还没有任务


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D06.1 | 弹幕功能余项：功能清点里弹幕部分的 3 项缺失、2 项有问题 | 功能 | 不做 | — | — | [设计或说明](D06.1-弹幕功能余项/README.md) |

<!-- docs:生成结束 -->
