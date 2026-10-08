# E05.5 统一礼物模型 LiveGift 和统一礼物文字：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a7e652b7cfafd911e`）
- 分支和提交：`worktree-agent-a7e652b7cfafd911e`，基于 master `595a2385e`；阶段 1、阶段 2 各一次提交（见文末）
- 任务书：brief.md；说明：README.md（登记提交 `68ceeeb44` 写的，和本记录同一个文件夹）；调研：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2、3、6.1、7 节

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 `LiveGift` 和三个枚举 | 做了：`packages/live_core/lib/src/live_gift.dart`，从 `live_core.dart` 导出 | 单位枚举照 README 的名字（`fen`、`goldSeed`、`silverSeed`、`diamond`、`redBean`、`point`、`bits`、`kicks`、`cheese`、`starBalloon`、`douyinCoin`、`other`）；`tier` 是算出来的（getter），不是存的字段 |
| c2 `giftTierOf` | 做了：`giftTierOf(unit, totalValue, {free})`，折算只在一张表 `giftUnitsPerYuan`，门槛 `giftValuableYuan` 10、`giftPreciousYuan` 100 | `free` 用命名参数（代码检查不允许布尔位置参数） |
| c3 九个平台的类是 `LiveGift` 的子类 | 做了：哔哩哔哩、斗鱼、虎牙、猫耳、克拉克拉、niconico、YouTube、百度的类都 `extends LiveGift`；Kick 新建 `KickGift` | 虎牙 `HuyaGift.id` 从整数改成文字（`'22225'`，0 是空），因为公共字段 `id` 是文字；哔哩哔哩 `BilibiliGift` 多了 `free`（银瓜子）、`kind`、`unitPrice` 三个构造参数 |
| c4 文字统一成“名称 ×数量” | 做了：克拉克拉、niconico、Kick 改了；YouTube 也从 `sent Donut` 改成 `Donut ×1` | YouTube 不在 README 的三个里，但它也是平台的整句（英文），一起统一；YouTube 的文字不是 `sent <名称>` 时没有名称，照旧显示原文 |
| c5 `live_message.dart` 的注释 | 做了：`LiveMessageType.gift` 写明 `data` 是 `LiveGift`；`LiveMessage` 加了只读的 `gift`（`data` 是 `LiveGift` 时就是它） | |
| 界面 | 没改 | 任务书不改界面；聊天列表照旧读 `message`（`chat_list.dart:657`），文字已经是“名称 ×数量” |
| 冻结输出 | 没改 | 9 个平台的 `expected.json` 里没有旧的礼物整句（`我送了`、`を贈りました`、`送出了` 都搜不到），测试也是按平台类的字段比的；新公共字段的断言直接写在测试里 |

## 根因

