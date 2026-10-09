# D07.7 要先录样本的平台补礼物：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-aa187e4b8b348505a`）
- 分支和提交：`worktree-agent-aa187e4b8b348505a`，基于 master `f81ce8d72`（含 E05.5、D07.1～D07.4、D07.6、D07.2、A08.11/12/15）；每个平台一次代码提交，文档一次提交（见文末）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；真机：[verify.md](verify.md)

## 逐条对照

| 平台（按日常使用排） | 做了没有 | 录样本 | 偏差和原因 |
|---|---|---|---|
| 酷狗 601 | 做了 | 直连，6 个房间同时 15 分钟，1 个房间有 17 个礼物（另 5 个房间 0 个） | 礼物表不用另取：601 自带名称、单价、图 |
| 六间房 201、跟风飞屏 | 做了 | 直连，5 个房间 15 分钟，21 个礼物；324 一个都没有 | 324 按网页脚本合成测试；图没有（礼物表是 8 MB 的脚本，不取） |
| LOOK 102 | 做了 | 直连，5 个房间 15 分钟，4 个礼物 | 价值单位“音符”按样本推断（`giftWorth`），不排档位 |
| SOOP 星气球、订阅 | 做了 18、33、87、105、91、93 | 代理，4 个房间 10 分钟：18 共 33 个、87 1 个、91 1 个、93 4 个 | 33、105 没录到，按网页播放器脚本的字段；108（送订阅）没录到，不做 |
| PandaTV 후원 | 做了 `SponCoin` | 代理，5 个房间 15 分钟，42 个 | `ItemCoin` 没录到，不做 |
| SHOWROOM 礼物 | 做了 t 2 和礼物表 | 代理，5 个房间 15 分钟，662 个 | t 11、17 没录到（只有 t 2），不做 |
| TwitCasting `gift=1` | 做了 | 代理，5 个房间 15 分钟，14 个 | — |
| Kick Kicks | 只修了订阅（没有样本） | 代理，6 个热门频道 15 + 20 分钟，0 个 `KicksGifted` | 根因：Kicks 在 `channel_<频道号>` 上，连接只订了 `chatrooms.<号>.v2` 和 `channel.<号>`；修好后 20 分钟仍没人送（见“Kick”） |
| FC2 打赏和礼物 | 没做 | 代理，热门 4 个、7 个房间各 15 分钟（共 30 分钟），0 个 `system_comment` | 平台人少（最多 171 人），录不到就停（任务书“不硬猜字段”） |

## 根因

- 酷狗：`kugoulive.dart` 的 `decode` 对 601 只回确认（`ack`），不解 `GiftEffectSocketMsg.Content`。
- 六间房：`sixroom.dart` 的 `_collect` 不认 201；跟风飞屏的 324 也不认。
- LOOK：`looklive.dart` 的 `chat` 只认文字（类型 0）和表情（自定义 2601），自定义 102 丢掉。
- SOOP：`soop.dart` 的 `decode` 只认服务 5（聊天）。
- PandaTV：`pandalive.dart` 的 `chat` 只认四种聊天类型，`SponCoin` 丢掉。
- SHOWROOM：`showroom.dart` 的 `decode` 只认 t 1；礼物名称要礼物表，没人取。
- TwitCasting：地址不带 `gift=1`，服务器根本不推礼物（D01.12 差异 5）。
- Kick：`kick.dart` 订阅 `chatrooms.<聊天室号>.v2`、`channel.<频道号>`，而网页客户端在 `channel_<频道号>` 上收 `KicksGifted`（kick.com 页面脚本 `useRealtime(channel_${channelId}, "KicksGifted")`），所以 4.x 从来收不到 Kicks；`kicks()` 的字段按公开客户端库写的，一直没跑到。

## 数据从哪来

