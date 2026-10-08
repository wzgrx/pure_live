# E05.5 统一礼物模型 LiveGift 和统一礼物文字：任务书

## 背景

- 来源：V03.5 全平台礼物调研（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 0 节第 1 条、第 6.1 节、第 7 节第一行；用户 2026-10-09 要“所有平台的礼物都要有自己的显示设计，并且可以打开和关闭”，D-040 同意按方案 A 做。
- 现象：每个平台的礼物数据是自己的类，字段各不相同，应用只能用一句拼好的文字；niconico、Kick 的文字里带送礼人，礼物行前面又印一次名字。
- 为什么现在做：第二档；D07.1～D07.7、A08.11、A08.12、H01.8 都依赖它，是礼物这一串的第一步。
- 已经做过的：B-21（C01.2，礼物进聊天列表）、A08.6 c3（`showChatGifts`）。

## 目标和验收

1. `live_core` 有 `LiveGift`（字段见本文件夹 README 的 c1 表）和三个枚举 `LiveGiftUnit`、`LiveGiftTier`、`LiveGiftKind`，从 `package:live_core/live_core.dart` 导出。
2. 9 个上报礼物的平台（哔哩哔哩、斗鱼、虎牙、猫耳、克拉克拉、niconico、YouTube、百度、Kick）的礼物消息 `data` 都是 `LiveGift`（平台类是它的子类），现有字段一个不少；哔哩哔哩 `GUARD_BUY` 的 `kind` 是 `membership`。
3. 平台给了连击号的填 `comboKey`（哔哩哔哩 `batch_combo_id`、斗鱼按 `hits` 所在的连击，没有就空）；平台给了单价、总价、图标、免费标记的都填上；`tier` 由 `giftTierOf` 算。
4. 所有礼物消息的 `message` 是“名称 ×数量”；克拉克拉、niconico、Kick 不再带送礼人和整句；Kick 不再有写死的中文。
5. 聊天列表的礼物行照旧显示（文字变成“名称 ×数量”），没有别的界面变化。

## 现状（读代码得出）

- `packages/live_core/lib/src/live_message.dart:8-9`：`LiveMessageType.gift`，注释 “not shown yet”；`LiveMessage` 已有 `userLevel`、`fansName`、`fansLevel`、`badges`、`data`。
- 礼物类：`bilibili.dart:20`（编号、名称、数量、金瓜子总价、连击编号；`_gift` `:757` 只在金瓜子时记总价 `:766`；`_guard` `:784` 价格 × 月数）、`douyu.dart:301`（编号、名称、数量、连击 `hits`、收礼人）、`huya.dart:13`、`:256`（编号、名称、数量、连击、总价 `lPayTotal`）、`missevan.dart:16`、`:334`、`:518`（钻石单价、图标、福袋）、`kilakila.dart:13`、`:283`、`:310`（红豆总价、收礼人、图标、免费；文字 `:341`）、`niconico.dart:80`、`:432-452`（点数）、`youtube.dart:38`、`:669`（名称、图片）、`baidulive.dart:15`、`:293`（编号、名称、数量、免费、图标）、`kick.dart:108`、`:164-178`（没有类）。行号来自 V03.5（master `87dd63729`），按类名再找。
- 冻结输出：`fixtures/<平台>/danmaku/S*/expected.json`，测试在 `packages/live_danmaku/test/sites/`。

## 3.x 基线

- 3.x 不上报礼物；没有要保留的礼物行为。`LiveMessage` 的其他字段和 3.x 的对照不变。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节包的依赖方向：`live_core` 不依赖别的包；样本隐私）。
3. 本文件夹 `README.md`；V03.5 第 2 节一览表（每个平台有哪些字段）、第 3 节、第 6.1 节。

## 范围

- 可以改：`packages/live_core/lib/src/`（新文件 `live_gift.dart`、`live_message.dart` 注释、`live_core.dart` 导出）；`packages/live_danmaku/lib/src/sites/` 里上面 9 个平台的礼物类和礼物文字；`fixtures/*/danmaku/*/expected.json`（只更新礼物的部分）；对应测试。
- 不能改：聊天、醒目留言、通知的解析；界面（`apps/pure_live/lib/`，除非编译需要）；过滤链；设置；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 模型和枚举、c2 `giftTierOf`、c3 九个平台的类填它、c5 注释 | `live_core/lib/src/live_gift.dart`、9 个 `sites/*.dart`、冻结输出 | 测试通过；冻结输出只多字段 |
| 2 | c4 文字统一成“名称 ×数量”（克拉克拉、niconico、Kick） | `kilakila.dart`、`niconico.dart`、`kick.dart`、冻结输出 | 三个平台的礼物文字测试改好；应用的礼物行测试照过 |

## 测试

- 新 `packages/live_core/test/live_gift_test.dart`：字段默认值；`giftTierOf` 每种单位的门槛边界（9.99 元、10 元、100 元）；免费一律 `normal`。
- `packages/live_danmaku/test/sites/` 各平台：礼物消息的 `data is LiveGift`、`comboKey`、`unit`、`kind`；哔哩哔哩上舰是 `membership`；克拉克拉、niconico、Kick 的 `message` 不含送礼人。
- `apps/pure_live/test/features/live_play/` 里礼物行的现有测试照样通过（文字变了的跟着改）。
- 不访问真实平台；用样本时间的测试固定“现在”（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 进一个热闹的哔哩哔哩、斗鱼直播间，开着“在聊天列表显示礼物” | 礼物行照旧出现，文字“名称 ×数量” |
| 2. 克拉克拉或 niconico 有礼物时 | 名字只出现一次 |

## 风险和注意

- 冻结输出改动多：只改礼物相关的字段，提交里分开写，便于审查。
- 子类化时注意 Dart 的 `final class` 不能被继承：`LiveGift` 用普通类或 `base class`。
- 别把汇率写死在多处：只在 `giftTierOf` 的表里。

## 环境和提交

- `source ~/tools/purelive-env.sh`；改过的包跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart test`；`python3 tools/docs/docs.py --check`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/E05.5` 或本机工作区；提交信息以 `[E05.5]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；每个平台填了哪些字段、哪些平台没有的字段；冻结输出改了几个文件；测试数量；需要维护者定的折算和门槛。
