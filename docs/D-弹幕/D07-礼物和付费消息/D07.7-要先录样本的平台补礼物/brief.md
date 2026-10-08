# D07.7 要先录样本的平台补礼物：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 2 节、第 3 节、第 7 节 D07.7、第 8 节；用户 2026-10-09（D-040）。
- 现象：酷狗、六间房、LOOK、SOOP、PandaTV、SHOWROOM、TwitCasting、FC2 的直播间没有礼物；Kick 的礼物没有样本核对过。
- 为什么现在做：第三档；用户要“所有平台的礼物”，这些是剩下的、匿名能收到的平台。每个平台都要先录样本（PROCESS 第 2 节“平台”类）。
- 已经做过的：E05.5（开工前确认已合并）；各平台弹幕 D01.x（样本录的时候只留了聊天，`meta.json` 写着）。

## 目标和验收

1. 每个做了的平台：`fixtures/<平台>/danmaku/` 有一份带礼物的新样本（脱敏、`meta.json` 写清），record.md 有字段表。
2. 礼物解成 `LiveGift`：名称（没有就“礼物 {编号}”）、数量、单位和价值（有就填）、免费、连击键（有就填）；订阅类是通知。
3. 冻结输出更新，聊天的输出不变。
4. 录不到的平台写清原因，不硬猜字段。

## 现状（读代码得出）

- 见本文件夹 README 的表（行号来自 V03.5，master `87dd63729`）。
- 已有样本的说明：`fixtures/kugoulive/danmaku/S07-live/meta.json`（`dropped`：进场 201 共 37、礼物广播 602 共 16）、`S09-pk-chat`；`fixtures/sixroom/danmaku/S07-live/meta.json`（“gifts 201 … keeps only typeID”）；`fixtures/soop/danmaku/S07-live/meta.json`、`S09-live-ones-and-bars/meta.json`。

## 3.x 基线

- 3.x 这些平台都没有礼物（多数没有弹幕）。聊天照旧。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 2 节“平台”类）。
2. `fixtures/README.md`（脱敏）；`docs/specs/ENGINEERING.md`（不运行平台的私有 SDK、许可证）。
3. 本文件夹 `README.md`；E05.5 的 README；对应平台的 D01 任务记录。

## 范围

- 可以改：上面 9 个平台的 `packages/live_danmaku/lib/src/sites/*.dart`（礼物部分）和需要的礼物表请求（平台适配器）；`fixtures/<平台>/danmaku/`；测试；翻译文件。
- 不能改：聊天解析；连接方式（TwitCasting 只加 `gift=1` 参数）；其他平台；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 国内：酷狗 601、六间房 201、LOOK 102 | `kugoulive.dart`、`sixroom.dart`、`looklive.dart` | 样本和测试；字段表 |
| 2 | 韩国：SOOP 星气球和订阅、PandaTV 후원（开代理） | `soop.dart`、`pandalive.dart` | 同上 |
| 3 | 日本：SHOWROOM 礼物和礼物表、TwitCasting `gift=1` | `showroom.dart`、`twitcasting.dart` | 同上 |
| 4 | 其他：FC2 打赏和礼物、Kick Kicks 核对 | `fc2live.dart`、`kick.dart` | 同上 |

## 测试

- `packages/live_danmaku/test/sites/` 每个平台：样本里的礼物解出的字段；订阅是通知；聊天的冻结输出不变。不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 每个阶段挑一个平台的热闹直播间（海外开代理） | 礼物行出现，名称和数量对 |

## 风险和注意

- 录样本要访问真实平台：在本机录，不在测试里访问；样本里的昵称、uid、房间号按规则替换。
- 推断的服务号可能不对：录 2～3 分钟、挑礼物多的直播间。
- 9 个平台工作量大：可以按阶段拆成单独的任务（标题“接 D07.7”）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`dart test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.7`；每个阶段一次提交，信息以 `[D07.7]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每个平台：样本录到没有、字段表、解了什么、没做的原因；测试数量；改了哪些文件。
