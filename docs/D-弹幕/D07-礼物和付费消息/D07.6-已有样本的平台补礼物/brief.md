# D07.6 已有样本的平台补礼物：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 2 节一览表、第 3 节各平台证据、第 7 节 D07.6；用户 2026-10-09（D-040）。
- 现象：虎牙、猫耳、克拉克拉连击一下一行；AcFun、17LIVE、BIGO 没有礼物；Twitch 的 Bits 是普通聊天、送 N 个订阅出 N+1 条；CHZZK 订阅是普通聊天；YouTube 贴纸没图。
- 为什么现在做：第二档；这些平台的样本仓库里已经有，不用先录。
- 已经做过的：E05.5（`LiveGift`）——开工前确认已合并；D07.1 的合并做完后，第 1 阶段的连击键才看得到效果（可以先合并）。

## 目标和验收

1. 阶段 1：虎牙 `lComboSeqId`、猫耳 `combo.id`/`combo.num`、克拉克拉 `no` 和单价进 `LiveGift`；克拉克拉 220 的中间帧给 `comboTotal`（不再丢）。
2. 阶段 2：AcFun 进房取一次 `gift/list`（缓存在平台适配器），`CommonActionSignalGift` 和扔香蕉解成礼物（AC 币、香蕉两种单位；香蕉算免费）。
3. 阶段 3：17LIVE 礼物 13（没有名称时“礼物 {编号}”，走翻译）、BIGO 760969 是礼物。
4. 阶段 4：Twitch `bits=` 的聊天是礼物（`unit = bits`）；同一 `community-gift-id` 的 `subgift` 并进 `submysterygift` 一条；CHZZK 订阅（11）是通知并带月数和档位；YouTube 贴纸是醒目留言、带图。
5. 每个平台的冻结输出更新，只多不少；不改聊天的解析。

## 现状（读代码得出）

- 见本文件夹 README 的表（文件:行来自 V03.5，master `87dd63729`；按函数名再找）。
- 样本位置：`fixtures/huya/danmaku/S11*`、`S18-gift`（`meta.json` 写了删掉的字段）；`fixtures/missevan/danmaku/S09-events`；`fixtures/kilakila/danmaku/`；`fixtures/acfun/danmaku/S07-live/frames.jsonl`（第 3 行礼物表，负载用会话密钥加密，样本里有密钥）；`fixtures/17live/danmaku/S06-live`；`fixtures/bigo/danmaku/S05-live`（第 63、64 行）；`fixtures/twitch/danmaku/`；`fixtures/chzzk/danmaku/`；`fixtures/youtube/danmaku/`。
- 归档 v4 的 AcFun 礼物：`~/ref/pure_live_archive/packages/live_danmaku/lib/src/sites/acfun.dart`（本机参考，不要整份照搬）。

## 3.x 基线

- 3.x 这些平台都没有礼物（多数平台 3.x 没有弹幕）。聊天、人数、醒目留言照旧。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `fixtures/README.md`；`docs/specs/ENGINEERING.md`。
3. 本文件夹 `README.md`；E05.5、D07.1、D07.2 的 README；各平台 D01 任务的 README 和 record（例如 `docs/D-弹幕/D01-平台弹幕协议/D01.10-AcFun弹幕/record.md:77-80`）。

## 范围

- 可以改：`packages/live_danmaku/lib/src/sites/` 的 `huya.dart`、`missevan.dart`、`kilakila.dart`、`acfun.dart`、`seventeenlive.dart`、`bigo.dart`、`twitch.dart`、`chzzk.dart`、`youtube.dart`；AcFun 礼物表的请求（`packages/live_core` 的 AcFun 适配器）；对应的 `fixtures/*/danmaku/*/expected.json` 和测试；翻译文件（“礼物 {编号}”）。
- 不能改：聊天的解析；连接和心跳；其他平台；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 连击键：虎牙、猫耳、克拉克拉 | `huya.dart`、`missevan.dart`、`kilakila.dart` | 三个平台的样本测试 |
| 2 | AcFun 礼物表和礼物、香蕉 | `acfun.dart`、AcFun 适配器 | 礼物表从样本解出 48 个；合成的礼物信号测试 |
| 3 | 17LIVE 礼物 13、BIGO 760969 | `seventeenlive.dart`、`bigo.dart` | 样本测试 |
| 4 | Twitch Bits 和送订阅合并、CHZZK 订阅、YouTube 贴纸 | `twitch.dart`、`chzzk.dart`、`youtube.dart` | 样本和合成帧测试 |

## 测试

- `packages/live_danmaku/test/sites/` 下各平台：上面每条验收一个用例；合成帧在测试里写明“按公开协议合成”。
- 不访问真实平台；样本时间固定（D-017）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 虎牙热门直播间（D07.1 合并后） | 连击一行 |
| 2. AcFun 有礼物的直播间 | 礼物行有名称和价值 |
| 3. Twitch（代理）有 Bits 或送订阅时 | Bits 是礼物行；送 N 个订阅只一条 |

## 风险和注意

- AcFun 的负载加密：测试用样本里录下的会话密钥，不要把真实密钥加进新样本。
- Twitch 合并 `subgift` 要有超时（例如 10 秒内没来齐就按已到的数出），定时器至少 1 秒。
- 同一组同时只开一个开发：和 D07.1、D07.4 改的文件不重叠，但都在 D 组，排队。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`dart test`（`live_danmaku`、`live_core`）；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.6`；每个阶段一次提交，信息以 `[D07.6]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每个阶段做到没有；每个平台填了哪些字段；合成帧有哪些；测试数量；改了哪些文件；要在真机上看的。