| 平台 | 字段（来源） | `LiveGift` 怎么填 | 样本 |
|---|---|---|---|
| 酷狗 | 601 信封 `codec` 1，`GiftEffectSocketMsg.Content`（网页 `roomv2/main/index_*.js` 模块 80965 的 schema）：2 `giftid`、3 `giftname`、4 `num`、5 `price`（星币，礼物面板写“N星币”）、8 `image`、12 `roomid`、13 `senderid`、15 `sendername`、17/78 财富等级、18/19 收礼人、26 `comboId`、28 `comboIdV2`、29 `comboSumV2`、75 `comboGiftSum`；信封 `msgId`、`time` | `id`、`name`、`count`、`unitPrice = price`、`totalValue = price × num`、`unit = starCoin`、`price` 0 为 `free`；`comboKey = comboIdV2`（不是“0”时），否则 `comboId`；`comboTotal = comboGiftSum`；图是 `https://s4fx.kgimg.com` + `image`（网页 `imgHost`）；`receiverName = receivername` | `kugoulive/danmaku/S12-gifts`：17 个（灵羽仙珠 ×1、×10；主播自己送观众的 52000 星币生日派对和 300 毫秒内 10 个亲亲；一个观众的 4 种礼物） |
| 六间房 | 201：`fid`、`from`、`to`、`tm`、`askId`；`content.item`、`num`（数字或文字）、`giftCoin`（这次花的六币）、`itemName`、`groupnum`、`isContinue`、`keep.tmp_id`、`aiGiftPic`（网页 `Room.present.parseGet`、`chatMsg.parse`、`foldMsg`）；324：`content.type`、`msg`、`alias`、`uid`、`id`（`Room.GiftFlyFollow.parse`） | 201：`id = item`、`name = itemName`、`count = num`、`totalValue = giftCoin`（0 时没有）、`unitPrice = giftCoin / num`（整除时）、`unit = sixCoin`；`isContinue` 1 且有 `tmp_id` 时 `comboKey = fid:tmp_id`、`comboTotal = num × groupnum`；`receiverName = to`；324 类型 1 是 2000 六币的醒目留言 | `sixroom/danmaku/S08-gifts`：9 个（御风铃 1000、无限火力库存带留言、心动电池三下一个连击、蓝宝石钻戒两下、喜欢你库存、神秘人 ×3） |
| LOOK | 13-7 消息 `2` 为 100，`4`（custom）`type` 102：`content.giftId`、`giftName`、`giftIconUrl`、`number`、`giftWorth`、`giftValue`、`receiver`、`user` | `id`、`name`、`count = number`、`unitPrice = giftWorth`、`totalValue = giftWorth × number`、`unit = note`（**推断**：小麦穗、时光相册 1，旋转木马 100）；图改成 https；送礼人同聊天（名字、等级、粉丝团） | `looklive/danmaku/S06-gifts`：4 个 |
| SOOP | 网页播放器 `LivePlayer.js`（`readBody` 去掉第一个空字段后的 `t.packet`）：18 `[0] bj [1] 送礼人 [2] 昵称 [3] cnt … [11] uuid`；33 往后错一位；105 `[2] [3] [4]`；87 `[2] [3] … [7] urlImg … [9] adcon_cnt … [15] uuid`；91 `[2] sendId [3] 昵称 [8] uuid`；93 `[1] [2] [3] month … [6] accMonth … [8] uuid` | 星气球、视频气球：`kind = tip`、`name = 별풍선`/`영상풍선`、`count = cnt`、`unitPrice` 1、`totalValue = cnt`、`unit = starBalloon`；广告气球：`name = 애드벌룬`、没有价值（`other`）、图 `urlImg`；消息编号是 uuid；91/93 是订阅通知“X 订阅了频道，已订阅 N 个月” | `soop/danmaku/S10-balloons`：22 个包（星气球 16、广告气球 1、订阅 1、订阅仪式 4） |
| PandaTV | 发布的 `data.type` `SponCoin`，`message` 是 JSON 文字：`nick`、`id`、`coin`、`excelNick`（엑셀방송里收心的成员）、`heartMessage.message` | `kind = tip`、`name = 하트`、`count = coin`、`unitPrice` 1、`totalValue = coin`、`unit = heart`、`receiverName = excelNick`；留言另报一行聊天；编号 `<频道>:<offset>` | `pandalive/danmaku/S08-hearts`：15 个（2 个带留言） |
| SHOWROOM | t 2：`u`、`ac`、`g`、`gt`、`n`、`cl`、`created_at`；礼物表 `live/gift_list?room_id=`：`normal`、`enquete` 的 `gift_id`、`gift_name`、`point`、`free`、`image` | `id = g`、`count = n`；有礼物表时 `name`、`free`、付费礼物 `unitPrice = point`、`totalValue = point × n`、`unit = point`；没有礼物表时只有编号，`gt` 2 当免费；图是礼物表的 `image`，否则 `static.showroom-live.com/image/gift/<g>_s.png` | `showroom/danmaku/S07-gifts`（16 个，3 个房间）；`showroom/S06-gift-list`（254 个礼物） |
| TwitCasting | `gift` 事件：`id`、`message`（播放器的说明，含 🍡 分数）、`plainMessage`（送礼人的话）、`isPaidGift`、`item{name, image, showsSenderInfo}`、`sender{id, name, screenName}`、`createdAt` | `name = item.name`（如“お茶ｘ10”，数字是道具的一部分）、`count` 1、图 `item.image`、没有价值；`TwitcastingGift.paid = isPaidGift`；`plainMessage` 另报一行聊天；`showsSenderInfo` 为 false 的（活动分数通知，主播自己的账号发的）不报 | `twitcasting/danmaku/S09-gifts`：14 个事件（12 个礼物、2 个通知） |
| Kick | `channel_<频道号>` 上的 `KicksGifted`：`gift_transaction_id`、`message`、`sender`、`gift{gift_id, name, amount, pinned_time}`（网页脚本、公开客户端库） | 照旧（E05.5、D07.2）：有留言是醒目留言，没有是礼物 `KickGift` | 没有（35 分钟 0 个）；测试用合成帧 |

