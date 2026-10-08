# V03.5 全平台礼物、醒目留言和弹幕数据调研

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：文档（调研）
- 来源：用户 2026-10-09：“分析所有平台的礼物系统，还原、增强、优化这些功能；所有平台的礼物都要有自己的显示设计，并且可以打开和关闭”
- 相关：B-21（礼物进聊天列表，C01.2）、A08.6 c3（“在聊天列表显示礼物”改成设置 `showChatGifts`）、A08.1（聊天列表和醒目留言）、A08.10（名字和内容的样子，和本报告同时在改）、E06.2（17LIVE 名字颜色和徽章、酷狗 PK“对方”）、D01 各平台任务；决定 D-001、D-003、D-005、D-017、D-018、D-036
- 日期：2026-10-09。代码：master `87dd63729`，下文路径都相对仓库根目录。只读：读代码、读样本（`fixtures/<平台>/danmaku/`，脚本只在本机临时目录解码）、读 3.x（`git show v3.2.11:…`）和上游（远程分支 `upstream/master`、`~/ref/pure_live_TV`、`~/ref/media_core`、`~/ref/flame_barrage`）。没有访问任何平台，没有用 `tools/live_cli`。
- 写法约定：“样本里有”指录制的真实帧里看到了（写了条数）；“协议资料（未录样本）”指平台网页和公开资料里有、但仓库样本没录到，开发前要先录样本（PROCESS 第 2 节“平台”类）；“推断”是根据字段名或同类平台推出来的。

---

## 0. 结论（按影响排序）

| # | 发现 | 位置 | 影响 |
|---|---|---|---|
| 1 | **没有统一的礼物数据。** 礼物是 `LiveMessage(type: gift)`，`message` 是一句已经拼好的文字，单价、数量、连击、图标放在各平台自己的类里（9 个类，字段各不相同），应用只用 `message`。各平台的文字格式也不一样：多数是 `名称 ×数量`，克拉克拉是“我送了豆咖 3 个念念相守”，niconico 是日文整句，Kick 是“X 送出了 Kicks（100 Kicks）”。niconico 和 Kick 的句子里已经带了送礼人，礼物行前面又印一次名字，**名字出现两遍** | `packages/live_core/lib/src/live_message.dart:8`（注释还写着 “not shown yet”）；`kilakila.dart:341`、`niconico.dart:452`、`kick.dart:178`；`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:657-689` | 高：做不出统一的礼物行，也做不了连击合并和价值 |
| 2 | **礼物只在聊天列表里有一行，别的地方都没有。** 飞行弹幕只加聊天（`room_controller.dart:1131`）；多画面直接丢掉（`multiview_controller.dart:1002`）；录制的弹幕 XML 只写聊天（`app/recording.dart:63`、`packages/live_record/lib/src/chat.dart:321`）；电视直播间没有聊天列表 | 见左 | 用户要的“礼物的显示设计、可以开关”只做到了一半 |
| 3 | **礼物不过任何过滤。** `DanmakuMessageFilter.accepts` 遇到非聊天直接放行（`packages/live_danmaku/lib/src/filters/message_filter.dart:105`），控制器的礼物分支也不调过滤（`room_controller.dart:1148-1151`）：屏蔽的用户、屏蔽词照样出现在礼物行；断线重连补发的礼物不去重，也没有年龄限制。上游的 3.x 后续版本对礼物查了屏蔽（`upstream/master:lib/domains/live/presentation/playback/controllers/danmaku_controller.dart:230`） | 见左 | 中：屏蔽不完整，重连后可能重复 |
| 4 | **礼物和聊天共用聊天记录的 500 行**（`chat_feed.dart:107`），每条礼物一行、不合并。热门直播间（斗鱼样本 60 秒 125 条 `dgb`，几乎都是“粉丝荧光棒”连击）礼物会把聊天挤出去 | `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart:107`、`room_controller.dart:1151` | 中高 |
| 5 | **很多平台的礼物协议里有、4.x 没解或丢了字段。** 哔哩哔哩访客收到的礼物是 `SEND_GIFT_V2`（protobuf），不解，访客只看得到上舰；SOOP 的星气球（별풍선）、Twitch 的 Bits、AcFun、BIGO、17LIVE、六间房、LOOK、酷狗、PandaTV、FC2、SHOWROOM、TwitCasting 的礼物都丢了（酷狗只回 ack，`kugoulive.dart:436`）；已经解的平台也只留了一部分：连击号（虎牙 `lComboSeqId`、猫耳 `combo.id`、斗鱼 `hits`）都没用上，每一下一行；哔哩哔哩不留单价和图标、粉丝牌、舰长等级。AcFun 的礼物表（名称、单价、图标）样本里就有，斗鱼进房时取的 `betard` 里也有一份（不全）。抖音协议里有礼物，但匿名网页端收不到（E01.4 实测） | 第 2、3 节 | 中高 |
| 6 | **醒目留言的平台表和价格单位不准。** `superChatPlatforms` 只有哔哩哔哩、虎牙、斗鱼（`packages/live_core/lib/src/live_site.dart:73`），CHZZK、YouTube、Kick、Picarto、17LIVE、猫耳、克拉克拉也发醒目留言，这 7 个平台醒目留言页空的时候却说“这个平台没有醒目留言”；价格没有平台文字时一律显示 `￥数字`（`chat_list.dart:918-919`），虎牙等平台的单位不是元 | 见左 | 中 |
| 7 | **3.x 从来没有显示过平台礼物。** 3.x 只有 `LiveMessageType.gift` 这个枚举（`v3.2.11:lib/common/models/live_message.dart:6`），8 个有弹幕的平台都不上报礼物；礼物只出现在本地互动（`v3.2.11:lib/modules/live_play/controllers/live_play_controller.dart:594`，横幅 3 秒）。所以礼物显示是 4.x 的新功能（B-21），**开关的默认值不受“3.x 用户感觉不到变化”之外的约束**，但飞行弹幕里的礼物是新行为，默认应关（D-036） | — | 定默认值的依据 |

**建议（第 6 节，推荐方案 A）**：建一个统一的礼物模型 `LiveGift`（名称、数量、连击、单价和单位、总价值、图标、档位、动画编号），各平台适配器填它；聊天列表里一种礼物行（和聊天行分开，名字样式跟 A08.10），同一个人同一个礼物连击合并成一行、数字跳动；有图标就画 16 像素的图；价值按平台单位显示，可选换算成元；“在聊天列表显示礼物”保留，加“飞行弹幕显示礼物”（默认关）和“只显示值钱的礼物”（门槛）；醒目留言和上舰、开会员仍进醒目留言（上舰是新加的）；横屏用同一个组件；忙的直播间限流合并。第 7 节是建议登记的 11 个任务（编号是建议）。

