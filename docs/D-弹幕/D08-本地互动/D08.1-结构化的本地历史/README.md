# D08.1 结构化的本地历史：本地弹幕进记录、重进房间放回

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.6](../../../V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md) 第 2.2 节 P2、P3，第 4 节 E5，第 5.3 节（做法 A）；用户 2026-10-09 点名“记录”“历史”（D-040）
- 相关：本地互动界面 [A08.2](../../../A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md)（c12 记录）；后续 D08.2（最近发过）、D08.3（记“升级”）、D08.4（连击记一条）；备份 J03、设备同步 J05；存储 J02；决定 D-018、D-040（“进房放回”默认开是写明的例外）；任务书 [brief.md](brief.md)

## 目标

1. 自己发过的本地弹幕、送过的礼物、加过的币都记下来，按类型、按直播间能看；点一条可以“再发一次”。
2. 换界面语言后记录跟着换语言（存的是数据，不是拼好的句子）。
3. 重进同一个直播间时，最近发过的本地弹幕放回聊天列表（标“之前发的”），不会一离开就没了。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 存什么 | 30 条拼好的句子（`v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart:905-910`） | 同：`localInteraction.history`（`StringListSetting`，`packages/live_store/lib/src/settings/settings.dart:1294`），`_withHistory`（`features/live_play/local_interaction/logic/local_interaction.dart` 的 `recharge`、`sendGift`） | 结构化的表 |
| 记哪些 | 送礼、加币 | 同；本地弹幕不进记录（`createChat` 不写，`room_controller.dart:1159` 的 `addLocal` 只进 `ChatFeed`） | 弹幕、礼物、加币、升级 |
| 看 | 面板 10 条、设置页能清空 | 面板和设置页都显示 30 条、能清空（`local_interaction_panel.dart:447-527` 的 `LocalHistory`，清空 `:519`） | 分段“全部 / 弹幕 / 礼物 / 币”，每条时间和直播间，点一条再发一次 |
| 离开直播间 | 没了 | 没了 | 24 小时内重进放回最多 20 条 |

## 方案（V03.6 第 5.3 节，做法 A，D-003 维护者选 A）

- c1 新表 `local_events`（`packages/live_store/lib/src/database.dart` 加建表语句，`schemaVersion` 1 → 2 带迁移；新文件 `local_events.dart` 管读写）：`id`、`at`（毫秒）、`kind`（`chat`、`gift`、`recharge`、`level`、`legacy`）、`platform`、`roomId`、`roomName`、`text`、`giftId`、`count`、`coins`、`style`（本地弹幕发出时的样式 JSON，可空）。最多 **2000 条**，超出从旧的删。
- c2 写入：`LocalInteraction` 发弹幕、送礼、加币时写一条（拼句子的 `_withHistory` 保留，照旧写 `localInteraction.history`，让覆盖回 3.x 时仍有记录——D-018 键名和含义不变）。
- c3 旧记录迁移：第一次启动时把 `localInteraction.history` 的 30 条句子转成 `kind = legacy` 的记录（只读迁移，原键不删）；迁移做一次，在 `meta` 表记一笔。
- c4 备份带上这张表（J03 的 v4 备份加一节）；设备同步作为一项可选内容（J05，“同步前勾选内容”里加一类，默认不勾）。
- c5 界面（照 A08.2 的样子，在 A08.2 README 补一条）：互动面板的“本地互动记录”和设置页同一个组件，改成分段按钮“全部 / 弹幕 / 礼物 / 币”，每条显示时间和直播间名；点一条弹幕或礼物 →“再发一次”（礼物要扣币，余额不够照旧提示）；设置页加“导出到剪贴板”。清空的撤销归 A08.13（V03.6 E2），本任务不改清空。
- c6 进房放回：新设置 `localInteraction.replayOnEnter`（**默认开**，D-040 写明的例外：只放回自己发过的、只有自己看得到；关掉和现在一样）；进直播间时同一个 `platform + roomId` 24 小时内发过的本地弹幕，最多 20 条，按时间放在列表顶上，标“之前发的”（不飞过画面）。

## 验证

- 自动测试和真机见 brief.md。

## 留下的问题

- 记录里的直播间名是发送时的名字；主播改名不回写（用 `roomId` 查）。