## 设计选择（D-003，维护者授权由执行者定）

1. **新单位**：`LiveGiftUnit.starCoin`（酷狗星币，100 个 = 1 元，进 `giftYuanUnits`，“换算成元”时写元；100:1 是酷狗充值的固定比例，礼物面板的“星币”价格样本里核对过，比例本身没在录制里出现）、`heart`（PandaTV 하트，约 110 韩元，和星气球一样 1.7 个约 1 元，只排档位不换算）、`note`（LOOK 音符，比例没核对，不排档位不换算）。翻译键 `gift_value_star_coin`、`gift_value_heart`、`gift_value_note`。
2. **酷狗**：连击键先用 `comboIdV2`（送礼人 id + 连击开始的毫秒），没有再用 `comboId`，都是“0”时不填（D07.1 按送礼人 + 礼物合并）。样本里每一次送都有自己的 `comboIdV2`，所以一次送一行。服务器对没确认的礼物会再发两次（D01.26 实测），连接现在照样回确认，另外按 `msgId` 去重（最多记 256 个），重复的不再报。主播送给观众的礼物照报，礼物行写“送给 观众N”。
3. **六间房**：礼物值用 `giftCoin`（这一下花的六币），库存礼物 `giftCoin` 0 时**不标免费**（平台没说免费，只是不花六币），只是没有价值；六币对元的比例 D07.2 没核对，仍不排档位。没有礼物表（8 MB 的脚本，手机上每次进房都取太重），礼物没有图，带 `aiGiftPic` 的除外。`fid` 为空或 0 的 201 是游戏奖品（网页写“参与 … 获得”），不报。
4. **六间房飞屏**：飞屏（108，1000 六币）和跟风飞屏（324 类型 1，2000 六币）都是醒目留言；它们的购买在 201 里还会以礼物 106、1516 出现，**不再报礼物**，一笔钱只出现一次（和哔哩哔哩醒目留言不出礼物行一样）。324 的其他类型是“有人跟风”，网页只给计数，不报。
5. **SOOP**：星气球、视频气球、广告气球是 `tip`（没有礼物物品的钱），名称用平台的韩文（礼物名是平台写的名字，和“小心心”一样）；数量就是星气球数，价值 = 数量。广告气球没有能放的价值，只报个数和图。订阅照 D07.6 的 CHZZK 写中文通知（`订阅了频道，已订阅 N 个月`），93 用 `accMonth`（没有用 `month`）；91 的“type”（样本是 103）意思不明，不读。
6. **PandaTV**：心是 `tip`，数量即价值；엑셀방송里 `excelNick` 是收心的成员，填 `receiverName`，礼物行写“送给 成员名”。
7. **送礼带的话另报一行聊天**（TwitCasting `plainMessage`、PandaTV `heartMessage`）：A08.11 的礼物行只画 `LiveGift`、不画 `message`，这两句话又不会以聊天再来一次，所以和 D07.6 的 Twitch Bits 一样，礼物之后报一行同一个人的聊天，编号是礼物编号加 `:words`（不和礼物撞去重）。六间房 201 的 `content.msg`（样本里一条）没有另报：网页只在动画里放，不进聊天列表。
8. **SHOWROOM 礼物表**：和 D07.6 的 AcFun 一样放在平台适配器（`ShowroomSite.giftCatalog`：并发共用一个请求、30 分钟内复用、失败 5 分钟内不再取、最多 16 个房间、`Isolate.run` 解析），由 `ShowroomDanmakuArgs.gifts` 在连弹幕时后台取一次，不让进房多等一个请求。礼物表不带 `Accept-Language` 时名字是英文（“Twinkle star”），照用平台给的。免费礼物（星星、种子）没有价值；付费礼物按 `point` 算（SHOWROOM 点数约 1 日元，用已有的 `point` 单位）。
9. **TwitCasting**：只在 `eventpubsuburl.php` 给的地址后加 `gift=1`（任务书允许的唯一连接改动）。道具没有价格，`isPaidGift` 不当“免费”的反面用，放在 `TwitcastingGift.paid` 里留着。
10. **Kick 改了订阅**（任务书写“不能改连接方式”，这里是偏差）：Kicks 只在 `channel_<频道号>` 上推，不订阅就永远收不到，和 TwitCasting 的 `gift=1` 是同一类“平台把礼物放在另一个地方”。连接多订一个公开频道（不需要授权），只读那个频道上的 `KicksGifted`。网页还在 `chatroom_<聊天室号>` 上收送订阅（`GiftedSubscriptionsEvent`）、积分兑换，这次没录到，没加。
11. **FC2 不做**：两次各 15 分钟、共 7 个房间（推荐里人最多的，最多 171 人），一条 `system_comment` 都没有，连 30 条历史评论里也没有；字段只在 D01.23 记录里（`tip_amount`、`gift_id`，礼物名要 `gift_list`），不硬猜。