---

## 1. 范围和方法

- 平台：`apps/pure_live/lib/app/platforms.dart:231-283` 的 `buildDanmakuRegistry` 登记的 28 个平台，加上没有弹幕的 6 个（网易 CC、映客、小红书、微博、LiveMe、TikTok），共 34 个。网络电视（IPTV）没有弹幕，不在表里。
- 每个平台看：协议里有哪些和礼物、醒目留言（付费消息）、上舰或会员、点赞、进场、关注有关的消息；礼物有哪些字段（名称、数量、连击、单价和单位、总价值、图标、送礼人等级、粉丝牌或舰长、动画编号）；有没有礼物表接口；4.x 解了什么、丢了什么；3.x 和上游有什么。
- 样本：28 个平台的 `fixtures/<平台>/danmaku/S*/frames.jsonl` 全部解成文字（文本帧原样，二进制帧 base64 解开后找 zlib、gzip 流再解；哔哩哔哩 protover 3 是 Brotli，看配对的 protover 2 样本；AcFun 的负载用会话密钥加密，用样本里录下的密钥解开）。样本是录的时候脱敏、按需裁剪过的，**很多平台录样本时只留了聊天，礼物帧被丢掉或只留了类型号**，这些在 `meta.json` 的 `scrubbed`、`dropped`、`note` 里写着，表里照写。

---

## 2. 全平台一览

列的意思：“协议里有”= 平台的弹幕通道能给的（标“样本”的是样本里看到的条数）；“4.x 解出”= 现在的解析器上报的；“现在显示”= 应用里用户看得到的（礼物都只是聊天列表一行，见第 4 节）；“缺口”= 要补的。

