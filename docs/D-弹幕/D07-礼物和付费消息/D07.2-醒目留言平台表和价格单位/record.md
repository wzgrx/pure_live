# D07.2 醒目留言的平台表和价格单位；舰长、会员进醒目留言；六间房飞屏：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a1c9211b5c0aedbed`）
- 分支和提交：`worktree-agent-a1c9211b5c0aedbed`，基于 master `aa12028ff`（含 E05.5、D07.1、D07.3、D07.4、A08.11、A08.12、A08.14、D08.2）；提交见文末
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（“定稿”一节是这次定的 D-003 选择）；调研：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2 节、第 4 节 F-6、F-7、第 6.5、6.6 节

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 平台表 | 做了：`superChatUnits`（平台 → 单位，`packages/live_core/lib/src/live_site.dart`），`superChatPlatforms` 是它的键，11 个 | 任务书写 10 个；六间房的飞屏这次成了醒目留言，所以也算（第 5 条），共 11 个。`hasSuperChats` 只有聊天面板一处用（`features/live_play/danmaku/chat_panel.dart:147`），电视、多画面没有醒目留言页，不受影响 |
| 2 价格文字 | 做了：`superChatPriceLabel`（`live_core`）+ 应用的 `superChatPrice`（`chat_list.dart`）用礼物行的单位翻译键（`giftUnitText`，`shared/danmaku/gift_words.dart`）；`LiveSuperChatMessage.unit` 新字段，11 个平台的适配器都填 | 新增单位 `LiveGiftUnit.yuan`、`sixCoin`；有平台文字的（猫耳、克拉克拉、Picarto、CHZZK、YouTube、17LIVE、Kick）照旧显示平台文字 |
| 3 上舰、会员进醒目留言 | 做了：新设置 `superChatIncludesMembership`（默认开），`membershipCard`（`features/live_play/logic/membership_cards.dart`）+ 控制器的礼物、通知分支 | 设置行放在 A08.12 两行之后（不依赖“在聊天列表显示礼物”，放在它的两个附属行中间会让人以为它也跟着变灰）；Kick、Picarto 的订阅也算（同一类事） |
| 4 CHZZK 11 是通知 | 做了：`_subscription`（`chzzk.dart`），带月数和档位名 | 没有留言的订阅以前什么都不显示，现在是一条通知 |
| 5 六间房 108 是醒目留言 | 做了：`SixRoomDanmakuProtocol.fly`，1000 六币，1 分钟 | 没录到 108（见“样本”），按网页脚本的字段写的帧；“跟风飞屏”2000 六币是另一种消息（324），没做 |
| 6 翻译 | 做了：zh、en 各 5 个键，按键名排序、4 空格缩进，没删键（D-024） | |

## 根因

- 7 个平台的醒目留言页空着时说“没有醒目留言”：`superChatPlatforms` 只有 3.x 的三个（改前 `packages/live_core/lib/src/live_site.dart:73`），它是 3.x 时写的，后来 CHZZK、YouTube、Kick、Picarto、17LIVE、猫耳、克拉克拉的适配器都报了醒目留言，表没跟着改。
- 价格一律 `￥`：`superChatPrice`（改前 `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:972-973`）没有平台文字时写 `'￥${price}'`；`LiveSuperChatMessage` 没有单位，应用不知道价格是什么单位。
- 上舰和会员只是一行：控制器只把 `LiveMessageType.superChat` 送进醒目留言（改前 `room_controller.dart:1196-1200`），礼物分支和通知分支不看 `LiveGift.kind` 和通知的种类。
- CHZZK 订阅是聊天：`line` 把 `subscriptionType`（11）和文字（1）放在同一个分支（改前 `chzzk.dart:375`），`extras.month`、`tierName` 不读。
- 六间房飞屏是聊天：`fly` 直接用聊天行（改前 `sixroom.dart:369-372`），D01.28 时没有价格依据，留作候选。

## 设计选择（D-003）

README“定稿”一节的 9 条，补几点理由：

