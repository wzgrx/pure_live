# D07.6 已有样本的平台补礼物：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a9376cc02dd109863`）
- 分支和提交：`worktree-agent-a9376cc02dd109863`，基于 master `7e93d6f77`（含 E05.5、D07.1、D07.3、A08.11、A08.12）；四个阶段各一次代码提交，文档一次提交（见文末）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；真机：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 阶段 1 虎牙 `lComboSeqId`、猫耳 `combo.id`/`combo.num`、克拉克拉 `no` 和单价；克拉克拉 220 中间帧给 `comboTotal` | 做了 | 虎牙的键是“送礼人 uid:序号”，不是只有序号（见设计选择 1）；克拉克拉多了连接里的去重（设计选择 2） |
| 阶段 2 AcFun 进房取一次 `gift/list`（缓存在平台适配器），礼物和扔香蕉解成礼物（AC 币、香蕉；香蕉免费） | 做了：48 个礼物从样本解出；礼物信号用合成帧测 | “进房取一次”改成“连弹幕时后台取一次”（和 D07.3 一样，不让进房多等一个请求）；没有礼物表时礼物照样报（只有编号），不像归档 v4 那样丢掉 |
| 阶段 3 17LIVE 礼物 13（没有名称时“礼物 {编号}”，走翻译）、BIGO 760969 | 做了 | BIGO 的名字在后一帧（tag 6），连接等它最多 1 秒 |
| 阶段 4 Twitch `bits=` 是礼物（`unit = bits`）；同一 `community-gift-id` 的 `subgift` 并进 `submysterygift`；CHZZK 订阅（11）是通知带月数和档位；YouTube 贴纸是醒目留言、带图 | 做了 | Bits 报成两条（礼物 + 原来的聊天），见设计选择 6；贴纸的图要画出来，改了醒目留言卡片（`super_chats.dart`，A08 的文件，不在协调名单里） |
| 每个平台的冻结输出只多不少；不改聊天的解析 | 做了：没有 `expected.json` 要改（冻结输出都是 3.x、归档 v4 或网页的读法，测试里按“差异”比）；聊天行的解析一行没改 | 17LIVE：v4 本来就报这 18 个礼物，差异 3 去掉了；克拉克拉 S07 第 15 帧的连击中间帧也和 v4 一样了 |

## 根因

- 虎牙 `huya.dart` 的 `gift` 不读 tag 39（`lComboSeqId`）；猫耳 `missevan.dart` 的 `gift` 不读 `combo`；克拉克拉 `kilakila.dart` 的 `gift` 丢掉 `isDoubleHit` 的 220、不读 `no`。D07.1 只好按“送礼人 + 礼物”合并。
- AcFun `acfun.dart` 的 `push` 只认聊天和人数；4.x 移植时没带上归档 v4 的 `gift/list` 请求（D01.10 记录“差异 2”）。
- 17LIVE `seventeenlive.dart` 的 `message` 对 type 13 返回 null；BIGO `bigo.dart` 的 `decode` 对 `oriUri` 760969 什么都不给。
- Twitch `chat` 不看 `bits` 标签；`USERNOTICE` 每条都是通知，送 N 个订阅出 N+1 条。CHZZK 订阅（11）和普通聊天同一个分支。YouTube 贴纸走 `_notice`，图丢了。

## 数据从哪来