| 平台 | 协议里有（礼物 / 醒目留言 / 上舰会员 / 点赞进场关注） | 4.x 解出 | 现在显示 | 缺口 |
|---|---|---|---|---|
| 哔哩哔哩 | 礼物：JSON `SEND_GIFT`（名称、数量、金瓜子或银瓜子、总价 `total_coin`、连击 `batch_combo_id`；单价 `price`、图标 `gift_info.img_basic`、粉丝牌和舰长 `medal_info`、财富等级、盲盒、动画 `effect` 是协议资料）、`COMBO_SEND`（`total_num`、`combo_total_coin`）；**访客收到的是 `SEND_GIFT_V2`**（protobuf：第 2 字段打码昵称，第 10 字段礼物 1 编号、2 名称、3 数量、8 金瓜子、9 `tid`、10 时间；E01.1 实测 32 条，样本里 2 条且内容已删）；上舰 `GUARD_BUY`（舰长、提督、总督，月数、单价 198000）/ 醒目留言 `SUPER_CHAT_MESSAGE`（样本 22 条：`price` 元、`user_info.user_level`、`guard_level`、粉丝牌、背景色）、`_JPN`、`_DELETE` / 进场 `INTERACT_WORD_V2`（149）、舰长进场 `ENTRY_EFFECT`（52）、点赞 `LIKE_INFO_V3_CLICK`（7）、全站礼物 `NOTICE_MSG`（2）/ 礼物表 `giftConfig`（协议资料） | 礼物、连击（同一连击只报第一条，`bilibili.dart:179-186`）、上舰：编号、名称、数量、金瓜子总价、连击编号（`BilibiliGift`）；醒目留言：价格、背景色、头像 | 礼物行；醒目留言页 + 列表一行 | **访客的 `SEND_GIFT_V2` 不解，访客只看得到上舰**（D01 已知问题）；连击总数丢了；不留单价、图标、粉丝牌、舰长等级；上舰没进醒目留言；醒目留言不留等级、舰长、粉丝牌 |
| 斗鱼 | 礼物 `dgb`（样本 182 条：`gfid`（背包礼物是 0，编号在 `pid`）、`gfn`、`gfcnt`、连击 `hits`、`bcnt`、用户等级 `level`、粉丝牌 `bnn`/`bl`、头像 `ic`、收礼人 `receive_nn`、特效 `eid`/`eic`；**没有单价和图标**）；礼物表：进房已经取的 `betard` 里的 `room_gift.gift`（`fixtures/douyu/S05-offline/body.json` 13 个：名称、`price`（分）、`unit`、`pc_icon`、`gift_effect`），**但它只有房间的付费礼物，样本里实际收到的荧光棒、陪伴印章、精英宝典都不在表里**，完整的礼物接口没有核实 / 醒目留言 `comm_chatmsg`、语音醒目留言 `voice_trlt`（真实样本没留，只有合成的）/ 进场 `uenter`（265）、升级 `upgrade` / 贵族开通（协议资料） | 礼物：编号、名称、数量、连击、收礼人（`DouyuGift`）；醒目留言两种 | 同上 | 连击每一下一行（119/125 条 `hits` > 1）；不留等级、粉丝牌、背包标记；单价和图标要礼物表 |
| 虎牙 | 礼物 uri 6501（样本 S11 68 条、S18 27 条：编号 `iItemType`、名称 `sPropsName`、数量、`iItemCountByGroup`、连击 `iItemGroup`、**连击号 `lComboSeqId`**、总价 `lPayTotal`（单位没核实：粉丝通行证 10、贵族水晶 100）、主播 `sPresenterNick`；图标、用户和贵族结构、特效在协议里，录样本时删了，见 `S18-gift/meta.json`）/ 醒目留言（头条留言板 uri 2001314 + `getHeadLineMessageBoard` 接口）/ 贵族通知 1001、贵族进场（协议资料，C-11 受阻）/ 礼物表 `getPropsList`（协议资料） | 礼物：编号、名称、数量、连击、总价（`HuyaGift`）；醒目留言 | 同上 | 不读 `lComboSeqId`，连击每一下一行；不留图标、贵族、粉丝牌；没有名称的礼物丢掉（没有礼物表） |
| 抖音 | 礼物 `WebcastGiftMessage`（3.x 的 protobuf 定义里有：`giftId`、`repeatCount`、`comboCount`、`groupCount`、`repeatEnd`、`groupId`、`gift.diamondCount`（抖币单价）、`gift.image`、`gift.name`；`v3.2.11:lib/core/danmaku/proto/douyin.pb.dart:1295`、`:1820`）——**匿名网页端收不到**：E01.4 实测两个房间约 2000 条消息、D01 录的 5 个房间 150 秒都没有（`docs/E-直播平台/E01-国内五大平台/E01.4-抖音/record.md:284`）；样本只有礼物排序 `WebcastGiftSortMessage`（32）/ 点赞 `WebcastLikeMessage`（11）、进场 `WebcastMemberMessage`（128）、关注 `WebcastSocialMessage`（34）、粉丝团 `WebcastFansclubMessage`（37）/ 平台没有醒目留言 | 只有聊天和人数（`douyin.dart:147-148`） | 没有 | 受阻：要先确认登录后能不能收到礼物；能收到时解析是中等工作量（字段号已知） |
| 快手 | 网页轮询接口 `liveStreamFeeds` 只有评论（样本 42 条全是 `comment`）；房间页的礼物表 `allGifts`、`giftList` 匿名是空的（`fixtures/kuaishou/S09-room-live/body.html`）；礼物在桌面端 WebSocket（C-16 不做：要浏览器签名） | 只有聊天 | 没有 | 平台限制，不做 |
| YY 直播 | 礼物和进场在应用 15012（固定字段：送礼人、主播、礼物编号、数量，加一个键值表 `giftName`、`free_gift`…，见 E02.1 记录），4.x 不订阅（`yy.dart:384`；C-20 受阻：没有样本） | 只有聊天和人数 | 没有 | 受阻（C-20） |
| SOOP | 星气球、广告气球、视频气球、订阅、挑战任务（服务号按公开的网页播放器资料推断：18、33、87、105、91/93，未核实）；样本只录了约 24 秒，**没有这些服务**，聊天以外的服务内容都删了（`fixtures/soop/danmaku/S07-live/meta.json`、`S09-live-ones-and-bars/meta.json`） | 只有聊天（`soop.dart:104-108`） | 没有 | 解星气球（数量就是价值，单位“星气球”）、订阅；先录样本 |
| Twitch | Bits：`PRIVMSG` 的 `bits=` 标签（协议资料，样本 0 条）；订阅 `sub`、`resub`、`subgift`、`submysterygift`（样本 19 条，档位 `msg-param-sub-plan`、月数、送出数）、`raid`（2）、`viewermilestone`（8）；Hype Chat、频道点数（协议资料） | 订阅、送订阅、突袭是通知（`twitch.dart:170`、`:285`，数字只在平台给的句子里）；Bits 当普通聊天 | 通知行；Bits 是普通聊天 | Bits 当礼物（单位 Bits）；`submysterygift` 和它后面的 N 条 `subgift` 合并（按 `community-gift-id`），现在会出 N+1 条通知 |
| AcFun | 礼物 `CommonActionSignalGift`（礼物编号、`batchSize`、`comboCount`、时间、用户）、扔香蕉、点赞、进场、关注、守护团（`docs/D-弹幕/D01-平台弹幕协议/D01.10-AcFun弹幕/record.md:77-80`）；推送只有礼物编号，名称、单价、图标在**礼物表 `gift/list`，样本里就有**（`fixtures/acfun/danmaku/S07-live/frames.jsonl` 第 3 行：48 个礼物，`giftName`、`giftPrice`、`payWalletType`（AC 币或香蕉）、`webpPicList` 图、`canCombo`、`magicFaceId` 动画）；解密后的样本有点赞 15、进场 3，礼物 0 / 平台没有醒目留言 | 只有聊天和人数（`acfun.dart:504-525`）；不请求礼物表 | 没有 | 解礼物和香蕉，进房取一次礼物表（归档 v4 做过）；先录有礼物的样本 |
| Picarto | 打赏（Kudos，样本 `S14-tip` 1 条：`x` 筹码数、`mk`/`mc` 筹码表情、`cb` 筹码徽章）、订阅 `ns`、突袭 | 打赏是醒目留言（`picarto.dart:212`，`x Kudos`）；订阅、突袭是通知 | 醒目留言 | 不在 `superChatPlatforms`（第 4 节 F-6）；筹码徽章没用 |
| TwitCasting | 礼物（アイテム：`item{id, name, image, effectCommand}`、`isPaidGift`、留言）只发给带 `gift=1` 的地址，4.x 不要（`twitcasting.dart:22-23`）；平台没给单价 | 只有聊天 | 没有 | 加 `gift=1` 解礼物（先录样本） |
| 猫耳 FM | 礼物 `gift`/`send`（样本 4 条：编号、名称、数量、钻石单价（10 钻 = 1 元）、图标 `icon_url`、福袋 `lucky`、**连击 `combo{id, num, remain_time}`**、特效、送礼人头衔 `titles`）、给别的主播送礼 `gift/cross_send`、超粉续费 / 付费提问 `question/ask` / 贵族开通续费、PK | 礼物（`MissevanGift`，`missevan.dart:334`、`:518`：编号、名称、数量、单价、图标、福袋）；提问是醒目留言；贵族、PK 是通知 | 礼物行；醒目留言 | 连击字段丢了，每一下一行；礼物行不带送礼人等级、粉丝牌、贵族 |
| 克拉克拉 | 礼物 220（动画，连击中间帧带累计数和**累计总价**）、10004（连击结束的礼物行，`price` 是单价）（样本 220 共 8、10004 共 4：编号、名称、数量、红豆、图标 `pic`、连击号 `no`、收礼人、亲密度、礼物等级）；送礼人等级、粉丝团、头衔 / 付费提问 240、241 / 进场、点赞、点亮 | 礼物（`KilakilaGift`，`kilakila.dart:283`、`:310`：总价、收礼人、图标、免费）；提问是醒目留言 | 礼物行（文字是“我送了豆咖 3 个……”） | 文字格式统一；不留单价、连击号、粉丝团 |
| niconico | 礼物（ギフト，样本 `S10-gift` 1 条：`item_id`、名称、点数 `point`、留言、贡献排名）、ニコニ広告（样本 1 条，点数）/ 运营评论、节目结束（通知） | 礼物（`NiconicoGift`，`niconico.dart:432`、`:440`）；ニコニ広告不报 | 礼物行（日文整句，含送礼人） | 名字重复；ニコニ広告当礼物；图标要按编号拼地址（推断） |
| SHOWROOM | 礼物 `t` 2、11、17（礼物编号 `g`、数量 `n`、类型 `gt`；名称、单价、图标要礼物表，协议资料）、应援点 5、投票、对战（`docs/D-弹幕/D01-平台弹幕协议/D01.16-SHOWROOM弹幕/record.md:49-53`）；样本 `S06-live` 只有评论 18、字幕 2、系统 1 | 只有评论（`showroom.dart:31`） | 没有 | 解礼物（先录样本，要礼物表） |
| CHZZK | 치즈 후원（样本 13 条：`payAmount`、`donationType` CHAT 9、VIDEO 2、MISSION 2、匿名、周榜）、订阅 11（样本 1 条：月数、档位名）、送订阅 12（2）；名字颜色、徽章图 | 后援是醒目留言（`chzzk.dart:426`）；送订阅是通知（`:464`）；**订阅（11）当普通聊天，月数和档位丢了**（`:375`） | 醒目留言 | 订阅改成通知；视频、任务后援加标记；不在 `superChatPlatforms` |
| LiveMe | 弹幕要登录 IM（D01.18 受阻），礼物消息没识别出来 | — | — | 受阻 |
| TikTok | 和抖音同一套字段号（`WebcastGiftMessage` 等，推断）；弹幕要平台 SDK 签名（D01.19 受阻） | — | — | 受阻 |
| YouTube | Super Chat（样本 70 条，`purchaseAmountText` 买家币种的文字）、Super Sticker（3，有图）、会员（11）、送会员（1）、新礼物 `giftMessageViewModel`（3，名称和图片，没有价格和数量） | Super Chat 是醒目留言（`youtube.dart:593`，价格 0、只有文字价格）；贴纸当“订阅”类通知、图丢了（`:638`）；会员、送会员是通知（`:650`）；礼物（`YouTubeGift`，`:669`，名称、图片） | 醒目留言、通知、礼物行 | 贴纸改成醒目留言或礼物（带图）；不在 `superChatPlatforms` |
| BIGO LIVE | 礼物 `oriUri` 760969（样本 1 条：`vgift_typeid`、`vgift_name`、`vgift_count`、连送 `send_times`、主播豆总数 `ticket_num`）、聊天列表里的礼物行 tag 6（1）、付费弹幕 tag 2（没有金额）、点赞、关注、进场；礼物表 `getOnlineGifts`（网页，未用） | 聊天（tag 1、2）；礼物不报（`bigo.dart:299`） | 付费弹幕是普通聊天 | 解 760969 的礼物；单价和图标要礼物表 |
| PandaTV | 후원 `SponCoin`、`ItemCoin`（`message` 里 `{nick, id, coin}`，`heart` 是签名心）、粉丝进场（`docs/D-弹幕/D01-平台弹幕协议/D01.22-PandaTV弹幕/record.md:60`）；样本只有聊天 | 聊天（`pandalive.dart:103`） | 没有 | 解 후원（归档 v4 做过）；先录样本 |
| FC2 LIVE | `system_comment` 里的打赏 `tip_amount`（点数）、礼物 `gift_id`（名称要 `gift_list`）、进出（`fc2live.dart:128`）；`point_information`（样本 1 条，`amount` 0） | 不报 | 没有 | 解打赏和礼物（先录样本） |
| Steam 直播 | 平台没有礼物 | 聊天 | — | 无 |
| 京东直播 | 没有礼物系统；点赞 `thumbs_up`（样本 21）、进场、下单、领券、关注（`jdlive.dart:308`） | 聊天 | — | 无（购物消息不做） |
| 酷狗直播 | 礼物 601（`SENDGIFT`，负载是 `GiftEffectSocketMsg.Content`，**字段没有文档**，实测见过 29 条没留样本；只回 ack，`kugoulive.dart:170`、`:436`）、全站礼物广播 602（样本里 21 条被删）、进场 201、关注 615/618、PK 613；聊天里的守护、亲密度已经解（只用来上色） | 礼物不报 | 没有 | 解 601：先从网页脚本找字段、录样本 |
| 百度直播 | 礼物 107/10024（样本 3 条免费“拍拍”：编号、名称、数量、免费、图标 `gift_url`、`total_value`、`charm_value`，都是 0）；点赞、进场、升级 | 礼物（`BaiduLiveGift`，`baidulive.dart:293`：编号、名称、数量、免费、图标） | 礼物行 | 价值字段没解（单位没录到付费礼物，没核实） |
| 六间房 | 礼物 201（样本 6 条，只留了 `typeID`，**字段不知道**）、进场 123、付费飞屏 108（1000 或 2000 六币，价格只在网页里写着） | 飞屏当普通聊天（`sixroom.dart:369`）；礼物不报（`:284`） | 飞屏是普通聊天 | 飞屏改成醒目留言；解礼物（先录内容） |
| LOOK 直播 | 云信自定义消息 102：礼物和点歌是同一种（**字段不知道**），进场 114、关注 104、PK、抽奖；聊天里有贵族等级、守护、亲密度（样本有） | 聊天和表情（`looklive.dart:438-466`）；贵族、守护丢了 | 没有 | 解 102（先录样本）；贵族和守护做徽章 |
| 17LIVE | 礼物 type 13（各样本共 35 条：`giftID`、`point`、`resultPoint`、`combo.count`、`combo.validDurationMs`、`animationResourceID`；**名称、图标要礼物表，接口没找到**）、福袋 32、反应 28、进场 18、守护和军团 54；付费弹幕（样本 1 条，`barrage.point` 79） | 付费弹幕是醒目留言（`seventeenlive.dart:617`）；礼物不报（`:686`） | 醒目留言 | 解礼物 13（先只显示编号，再找礼物表） |
| Kick | Kicks `KicksGifted`（没有样本，按公开客户端库：`gift.name`、`gift.amount`（100 Kicks = 1 美元）、`pinned_time`）、订阅、送订阅、主持；聊天的 `badges_v2` 带图片地址（样本有） | 有留言是醒目留言，没留言是礼物行（`kick.dart:164`，没有数据类，文字带名字） | 礼物行（名字两遍）、醒目留言 | 统一模型；徽章图；先录样本 |
| 网易 CC | 匿名加入没回应（C-22） | — | — | 受阻 |
| 映客 | 匿名拿不到弹幕地址（E02.5） | — | — | 不做 |
| 小红书 | 平台不提供（E02.7） | — | — | 不做 |
| 微博 | 匿名没找到实时评论通道（E02.8） | — | — | 不做 |