1. **为什么不在列表里加醒目留言行**：任务书和 D-040 都写“列表里的行不变”；上舰本来就有礼物行（A08.11 的“很值钱”标记），再加一条醒目留言行就是同一件事两行。卡片只进醒目留言页（`_addSuperChats`），不进 `ChatFeed`。六间房飞屏是真的醒目留言，照其他平台的做法进页面也进列表一行（只一行，原来的聊天行没了）。
2. **为什么用新的通知种类而不是在控制器里猜**：Twitch 的社区礼包是一条 `submysterygift` 加 N 条 `subgift`，只有标签 `msg-param-community-gift-id` 分得出来，控制器拿不到标签。把“分到的那份”标成 `giftedSubscription`，其余的 `subscription` 都是买的那一下，控制器只看种类。这样改动最小：Twitch 只改选种类的一处、YouTube 的“收到会员礼物”一处，录制样本里只有 3 条 Twitch 通知的种类变了。D07.6 第 4 阶段把 N 条 `subgift` 并进 `submysterygift` 时，并掉的本来就不出卡，不冲突。
3. **YouTube Super Sticker 改成 `system`**：它是付费的，但不是会员；照原来的 `subscription` 会出一张写“会员”的卡。D07.6 要把它改成带图的醒目留言，这里只把种类改了，文字不变。
4. **卡片的 id**：`membership:<平台>:<消息 id>`，没有 id 的用“用户 id、名字、平台时间、文字”拼；平台重发同一条时是同一张卡（醒目留言的集合按 id 去重），关掉开关时按前缀拿掉。
5. **停留时间**：照 Kick、CHZZK 已经在用的哔哩哔哩醒目留言的档（按元）；没有价格的（会员、订阅通知）1 分钟，和最短的醒目留言一样。
6. **YouTube 价格数字**：小数点按“最后一个 `.` 或 `,` 后面只有 1～2 位”认，其他分隔符都当千位；只用来比较（`LiveSuperChatMessage` 没有 id 时按名字、文字、价格判断是不是同一条），显示不用它。
7. **大数字的写法**：和礼物行一样（`readableAudience`），英文 1000 写成“1k”。

## 平台代码改动（给 D07.6 合并时看）

都只动醒目留言和订阅通知相关的几行，和礼物解析分开：

| 文件 | 改了什么 |
|---|---|
| `packages/live_danmaku/lib/src/sites/twitch.dart` | 新常量 `communityShares`；`USERNOTICE` 选通知种类的三元式多一层：带 `msg-param-community-gift-id` 的 `subgift`/`anonsubgift` 是 `giftedSubscription` |
| `packages/live_danmaku/lib/src/sites/chzzk.dart` | `subscriptionType` 从聊天分支拿出来，新 `_subscription`；`_donation` 加 `unit: cheese` |
| `packages/live_danmaku/lib/src/sites/youtube.dart` | `_superChat` 的 `price` 用 `superChatAmount`；`_notice` 加 `kind` 参数；收到会员礼物是 `giftedSubscription`，Super Sticker 是 `system` |
| `packages/live_danmaku/lib/src/sites/seventeenlive.dart`、`kick.dart`、`missevan.dart`、`kilakila.dart`、`douyu.dart`、`bilibili.dart` | 醒目留言加一行 `unit:` |
| `packages/live_danmaku/lib/src/sites/sixroom.dart` | 108 改成醒目留言，`flyScreenPrice`、`flyScreenDuration` |
| `packages/live_core/lib/src/sites/bilibili/bilibili_api.dart`、`huya/huya_api.dart` | 轮询的醒目留言加 `unit: yuan` |
| `packages/live_danmaku/lib/src/connection_base.dart` | 清理不可见字符时带上 `unit` |

## 样本

