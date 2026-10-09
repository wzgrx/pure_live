# D07.4 哔哩哔哩礼物补全：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a946b61371cf48f76`）
- 分支和提交：`worktree-agent-a946b61371cf48f76`，基于 master `e256093f6`（含 E05.5、D07.1、A08.11、D02.2、D08.1）；两次代码提交、一次文档提交（见文末）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；调研：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 2、3 节哔哩哔哩、第 7 节

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 `SEND_GIFT` 的字段 | 做了：单价、图标 `gift_info.img_basic`、粉丝牌（`sender_uinfo.medal`，没有再 `medal_info`）、收礼人 `receive_user_info.uname`、`coin_type` 银瓜子算免费；`COMBO_SEND` 同样读图标、粉丝牌、收礼人 | 登录态的 `SEND_GIFT` 没有录到（没有账号，任务书说维护者录）：测试用照协议写的帧，字段名和访客收到的 `COMBO_SEND`（JSON，录到了）、`SEND_GIFT_V2`（同一份数据的 protobuf）对得上。送礼人的舰长等级不画，见设计选择 3 |
| c2 每条都报、`COMBO_SEND` 的累计 | D07.1 已做（`_isRepeatedCombo` 去掉，`comboTotal = total_num`），本任务没再动解析 | 真实录制发现 `COMBO_SEND` 在最后一下 5.15 秒后才到，超出 D07.1 的 5 秒窗口，结束的连击会多出一行“×2”：在 `GiftCombiner` 加了“连击总结”的 15 秒窗口（根因见下），D07.1 原有的测试都照过 |
| c3 访客的 `SEND_GIFT_V2` | 做了：先录了没删内容的访客样本（`S13-guest-gifts`），按字段号解（字段表见下）；送礼人是打码昵称，照 D-013 不还原、不能“屏蔽此用户”（屏蔽表本来就跳过打码昵称，测试守着） | |
| 礼物表 `giftConfig` | 做了：匿名能取（不带 Cookie、不登录，所有房间同一份 905 个礼物）；站点适配器取一次、全站缓存 6 小时，弹幕连接每次连接要一次、不等它；失败了不缓存，礼物照报，只是没有表里才有的图和价 | 访客的 V2 本身就带图标（51 条全有），表主要给上舰的图（`guard_resources`）、包里没有图或价的礼物用 |
| 上舰 | 做了：`BilibiliGift.guardLevel`（1 总督、2 提督、3 舰长），`gift_name` 空时用等级的名字；图标从礼物表的 `guard_resources` 取 | |
| A08.11 礼物行 | 没改界面：图、价值、档位照 A08.11 自动出来；widget 测试经真实解析器（访客样本）看图、“100 金瓜子”、粉丝牌、“送给 主播”、连击“×2”“200 金瓜子”、上舰的图和“很值钱” | |

## 根因

- 访客看不到礼物：访客收到的礼物全是 `SEND_GIFT_V2`（JSON 里 `data.pb` 是 Base64 的 protobuf），分发表没有这个命令（`packages/live_danmaku/lib/src/sites/bilibili.dart` 的 `_notice`，改前 `:490-492` 只认 `SEND_GIFT`、`COMBO_SEND`、`GUARD_BUY`），整条丢掉。录制 240 秒：50 条 `SEND_GIFT_V2`、1 条 `COMBO_SEND`，没有 `SEND_GIFT`。
- 礼物没有图、价：`_gift`（改前 `:757`）只读编号、名称、数量、金瓜子总价，没读 `price`、`gift_info`、粉丝牌；银瓜子礼物的价值丢了（E05.5 时只标免费）。
- 连击结束多一行（D07.1 的窗口）：`GiftCombiner.add` 只在上一下 5 秒内、最后 20 行里才合并（`apps/pure_live/lib/features/live_play/logic/gift_combiner.dart` 的 `comboWindow`）；`COMBO_SEND` 是连击结束后才发的总结（V2 的 13 号字段 `combo_stay_time` 是 10），样本里 5.15 秒后到，于是开了新行。D07.1 只有照协议写的帧，没有真实时间。

## `SEND_GIFT_V2` 字段表（`data.pb`，录制 `S13-guest-gifts` 50 条 + 另外 2 个房间 3 条核对）