| 平台 | 字段（来源） | `LiveGift` 怎么填 | 样本 |
|---|---|---|---|
| 虎牙 | 6501：0 `iItemType`、2 `iItemCount`、4 `lSenderUid`、9 `iItemGroup`、20 `sPropsName`、39 `lComboSeqId`、41 `lPayTotal` | `comboKey = "<uid>:<lComboSeqId>"`（0 时空），其余照旧 | `huya/danmaku/S18-gift`：8 个连击号，观众2 的虎粮 18 包同一个号 |
| 猫耳 | `combo{id, num, remain_time}` | `comboKey = combo.id`（全 0 时空）、`comboTotal = combo.num` | `missevan/danmaku/S09-events` 第 16、17 帧（幻彩礼炮连击两下） |
| 克拉克拉 | 220：`doubleCount`（累计）、`price`（累计价）、`isDoubleHit`、`no`；10004：`doubleCount`（总数）、`price`（单价）、`no` | `comboKey = no`；连击中间帧和结束行 `count = comboTotal = doubleCount`；中间帧 `unitPrice = price / doubleCount`（整除时） | `kilakila/danmaku/S10-live-gifts-questions`：飞天小猪中间帧 3 个 204 红豆、结束行单价 68 |
| AcFun | `gift/list`：`giftId`、`giftName`、`giftPrice`、`payWalletType`（1 AC 币、2 香蕉）、`webpPicList`/`pngPicList`；`CommonActionSignalGift`：1 用户、2 时间、3 `giftId`、4 `count`、5 `combo`、6 `value`、7 `comboId`；`AcfunActionSignalThrowBanana`：1 用户、2 数量、3 时间 | `count = 4`、`comboTotal = 4 × 5`、`comboKey = 7`；有礼物表时 `name`、`unitPrice`、`totalValue`、`unit = acCoin`、`iconUrl`；香蕉 `unit = banana`、`free`；消息编号 `送礼人:comboId:combo` | `acfun/danmaku/S07-live` 第 3 行（礼物表 48 个）；礼物信号**合成** |
| 17LIVE | type 13 `giftMsg`：`giftID`、`point`、`displayUser`、`giftMetas[].combo.count`、`validDurationMs` | `id = giftID`、`name` 空、`count = 1`、`comboTotal = combo.count`、`unit = point`、`point` 0 时 `free` | `17live/danmaku/S06-live`：18 条，6 种礼物，全是 0 点 |
| BIGO | 760969：`vgift_typeid`、`vgift_name`、`vgift_count`、`send_times`、`ticket_num`、`from_uid`；后面的 tag 6：`uid`、`grade`、`content.n` | `id`、`name`、`count`、`comboTotal = count × send_times`；没有单价（`unit = other`）；名字和等级取 tag 6 | `bigo/danmaku/S05-live` 第 63、64 行 |
| Twitch | `PRIVMSG` 的 `bits`；`USERNOTICE` 的 `msg-param-community-gift-id`、`msg-param-mass-gift-count` | 打赏 `kind = tip`、`name = Bits`、`count = 1`、`unitPrice = totalValue = bits`、`unit = bits`、`comboKey = bits:<id>` | `bits=` 和配对的送订阅**合成**；`twitch/danmaku/S09-live`、`S10-live` 的 3 对 `submysterygift`/`subgift`（编号逐个打乱了，配不上） |
| CHZZK | 11：`extras.month`、`extras.tierName`、`extras.nickname`、`content` | 订阅通知（`LiveNoticeKind.subscription`），编号 `subscription:<user>:<time>`；留言照旧是聊天 | `chzzk/danmaku/S11-recent`（32 个月、「나나양 좋아」）、`S12-synthetic` |
| YouTube | `liveChatPaidStickerRenderer`：`purchaseAmountText`、`sticker.thumbnails`、`sticker.accessibility`、`backgroundColor`、`authorPhoto` | 醒目留言：`priceText`、`price = 0`、`message` 是说明、`image` 是最大的图、两种颜色都是 `backgroundColor`；显示时长按 ticker，没有就 1 分钟 | `youtube/danmaku/S10-live-all-chat`：3 条贴纸 |

没有新录样本，也没有新加 `fixtures`（礼物表就在 AcFun 的 S07 里）。合成的帧都写在测试里，注明“按公开协议合成”。

## 设计选择（D-003，维护者授权由执行者定）

