# E05.5 统一礼物模型 LiveGift 和统一礼物文字

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 0 节第 1 条、第 6.1 节、第 7 节（建议编号 E05.x）；用户 2026-10-09（D-040）
- 相关：决定 D-040、D-003、D-005、D-018；后续 [D07](../../../D-弹幕/D07-礼物和付费消息/README.md) 的 D07.1～D07.7、A08.11、A08.12、H01.8 都依赖本任务；任务书 [brief.md](brief.md)

## 目标

所有平台的礼物消息带同一种数据 `LiveGift`（名称、数量、连击、单价和单位、总价值、图标、档位、收礼人、种类），应用以后只看它，不再看各平台自己的类；礼物消息的 `message` 统一成“名称 ×数量”，不带送礼人，也不是平台的整句。这样聊天列表才能画统一的礼物行（A08.11）、做连击合并（D07.1）、按价值筛选（A08.12）。

## 3.x 和现状

| 方面 | 3.x | 现在（行号是 V03.5 写的，master `87dd63729`） | 要做到 |
|---|---|---|---|
| 礼物数据 | 只有枚举 `LiveMessageType.gift`（`v3.2.11:lib/common/models/live_message.dart:6`），不上报 | `LiveMessage(type: gift)`，`data` 是 9 个平台各自的类：`BilibiliGift`（`packages/live_danmaku/lib/src/sites/bilibili.dart:20`）、`DouyuGift`、`HuyaGift`（`huya.dart:13`）、`MissevanGift`（`missevan.dart:16`）、`KilakilaGift`（`kilakila.dart:13`）、`NiconicoGift`（`niconico.dart:80`）、`YouTubeGift`（`youtube.dart:38`）、`BaiduLiveGift`（`baidulive.dart:15`）；Kick 没有类（`kick.dart:164`） | 都是 `LiveGift`（或它的子类） |
| 模型注释 | — | `packages/live_core/lib/src/live_message.dart:8` 还写着 “Gift (not shown yet)” | 改成说明礼物数据 |
| 文字 | — | 多数“名称 ×数量”；克拉克拉“我送了豆咖 3 个念念相守”（`kilakila.dart:341`）、niconico 日文整句含送礼人（`niconico.dart:452`）、Kick“X 送出了 Kicks（100 Kicks）”写死中文（`kick.dart:178`） | 一律“名称 ×数量”；名字只在 `userName` |
| 应用 | — | 礼物行只用 `message`（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:657-689`） | 本任务不改界面；行照旧能显示 |

## 方案

- c1 `packages/live_core` 加 `LiveGift`（新文件 `lib/src/live_gift.dart`，从 `live_core.dart` 导出），字段照 V03.5 第 6.1 节：

| 字段 | 意思 | 例子 |
|---|---|---|
| `id`、`name` | 平台的礼物编号、名称 | `196`、`火箭` |
| `count` | 这次送的个数 | 10 |
| `comboKey`、`comboTotal` | 连击标识（平台给的连击号；没有时为空，D07.1 用“送礼人 + 礼物编号”兜底）、连击累计（可空） | 哔哩哔哩 `batch_combo_id`、斗鱼 `hits`、虎牙 `lComboSeqId`、17LIVE `combo.count` |
| `unitPrice`、`totalValue`、`unit` | 单价、总价值（平台单位的整数，可空）、单位（枚举 `LiveGiftUnit`：`fen`（人民币分）、`goldSeed`（金瓜子）、`silverSeed`、`diamond`（猫耳钻石）、`redBean`（克拉克拉红豆）、`point`（niconico、17LIVE、FC2）、`bits`、`kicks`、`cheese`（치즈）、`starBalloon`（별풍선）、`douyinCoin`、`other`） | 斗鱼 50000 分、哔哩哔哩 100000 金瓜子 |
| `free` | 免费礼物（银瓜子、荧光棒、背包、拍拍） | |
| `iconUrl` | 礼物图（平台给的地址，或按礼物表拼出来；可空） | 猫耳 `icon_url` |
| `tier` | 档位枚举 `LiveGiftTier`：`normal`、`valuable`、`precious` | |
| `receiverName` | 收礼人（连麦嘉宾时不是主播，可空） | 斗鱼 `receive_nn` |
| `kind` | 枚举 `LiveGiftKind`：`gift`、`membership`（上舰、开会员）、`subscription`、`tip`（打赏） | 哔哩哔哩 `GUARD_BUY` → `membership` |

  送礼人的等级、粉丝牌、舰长照用 `LiveMessage` 已有的 `userLevel`、`fansName`、`fansLevel`、`badges`，不进 `LiveGift`。
- c2 档位规则放在 `live_core` 一个纯函数 `giftTierOf(unit, totalValue, free)`：免费 → `normal`；人民币类按元 <10 `normal`、10～<100 `valuable`、≥100 `precious`（金瓜子 1000 = 1 元、分 100 = 1 元、猫耳 10 钻 = 1 元、抖币 10 = 1 元）；其他单位先用 V03.5 给的折算填一张表（Bits 100 ≈ 1 美元、Kicks 100 = 1 美元等），**门槛在 A08.11 的评审页列出来由维护者按 D-003 定**，这里只要表能改一处生效。没有价值的礼物（只有编号）一律 `normal`。
- c3 9 个平台的礼物类改成 `LiveGift` 的子类（**选 A**：保留平台独有的字段和类名，冻结输出和老代码不用大改；B 全部换成 `LiveGift`、丢掉平台类——不选，D07 的平台任务还要用独有字段），构造时填好公共字段；Kick 新建 `KickGift`。现在已有的字段一个不丢（冻结输出只多不少）。
- c4 文字：`message` = `名称 ×数量`（`count` 为 1 也写 `×1`，和现在多数平台一样）；克拉克拉、niconico、Kick 改掉；不再把送礼人、平台的整句拼进去（顺带解决 Kick 写死的中文，Z05.2 同类）。录制、多画面等只看 `message` 的老代码照常工作。
- c5 `live_message.dart:8` 的注释改成“礼物；数据是 `LiveGift`”。
- 不做：界面（A08.11）、过滤和合并（D07.1）、新平台的礼物解析（D07.3～D07.7）。

## 验证

- 自动测试：`packages/live_core/test/` 加 `live_gift_test.dart`（字段、`giftTierOf` 的表）；`packages/live_danmaku/test/sites/` 各平台的冻结输出更新（`fixtures/<平台>/danmaku/S*/expected.json`）。
- 真机：没有用户看得到的变化，除了克拉克拉、niconico、Kick 的礼物行文字；并入 A08.11 的真机一起看。

## 留下的问题

- 各单位的折算和档位门槛等 A08.11 评审时定（V03.5 第 8 节最后一条）。
- 虎牙 `lPayTotal`、百度礼物的价值单位没有核实（V03.5 第 8 节），先填 `other` 并在代码里注明。