- 用到的录制样本：哔哩哔哩 `S13-protover3`（醒目留言 30 元）、CHZZK `S11-recent`（后援、订阅 11）、Twitch `S09-live`（订阅、社区礼包）、YouTube `S07-live-paid`（Super Chat 的价格文字）、`S10-live-all-chat`（会员、里程碑）。哔哩哔哩 `GUARD_BUY` 没有录制（D07.4 也是），用 D07.4 读的字段写的帧。
- 六间房飞屏：2026-10-09 用一个只读的匿名程序（`getChat.php`、网页的 Origin 和 UA、游客登录、`encpass` 空、16 秒心跳，和 D01.28 的录制工具一样）同时连了 4 个最热的房间（58018、304055、10170、80518）各 40 分钟，收到 7000 多条消息（1570、123、1413、4185、413……），**一条 108 都没有**，所以没有可进仓库的样本，录的东西也没留（里面只有聊天和进场）。价格的依据是公开网页（curl，不带 Cookie）：房间页 `https://v.6.cn/80518` 的按钮 `data-sug="飞屏，价格：1000个六币"`、`"跟风飞屏，价格：2000个六币"`；脚本 `chunkimport-room_2016_59f3e19f42e15dcfx.js` 里 `Room.GiftFly`：108 → `add(t)`（`t.from + "说：" + t.content`、`fpic`、`ftype`），153 → `add(t, 1)`（系统飞屏），发送时确认“‘飞屏’等同于礼物，价值1000六币”（`prop_flymsg`）；跟风飞屏用 `Room.present.send({gid: 1516, …})` 送、留言走 324（`Room.GiftFlyFollow.parse`）。

## 改了哪些文件

- `live_core`：`live_gift.dart`（`yuan`、`sixCoin`，`yuan` 的比例 1）、`live_message.dart`（`LiveSuperChatMessage.unit`、`LiveNoticeKind.giftedSubscription`、`superChatPriceLabel`、`superChatAmount`）、`live_site.dart`（`superChatUnits`、`superChatPlatforms`）、`sites/bilibili/bilibili_api.dart`、`sites/huya/huya_api.dart`。
- `live_danmaku`：见上表。
- `live_store`：`settings.dart`（`superChatIncludesMembership`）。
- 应用：`features/live_play/logic/membership_cards.dart`（新）、`logic/room_controller.dart`（`membershipCards`、`_addMembershipCard`、`_onMembershipCards`，礼物和通知分支）、`danmaku/chat_list.dart`（`superChatPrice`）、`danmaku/super_chats.dart`（价格文字 `Flexible`）、`shared/danmaku/gift_words.dart`（`giftUnitText`，`yuan` 进 `giftYuanUnits`）、`shared/danmaku/chat_list_settings.dart`（设置行）、`features/settings/settings_catalog.dart`（搜索条目）、翻译文件。
- 工具和清单：`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`（新设置归 D07）。

## 新设置、翻译键、门禁基线

- 新设置：`superChatIncludesMembership`（`danmaku` 分节，同步，**默认开**，D-040 写明的例外），登记在 `Settings.all`、`settings_defaults_test.dart` 的 `newInV4`、`settings_audit_notes.py`、`OWNERS.toml`（D07）。
- 翻译键（zh、en）：`gift_value_six_coin`、`super_chat_card_membership`、`super_chat_card_subscription`、`super_chat_include_membership`、`super_chat_include_membership_desc`。没有删键。
- 门禁基线没动。

## 测试