1. **虎牙的键带送礼人**：`lComboSeqId` 看起来是连击开始的毫秒时间（`1790800575070`），热门房间两个人同一毫秒开始连击会撞上，所以键是 `uid:序号`。序号是 0 的包（样本里两包虎粮 ×10）不填键，D07.1 按送礼人 + 礼物合并。
2. **克拉克拉的中间帧也报，结束行去重**：中间帧和结束行都写“到现在一共多少”（`count = comboTotal = doubleCount`），D07.1 的合并取较大的数；但它把“平台的数没涨”（`comboTotal` 不大于这一行的）当成新连击开新行，结束行和最后一下数一样，会多一行。所以 `KilakilaDanmakuConnection` 记着每个 `no` 报到多少（最多 256 个），数没涨的结束行或重复的一下不报；结束行数更大（最后几下被跳过）或者没见过这个连击（中途进房）就照报。静态的 `decode` 不去重，冻结输出看得到每一帧。
3. **AcFun 的 `batchSize` 和 `comboCount`**：照归档 v4 读 `count`（一次送几个），另外按公开客户端库的说法（“礼物总数是 Count × Combo”）把 `count × combo` 当作连击累计，`comboId` 当键。这几条字段号没有真实样本，真机核对（verify 第 3 步）。
4. **AcFun 的单位**：新加 `LiveGiftUnit.acCoin`（10 AC 币 = 1 元，平台定死的汇率，所以也进了“礼物价值换算成元”的单位表 `giftYuanUnits`）和 `banana`（免费，不进 `giftUnitsPerYuan`）。礼物行写“2888 AC币”，换算成元写“288.8 元”。
5. **AcFun 礼物表的取法**：和 D07.3 一样，不放进 `getRoomDetail`（刷新、录制、多画面都调它），由 `AcfunDanmakuArgs.gifts` 在弹幕连接开始时后台取一次；`AcfunSite.giftCatalog` 内存缓存（每个房间 30 分钟、最多 16 个房间、失败的 5 分钟内不再试）、并发共用一个请求、`Isolate.run` 解析；请求用当前的访客会话（和 `startPlay` 一样，不带 Cookie）。取不到也报礼物，只有编号。
6. **Twitch Bits 报两条**：A08.11 的礼物行只画 `LiveGift`，不画 `message`，把留言放进礼物消息里会丢掉留言（而且任务书不许改聊天解析）。所以先报一条打赏（`TwitchCheer`，编号 `<id>:bits`，不和原聊天撞去重），再报原来的聊天。每次打赏自己一行（`comboKey = bits:<id>`），因为每条都有自己的留言；数量是 1、价值是 Bits 数，礼物行写“打赏 Bits 500 Bits”。
7. **送订阅的合并**：公告（`submysterygift`、`anonsubmysterygift`）一到就照常出；它送出的 `subgift`、`anonsubgift` 按 `community-gift-id` 不再出（公告后 1 分钟内、最多公告的数量）。样本里两次 `subgift` 比公告早到 0.6～0.7 秒，所以没有公告的 `subgift` 先等 2 秒（定时器 ≥1 秒），公告来了就丢掉，等不到就照常出。合并只在连接里做，静态的 `decode` 在 `TwitchDanmakuFrame.communityGifts` 里标出哪些通知属于哪个送订阅。
8. **CHZZK 订阅的文字**：`chzzk.dart` 送订阅券的通知已经是中文拼平台的名字（“X 向频道赠送了 5 张「팬」订阅券”），订阅通知照这个写：“X 订阅了「档位名」，已订阅 N 个月”；没有档位写“订阅了频道”，没有月数只写前半句。D07.2 以后把订阅放进醒目留言时用这条通知的数据。
9. **YouTube 贴纸**：和 Super Chat 一样价格是页面文字、`price` 0；`LiveSuperChatMessage` 加了可选的 `image`（只加不改，`connection_base` 清洗时也带上）；醒目留言卡片在内容前面画 56 见方的贴纸（按显示尺寸解码，走应用图片缓存，加载不出来不占位）。贴纸的颜色不是 Super Chat 的档位色，没有 ticker 时显示 1 分钟。这是临时样子，A08 评审时再定。
10. **只有编号的礼物**：`giftName` 在名称为空、编号不空时写“礼物 {编号}”（新键 `gift_line_numbered`，中英都加），所有平台通用（以前直接显示编号）。
11. **BIGO 的名字**：760969 只有 `from_uid`；网页聊天列表里的礼物行（tag 6）紧跟着到（样本 75 毫秒），带名字和等级。连接把礼物压住最多 1 秒等这一行，等到了带名字报，等不到不带名字报；连接关掉时压着的丢掉。tag 6 本身不报（网页也是把它当礼物行，不是聊天）。

## 合并的需要（不改 `gift_combiner.dart`，写在这里）

- D07.1 的 `giftComboRestarted` 把“平台累计数不大于上一条”（`next <= running`）当作新连击。克拉克拉结束行和 Bilibili `COMBO_SEND` 这类“总结”包常和最后一下同数。如果改成只有“数变小”（`next < running`）才算新连击，克拉克拉连接里的去重（设计选择 2）就可以去掉；D07.4 的 `summaryWindow` 只放宽了时间，没改这一条。
- 17LIVE、BIGO 没有连击号：D07.1 按送礼人 + 礼物合并，`comboTotal` 正常往上涨，不用改。

## 改了哪些文件

- `packages/live_core`：`live_gift.dart`（`acCoin`、`banana`，`giftUnitsPerYuan` 加 `acCoin: 10`）；`live_message.dart`（`LiveSuperChatMessage.image`）；`sites/acfun/acfun_api.dart`（`AcfunGiftInfo`、`AcfunGiftCatalog`、`AcfunApi.giftList`、`giftListUrl`，`AcfunDanmakuArgs.gifts`）；`sites/acfun/acfun_site.dart`（`giftCatalog` 和缓存）
- `packages/live_danmaku/lib/src/sites/`：`huya.dart`、`missevan.dart`、`kilakila.dart`（`KilakilaGiftCombos`）、`acfun.dart`（`AcfunGift`）、`seventeenlive.dart`（`SeventeenLiveGift`）、`bigo.dart`（`BigoGift`、`BigoGiftSender`）、`twitch.dart`（`TwitchCheer`、`TwitchCommunityGift`）、`chzzk.dart`、`youtube.dart`；`connection_base.dart`（清洗醒目留言时带上 `image`）
- 应用：`shared/danmaku/gift_words.dart`（“礼物 {编号}”、AC 币的价值和换算）；`features/live_play/danmaku/super_chats.dart`（贴纸图）；翻译 `gift_line_numbered`、`gift_value_ac_coin`
- 测试：`live_core` 的 `live_gift_test.dart`、`sites/acfun_api_test.dart`、`sites/acfun_site_test.dart`；`live_danmaku` 的 `huya_test.dart`、`missevan_test.dart`、`sites/kilakila_test.dart`、`sites/acfun_test.dart`、`sites/seventeenlive_test.dart`、`sites/bigo_test.dart`、`twitch_test.dart`、`chzzk_test.dart`、`sites/youtube_test.dart`；应用新加 `platform_gift_support.dart`（共用）、`gift_combo_keys_test.dart`、`acfun_gift_catalog_test.dart`、`seventeenlive_bigo_gifts_test.dart`、`overseas_paid_test.dart`，改 `gift_line_test.dart`（G1 的单位表多了 `acCoin`）