## 合并的需要（不改 `gift_combiner.dart`，写在这里）

- **收礼人不同的礼物会合并**：D07.1 没有连击键时按“送礼人 + 礼物”合并（`giftComboKey`），不看 `receiverName`。酷狗样本里主播 300 毫秒内给 10 个观众各送一个亲亲，合成一行“送给 观众4 亲亲 ×10”，后 9 个收礼人看不到。建议：`receiverName` 不为空时把它加进没有连击键的合并键。
- **“总结”是猜出来的**：`giftIsComboSummary` 把“有连击键且 `comboTotal == count`”当作哔哩哔哩 `COMBO_SEND` 那样的总结。酷狗每一次送（`comboGiftSum` = `num`）和六间房连击的第一下（`groupnum` 1）都长这样，现在因为没有同键的行所以无害；以后平台的同键消息先到“总结形状”再到别的，就会按 15 秒窗口合并。建议在 `LiveGift` 上加一个明确的“总结”标记，由解析器填。
- D07.6 记录里的“数没涨就开新行”问题照旧。

## 改了哪些文件

- `packages/live_core`：`live_gift.dart`（`starCoin`、`heart`、`note`，`giftUnitsPerYuan` 加 `starCoin: 100`、`heart: 1.7`）；`sites/showroom/showroom_api.dart`（`ShowroomGiftInfo`、`ShowroomGiftCatalog`、`ShowroomApi.giftList`、`giftListUrl`，`ShowroomDanmakuArgs.gifts`、`withGifts`）；`sites/showroom/showroom_site.dart`（`giftCatalog` 和缓存，进房的弹幕参数带上它）
- `packages/live_danmaku/lib/src/sites/`：`kugoulive.dart`（`gift`、`_giftContent`、`imageHost`，连接按 `msgId` 去重）、`sixroom.dart`（`giftMessage`、`followFly`、`flyScreenGifts`）、`looklive.dart`（`gift`）、`soop.dart`（`balloon`、`subscription`、`fieldsOf`、服务号常量）、`pandalive.dart`（`hearts`）、`showroom.dart`（`gift`、`giftImage`，连接后台取礼物表）、`twitcasting.dart`（`TwitcastingGift`、`gift`、`withGifts`）、`kick.dart`（`kicksChannel`，多订一个频道）
- 应用：`shared/danmaku/gift_words.dart`（三个单位的文字，星币进“换算成元”）；翻译 `gift_value_star_coin`、`gift_value_heart`、`gift_value_note`
- 样本：`fixtures/kugoulive/danmaku/S12-gifts`、`sixroom/danmaku/S08-gifts`、`looklive/danmaku/S06-gifts`、`soop/danmaku/S10-balloons`、`pandalive/danmaku/S08-hearts`、`showroom/danmaku/S07-gifts`、`showroom/S06-gift-list`、`twitcasting/danmaku/S09-gifts`（每个都有 `meta.json`：录了什么、删了什么、怎么换的名字和编号）
- 测试：见下

