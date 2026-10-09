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

## 定稿（2026-10-09，D-003 由执行者定，理由见 [record.md](record.md)）

- 上面四条选择照建议做（17LIVE“礼物 {编号}”、Bits 是打赏、贴纸是醒目留言、AcFun 照归档 v4 读、加上连击号）。另外定的：
  - 虎牙连击键是“送礼人 uid:`lComboSeqId`”（序号是连击开始的毫秒时间，两个人可能撞上）；没有序号的（0）不填，D07.1 按送礼人 + 礼物合并。
  - 克拉克拉的连击中间帧（220、`isDoubleHit`）现在也报，数量和 `comboTotal` 都是到这一下为止的累计，`price` 是累计价（能整除时算出单价）；连接里记着每个连击（`no`）报到多少，结束行（10004）或重复的一下只是重复已报的数就不报——D07.1 的合并把“数没变”当成新连击，会多出一行（见 record“合并的需要”）。
  - AcFun：`count` 是一次送几个（batch），`comboTotal = count × combo`，`comboKey` 是 `comboId`；单位新加 `acCoin`（10 AC 币 = 1 元，进“换算成元”）和 `banana`（免费）。礼物表在 `AcfunSite` 内存缓存（房间 30 分钟、16 个房间、失败 5 分钟），连弹幕时后台取，取到之前的礼物只有编号。
  - BIGO：760969 不带名字，后面紧跟的聊天礼物行（tag 6）带名字和等级；连接等这一行最多 1 秒，等到就带名字报，等不到就不带名字报。
  - Twitch：一条带 `bits` 的聊天报两条：先礼物（打赏、Bits、编号 `<id>:bits`，每次一行不合并），再原来的聊天（不改）。送订阅：公告（`submysterygift`）照常一条，它送出的 N 条 `subgift` 不再出；`subgift` 先到的等公告最多 2 秒，公告到了就丢掉，等不到就照常出。
  - CHZZK：订阅（11）先出一条订阅通知（“X 订阅了「档位名」，已订阅 N 个月”，中文照本文件里送订阅券通知的写法），留言照旧是聊天。
  - YouTube：贴纸进醒目留言（价格是页面的金额文字、内容是贴纸的说明），`LiveSuperChatMessage` 新加 `image`，醒目留言卡片在内容前面画贴纸（56 见方）。
  - 名称为空、只有编号的礼物，礼物行写“礼物 {编号}”（新翻译键 `gift_line_numbered`），所有平台通用。

## 留下的问题

- 17LIVE 礼物表接口没找到（名称、图、单价）；AcFun 礼物信号、Twitch Bits 没有真实样本（录到后补冻结输出）；Twitch 样本把 `community-gift-id` 逐个打乱了，合并只能用合成帧测。
- 克拉克拉的结束行靠连接去重；D07.1 的合并如果把“平台累计数相同”当成同一连击（不算新连击），这段去重可以去掉。
- YouTube 贴纸卡片的样子是临时的（A08 评审时再定）；BIGO 礼物没有单价（`getOnlineGifts` 没接）。