外层 JSON：`{"cmd":"SEND_GIFT_V2","danmu":{"area":0},"data":{"dmscore":…,"pb":"<Base64>"}}`。V03.5 写的“第 10 字段 8 金瓜子”实际是 `coin_type` 文字（`gold`），价格在 5、7。

| 字段 | 值（样本） | 对应 `SEND_GIFT` 的 | 用了没有 |
|---|---|---|---|
| 1 | 访客没有 | `uid` | 用：`userId`（没有就是 `0`，和访客的聊天、`COMBO_SEND` 一样） |
| 2 | `想***` | `uname`（访客打码） | 用：`userName` |
| 3 | 头像地址 | `face` | 不用（礼物行没有头像） |
| 4 | `#00D1F1` | `name_color` | 不用 |
| 5 | 3、2、无 | 送礼人的 `guard_level`（推测） | 不用 |
| 8 | 子消息 | `medal_info` | 用 5 `medal_level`、6 `medal_name`；1 `target_id`、7～10 颜色、11 `is_lighted`、12 `guard_level` 不用 |
| 10 | 子消息 | 礼物本身 | 见下 |
| 10.1 | 31039 | `giftId` | 用 |
| 10.2 | `牛哇牛哇` | `giftName` | 用 |
| 10.3 | 1、10 | `num` | 用 |
| 10.4 | 1、2 | `giftType`（推测） | 不用 |
| 10.5 | 100、9900 | `price` | 用：单价 |
| 10.6 | 同 10.5 | `discount_price`（推测） | 不用 |
| 10.7 | 100、1000 | `total_coin`（= 5 × 3） | 用：价值 |
| 10.8 | `gold` | `coin_type` | 用：`silver` 算免费 |
| 10.9 | `4825830807182606848` | `tid` | 用：消息编号 `bilibili:gift:<tid>` |
| 10.10 | 1791512155 | `timestamp`（秒） | 用：`sentAt` |
| 10.11 | 1、2 | 连击第几下（`super_gift_num` 一类，推测） | 不用（D07.1 逐条相加，`COMBO_SEND` 给总数） |
| 10.12 | `batch:gift:combo_id:…` | `batch_combo_id` | 用：`comboKey` |
| 10.13 | 10 | `combo_stay_time` | 不用（解释了 `COMBO_SEND` 晚到） |
| 10.14 | 100、200 | `combo_total_coin`（连击到这一下的总价） | 不用 |
| 10.15、10.16、10.17、10.24 | 5、浮点 1.0、1、整数 | `effect`、`magnification`、`crit_prob`、`rnd` 一类（没核实） | 不用 |
| 10.18 | `投喂` | `action` | 不用 |
| 10.29 | {1 名字, 2 uid} | `receive_user_info` | 用 1：`receiverName` |
| 10.33 | 收礼人的 `uinfo` | `receiver_uinfo` | 不用（样本里删了） |
| 10.35 | {1 png, 2 webp, 5 gif} | `gift_info` | 用 1 `img_basic`：图标 |
| 10.34、10.37 | 编号 | 不明 | 不用（样本里删了） |
| 11 | 1 | 不明 | 不用 |
| 13 | 子消息 | 不明 | 不用 |
| 15 | 子消息 | `sender_uinfo` | 用 2.1 名字（2 没有时）、3.1 牌子名和 3.2 等级（8 没有时；样本里 2 条只有这里有牌子） |

## 各包的字段对应（`BilibiliGift` / `LiveGift`）