**数一下**：4.x 上报礼物的 9 个平台（哔哩哔哩、斗鱼、虎牙、猫耳、克拉克拉、niconico、YouTube、百度、Kick）；协议里有礼物、匿名能收到、4.x 丢掉的 13 个（SOOP、Twitch Bits、AcFun、TwitCasting、SHOWROOM、BIGO、PandaTV、FC2、酷狗、六间房、LOOK、17LIVE、哔哩哔哩访客的 `SEND_GIFT_V2`），其中只有 AcFun（礼物表）、BIGO、17LIVE 的样本里有礼物字段，其余都要先录样本；平台限制或受阻的 9 个（抖音（匿名收不到）、快手、YY、LiveMe、TikTok、CC、映客、小红书、微博）；平台本身没有礼物的 2 个（Steam、京东）。上报醒目留言的 10 个（哔哩哔哩、斗鱼、虎牙、猫耳、克拉克拉、Picarto、CHZZK、YouTube、17LIVE、Kick）。

---

## 3. 各平台的证据

只写表里装不下的。样本行号是 `frames.jsonl` 的行，条数是解码后数到的。

- **哔哩哔哩**（D01.2）：分发在 `bilibili.dart:490-492`；`_gift` `:757`（金瓜子才记总价 `:766`；`tid` 当消息编号）；`_guard` `:784`（`price × num`）；`_superChat` `:835`。数据类 `BilibiliGift` `:20`（编号、名称、数量、金瓜子、连击编号）。连击只报第一条（类注释 `:73-74`），所以“×1”之后的累计（`COMBO_SEND.total_num`）看不到最终数。样本命令统计（`S13-live`、`S13-protover2-paired`、`S13-vectors` 合计）：`DANMU_MSG` 192、`INTERACT_WORD_V2` 149、`ENTRY_EFFECT` 52、`SUPER_CHAT_MESSAGE` 22、`LIKE_INFO_V3_UPDATE` 13、`LIKE_INFO_V3_CLICK` 7、`SEND_GIFT_V2` 2、`SUPER_CHAT_MESSAGE_JPN` 4；**没有 `SEND_GIFT`、`COMBO_SEND`、`GUARD_BUY`**（访客收不到）。醒目留言样本（`S13-vectors` 第 37 行）有 `price` 50、`rate` 1000、`user_info.user_level` 12、`guard_level` 0。
- **斗鱼**（D01.3）：`dgb` 在 `douyu.dart:182` 分发，`gift` `:301`。`S13-live` 的 125 条 `dgb` 里 119 条是 `gfid` 824 粉丝荧光棒（免费背包礼物），字段一律有 `gfid`、`gfn`、`gfcnt`、`hits`、`bcnt`、`level`、`bnn`、`bl`、`brid`、`ic`、`receive_nn`、`receive_uid`。`S15-gifts` 是 57 条 `dgb`。礼物表在 `betard` 回答的 `room_gift.gift`（`fixtures/douyu/S05-offline/body.json`），例如 196 火箭 `price` 50000 `unit` 2、`pc_icon` 相对路径、`gift_effect` 143；4.x 的 `douyu_api.dart:346` 已经请求 `betard`，但不读这一块。这张表只有房间的付费礼物（样本 13 个），`S13-live`、`S15-gifts` 里实际收到的 824 荧光棒、陪伴印章、精英宝典都不在里面，完整的礼物接口（`gift.douyucdn.cn` 一类）没有核实。
- **虎牙**（D01.4）：`HuyaGift` `huya.dart:13`，解析 `:256`。样本把 6501 的大部分字段删了（`S18-gift/meta.json`：保留 0、2、3、5、6、8、9、20、24、25、39、41，删了支付编号、图标、用户和贵族结构、特效），说明协议里有图标和贵族信息。
- **抖音**（D01.5）：`douyin.dart:147-148`。3.x 的 protobuf 定义里 `GiftMessage`（`giftId`、`gift`、`repeatCount`、`comboCount`、`groupCount`…）和 `GiftStruct`（`image`、`diamondCount`、`name`…）都在；4.x 自己写 protobuf 读取（`codec/protobuf.dart`），加礼物只要按字段号读。但匿名网页端收不到 `WebcastGiftMessage`（E01.4 记录第 284 行、D01.5 README 第 26、54 行），样本 `S13-live` 里也没有，所以先要确认登录后能不能收到。
- **AcFun**（D01.10）：负载用会话密钥加密；解密后（用样本里的会话密钥）的统计是 `CommonStateSignalDisplayInfo` 151、`AcfunStateSignalDisplayInfo`（香蕉总数）259、`CommonActionSignalLike` 15、`CommonActionSignalUserEnterRoom` 3、评论 1，没有礼物信号。礼物表在 `S07-live/frames.jsonl` 第 3 行（`gift/list` 的回答，`giftId` 49 处）。归档 v4 请求过这张表并上报礼物（`~/ref/pure_live_archive/packages/live_danmaku/lib/src/sites/acfun.dart`），4.x 移植时没带上（`acfun.dart:510-513` 注释）。
- **猫耳**：`MissevanGift` `missevan.dart:16`（钻石单价，10 钻 = 1 元）；样本 `S09-events` 有 1 条 `gift`/`send`。
- **克拉克拉**：`KilakilaGift` `kilakila.dart:13`（红豆总价、`free`）；220 的连击中间帧（`isDoubleHit`）丢掉（`:314`）。
- **niconico**：`NiconicoGift` `niconico.dart:80`（点数）；文字 `:452` 是“〇〇さんがギフト「…（100pt）」を贈りました”。
- **YouTube**：`YouTubeGift` `youtube.dart:38`（名称、图片，没有价格）。Super Chat 的 `price` 是 0、只有 `priceText`（`:593` 起），排序和“值不值钱”判断没有数字。
- **Kick**：`kick.dart:108` 分发 `KicksGifted`，`:164`；没有数据类，文字带名字（`:178`），名字两遍；中文写死（Z05.2 同类问题）。
- **百度**：`BaiduLiveGift` `baidulive.dart:15`；样本 `S05-live-gift` 3 条免费“拍拍”。
- **17LIVE**：`seventeenlive.dart:686` 注释“gifts…不报”；`S06-live` 的 type 统计：3 评论 26、13 礼物 18、6 直播信息 11、38 人数 9、74 8、32 福袋 8、79 6、28 反应 5、18 进场 2。礼物 `giftMsg`：`giftID` “2609_jp_cp_akanya”、`point` 0、`combo.count` 3、`validDurationMs` 3000。
- **BIGO**：`S05-live` 第 63 行 `oriUri` 760969：`vgift_typeid` 1、`vgift_name` Flower、`vgift_count` 1、`send_times` 1、`ticket_num`；第 64 行 tag 6 的礼物聊天带 `grade` 25。
- **酷狗**：`S07-live/meta.json` 的 `dropped`：进场 201 共 37、礼物广播 602 共 16；`S09-pk-chat`：602 共 5、PK 613 共 3。
- **六间房**：`S07-live/meta.json`：“entries 123, gifts 201 … keeps only typeID”。
- **CHZZK**：样本 `messageTypeCode` 1 共 468、10（后援）11、11（订阅）1、30 共 1；直播流里 `msgTypeCode` 10 共 2、12（送订阅）2。`donationType` CHAT 9、VIDEO 2、MISSION 1、MISSION_PARTICIPATION 1。
- **Twitch**：样本 `msg-id`：`resub` 7、`sub` 6、`subgift` 3、`submysterygift` 3、`raid` 2、`viewermilestone` 8、`announcement` 1；`bits=` 0 条。
- **京东**：`type` `chat_group_message` 45、`thumbs_up` 21、`get_statistics_result` 21。

