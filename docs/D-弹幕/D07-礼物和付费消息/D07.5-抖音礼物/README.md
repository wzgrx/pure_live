# D07.5 抖音礼物（受阻：先确认登录后能不能收到）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节抖音一行、第 3 节抖音、第 7 节 D07.5、第 8 节第 4 条；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)、[D07.1](../D07.1-礼物过滤连击合并和限速/README.md)；抖音弹幕 [D01.5](../../D01-平台弹幕协议/D01.5-抖音弹幕/README.md)；抖音平台 [E01.4](../../../E-直播平台/E01-国内五大平台/E01.4-抖音/README.md)；任务书 [brief.md](brief.md)

## 目标

抖音直播间里有人送礼时，礼物行出现（名称、数量、连击、抖币价值、图标）。

## 为什么受阻

匿名网页端收不到 `WebcastGiftMessage`：E01.4 实测两个房间共约 2000 条消息、28 种，没有礼物（[E01.4 记录](../../../E-直播平台/E01-国内五大平台/E01.4-抖音/record.md)第 284 行）；D01 录的 5 个房间 150 秒也没有；样本 `fixtures/douyin/danmaku/S13-live` 只有礼物排序 `WebcastGiftSortMessage`（32 条）。**解除条件**：用登录的网页端录一段热闹直播间的弹幕，里面确实有 `WebcastGiftMessage`。录到了就改成“未开始”开工；登录后也收不到就改“不做”，原因写进 DECISIONS。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 协议定义 | `v3.2.11:lib/core/danmaku/proto/douyin.pb.dart:1295`（`GiftMessage`：`giftId`、`repeatCount`、`comboCount`、`groupCount`、`repeatEnd`、`groupId`、`gift`）、`:1820`（`GiftStruct`：`image`、`diamondCount` 抖币单价、`name`）；3.x 也不上报 | `packages/live_danmaku/lib/src/sites/douyin.dart:147-148` 只有聊天和人数；4.x 自己读 protobuf（`codec/protobuf.dart`） | 按字段号读 `WebcastGiftMessage` |
| 连击 | — | — | `comboKey = groupId`，`repeatEnd` 为真时是连击结束的总数 |

## 方案（解除受阻后）

- c1 录样本（登录态，维护者的账号，按 `fixtures/README.md` 脱敏：Cookie、uid、昵称替换）；确认字段号和 3.x 的定义一致。
- c2 解析：`WebcastGiftMessage` → `LiveGift`：名称、`count = repeatCount`（或 `groupCount × comboCount`，以样本为准）、`unit = douyinCoin`、`unitPrice = diamondCount`、`iconUrl = gift.image` 的第一个地址、`comboKey = groupId`、`comboTotal`；`repeatEnd` 为真的那条带最终总数。
- c3 登录态才收得到时，礼物只在登录后有：不另做提示（和哔哩哔哩访客不一样，抖音没有“打码”）。

## 验证

- 自动测试：新样本的冻结输出。
- 真机：登录后在热闹的抖音直播间看礼物行。