| 字段 | `SEND_GIFT` | `COMBO_SEND` | `SEND_GIFT_V2` | `GUARD_BUY` |
|---|---|---|---|---|
| `id` | `giftId` | `gift_id` | 10.1 | `gift_id` |
| `name` | `giftName`，空时礼物表 | `gift_name`，空时礼物表 | 10.2，空时礼物表 | `gift_name`，空时按 `guard_level` |
| `count` | `num` | `total_num` | 10.3 | `num`（月数） |
| `comboKey` / `comboTotal` | `batch_combo_id` / — | `batch_combo_id` / `total_num` | 10.12 / — | — |
| `unitPrice` | 总价 ÷ 数量（除得尽时），否则 `price`，否则礼物表（同一种瓜子） | `combo_total_coin` ÷ `total_num`，否则礼物表 | 10.7 ÷ 10.3，否则 10.5，否则礼物表 | `price` |
| `totalValue` / `unit` | `total_coin`，否则单价 × 数量；金瓜子 `goldSeed`，银瓜子 `silverSeed` 且 `free` | `combo_total_coin` 同左 | 10.7 同左 | `price × num`，`goldSeed` |
| `iconUrl` | `gift_info.img_basic`，否则礼物表 | 同左 | 10.35.1，否则礼物表 | 礼物表 `guard_resources[level].img` |
| `receiverName` | `receive_user_info.uname` | 同左 | 10.29.1 | — |
| 送礼人 | `uname`（空时 `sender_uinfo.base.name`）、`uid` | 同左 | 2（空时 15.2.1）、1 | `username`、`uid` |
| 粉丝牌（`fansName`、`fansLevel`） | `sender_uinfo.medal{name, level}`，否则 `medal_info{medal_name, medal_level}` | 同左 | 8.6、8.5，否则 15.3.1、15.3.2 | — |
| 其他 | `tid` → 消息编号，`timestamp` | — | 10.9、10.10 | `guardLevel`、`start_time` |

## 设计选择（D-003，维护者定）

1. **礼物表放站点适配器、全站一份**：接口不分房间（5050、545068、不带房间号都是同一份 905 个），所以不带房间号，`BilibiliSite.giftCatalog()` 取一次、并发只请求一次、缓存 6 小时（和 WBI 密钥一样长），不带登录 Cookie（公开接口）。1.5 MB，在另一个 isolate 里解析，不占界面线程。失败返回空表、不缓存，下一个房间再试。弹幕连接通过 `BilibiliDanmakuArgs.giftCatalog` 拿，每次连接要一次、不等它（礼物先照报）。**只放在哔哩哔哩自己的代码里**（`live_core` 的 `bilibili_api.dart`、`bilibili_site.dart`），没有做跨平台的礼物目录缓存；D07.3（斗鱼）要做共用的缓存时可以把它挪过去。
2. **包里的优先，表只补缺**：图标、名称、单价都是包里有就用包里的；单价按“总价 ÷ 数量”（盲盒的 `price` 是开出来的礼物价，`total_coin` 才是付的钱），除不尽时用 `price`，都没有才用表（瓜子种类要一样）。
3. **送礼人的舰长等级不另画**：README 的 D-003 选项“照聊天行（D01.32）的做法”。聊天行只画粉丝牌（牌子名 + 等级），不画舰长，所以礼物行也只给 `fansName`、`fansLevel`；舰长等级（`medal_info.guard_level`、V2 的 8.12）先不读。买上舰的 `GUARD_BUY` 留 `guardLevel`，名称就是“舰长/提督/总督”，图从表里取。
4. **银瓜子**：E05.5 时银瓜子只标免费、价值丢掉；现在单位是 `silverSeed`、价值是银瓜子数，仍然 `free`（礼物行不显示价值，档位 `normal`）。
5. **访客的 `userId` 是 `0`**：和访客的聊天、`COMBO_SEND` 一致；合并的兜底键有名字，不会把不同访客合在一起（V2 都有 `batch_combo_id`）。
6. **收礼人**：`receive_user_info.uname` 进 `receiverName`；礼物行在收礼人不是本房间主播时写“送给 X”（连麦时）。
7. **连击总结的窗口（改了 D07.1 的 `GiftCombiner`）**：有平台连击号、并且平台累计数等于自己的数量的消息（哔哩哔哩的 `COMBO_SEND`）是“连击总结”，上一下之后 15 秒内都算到原来那一行，不管那一行离底部多远；其他礼物照旧 5 秒、20 行。斗鱼第一下 `hits` 也等于数量，但新连击的 `hits` 不比上一次大，照旧算新连击（`restartedBy`）。15 秒：`combo_stay_time` 10 秒加余量。

## 样本（`fixtures/`，脱敏规则见各自的 `meta.json`）

