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

## 定稿（D-003，维护者定，2026-10-09）

用户授权维护者选（D-040）；开发时定的写在这里，理由和细节见 [record.md](record.md)。

1. **平台表 `superChatUnits`（`live_site.dart`）**：平台 → 价格单位，`superChatPlatforms` 就是它的键。V03.5 的 10 个，再加六间房（飞屏成了醒目留言），共 11 个：

   | 平台 | 醒目留言 | 单位（`LiveGiftUnit`） | 价格文字 |
   |---|---|---|---|
   | 哔哩哔哩 | `SUPER_CHAT_MESSAGE`、轮询的列表 | `yuan`（元） | 应用写“30 元” |
   | 斗鱼 | `comm_chatmsg`、语音 `voice_trlt`（分，读成元） | `yuan` | 应用写 |
   | 虎牙 | 头条留言板 | `yuan`（没核实，照 3.x 的 `￥`） | 应用写 |
   | 猫耳 | 付费提问 | `diamond` | 平台的“50 钻” |
   | 克拉克拉 | 付费提问 | `redBean` | 平台的“1,000红豆” |
   | Picarto | Kudos 打赏 | `other` | 平台的“5 Kudos” |
   | CHZZK | 치즈 후원 | `cheese` | 平台的“1,000 치즈” |
   | YouTube | Super Chat | `other`（买家币种） | 平台的“$5.00” |
   | 17LIVE | 付费弹幕 | `point` | 平台的“79 coins” |
   | Kick | 带留言的 Kicks | `kicks` | 平台的“500 Kicks” |
   | 六间房 | 飞屏 108 | `sixCoin`（新） | 应用写“1000 六币” |

   Twitch 不在表里：Bits 是礼物（D07.6），没有醒目留言；它的订阅照样能进醒目留言（第 5 条）。
2. **价格文字**：`superChatPriceLabel`（`live_core`）：有平台文字用平台文字；没有时按单位，单位的字用礼物行同一组翻译键 `gift_value_*`（同一个单位全应用一种写法），没有字的单位只写数字；再也不写 `￥`。新单位 `yuan`（整元）和 `sixCoin`（六币），不新建一套单位。
3. **YouTube 的价格数字**：`superChatAmount` 从平台文字粗解出整数（`TRY 550.00` → 550，`₫1,000,000` → 1000000，`2,50 €` → 2），只用来比较和排序；显示照旧用平台文字（README 方案里写的选择）。
4. **上舰和开会员进醒目留言：A，默认开**（D-040 写明的例外）。开着时**只在醒目留言页多一张卡**，聊天列表里照旧一行（上舰是礼物行，会员、订阅是通知行），**不再加醒目留言行**：同一件事在列表里只出现一次；列表的行受“在聊天列表显示礼物”、合并、限速管，卡片只受这个开关管。关掉时页上已有的卡片立即拿掉（真的醒目留言不动），列表不变。
5. **哪些算**：礼物里 `kind` 是 `membership`、`subscription` 的（哔哩哔哩 `GUARD_BUY`，以后 D07.6 改成礼物的订阅也自动算）；通知里 `LiveNoticeKind.subscription` 的（YouTube 会员和送会员、Twitch 订阅和送订阅、CHZZK 订阅和送订阅、Kick、Picarto 的订阅；Kick 和 Picarto 是同一类事，一起算）。一次送 N 个不会出 N+1 张卡：Twitch 社区礼包的 N 条 `subgift` 由 D07.6 的连接并进 `submysterygift` 一条（只有那一条出卡；等不到公告、单独显示的那条也出一张）；YouTube 的“收到会员礼物”改成新的 `LiveNoticeKind.giftedSubscription`，不出卡，送的人那一条已经算了。Twitch Bits（D07.6 的礼物，`kind = tip`）不算：D07.6 选了不进醒目留言（常见、金额小），它在列表里是礼物行加留言的聊天行，醒目留言页没有它。YouTube 的 Super Sticker 是 D07.6 做的醒目留言（带贴纸图），价格数字照第 3 条从文字解出，卡片照用（贴纸图的排法是 D07.6 的，暂定）。
6. **卡片上写什么**：上舰：价格按金瓜子折成元（舰长 198 元一个月 × 月数），正文“开通 舰长 ×1 个月”，没有价格时写“舰长”；通知：价格位置写“会员”（YouTube）或“订阅”（其他平台），正文是通知去掉前面的名字。停留时间照哔哩哔哩醒目留言按元的档（舰长 5 分钟，提督 1 小时，总督 2 小时），没有价格的 1 分钟。没有头像，颜色用卡片的主题色。屏蔽的用户不出卡；“在聊天列表显示礼物”关着时照样出卡。
7. **CHZZK 订阅（11）**：用 D07.6 的通知 `<名字> 订阅了「档位名」，已订阅 32 个月`，订阅者的留言另是一行聊天（两边同时做了，合并时取 D07.6 的，本任务的写法去掉）。卡片的正文是通知那一句，留言不进卡片；列表里是一行通知加一行留言，不是同一件事的两行。
8. **六间房飞屏**：只有 108 是用户付费的飞屏，价格固定 1000 六币（房间页 `data-sug` 和脚本里的确认框）；2000 六币的“跟风飞屏”在网页上是礼物（`gid` 1516）加另一种消息 324，字段没样本，留给 D07.7；153 是系统飞屏，不算。停留 1 分钟；没有头像和颜色。
9. **价格那一行**：卡片的价格文字可以换行（`Flexible`），240 宽、2 倍字时“1000 六币”不再溢出；卡片其他地方没动。

## 验证

- 自动测试：见 brief.md。
- 真机：CHZZK 或 YouTube 有醒目留言的直播间；哔哩哔哩舰长多的直播间（登录后）。

## 留下的问题

- 虎牙醒目留言价格的单位没有核实（V03.5 第 8 节），先照 3.x 当元。
- 卡片价格前的图标是人民币符号（`AppIcons.superChatPrice`，`money_cny_circle_fill`），海外平台的价格前也是它；换图标是卡片的样子，归 A08。
- 六币和元的比例没核实，六币不参与礼物档位。
- 六间房飞屏没录到样本（2026-10-09 4 个最热的房间各 40 分钟，一条 108 都没有），测试按网页脚本的字段写的帧；“跟风飞屏”（324）留给 D07.7。