## 新设置、翻译键、门禁基线

- 新设置：没有。
- 翻译键：`gift_value_star_coin`（“{value} 星币” / “{value} star coins”）、`gift_value_heart`（“{value} 爱心” / “{value} hearts”）、`gift_value_note`（“{value} 音符” / “{value} notes”）。
- 门禁基线：没改。

## 测试

- `live_core`：`live_gift_test.dart`（星币 100:1 的档位）、`sites/showroom_api_test.dart`（礼物表 254 个、坏行、拒绝）、`sites/showroom_site_test.dart`（进房不多发请求、并发共用、30 分钟、失败 5 分钟、16 个房间）。
- `live_danmaku`：每个平台一组（样本逐条、字段、边界、经过连接）：`sites/kugoulive_test.dart` 3 个（样本 17 个礼物逐字段；不是本房间、图、JSON 礼物、免费；连接每个礼物报一次、重复的 `msgId` 不报、每个都回确认）、`sites/sixroom_test.dart` 4 个（样本 9 个；奖品、飞屏购买、隐藏、连击；324 合成；连接）、`sites/looklive_test.dart` 2 个、`soop_test.dart` 3 个（样本 22 个包；33、105 按脚本合成；连接）、`sites/pandalive_test.dart` 2 个、`sites/showroom_test.dart` 3 个（有礼物表、没有礼物表、连接后台取表）、`sites/twitcasting_test.dart` 3 个（另改了 7 个用例的地址：多了 `gift=1`）、`sites/kick_test.dart` 1 个（`channel_` 上的 Kicks），改了订阅的用例。
- 应用（经过真实解析器 + 样本 + A08.11 礼物行 + D07.1 合并）：`kugou_sixroom_gifts_test.dart` 3 个、`looklive_gifts_test.dart` 1 个、`soop_balloons_test.dart` 2 个、`pandalive_hearts_test.dart` 1 个、`showroom_gifts_test.dart` 2 个、`twitcasting_gifts_test.dart` 1 个；`gift_line_test.dart` 的 G1 单位表加了 `starCoin`、`heart`。
- 全部结果和门禁见文末。

