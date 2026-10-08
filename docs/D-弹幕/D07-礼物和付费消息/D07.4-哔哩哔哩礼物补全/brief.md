# D07.4 哔哩哔哩礼物补全：游客的 SEND_GIFT_V2、图标、舰长等级：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 2、3 节哔哩哔哩、第 6.4 节、第 7 节 D07.4；用户 2026-10-09（D-040）。
- 现象：没登录看哔哩哔哩只看得到上舰，看不到礼物；登录后的礼物没有图标和价值，连击只看到“×1”。
- 为什么现在做：第二档；哔哩哔哩是最常用的平台。
- 已经做过的：E05.5（`LiveGift`）、D07.1（合并）——开工前确认已合并（至少 D07.1 第 2 阶段要在本任务第 1 阶段之前或同时合并）；D01.32（粉丝牌、头像、访客提示）。

## 目标和验收

1. `SEND_GIFT`：`unitPrice`、`totalValue`、`unit`（金瓜子 / 银瓜子算免费）、`iconUrl`、`tier`；送礼人的粉丝牌和舰长和聊天行一样。
2. 每条 `SEND_GIFT` 都上报，`comboKey = batch_combo_id`；`COMBO_SEND` 给出累计 `comboTotal`；在 D07.1 的合并下，列表里一个连击一行、最终数字和 `COMBO_SEND.total_num` 一致。
3. 访客：`SEND_GIFT_V2` 解出名称、数量、金瓜子、编号；送礼人是打码昵称，不能“屏蔽此用户”（D-013）。
4. 没有新样本的部分不猜：第 2 阶段先录样本。

## 现状（读代码得出）

- `packages/live_danmaku/lib/src/sites/bilibili.dart`：分发 `:490-492`；`BilibiliGift` `:20`；类注释 `:73-74`（同一连击只报第一条）、`:179-186`；`_gift` `:757`（`:766` 金瓜子才记总价；`tid` 当消息编号）；`_guard` `:784`；`_superChat` `:835`。
- 样本：`fixtures/bilibili/danmaku/S13-live`、`S13-protover2-paired`、`S13-vectors`：`DANMU_MSG` 192、`SUPER_CHAT_MESSAGE` 22、`SEND_GIFT_V2` 2（内容已删），**没有 `SEND_GIFT`、`COMBO_SEND`、`GUARD_BUY`**（访客收不到）。
- protobuf 读取：`packages/live_danmaku/lib/src/codec/protobuf.dart`。

## 3.x 基线

- 3.x 不上报哔哩哔哩礼物（`v3.2.11:lib/core/danmaku/bilibili_danmaku.dart` 只有醒目留言 `:415`）。要保留：醒目留言、聊天的解析不变。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `fixtures/README.md`（脱敏规则；门禁查样本隐私）；`docs/specs/ENGINEERING.md`。
3. 本文件夹 `README.md`；D07.1、E05.5 的 README；`docs/D-弹幕/D01-平台弹幕协议/D01.32-哔哩哔哩访客昵称和粉丝牌/README.md`。

## 范围

- 可以改：`bilibili.dart`；`fixtures/bilibili/danmaku/`（新样本和冻结输出）；哔哩哔哩的礼物表请求（放平台适配器）；对应测试。
- 不能改：聊天、醒目留言、访客提示的行为；D-013；其他平台；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 字段、c2 每条都报和 `COMBO_SEND`（登录态的样本：维护者用自己的账号录，脱敏后进 `fixtures/`） | `bilibili.dart`、新样本 | 样本测试通过；和 D07.1 一起看合并后的数字 |
| 2 | c3 访客的 `SEND_GIFT_V2`（先录没删内容的访客样本），礼物表 `giftConfig`（匿名能取才做） | `bilibili.dart`、新样本 | 样本测试通过；record.md 写字段表 |

## 测试

- `packages/live_danmaku/test/sites/` 哔哩哔哩：新样本里 `SEND_GIFT` 的单价、图标、粉丝牌；连击每条都报、`COMBO_SEND` 的累计；银瓜子礼物 `free`；`SEND_GIFT_V2` 的字段；打码昵称的礼物不能屏蔽（和 D02.1 一致）。
- 不访问真实平台；用样本时间的测试固定“现在”（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 未登录，热闹的哔哩哔哩直播间 | 能看到礼物行（打码昵称） |
| 2. 登录后同一直播间 | 礼物有图、有价值；连击一行、最终数字对 |

## 风险和注意

- 登录态样本里有真实 Cookie、uid：录的时候只留帧内容，按 `fixtures/README.md` 替换，门禁的隐私检查要过。
- 每条都报以后消息数变多：合并在 D07.1，限速也在那里，本任务不要自己去重。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`dart test`（`live_danmaku`）；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.4`；提交信息以 `[D07.4]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新样本（哪个房间类型、多长、脱敏了什么）；`SEND_GIFT_V2` 的字段表；测试数量；改了哪些文件。
