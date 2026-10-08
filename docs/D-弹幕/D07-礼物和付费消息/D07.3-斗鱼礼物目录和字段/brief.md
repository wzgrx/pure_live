# D07.3 斗鱼礼物目录（betard）和礼物字段：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 2 节斗鱼、第 3 节斗鱼、第 7 节 D07.3；用户 2026-10-09（D-040）。
- 现象：斗鱼礼物行只有“名称 ×数量”，没有图、没有价值，分不清火箭和荧光棒。
- 为什么现在做：第二档；斗鱼是国内五大，礼物最多的平台之一。
- 已经做过的：E05.5（`LiveGift`）——开工前确认已合并；D01.3（斗鱼弹幕）。

## 目标和验收

1. 进房时从已请求的 `betard` 回答里读出房间礼物表，不多发请求。
2. `dgb` 礼物填好 `unitPrice`、`totalValue`、`unit = fen`、`iconUrl`、`tier`（表里有的）；背包礼物（`gfid` 0）编号取 `pid`、`free = true`。
3. `comboKey`、`comboTotal` 按 `hits` 填；送礼人的 `userLevel`、`fansName`、`fansLevel` 填上。
4. 表里没有的礼物照旧显示名称，不报错。
5. 第 2 阶段：完整礼物接口核实结果写进 record.md；能取到时补进表。

## 现状（读代码得出）

- `packages/live_danmaku/lib/src/sites/douyu.dart:182`（`dgb` 分发）、`:301`（`gift`，`DouyuGift`）。
- `packages/live_core/lib/src/sites/douyu/douyu_api.dart:346`（`betard/<rid>`），回答里 `room_gift.gift` 没有读。
- 样本：`fixtures/douyu/S05-offline/body.json`（`betard`，13 个礼物，例如 196 火箭 `price` 50000 `unit` 2、`pc_icon` 相对路径、`gift_effect` 143）；`fixtures/douyu/danmaku/S13-live`（125 条 `dgb`，119 条 824 荧光棒）、`S15-gifts`（57 条 `dgb`）。字段：`gfid`、`gfn`、`gfcnt`、`hits`、`bcnt`、`level`、`bnn`、`bl`、`brid`、`ic`、`receive_nn`、`receive_uid`。

## 3.x 基线

- 3.x 不上报斗鱼礼物；`betard` 的请求头（Edge 114 UA，`douyu_api.dart:148`）照旧。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`（样本隐私）；`fixtures/README.md`（录样本、脱敏）。
3. 本文件夹 `README.md`；E05.5 的 README（字段）；`docs/D-弹幕/D01-平台弹幕协议/D01.3-斗鱼弹幕/` 的记录。

## 范围

- 可以改：`douyu.dart`、`douyu_api.dart` 和斗鱼的弹幕参数类；`fixtures/douyu/`（新样本、冻结输出）；对应测试。
- 不能改：斗鱼的播放、搜索、聊天解析；其他平台；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 读 `betard` 的礼物表、c2 `dgb` 的字段 | 见“范围” | 样本测试通过，冻结输出更新 |
| 2 | c3 核实完整礼物接口，能取到就补进表（访问真实接口录样本，脱敏） | `douyu_api.dart`、新样本 | record.md 写结论；有接口时测试覆盖 |

## 测试

- `packages/live_core/test/sites/` 斗鱼：从 `S05-offline/body.json` 解出 13 个礼物，火箭单价 50000、图标完整地址。
- `packages/live_danmaku/test/sites/` 斗鱼：`S13-live` 里荧光棒 `free`、`pid` 编号；火箭类 `tier = precious`；`hits` 的连击键；等级和粉丝牌。
- 不访问真实平台（第 2 阶段录的样本进 `fixtures/`，测试只读样本）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 斗鱼热门直播间，开礼物 | 付费礼物有图（A08.11 做完后）、有价值；荧光棒没有价值 |

## 风险和注意

- `betard` 的表只有房间的付费礼物（样本 13 个），大部分实际收到的礼物不在表里，别当成“没有礼物”。
- 图标前缀要核实，别用样本里猜的域名。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`dart test`（`live_core`、`live_danmaku`）；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.3`；提交信息以 `[D07.3]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；礼物表从哪来、多少个；完整接口的结论；测试数量；改了哪些文件。