- `live_core`：`live_site_test.dart` 改 1 个（11 个平台和单位、不可改、Twitch 等没有）、新增 1 组 2 个（价格文字：平台文字优先、元、金瓜子、钻石、Bits、六币、只有文字、没有字的单位、没有价格；`superChatAmount` 15 种写法）；`models_test.dart` 改 1 个（通知种类的顺序）；`bilibili_api_test.dart`、`huya_api_test.dart` 各加单位的断言。
- `live_danmaku`：`chzzk_test.dart` 改 4 处（S11 录制的订阅是通知、带月数和档位；合成样本的两条订阅和最近聊天里的一条；后援的单位）；`twitch_test.dart` 改 3 处（S09、S10 里社区礼包的 `subgift` 是 `giftedSubscription`）、新增 1 个（社区礼包的那份、单独送的、礼包本身）；`youtube_test.dart` 改 6 处（价格数字、Super Sticker 是 `system`、收到会员礼物是 `giftedSubscription`）；`sixroom_test.dart` 改 1 个（108 是醒目留言：1000 六币、1 分钟、没有时间时从现在起、在 1413 里也读）；`douyu_test.dart` 新增 1 个（两种醒目留言是元）；`picarto`、`seventeenlive`、`missevan`、`kilakila`、`kick`、`connection` 各加单位的断言。
- `live_store`：新增 `super_chat_membership_test.dart` 2 个（默认开、同步、备份往返、3.x 备份不带它时是开的）。
- 应用：新增 `super_chat_membership_test.dart` 25 个：价格（录制的哔哩哔哩“30 元”、CHZZK“1,820 치즈”、六间房“1000 六币”，平台文字优先，没有文字时各单位，英文）；卡片（上舰的元、月数、停留时间、没价格写“舰长”、同一条同一张卡；Twitch S09 每个订阅和礼包一张、分到的那份没有；CHZZK S11、YouTube S10 的卡；聊天、礼物、醒目留言、其他通知没有）；直播间（默认开：一张卡、列表只有一行礼物、没有醒目留言行；关着：没有卡、列表一样；关掉时卡片立即拿掉、真的醒目留言留着、之后不再出卡；礼物行关着照样出卡、屏蔽的人没有；订阅通知一行加一张卡、分到的那份只有一行；六间房飞屏进醒目留言页和列表一行、不再是聊天）；醒目留言页 360、280、240 宽 × 1、2 倍字 × 浅色、深色、纯黑三种主题：三张卡都在、价格文字对、不溢出、280 以下和大字时头部叠起来。`live_play_tabs_test.dart` 新增 2 个（CHZZK、YouTube、Kick、六间房的空状态是“会显示在这里”；设置行在标签页和画面面板的位置、默认开、两处同一个设置）；`settings_danmaku_test.dart` 新增 1 个（弹幕列表组里的位置、默认开、不跟礼物开关变灰、搜索“上舰”“醒目留言 会员”找得到）；`gift_line_test.dart` 改 1 处（`giftUnitsPerYuan` 多了 `yuan`）；`chat_line_roles_test.dart` 改 1 处（醒目留言行的价格“30 元”，原来是“￥30”）。
- 全部测试在门禁里跑（结果见文末）。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. CHZZK 或 YouTube 的直播间，醒目留言标签（没有醒目留言时） | “暂无醒目留言 / 当前直播间的付费留言会显示在这里。”，不再是“…的直播间没有醒目留言。” |
| 2. 有醒目留言时（YouTube Super Chat、CHZZK 후원） | 价格是平台的写法（“$5.00”“1,000 치즈”）；哔哩哔哩、斗鱼的是“30 元”，不再是“￥30” |
| 3. 哔哩哔哩登录后，舰长多的直播间（开播纪念、生日会），等有人上舰 | 聊天列表一行礼物（和以前一样）；醒目留言页一张卡：名字、“198 元”、正文“开通 舰长 ×1 个月”，5 分钟后消失 |
| 4. 弹幕设置 → 弹幕列表 → 关掉“上舰和开会员进醒目留言” | 醒目留言页上的上舰卡立即没了（真的醒目留言还在）；之后上舰只有列表的一行 |
| 5. Twitch 或 YouTube 有人订阅、开会员时（开着开关） | 列表一行通知；醒目留言页一张写“订阅”或“会员”的卡；一个人送 5 个订阅只一张卡 |
| 6. 六间房热门直播间等飞屏（付费，较少见） | 飞屏在醒目留言页一张卡、价格“1000 六币”，聊天列表一行醒目留言样式的行（不再是普通聊天） |
| 7. 手机横屏（右边 280 宽的聊天栏）、系统字体调大，看醒目留言页 | 卡片头部叠起来，价格、名字不溢出 |

## 提交

（见下一节补记）