## 真机上要看的

- 见 [verify.md](verify.md)。重点：酷狗、六间房礼物行有没有出来、名称和价值对不对（酷狗有图和“N 星币”，“换算成元”打开时写元）；六间房连击一行涨数、飞屏和跟风飞屏只出现在醒目留言里；SOOP 星气球是“打赏 별풍선 ×N”；SHOWROOM 进房前几秒的礼物可能只有编号，之后有名称；TwitCasting、PandaTV 送礼带的话是礼物下面的一行聊天；Kick 有人送 Kicks 时出现（这次没录到，字段是网页脚本和公开库的）。

## 停在哪

- 做完的：酷狗、六间房、LOOK、SOOP、PandaTV、SHOWROOM、TwitCasting；Kick 修了订阅。
- 没做的：FC2（录不到）；Kick 的 Kicks 没有真实样本（字段未核对）；SOOP 108 送订阅、33 和 105 没有真实样本；PandaTV `ItemCoin`；SHOWROOM t 11、17；Kick `chatroom_` 上的送订阅。
- 下一步：K90 按 verify.md 看；Kick 在 Kicks 多的时候（大主播活动）再录一次核对字段；FC2 可以等有登录态时再试。

## 提交和门禁

- `9f7b45f6b` [D07.7] Kugou (601) and Six Rooms (201) gifts from recorded samples; Six Rooms follow fly-screens
- `34198ad10` [D07.7] SOOP star, relayed, video and ad balloons as tips; subscriptions as notices
- `54051b0b7` [D07.7] TwitCasting gifts: ask for gift=1 as the player does, report gift events
- `5f32f506a` [D07.7] SHOWROOM gifts (t 2) named, priced and pictured from the room's gift table
- `92316b992` [D07.7] PandaTV hearts (SponCoin) as tips; the words sent with them as chat
- `c566e2275` [D07.7] LOOK gifts (custom message 102) with their worth in notes
- `eb1f49f8d` [D07.7] Kick: subscribe to channel_<channelId>, where the web client hears KicksGifted
- `2396ddaf7` [D07.7] Record the recordings, the fields, the design choices and the real-device steps（本记录、verify.md、README、登记表和生成的文档）
- 录样本用的脚本（经过真实连接、给连接一个记下每一帧的 connector）和脱敏脚本留在本机临时目录，原始录音脱敏后已删掉。Kick 第二次录了 20 分钟（订阅了 `channel_<频道号>`，6 个频道都订阅成功），仍是 0 个 `KicksGifted`；FC2 第二次 7 个房间 15 分钟，0 个 `system_comment`。
- `bash tools/gate/gate.sh --all` 在 `2396ddaf7` 上通过（`gate: passed (all, 14 members)`，日志 `scratchpad/d077-1791532606/gate.log`）。合并后要再运行一次 `python3 tools/docs/docs.py`。

## 合并时（2026-10-09，维护者）

- 连击的第 1 条需要（备用合并键不看收礼人）已做：`giftComboKey` 的备用键在礼物写了收礼人时带上收礼人（`packages/live_core/lib/src/live_gift_combo.dart`），没写收礼人的键不变。酷狗主播给十个观众各送一次亲亲，现在是十行、各写自己的收礼人。测试：`packages/live_core/test/live_gift_combo_test.dart`，`kugou_sixroom_gifts_test.dart` 改成十行。第 2、3 条（明确的“总结”标记、重开规则）没改，留在这里。
- H01.8 的 `recordYuanUnits` 跟着 `giftYuanUnits` 加了 `starCoin`（测试要求两边一样），录制的酷狗礼物按 100 星币一元写 `price`。