- 没有统一的礼物数据：`LiveMessageType.gift` 的注释还是 “Gift (not shown yet)”（`packages/live_core/lib/src/live_message.dart:8`），各平台的礼物类之间没有共同的类型，应用只能用 `message` 一句话（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:657`）。
- 名字出现两遍、写死中文：克拉克拉 `packages/live_danmaku/lib/src/sites/kilakila.dart:341`（“我送了{收礼人}{数量}个{礼物}”）、niconico `niconico.dart:452`（日文整句带送礼人和贡献名次）、Kick `kick.dart:179`（“X 送出了 …（N Kicks）”）；YouTube `youtube.dart:677` 是英文的 `sent Donut`。礼物行前面已经印了 `userName`。（行号是 master `595a2385e` 的。）

## 设计选择（D-003，按任务书和 README 的方案 A）

1. **平台类是子类**（README c3 选 A）：`data` 仍是平台的类，独有字段（猫耳福袋、niconico 留言和名次、YouTube 原文、斗鱼 `hits`、虎牙 `lPayTotal`）都在，老测试按类比较不用大改；应用以后只认 `LiveGift`。`LiveGift` 是 `base class`（`final class` 不能继承）。
2. **相等**：`LiveGift ==` 要求同一个类（`runtimeType`）和全部公共字段相等；子类再比自己的字段。所以平台类和普通 `LiveGift` 永远不相等，测试里的常量要写全公共字段（哔哩哔哩银瓜子要写 `free: true`）。
3. **送礼人不进 `LiveGift`**：用 `LiveMessage` 的 `userName`、`userId`、等级、粉丝牌、徽章，屏蔽和名字样式对礼物和聊天一样起作用（README c1 最后一段）。
4. **价值可空**：`unitPrice`、`totalValue`、`comboTotal` 是 `int?`，没有就是 null（和“0 元”分开）；平台明说的 0（猫耳 price 0、niconico 0 点）照填 0 并标 `free`。
5. **斗鱼的连击键**：包里没有连击号；`hits` 有值时 `comboKey` 是“送礼人 uid:礼物编号”（背包礼物没有 `gfid`，用名称）。和 D07.1 的兜底规则一样，只是斗鱼先填好。
6. **档位门槛和海外折算是临时的**：国内按固定汇率（金瓜子 1000、分 100、钻石 10、抖币 10 = 1 元）；海外粗算（Bits、Kicks 14 ≈ 1 元，치즈 190，별풍선 1.7，点数 21）；红豆、银瓜子、`other` 不进表，一律 `normal`。A08.11 评审时列出来定，改表一处生效。
7. **统一的“送出 小心心 ×3”文字（带翻译）不在本任务做**：任务书不改界面，`message` 是不分语言的“名称 ×数量”；“送出”“开通”这些翻译键是 A08.11 礼物行的一部分（V03.5 第 6.3 节）。
8. **niconico 的贡献名次、Kick 和 niconico 的价值不再出现在文字里**：都留在数据里（`contributionRank`、`totalValue`），A08.11 的礼物行画价值时再显示。

## 各平台填了哪些公共字段

| 平台（类） | `id` | `count` | `kind` | `comboKey` / `comboTotal` | `unitPrice` / `totalValue` / `unit` | `free` | `iconUrl` | `receiverName` |
|---|---|---|---|---|---|---|---|---|
| 哔哩哔哩 `BilibiliGift` | `giftId`/`gift_id` | `num`、连击 `total_num`、上舰月数 | 上舰 `membership`，其余 `gift` | `batch_combo_id` / — | 上舰 `price` / 金瓜子总价（只有金瓜子时） / `goldSeed` | 银瓜子 `SEND_GIFT` | — | — |
| 斗鱼 `DouyuGift` | `gfid` | `gfcnt` | `gift` | uid:礼物（`hits` 有值时） / `hits` | — / — / `other` | — | — | `receive_nn` |
| 虎牙 `HuyaGift` | `iItemType`（文字） | `iItemCount` | `gift` | — / `iItemGroup` | — / `lPayTotal` / `other`（单位没核实） | — | — | — |
| 猫耳 `MissevanGift` | `gift_id` | `num` | `gift` | — | `price` / 单价 × 数量 / `diamond` | 单价 0 | `icon_url` | — |
| 克拉克拉 `KilakilaGift` | `c.id` | `c.doubleCount` | `gift` | — | 单个的价（礼物行、或只送一个时） / 红豆总价 / `redBean` | 总价 0 | `c.pic` | `c.giftReceiverName` |
| niconico `NiconicoGift` | `item_id` | 1 | `gift` | — | `point` / `point` / `point` | 0 点 | — | — |
| YouTube `YouTubeGift` | — | 1 | `gift` | — | — | — | `giftImage` | — |
| 百度 `BaiduLiveGift` | `gift_id` | `gift_count` | `gift` | — | —（`total_value` 的单位没核实） | `is_free` | `gift_url` | — |
| Kick `KickGift`（新） | — | 1 | `gift` | — | `gift.amount` / 同 / `kicks` | — | — | — |

没有新解析任何字段（`coin_type` 原来就读，只多用来标免费）。平台没给的（斗鱼单价和图标、虎牙连击号 `lComboSeqId`、哔哩哔哩单价和图标、猫耳连击、克拉克拉连击号）是 D07.3～D07.6 的。

## 改了哪些文件

- `packages/live_core/lib/src/live_gift.dart`（新）、`live_message.dart`、`live_core.dart`
- `packages/live_danmaku/lib/src/sites/`：`bilibili.dart`、`douyu.dart`、`huya.dart`、`missevan.dart`、`baidulive.dart`（阶段 1）；`kilakila.dart`、`niconico.dart`、`kick.dart`、`youtube.dart`（阶段 2）
- 测试：`packages/live_core/test/live_gift_test.dart`（新）；`packages/live_danmaku/test/` 下 `douyu_test.dart`、`huya_test.dart`、`missevan_test.dart`、`sites/bilibili_test.dart`、`sites/baidulive_test.dart`、`sites/kick_test.dart`、`sites/kilakila_test.dart`、`sites/niconico_test.dart`、`sites/youtube_test.dart`

## 新设置、翻译键、门禁基线

- 都没有。

## 测试

- 新增 `live_gift_test.dart` 9 个（默认值、数量下限、文字、档位、相等、`LiveMessage.gift`、`giftTierOf` 每种人民币单位在 9.9、10、99.9、100 元的边界、9.99 元、免费和没有价值、海外粗算）。
- 改了 9 个平台测试文件：每个平台断言 `data` 的公共字段（单位、种类、连击、价值、免费、图标、档位），哔哩哔哩上舰是 `membership` 和 `precious`；克拉克拉、niconico、Kick、YouTube 的 `message` 是“名称 ×数量”，不含送礼人。
- `live_core` 3675 个、`live_danmaku` 1595 个全部通过；应用的礼物行测试（`live_play_more_test.dart`、`live_play_more_page_test.dart`）没动、照过。门禁结果见下。

## 真机上要看的

- 见 [verify.md](verify.md)：哔哩哔哩、斗鱼礼物行照旧；克拉克拉、niconico 的礼物行名字只出现一次，文字“名称 ×数量”。

## 提交和门禁

- `c7a1a9549` [E05.5] Add the LiveGift model and make five platforms' gifts extend it（阶段 1：模型、`giftTierOf`、哔哩哔哩、斗鱼、虎牙、猫耳、百度）
- `d570c7774` [E05.5] Give KilaKila, niconico, Kick and YouTube gifts the shared text（阶段 2：克拉克拉、niconico、Kick、YouTube 的类和文字）
- 之后一次提交加本记录和 verify.md。
- `bash tools/gate/gate.sh --all` 在两个代码提交上通过（`gate: passed (all, 14 members)`）；这时任务文件夹还没放进来，因为本分支里没有 E05.5 的登记（登记在 `68ceeeb44`，还没合并到 master），文档检查会报“没登记的任务文件夹”。试着合并 `68ceeeb44`（不提交）：没有冲突；运行 `python3 tools/docs/docs.py` 重新生成 `docs/TASKS.md` 和 E05 的 README（多出本记录和 verify.md 的链接）后，`docs.py --check` 通过。合并两个分支后要再运行一次 docs.py。
- `live_danmaku` 整包跑时 `twitcasting_test.dart` 的“silent socket is replaced”超时一次，单独跑通过，门禁里也通过；和礼物无关（机器忙时的计时）。
