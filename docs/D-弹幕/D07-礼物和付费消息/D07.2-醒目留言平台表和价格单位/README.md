# D07.2 醒目留言的平台表和价格单位；舰长、会员进醒目留言；六间房飞屏

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 0 节第 6 条，第 4 节 F-6、F-7，第 6.5、6.6 节；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)（`kind`、`unit`）；醒目留言的样子 A08.1；礼物行 A08.11；决定 D-040（本任务的新开关默认开是写明的例外）、D-018；任务书 [brief.md](brief.md)

## 目标

1. 10 个会发醒目留言的平台都算“有醒目留言”：CHZZK、YouTube、Kick、Picarto、17LIVE、猫耳、克拉克拉的醒目留言页空着时不再说“这个平台没有醒目留言”。
2. 价格按平台的单位写（有平台文字用平台文字，没有时按单位，例如“30 元”“1000 金瓜子”“79 coins”），不再一律 `￥数字`。
3. 哔哩哔哩上舰、YouTube 会员、Twitch 订阅、CHZZK 订阅在醒目留言页有一张卡（新开关“上舰和开会员进醒目留言”，默认开），不再只是一行通知。
4. 六间房付费飞屏（1000 或 2000 六币）是醒目留言，不再当普通聊天。

## 3.x 和现状

| 方面 | 3.x | 现在（V03.5 的行号） | 要做到 |
|---|---|---|---|
| 有醒目留言的平台 | 哔哩哔哩、斗鱼、虎牙 | `superChatPlatforms = {'bilibili', 'huya', 'douyu'}`（`packages/live_core/lib/src/live_site.dart:73`），`hasSuperChats`（`:63`）用它 | 加 `chzzk`、`youtube`、`kick`、`picarto`、`17live`、`missevan`、`kilakila` |
| 价格 | `￥` | `superChatPrice`：有 `priceText` 用它，否则 `￥${price}`（`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:917-919`）；YouTube 的 `price` 是 0、只有 `priceText`（`youtube.dart:593`） | 按 `LiveGiftUnit` 写；YouTube 的排序用一个从 `priceText` 粗解出的数字（解不出为 0） |
| 上舰、会员 | 没有 | 哔哩哔哩 `GUARD_BUY` 是礼物（`bilibili.dart:784`）；YouTube 会员、Twitch 订阅、CHZZK 送订阅是通知（`youtube.dart:650`、`twitch.dart:170`、`chzzk.dart:464`）；CHZZK 订阅（11）当普通聊天（`chzzk.dart:375`）；控制器只把 `superChat` 送进醒目留言（`room_controller.dart:1134-1138`） | 开关开着时这几类也进醒目留言页一张卡，列表里照旧一行 |
| 六间房飞屏 | 没有弹幕 | 当普通聊天（`sixroom.dart:369`） | 醒目留言，价格 1000 或 2000 六币 |

## 方案

- c1 `superChatPlatforms` 补 7 个平台（`live_site.dart:73`，注释改成按 V03.5 第 2 节）；`hasSuperChats` 的用处跟着对。
- c2 价格文字：新函数（`live_core` 里，纯 Dart）`superChatPriceLabel(price, unit, priceText)`；`chat_list.dart` 的 `superChatPrice` 改用它，单位的文字走翻译（应用层做，`live_core` 只给单位枚举）。人民币类显示“N 元”；其他照平台单位。
- c3 上舰和会员：控制器的礼物分支和通知分支看 `LiveGift.kind == membership/subscription`（E05.5 填的），新设置 `superChatIncludesMembership`（`section: 'danmaku'`，**默认开**——V03.5 第 6.6 节的建议，D-040 写明的例外：只是醒目留言页多卡片，列表里的行不变）开着时额外生成一张醒目留言卡（价格 = 单价 × 月数，哔哩哔哩舰长 198 元一月），到点移除的规则和醒目留言一样。CHZZK 订阅（11）先改成通知行（`chzzk.dart:375`），再按同一规则进卡片。Twitch `submysterygift` 和它后面 N 条 `subgift` 的合并在 D07.6 第 4 阶段，这里只把 `submysterygift` 那一条进卡片。
- c4 设置行：A08 的“弹幕列表”一组（`apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`，在“在聊天列表显示礼物”下面）加开关“上舰和开会员进醒目留言”，说明“哔哩哔哩上舰、YouTube 会员、Twitch 和 CHZZK 订阅也在醒目留言里显示”；三处同一个组件；设置搜索能找到。
- c5 六间房：`sixroom.dart` 的 108 飞屏改成 `LiveMessageType.superChat`，价格按样本里的 1000 或 2000 六币（`LiveGiftUnit.other` 加单位文字“六币”）。
- 需要选的（D-003）：开关默认开（A）还是关（B）→ A，理由见 c3；YouTube 价格解析 → 只解出数字排序，显示照旧用平台文字。
- 不做：醒目留言卡片的样子（A08.1 定过）；斗鱼贵族开通、虎牙贵族（C-11 受阻）。

## 验证

- 自动测试：见 brief.md。
- 真机：CHZZK 或 YouTube 有醒目留言的直播间；哔哩哔哩舰长多的直播间（登录后）。

## 留下的问题

- 虎牙醒目留言价格的单位没有核实（V03.5 第 8 节），先保持平台文字。