---

## 4. 应用里现在的礼物和醒目留言

| 编号 | 现状 | 位置 |
|---|---|---|
| F-1 | 礼物行：礼物图标（`AppIcons.chatGift`，第三色）+ 名字（次要色）+ 文字（第三色），一条礼物一行，不合并、不画礼物图、不显示价值；长按、双击没有动作 | `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:657-689` |
| F-2 | 开关“在聊天列表显示礼物”（`showChatGifts`，默认开，A08.6 c3），在直播间“弹幕设置”和设置 → 弹幕的“弹幕列表”组；关掉时去掉已有的礼物行 | `packages/live_store/lib/src/settings/settings.dart:494-498`；`apps/pure_live/lib/shared/danmaku/chat_list_settings.dart:68-74`；`room_controller.dart:266-268`、`:807-817`；文字 `zh.json:904-905` |
| F-3 | 礼物不进飞行弹幕、不进多画面、不进录制、电视没有聊天列表 | `room_controller.dart:1131`、`:1148-1151`；`features/multiview/logic/multiview_controller.dart:1002`；`app/recording.dart:63`；`packages/live_record/lib/src/chat.dart:321` |
| F-4 | 礼物不过过滤（屏蔽用户、屏蔽词、去重、年龄） | `packages/live_danmaku/lib/src/filters/message_filter.dart:105`；`room_controller.dart:1150` |
| F-5 | 礼物和聊天共用 500 行 | `chat_feed.dart:107` |
| F-6 | `superChatPlatforms` 少 7 个平台；醒目留言价格兜底 `￥` | `packages/live_core/lib/src/live_site.dart:73`；`chat_list.dart:918-919`；醒目留言页 `danmaku/super_chats.dart` |
| F-7 | 醒目留言同时进醒目留言页和聊天列表一行（`chat_list.dart:690-700`，背景用平台颜色）；上舰、开会员是礼物或通知，不进醒目留言 | `room_controller.dart:1134-1138` |
| F-8 | 本地互动的礼物：聊天行“送出 🌶 辣条 ×1”（`local_chat_line.dart`），开“礼物特效”时画面中间横幅 3 秒（`local_interaction/local_gift_effect.dart`、`logic/local_room_session.dart:55-91`，3.x 同样 3 秒）；本地礼物不受“在聊天列表显示礼物”影响（`room_controller.dart:1157-1162`） | 见左 |
| F-9 | 横屏（手机横着、不全屏）右边 280 宽只有聊天列表，礼物行同一个组件（`live_play_page.dart:1327-1346`）；全屏横屏没有聊天列表，只有飞行弹幕 | 见左 |
| F-10 | 飞行弹幕层的队列上限：等待 120 条、最多等 5 秒、每帧进 4 条（`shared/danmaku/danmaku_overlay.dart:221-228`）；能画表情图（`ChatEmoteSegment`），也能把本地弹幕定在顶部或底部（`LiveMessagePlacement`） | 见左 |