## 新设置、翻译键、门禁基线

- 新设置：没有。
- 翻译键：`gift_line_numbered`（“礼物 {id}” / “gift {id}”）、`gift_value_ac_coin`（“{value} AC币” / “{value} AC coins”）。
- 门禁基线：没改。

## 测试

- `live_core`：新增 7 个（礼物表样本 48 个、坏条目、拒绝和改版、请求地址；`AcfunSite`：进房不多发请求、连弹幕时一次、不带 Cookie、并发共用、30 分钟后重取、失败 5 分钟内不重试、最多 16 个房间），改 2 个（单位表）。全部 3691 个通过。
- `live_danmaku`：新增约 20 个（每个平台：样本对照、字段逐个、坏数据、经过连接的行为），改了克拉克拉、17LIVE、BIGO、YouTube、CHZZK、Twitch 和样本对照的旧用例（礼物、通知、醒目留言多了）。全部 1646 个通过。
- 应用：新增 4 个文件 9 个用例（真实解析器 + 样本 + A08.11 礼物行 / 醒目留言卡片 + D07.1 合并）：虎牙一个连击一行 ×19；猫耳两下一行 ×2 带图、书写星辰“28 钻石”；克拉克拉中间帧加结束行一行“204 红豆”、跳过的几下合并成 ×5；AcFun 猴岛有图“2888 AC币”、precious、香蕉没价值、没有礼物表时“礼物 17”、换算“288.8 元”、按 `comboId` 合并成 ×6“36 AC币”；17LIVE“礼物 2609_jp_cp_akanya”×3、没价值；BIGO Flower ×1；Twitch“打赏 Bits”“500 Bits”、valuable、两次打赏两行；CHZZK 订阅通知；YouTube 贴纸卡片有图、价格、说明。`features/live_play/` 下全部 496 个通过。
- 门禁结果见文末。

## 真机上要看的

- 见 [verify.md](verify.md)：虎牙连击一行；克拉克拉连击一行、价值对；AcFun 礼物有名称、图和 AC 币（顺带核对 `count × combo`）；17LIVE 礼物行“礼物 {编号}”；BIGO 礼物行带名字；Twitch（代理）Bits 是打赏行、送 N 个订阅只一条；CHZZK 订阅通知；YouTube 贴纸是醒目留言卡片带图。

## 偏差

- 任务书写的分支名是 `ai/D07.6`，这次在本机工作区的分支上做（AGENTS.md 允许）。
- 动了 A08 的 `super_chats.dart`（贴纸图）和 `gift_words.dart`（“礼物 {编号}”、AC 币），都是小改；协调名单里的 `chat_list`、`chat_text`、`gift_line`、`message_panel` 只改了 `gift_line_test.dart` 的单位表一行。

## 提交和门禁

- `975df652d` [D07.6] Give Huya, Missevan and KilaKila gifts their combo keys（阶段 1）
- `9b597392b` [D07.6] Name, price and picture AcFun gifts from the room's gift table（阶段 2）
- `38fa3f2c1` [D07.6] Report 17LIVE (type 13) and BIGO (760969) gifts（阶段 3）
- `e8a8ecc11` [D07.6] Twitch Bits and community gifts, CHZZK subscriptions, YouTube Super Stickers（阶段 4）
- `826cdf116` [D07.6] Record the gift sources, the design choices and the real-device steps（本记录、verify.md、README、登记表和生成的文档）
- `bash tools/gate/gate.sh --all` 在 `826cdf116` 上通过（`gate: passed (all, 14 members)`，日志 `scratchpad/d076-1791522400/gate.log`）。第一次运行（`d076-1791520538`）只有 `live_danmaku` 的 `block_benchmark_test.dart`“手工检查一个规则花的时间”超时一次（机器上同时有别的任务在跑测试），和礼物无关，单独跑通过，重跑整个门禁通过。合并后要再运行一次 `python3 tools/docs/docs.py`。
