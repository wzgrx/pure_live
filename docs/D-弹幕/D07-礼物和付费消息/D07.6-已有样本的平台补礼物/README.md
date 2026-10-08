# D07.6 已有样本的平台补礼物：AcFun 目录、17LIVE、BIGO、连击键、Twitch Bits、CHZZK 订阅、YouTube 贴纸

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节、第 3 节、第 7 节 D07.6；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)；连击合并 [D07.1](../D07.1-礼物过滤连击合并和限速/README.md)；醒目留言 [D07.2](../D07.2-醒目留言平台表和价格单位/README.md)（CHZZK 订阅、Twitch 订阅进醒目留言用这里的数据）；各平台弹幕 D01；任务书 [brief.md](brief.md)

## 目标

仓库里已经有样本、不用先录的平台把礼物补齐：虎牙、猫耳、克拉克拉的连击能合并；AcFun、17LIVE、BIGO 的礼物出现在列表里；Twitch 的 Bits 是礼物、一次送 N 个订阅只出一条；CHZZK 的订阅不再是普通聊天；YouTube 的贴纸带图。

## 3.x 和现状

| 平台 | 现在（V03.5 第 2、3 节） | 要做到 | 样本 |
|---|---|---|---|
| 虎牙 | `HuyaGift`（`huya.dart:13`、`:256`）不读连击号 `lComboSeqId` | `comboKey = lComboSeqId` | `fixtures/huya/danmaku/S11`、`S18-gift`（字段大多删了，连击号留着） |
| 猫耳 | `MissevanGift`（`missevan.dart:16`、`:334`）丢了 `combo{id, num, remain_time}` | `comboKey = combo.id`、`comboTotal = combo.num` | `S09-events` 1 条 |
| 克拉克拉 | `KilakilaGift`（`kilakila.dart:13`、`:283`、`:310`）丢 220 的连击中间帧（`:314`）、不留连击号 `no` 和单价 | `comboKey = no`；10004 是结束行，`price` 是单价 | 220 共 8、10004 共 4 |
| AcFun | 只有聊天和人数（`acfun.dart:504-525`），不请求礼物表；归档 v4 做过（`~/ref/pure_live_archive/packages/live_danmaku/lib/src/sites/acfun.dart`） | 进房取一次 `gift/list`（48 个：`giftName`、`giftPrice`、`payWalletType` AC 币或香蕉、`webpPicList`、`canCombo`）；解 `CommonActionSignalGift`（编号、`batchSize`、`comboCount`）和扔香蕉 | `S07-live/frames.jsonl` 第 3 行是礼物表；解密后没有礼物信号（只有点赞 15、进场 3） |
| 17LIVE | 礼物 type 13 不报（`seventeenlive.dart:686`） | 解：`giftID`、`point`、`combo.count`、`validDurationMs`；名称没有礼物表时先显示编号（翻译“礼物 {编号}”） | `S06-live` 等共 35 条 |
| BIGO | 760969 不报（`bigo.dart:299`） | 解：`vgift_typeid`、`vgift_name`、`vgift_count`、连送 `send_times` | `S05-live` 第 63 行 |
| Twitch | Bits 当普通聊天；`submysterygift` 后面 N 条 `subgift` 出 N+1 条通知（`twitch.dart:170`、`:285`） | `bits=` 标签的聊天是礼物（`unit = bits`，留言照样显示）；按 `community-gift-id` 把 N 条 `subgift` 并进 `submysterygift` 一条 | `bits=` 0 条（**要合成测试帧**，按公开协议）；`subgift` 3、`submysterygift` 3 |
| CHZZK | 订阅（11）当普通聊天（`chzzk.dart:375`），月数和档位丢了 | 通知（`kind = subscription`，月数、档位名）；D07.2 已经改成通知时这里只补字段 | 11 共 1 条、12 共 2 条 |
| YouTube | Super Sticker 当“订阅”类通知、图丢了（`youtube.dart:638`） | 醒目留言（带贴纸图、`priceText`） | 贴纸 3 条 |

## 方案

- c1～c4 对应四个阶段（见 brief.md），每个阶段一组平台、一次合并。
- 选择（D-003）：
  - 17LIVE 没有礼物表时 → **A 显示“礼物 {编号}”**并记 `normal`；B 不显示——不选，用户要“所有平台的礼物都要显示”。礼物表接口以后找到再补。
  - Twitch Bits → **A 当礼物（`kind = tip`，留言放 `message` 后面）**；B 当醒目留言——不选，Bits 很常见、金额小，进醒目留言会刷屏。
  - YouTube 贴纸 → 醒目留言（和 Super Chat 同一类付费消息，V03.5 第 2 节）。
  - AcFun 的 `batchSize` 和 `comboCount` 怎么相加（V03.5 第 8 节没核实）→ 照归档 v4 的做法，测试用合成帧，真机核对。
- 不做：SOOP、SHOWROOM 等要先录样本的（D07.7）。

## 验证

- 自动测试：每个平台的样本对照；Twitch Bits 和 AcFun 礼物信号用按协议合成的帧（测试里注明是合成）。
- 真机：每个阶段挑一个平台看（海外开代理）。

## 留下的问题

- 17LIVE 礼物表接口没找到；AcFun 礼物信号没有真实样本（录到后补冻结输出）。