## 5. 3.x 和上游

- **3.x**：不上报、不显示平台礼物（见第 0 节第 7 条）。醒目留言：哔哩哔哩、斗鱼、虎牙（`v3.2.11:lib/core/danmaku/bilibili_danmaku.dart:415`、`douyu_danmaku.dart:146-148`、`huya_danmaku.dart:252`），醒目留言页，价格 `￥`。
- **上游 pure_live**（liuchuancong，`upstream/master`）：`11a47144e`（2026-10-03）照 4.x 加了哔哩哔哩的三种礼物，礼物当普通聊天进列表，先查屏蔽（`danmaku_controller.dart:230`），不触发特效；百度礼物同 4.x（`lib/shared/platforms/baidulive/baidu_live_danmaku.dart:244`）；酷狗 601 只回 ack（`kugou_live_link_danmaku.dart:330`）。**没有礼物的样式、合并和开关。**
- **pure_live_TV**：弹幕层只要聊天，礼物和进场只给列表（`lib/modules/live/playback/controllers/danmaku_session_controller.dart:111`）。
- **media_core**：礼物不路由（`packages/media_core_danmaku/lib/src/danmaku_controller.dart:463-467`）。
- **flame_barrage**：有一个连击计数的动画 `ComboAnimation`（`lib/src/animation/combo_animation.dart`：“ ×N”放大到 1.8 倍再回到 1，0.8 秒后淡出，同一连击来新数字时重新开始），可以借鉴连击数字的做法（不引入 Flame）。

---

## 6. 设计建议

### 6.1 礼物数据：统一模型（三个方案都要）

在 `live_core` 加一个 `LiveGift`，放进礼物消息的 `data`（各平台的类保留或改成它的子类，`message` 仍是 `名称 ×数量`，给录制和老代码用）：

| 字段 | 意思 | 例子 |
|---|---|---|
| `id`、`name` | 平台的礼物编号、名称 | `196`、`火箭` |
| `count` | 这次送的个数 | 10 |
| `comboKey`、`comboTotal` | 连击的标识（平台给的连击号，没有就用 送礼人 + 礼物编号）、连击累计 | 哔哩哔哩 `batch_combo_id`、斗鱼 `hits`、虎牙 `lComboSeqId`、17LIVE `combo.count` |
| `unitPrice`、`totalValue`、`unit` | 单价、总价值（平台单位的整数）、单位（枚举：元的分、金瓜子、钻石、红豆、点数、Bits、Kicks、치즈、星气球、抖币…） | 斗鱼 50000（分）、哔哩哔哩 100000 金瓜子 |
| `free` | 免费礼物（银瓜子、荧光棒、拍拍） | |
| `iconUrl` | 礼物图（平台给地址，或按礼物表、编号拼出来） | 猫耳 `icon_url`、斗鱼 `pc_icon` |
| `tier` | 档位：普通 / 值钱 / 很值钱（适配器按平台规则算，例如哔哩哔哩按元：<10、10–100、≥100） | |
| `receiverName` | 收礼人（连麦嘉宾时不是主播） | 斗鱼、克拉克拉 |
| `kind` | 礼物 / 上舰或开会员 / 订阅 / 打赏 | 哔哩哔哩 `GUARD_BUY` → 上舰 |

送礼人的等级、粉丝牌、舰长照用 `LiveMessage` 已有的 `userLevel`、`fansName`、`fansLevel`、`badges`（和聊天行一样画）。

### 6.2 显示：三个方案

| | A（推荐）礼物行 + 合并 + 可选上飞行弹幕 | B 只改聊天列表 | C 礼物单独一个区域 |
|---|---|---|---|
| 聊天列表 | 一种礼物行（下面 6.3），连击合并成一行 | 同 A | 聊天列表不放礼物，列表上方加一条礼物横条（最近 3 条，滚动） |
| 飞行弹幕 | 新开关“飞行弹幕显示礼物”（默认关），开了以后值钱的礼物用礼物样式飞过 | 不上 | 不上 |
| 醒目留言 | 醒目留言照旧；上舰、开会员也进醒目留言（新开关，默认开） | 不变 | 同 A |
| 横屏 | 同一个组件 | 同 A | 横条在 280 宽里放不下，要另做 |
| 工作量 | 大（分阶段） | 中 | 大，而且是新布局 |
| 风险 | 飞行弹幕变多：用门槛和限流控制 | 用户要的“礼物在画面上”做不到 | 改了 A08.1 确认过的布局，违反 D-001 和 UI.md 原则 2 |