- `fixtures/bilibili/danmaku/S13-guest-gifts/`：未登录（不带 Cookie、没有账号，游客 buvid 和 `getDanmuInfo` 的令牌，uid 0），虚拟主播区热闹的直播间 26966466，2026-10-09 10:15（北京时间）起 240 秒，protover 2（zlib，才好脱敏后重新打包）。701 条收到的消息里只留有礼物的 47 条、只留礼物通知（`SEND_GIFT_V2` 50、`COMBO_SEND` 1），每条重新打包成一个 protover 2 包，保留录制时间；发出的帧（带令牌和 buvid 的认证、心跳）去掉。脱敏：头像全换成 `noface.jpg`；主播（收礼人）和粉丝牌所属主播的 uid 换成 1000001、名字换成“主播”；`receiver_uinfo`（10.33）和不明编号（10.34、10.37）删掉；连击号里的 32 位哈希和主播 uid 换成同形的合成值。打码昵称本来就是打码的，粉丝牌名和等级（不打码）保留。检查过：原始录制里的 393 个头像地址、25 个连击哈希、17 个主播 uid 在样本里都找不到；门禁 `fixture privacy` 通过。
- `fixtures/bilibili/S18-gift-config/`：`giftPanel/giftConfig?platform=pc`，curl，不带 Cookie；905 个礼物裁到 8 个（样本里的 4 个和辣条、B坷垃、小心心、小花花），`combo_resources` 留 2 个，`guard_resources` 全留；留下的礼物都没有绑定主播（`bind_ruid`、`bind_roomid` 是 0），没有要脱敏的。
- 另外录了 4 个房间（1735947155、1775719573、545068、31999413 等，各 150～240 秒）只用来核对字段表，没有进仓库；545068（德云色）240 秒里访客没收到一条礼物。

## 改了哪些文件

- `packages/live_core/lib/src/sites/bilibili/bilibili_api.dart`：`BilibiliGiftInfo`、`BilibiliGiftCatalog`，`BilibiliApi.giftConfigUrl`、`giftCatalog`、`giftIcon`、`guardName`；`BilibiliDanmakuArgs.giftCatalog`。
- `packages/live_core/lib/src/sites/bilibili/bilibili_site.dart`：`giftCatalog()`（缓存、isolate 解析），两处 `BilibiliDanmakuArgs` 带上它。
- `packages/live_danmaku/lib/src/sites/bilibili.dart`：`BilibiliGift`（`silverCoins`、`guardLevel`、图标、收礼人，银瓜子单位）；连接取礼物表；`decode(gifts:)`；`_gift`、新 `_giftV2`、`_giftOf`、`_giftMedal`、`_guard`。
- `apps/pure_live/lib/features/live_play/logic/gift_combiner.dart`：`summaryWindow`、`isSummary`（设计选择 7）。
- 测试：`packages/live_danmaku/test/sites/bilibili_test.dart`、`packages/live_core/test/sites/bilibili_api_test.dart`、`bilibili_site_test.dart`、`apps/pure_live/test/features/live_play/gift_line_test.dart`、`gift_combiner_test.dart`。
- 样本：上面两份。文档：本记录、`docs/tasks.toml` 和生成的文档。

## 新设置、翻译键、门禁基线

- 都没有。

## 测试

