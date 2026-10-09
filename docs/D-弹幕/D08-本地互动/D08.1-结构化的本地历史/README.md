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

## 设计选择（D-003，维护者定，2026-10-09）

维护者按 D-003 定了下面这些（用户随时可以推翻）：

| 编号 | 要选的 | 定的 | 理由 |
|---|---|---|---|
| s1 | 表放哪 | `live_store` 新表 `local_events`（`schemaVersion` 1 → 2，`onUpgrade` 只加表和索引 `(platform, room_id, at)`）；`id` 用 `AUTOINCREMENT` | 照 c1；`AUTOINCREMENT` 让清空后的“撤销”能把记录按原来的 id 放回，新记录不会占用旧 id |
| s2 | 旧记录什么时候转 | 应用里第一次用到本地互动时（`localInteractionProvider` 建好、`adoptLegacyValues` 之后），不在 `LiveStore.open` 里 | 3.x 的导入在 `LiveStore.open` 之后才跑（`app/bootstrap.dart` 的 `importLegacyData`），放在打开数据库时会先记下“已转”，3.x 的 30 条就永远进不来 |
| s3 | 旧记录的时间 | 比现有最早的一条还早（现在没有就比“现在”早），按原来的顺序；界面上不写时间，写“旧记录” | 3.x 的句子本来没有时间；写一个假的时间会骗人 |
| s4 | 旧记录归哪段 | 只在“全部”里；“升级”（D08.3 写）也只在“全部” | 句子是拼好的，分不出是礼物还是币，硬猜会错 |
| s5 | 清空 | 清空同时清掉 `localInteraction.history` 和表；提示条的条数是表里的条数；“撤销”两样都放回（表里按原 id） | A08.13 的撤销照旧能用；不改清空的行为，只是多清一张表 |
| s6 | 显示多少 | 先 50 条，“显示更多（还有 N 条）”每次加 50 | 面板是一个 `ListView` 的子项，2000 条一次建出来太重 |
| s7 | 再发一次 | 每条弹幕和礼物右边一个文字按钮“再发一次”，点了就发，不先问；弹幕提示“已再发一次”，礼物照常扣币、显示横幅，余额不够照旧“体验币余额不足” | 点整行容易误触扣币；一个明确的按钮更稳；只在直播间里有（设置页没有房间） |
| s8 | 按直播间看 | 面板里分段下面一个“只看本直播间”筛选（只在直播间里有）；加币不属于任何直播间 | 目标 1“按直播间能看”；设置页每条都写了直播间名 |
| s9 | 加币记不记直播间 | 不记 | 加币按钮在设置页和面板是同一个组件，记了反而两处不一样 |
| s10 | 放回时用谁的身份 | 现在的身份（昵称、头衔、徽章），原来的文字；不飞过画面 | 表里不存身份（c1 没有这一列）；只是给自己看的回顾 |
| s11 | 放回放在哪 | `ChatFeed.addOldest` 放在所有行前面，id 取负数，不算进“N 条新弹幕”；同一个 `LiveRoomController` 只放一次，没有可放的也算一次（小窗交回来的房间已经有这次发的了） | “列表顶上”；不和平台消息抢位置 |
| s12 | 放回哪些 | 进房那一刻之前 24 小时、同一个 `platform + roomId`、只有弹幕、最多 20 条（最近的 20 条，按时间从旧到新） | 照 c6；这次进房后发的不会被再放一遍 |
| s13 | 备份 | 完整备份带 `localEvents` 一节（`{"events": [...]}`），有记录才写；恢复时整张表替换，并记下“旧记录已转”；文件里没有这一节（3.x、空记录、只备份关注）就不动 | 用户说“备份、清数据、恢复，记录还在”（真机第 4 步）；本地数据没有隐私问题（只在本机、只有自己看得到）；不写空节让老测试和 3.x 的文件一样 |
| s14 | 设备同步 | 一类可选内容“本地互动记录（N）”，默认不勾；不勾时其他内容照旧整包发 | 照 c4；记录是这台设备自己的 |
| s15 | 新设置放哪 | 设置页“画面上”一组，“显示本地体验等级”下面；面板里不放 | 面板已经很长；设置页有“设置 ›”入口 |
| s16 | 导出 | 设置页清空旁边“导出到剪贴板”，一行一条：`2026-10-09 20:05 · 主播 · 弹幕 · 晚上好`；旧记录 `旧记录 · 原句` | 照 c5 |

## 存储格式

- 表 `local_events`：`id INTEGER PRIMARY KEY AUTOINCREMENT`、`at INTEGER`（毫秒）、`kind TEXT`（`chat`、`gift`、`recharge`、`level`、`legacy`）、`platform`、`room_id`、`room_name`、`text`、`gift_id`（都是 `TEXT NOT NULL DEFAULT ''`）、`count`、`coins`（`INTEGER NOT NULL DEFAULT 0`）、`style TEXT`（本地弹幕发出时 18 个 `localInteraction.danmaku*` 设置的 JSON，可空）。最多 2000 条，写入时删掉最旧的。
- `meta` 表 `localEvents.legacyAdopted`：旧记录已转（值是转了几条）。
- 备份：`{"localEvents": {"events": [{"id": 3, "at": 1760011500000, "kind": "gift", "platform": "bilibili", "roomId": "6", "roomName": "主播", "giftId": "bili_snack", "count": 1, "coins": 10}, …]}}`，新的在前；空的字段不写。
- `localInteraction.history` 照旧写（D-018），覆盖回 3.x 时记录还在。

## 验证

- 自动测试和真机见 brief.md、[record.md](record.md)。

## 留下的问题

- 记录里的直播间名是发送时的名字；主播改名不回写（用 `roomId` 查）。
- 没开播的直播间放回本地弹幕后，弹幕列表不再显示“未开播”的说明（和现在在没开播的房间里发本地弹幕一样）。
- 数据库从 2 降回 1 的旧 4.x 打不开（drift 没有降级）；只影响装回 D08.1 之前的 4.x 测试包，3.x 不受影响（它用 Hive）。