按 D-003 推荐 **A**：不改确认过的布局，所有平台同一个组件，两个开关各管一处，飞行弹幕默认关，老用户感觉不到变化（D-036）。

### 6.3 礼物行的样子（方案 A）

- **和聊天行分开**：左边 16 像素礼物图（平台给了地址才画；没有就用现在的礼物图标 `AppIcons.chatGift`，第三色）；名字用 A08.10 定的名字样式（和聊天行同一个，粉丝牌、徽章、舰长也同样画在名字前）；后面是“送出”（次要色）+ **礼物名（第三色、加粗）** + “×N”（第三色、等宽数字）；最后是价值（小一号、次要色，例如“100 元”“2000 金瓜子”“79 coins”，见 6.5）。整行没有背景，和醒目留言（有背景色的卡片）、通知（次要容器色）一眼分得开；“卡片”列表样式下是同样的卡片，圆点换成礼物图。
- **档位**：普通礼物一行；值钱的（`tier` 值钱）整行左边加 2 像素的第三色竖线；很值钱的竖线 + 礼物名用平台色。只用颜色和线，不用动画和阴影（UI.md 第 9.3 节）。
- **文字走翻译**：“送出”“×”“上舰”“开通”都是翻译键（zh、en），平台给的中文、日文、韩文句子不再拼进 `message`（顺带解决 Z05.2 里这一类）。
- **长按**：和聊天行一样打开长按面板（复制、屏蔽这个用户），屏蔽的用户以后的礼物也不显示（F-4）。

### 6.4 连击合并

- 同一个 `comboKey`（或同一个送礼人 + 同一个礼物）在 **5 秒**内又来，不加新行，改原来那一行的数量（`×10` → `×20`），数字放大到 1.2 倍再回到 1（200 毫秒，系统要求少动画时不动；借鉴 flame_barrage 的做法）。
- 只合并仍在列表最后 20 行里的；合并后这一行移到最下面（跟随时看得到）；被定住（用户往上翻）时不移动，只改数字。
- 哔哩哔哩现在“同一连击只报第一条”（`bilibili.dart:73-74`）改成每条都报、由合并来处理，否则最终数字不对。

### 6.5 价值和单位

- 默认显示**平台单位**（金瓜子、钻石、鱼翅、Bits、치즈…），因为平台的单位本身就是用户熟悉的；设置里一个选项“礼物价值换算成元”（默认关），只对汇率固定的国内平台换算（哔哩哔哩金瓜子 1000 = 1 元、斗鱼分、猫耳 10 钻 = 1 元、抖音 10 抖币 = 1 元）；海外的币种不换算。
- 免费礼物不显示价值。
- 醒目留言价格：用 `priceText`，没有时按平台的单位写（不再一律 `￥`，F-6）。

### 6.6 开关

| 开关 | 默认 | 管什么 | 放哪 |
|---|---|---|---|
| 在聊天列表显示礼物（已有 `showChatGifts`） | 开 | 聊天列表里的礼物行 | 不变（“弹幕列表”组） |
| 只显示值钱的礼物（新） | 关 | 聊天列表里只留“值钱”以上，免费、普通礼物不显示 | 同组，在上一条下面，礼物关闭时变灰 |
| 飞行弹幕显示礼物（新） | 关 | 值钱以上的礼物在画面上飞：礼物图 + “名字 送出 礼物 ×N”，礼物色描边，滚动；很值钱的在顶部停 4 秒（用本地弹幕已有的 `LiveMessagePlacement.top`）；连击只飞第一下和结束时的总数 | 弹幕设置的“显示”组；小窗、多画面跟它 |
| 上舰和开会员进醒目留言（新） | 开 | 哔哩哔哩上舰、YouTube 会员、Twitch 订阅、CHZZK 订阅在醒目留言页加一张卡（不再只是通知行） | 弹幕设置的“弹幕列表”组 |
| 礼物特效（本地互动，已有） | 不变 | 只管本地互动的横幅，不管平台礼物 | 不变 |

新键名在开发时定（例如 `chatGiftsAboveTier`、`danmakuShowGifts`、`superChatIncludesMembership`、`giftValueInYuan`），只加不改（D-018）。

### 6.7 横屏和其他布局

- 手机横屏（280 宽）、宽屏右栏、竖屏标签都是同一个 `ChatList`，礼物行跟着走；280 宽时价值放到第二行（不截断礼物名）。
- 全屏横屏只有飞行弹幕，礼物看“飞行弹幕显示礼物”。
- 小窗、画中画、多画面：只飞行弹幕，跟同一个开关（多画面现在直接丢礼物，F-3）；电视同。
- 录制：弹幕 XML 加礼物（B 站格式里礼物是 `<gift>`，或按 `<d>` 的另一种模式），新开关“录制弹幕时包含礼物”，默认关（以后做，第 7 节 H0x.x）。

### 6.8 性能（忙的直播间）

- **先合并再进列表**：连击合并在控制器里做（`ChatFeed` 之前），一秒最多加 **10 条**礼物行（超出的同类礼物只累计到已有的行，不加新行）；免费礼物超过上限时直接丢掉（只计数）。
- **礼物不挤聊天**：礼物在 500 行里最多占 **150 行**，超出时先丢最老的礼物行，不丢聊天。
- 飞行弹幕：礼物和聊天共用队列，礼物每秒最多 **3 条**，超过的不上画面（只在列表里）。
- 礼物图：按显示尺寸解码（`ResizeImage`，和 `ChatBadge` 一样，16 像素），走应用的图片缓存；同一个地址只请求一次；加载不出来不占位。
- 礼物表（斗鱼 `betard` 已有；17LIVE、SHOWROOM、BIGO、AcFun 要另取）：进房时取一次，存在平台适配器里，不在界面线程解析。
- 基准：在 D04.1 的“每秒 200 条”基准里加“每秒 50 条礼物（同一礼物连击 + 不同礼物各一半）”，界面线程 ≤3 毫秒/帧（UI.md 第 9.4 节）。

---

## 7. 建议登记的实现任务

编号是建议，由维护者登记（只登记了本任务 V03.5）。顺序按“先数据、再样子、再扩平台”。界面任务要出效果图和评审页（PROCESS 第 4.1 节）；平台任务要先录真实样本（不在本任务里做）。

