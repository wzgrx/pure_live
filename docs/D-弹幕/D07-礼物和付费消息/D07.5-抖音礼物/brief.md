# D07.5 抖音礼物（受阻：先确认登录后能不能收到）：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 2、3 节抖音、第 7 节 D07.5；用户 2026-10-09（D-040）。
- 现象：抖音直播间没有礼物。
- **受阻**：匿名网页端收不到 `WebcastGiftMessage`（`docs/E-直播平台/E01-国内五大平台/E01.4-抖音/record.md` 第 284 行）。第 1 阶段就是解除受阻：确认登录后能不能收到。
- 已经做过的：E05.5、D07.1（开工前确认已合并）；D01.5（抖音弹幕，签名在本地算）。

## 目标和验收

1. 第 1 阶段：一份登录态的弹幕样本（热闹直播间，至少 60 秒），结论写进 record.md：收得到（有几条、字段号和 3.x 定义是否一致）或收不到（登记表改“不做”，DECISIONS 记一条）。
2. 第 2 阶段（收得到时）：`WebcastGiftMessage` 解成 `LiveGift`，名称、数量、抖币单价、图标、连击键和最终总数都有，样本测试覆盖。

## 现状（读代码得出）

- `packages/live_danmaku/lib/src/sites/douyin.dart:147-148`：只处理聊天和人数。
- 3.x 的字段号：`git show v3.2.11:lib/core/danmaku/proto/douyin.pb.dart` 的 `:1295`（`GiftMessage`）、`:1820`（`GiftStruct`）。
- 样本：`fixtures/douyin/danmaku/S13-live`（`WebcastGiftSortMessage` 32 条，没有礼物）。

## 3.x 基线

- 3.x 有协议定义但不上报礼物；聊天、人数照旧。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `fixtures/README.md`；`docs/specs/ENGINEERING.md`（不运行平台的私有 SDK）。
3. 本文件夹 `README.md`；`docs/D-弹幕/D01-平台弹幕协议/D01.5-抖音弹幕/README.md`。

## 范围

- 可以改：`douyin.dart`；`fixtures/douyin/danmaku/`；对应测试。
- 不能改：抖音的签名和连接；播放；版本号。不把登录态的 Cookie 写进仓库。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 用登录态录样本，确认礼物能不能收到（维护者做，要账号） | `fixtures/douyin/danmaku/`（脱敏后） | record.md 写结论；登记表改状态 |
| 2 | 按字段号解礼物和连击 | `douyin.dart`、冻结输出 | 样本测试通过 |

## 测试

- `packages/live_danmaku/test/sites/` 抖音：礼物的名称、数量、单价、图标；同一 `groupId` 的连击；`repeatEnd` 的总数。不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 登录抖音，进热闹的直播间 | 礼物行出现，连击一行 |

## 风险和注意

- 登录态样本的隐私：只留帧内容，替换 Cookie、uid、昵称。
- 收不到时不要再试别的签名或私有 SDK（D01 的风险规则）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`dart test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.5`；提交信息以 `[D07.5]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

能不能收到礼物；样本的情况；字段表；测试数量；改了哪些文件。