- `live_danmaku` `bilibili_test.dart`：新增 5 个（D07.4 组：访客样本 51 条逐条看——全部打码、uid 0、有图、金瓜子、单价 100、有粉丝牌，第一条逐字段，十个一起送，“薯条”两下加 `COMBO_SEND` 同一个连击号；打码昵称屏蔽不了、屏蔽词照样起作用（把“现在”固定成录制时间，D-017）；`SEND_GIFT_V2` 的各种形状（登录态的 uid、名字和只在 15 里的牌子、银瓜子、没有价和图时用表、表里也没有、没有名字用表、什么都不给的五种坏包、坏包不连累同一条消息里的下一条）；礼物表补 `COMBO_SEND`、`SEND_GIFT`、`GUARD_BUY`（包里的价和图优先、盲盒按付的钱、小心心按表算银瓜子、上舰的图和等级名、没有等级没有名字）；连接每次连接要一次表、不等它、失败照报）；改了 1 个（C-2：单价、银瓜子的价值和单位、`guardLevel`）。D07.1 的“每条都报”测试没动、照过；3.x 的 5 份冻结对照照过（旧样本的 `SEND_GIFT_V2` 内容是删掉的，照旧什么都不给）。
- `live_core`：`bilibili_api_test.dart` 新增 3 个（S18 解析、坏条目和坏信封、等级名和图片地址），`bilibili_site_test.dart` 新增 2 个（并发只请求一次、不带 Cookie、6 小时内复用、过期再取；失败不缓存）、改 1 个（进房的弹幕参数带礼物表）。
- 应用：`gift_line_test.dart` 新增 1 个（访客样本经真实解析器：图、“100 金瓜子”、粉丝牌、“送出”或“送给 主播”、连击“×2”“200 金瓜子”，上舰经礼物表有图、“很值钱”的 4 宽标记）；`gift_combiner_test.dart` 新增 2 个（访客样本按录制时间回放：51 条 → 49 行、0 条丢掉，“薯条 ×2”一行；`COMBO_SEND` 6 秒后、隔 30 行仍算原来那一行，漏掉的一下补上，15 秒后另起一行，普通的一下照旧 5 秒）。D07.1 原有的合并测试全部照过。
- 全部测试在门禁里跑（结果见文末）。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. 未登录（设置里退出哔哩哔哩），进一个热闹的直播间（虚拟主播区、点唱区），看 2 分钟 | 聊天列表里有礼物行：打码的名字（`想***`）、粉丝牌、礼物的图、“送出 牛哇牛哇 ×1”、“100 金瓜子”；以前访客一条礼物都看不到 |
| 2. 同一个房间等一个连击（有人连点同一个礼物） | 一个连击一行，数字往上涨；连击结束约 5 秒后不会再多出一行同样的“×N” |
| 3. 长按一条访客礼物行 | 没有“屏蔽此用户”（打码昵称，D-013）；屏蔽词加礼物名后，这个礼物不再出现 |
| 4. 登录后同一个房间 | 名字是全名；礼物有图、有价值；连击一行、最终数字和网页上的一致 |
| 5. 有人上舰时（可遇不可求） | “开通 舰长 ×1 个月”，舰长的图，“19.8万 金瓜子”，很值钱的标记 |
| 6. 断网进房再联网（或飞行模式进房） | 礼物照样出现（没有礼物表时上舰没有图），不卡、不报错 |

## 提交和门禁

- `23920a6dd` [D07.4] Fetch Bilibili's public gift table once and keep it for every room（礼物表）
- `ad7027eb1` [D07.4] Parse guests' SEND_GIFT_V2; fill Bilibili gift prices, pictures, medals and guard levels（解析、访客样本、合并窗口）
- `1e99a0a15` [D07.4] Record the SEND_GIFT_V2 field table, design choices, samples and real-device steps; mark it 待真机
- `ed20c0209` [D07.4] Use a cascade in the combo summary test（第一次门禁只有 `apps/pure_live analyze` 的一条 `cascade_invocations` 提示没过，测试全过）
- `bash tools/gate/gate.sh --all` 在 `ed20c0209` 上通过：`gate: passed (all, 14 members)`。
- 和别的任务可能冲突的文件：`gift_combiner.dart`（D07.1 的文件，本任务只加 `summaryWindow`、`isSummary` 和 `add` 里的一行判断；A08.12 如果改合并会碰到）、`gift_line_test.dart`、`gift_combiner_test.dart`（只在中间加用例和一个 `_pb` 小函数）、`bilibili.dart`（D01 的哔哩哔哩任务）、`docs/tasks.toml` 和生成的文档（合并后重新运行 docs.py）。

## 和 A08.12 合并（2026-10-09，维护者）

- A08.12 的飞行礼物（`shared/danmaku/gift_flights.dart`）也按 5 秒判断连击结束、结束时飞一次总数。哔哩哔哩的 `COMBO_SEND` 在结束后约 5 秒才到，会被当成新连击、把同一个总数再飞一次。现在飞行礼物记住 15 秒内结束的连击（和列表的 `summaryWindow` 一样长），总数不比飞过的大的总结消息不再飞；比飞过的大（房间漏收了几次）照常飞。判断“总结消息”的规则挪到共用的 `giftIsComboSummary`（`shared/danmaku/gift_combo.dart`），`GiftCombiner.isSummary` 用它。测试：`test/shared/gift_flights_test.dart` 的“D07.4: Bilibili's COMBO_SEND after the combo ended …”（改之前会飞第三次）。