| 建议编号 | 组 | 标题 | 范围 | 规模 | 依赖 |
|---|---|---|---|---|---|
| E05.x | E05 平台框架和模型 | 统一礼物模型 `LiveGift` | `live_core` 加模型（第 6.1 节）；现有 9 个平台的礼物类填它；文字统一成 `名称 ×数量`（克拉克拉、niconico、Kick 改），名字不再拼进文字 | 中 | 无 |
| D07.1 | D 组新子分类 D07 礼物和付费消息 | 礼物过滤和连击合并 | 礼物过屏蔽用户、屏蔽词和去重闸门（F-4）；控制器里按 `comboKey` 合并、限流、礼物在 500 行里的上限（第 6.4、6.8 节）；哔哩哔哩连击每条都报；基准加礼物 | 中 | E05.x |
| A08.11 | A08 弹幕界面 | 礼物行的样子 | 第 6.3 节的礼物行（图、名字、礼物名、×N、价值、档位线、长按）；“卡片”样式；横屏 280 宽；评审页；和 A08.10 的名字样式一致 | 中 | E05.x、A08.10 |
| A08.12 | A08 | 礼物开关和飞行弹幕里的礼物 | 新设置“只显示值钱的礼物”“飞行弹幕显示礼物”“礼物价值换算成元”（第 6.6 节）；飞行弹幕的礼物样式、顶部停留、限流；小窗、多画面跟开关 | 中 | A08.11、D07.1 |
| D07.2 | D07 | 醒目留言的平台表、价格单位，上舰和开会员进醒目留言 | `superChatPlatforms` 补 7 个（F-6）；价格按平台单位；哔哩哔哩上舰、YouTube 会员、Twitch 和 CHZZK 订阅进醒目留言（新开关）；六间房飞屏改成醒目留言 | 小～中 | E05.x |
| D07.3 | D07（平台） | 斗鱼礼物表和字段 | 读 `betard` 的 `room_gift`（单价、图标、动画），表里没有的礼物只显示名称；核实完整的礼物接口；`dgb` 留等级、粉丝牌；背包礼物（`gfid` 0、`pid`）算免费 | 小～中 | E05.x |
| D07.4 | D07（平台） | 哔哩哔哩礼物补全 | `SEND_GIFT` 留单价、图标、粉丝牌、舰长；访客的 `SEND_GIFT_V2`（protobuf，先录未脱敏结构的样本）；礼物表 `giftConfig` | 中 | E05.x；录样本 |
| D07.5 | D07（平台） | 抖音礼物（受阻） | 先确认登录后 IM 会不会推 `WebcastGiftMessage`（匿名收不到）；能收到时按 3.x 的字段号解，连击按 `groupId`、`repeatEnd` | 中 | E05.x；要登录态的样本 |
| D07.6 | D07（平台） | 已有样本的平台：AcFun、17LIVE、BIGO、猫耳和克拉克拉的连击、虎牙连击号 | AcFun 进房取 `gift/list`（样本有）并解礼物和香蕉；17LIVE 礼物 13（先显示编号）；BIGO 760969；猫耳 `combo`、克拉克拉 `no`、虎牙 `lComboSeqId` 填进连击键；Twitch Bits、CHZZK 订阅改通知、YouTube 贴纸带图 | 中 | E05.x |
| D07.7 | D07（平台） | 要先录样本的平台 | SOOP 星气球和订阅、SHOWROOM 礼物、TwitCasting `gift=1`、PandaTV 후원、FC2 打赏、酷狗 601、六间房 201 和飞屏、LOOK 102、Kick Kicks；每个平台先录样本（海外要代理），可以拆成每平台一个任务 | 大 | E05.x；录样本 |
| H0x.x | H 录制 | 录制弹幕时包含礼物 | 弹幕 XML 写礼物（格式照 B 站的 `<gift>` 或单独的 `<d>` 模式）；新开关默认关 | 小 | E05.x |

不建议做：快手礼物（C-16，要浏览器签名）、YY 礼物（C-20 受阻）、京东的下单消息、点赞和进场显示（C-7 的理由：刷屏，其他平台也不显示）。

---

## 8. 留下的问题

- 多数平台的礼物样本在录的时候被丢掉或删了字段（虎牙、酷狗、六间房、SOOP），哔哩哔哩访客的 `SEND_GIFT_V2` 内容也删了：开发 D07.x 前都要重新录（按 `fixtures/README.md` 脱敏，不进真实昵称和编号）。
- 虎牙 `lPayTotal`、百度礼物的价值单位没有核实。
- AcFun 礼物信号里 `batchSize` 和 `comboCount` 怎么相加没有核实（样本里没有礼物信号）。
- 抖音登录后的 IM 会不会推 `WebcastGiftMessage` 没有核实（匿名收不到）。
- SOOP 的服务号、酷狗 601、六间房 201、LOOK 102 的字段是推断或不知道的，要先从网页脚本确认。
- 档位的门槛（第 6.2、6.3 节）按平台定，开发 A08.11 时在评审页里列出来请用户确认（D-003）。

## 9. 结果

- 本报告只登记了 V03.5（完成）。第 7 节的任务由维护者登记；登记后在这里写每条去了哪。
- 2026-10-09 维护者按 D-040 全部登记（方案 A），去向：

| 建议编号 | 登记成 | 档位 |
|---|---|---|
| E05.x | [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md) | 第二档 |
| D07.1 | [D07.1](../../../D-弹幕/D07-礼物和付费消息/D07.1-礼物过滤连击合并和限速/README.md)（新子分类 [D07 礼物和付费消息](../../../D-弹幕/D07-礼物和付费消息/README.md)） | 第二档 |
| A08.11 | [A08.11](../../../A-界面设计/A08-弹幕界面/A08.11-礼物行的样子/README.md) | 第二档 |
| A08.12 | [A08.12](../../../A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物/README.md) | 第二档 |
| D07.2 | [D07.2](../../../D-弹幕/D07-礼物和付费消息/D07.2-醒目留言平台表和价格单位/README.md) | 第二档 |
| D07.3 | [D07.3](../../../D-弹幕/D07-礼物和付费消息/D07.3-斗鱼礼物目录和字段/README.md) | 第二档 |
| D07.4 | [D07.4](../../../D-弹幕/D07-礼物和付费消息/D07.4-哔哩哔哩礼物补全/README.md) | 第二档 |
| D07.5 | [D07.5](../../../D-弹幕/D07-礼物和付费消息/D07.5-抖音礼物/README.md)（受阻） | 第三档 |
| D07.6 | [D07.6](../../../D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物/README.md) | 第二档 |
| D07.7 | [D07.7](../../../D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物/README.md) | 第三档 |
| H0x.x | [H01.8](../../../H-录制/H01-录制核心/H01.8-弹幕XML带礼物/README.md) | 第三档 |
