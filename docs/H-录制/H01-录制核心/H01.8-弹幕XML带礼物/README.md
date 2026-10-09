# H01.8 录制的弹幕 XML 带礼物（新开关，默认关）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[V03.5](../../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 第 0 节第 2 条、第 4 节 F-3、第 6.7 节最后一条、第 7 节 H0x.x；用户 2026-10-09（D-040）
- 相关：依赖 [E05.5](../../../E-直播平台/E05-平台框架和模型/E05.5-统一礼物模型LiveGift/README.md)；弹幕 XML 的录制验证 H01.4；礼物过滤 D07.1；决定 D-018、D-040；任务书 [brief.md](brief.md)

## 目标

录制时同时录的弹幕 XML 可以带上礼物（新开关“录制弹幕时包含礼物”，默认关），回放时能看到谁送了什么。默认关，关着时录出来的 XML 和现在一模一样。

## 3.x 和现状

| 方面 | 3.x | 现在 | 要做到 |
|---|---|---|---|
| 写什么 | 只写聊天 | `apps/pure_live/lib/app/recording.dart:63`：`DanmakuReceived` 只收 `chat` 且过滤通过的；`packages/live_record/lib/src/chat.dart:321`：`message.type != LiveMessageType.chat` 直接返回 | 开关开着时也写礼物 |
| 格式 | 哔哩哔哩式 `<d p="…">` | 同 | 礼物写 `<gift ts="…" user="…" giftname="…" giftcount="…" price="…"/>`（哔哩哔哩录播姬的格式）；放在同一个文件里，`<d>` 不变（做成的样子见“定稿”） |
| 醒目留言 | 不录 | 不录（同上两处只认 `chat`） | 归同一个开关，写 `<sc>`（定稿第 5 条） |

## 方案

- c1 新设置 `recordDanmakuGifts`（录制的设置一节，默认关），在录制设置“弹幕”一组（H03 或 A10 的设置页，照现有布局放一行开关，说明“弹幕文件里也记下礼物；有的播放器不认礼物会忽略它”）。键名开发时定。
- c2 `recording.dart`：开关开着时礼物也送进写入器，礼物同样过 D07.1 的屏蔽（D07.1 没合并时只过屏蔽表）；连击：只写合并后的最终一条（录制不需要中间状态），没有合并时每条都写。
- c3 `live_record/lib/src/chat.dart`：写 `<gift>` 元素（时间按录制起点的偏移，和 `<d>` 一样；`price` 是 `LiveGift.totalValue`，单位写进 `unit` 属性），XML 转义照现有函数。
- 需要选的（D-003）：`<gift>` 元素（A，录播姬和多数弹幕播放器认）还是另一种 `<d>` 模式（B，会当成弹幕飞过，不选）→ A。

## 别的工具认什么（2026-10-09 读源码）

| 工具 | 写或读 | 礼物 | 醒目留言 | 舰长 | `price` 的单位 |
|---|---|---|---|---|---|
| 录播姬 BililiveRecorder（`BililiveRecorder.Core/Danmaku/BasicDanmakuWriter.cs`） | 写 | `<gift ts user uid giftname giftcount [raw] />`，每个包一条，**默认不录**（`RecordDanmakuGift`） | `<sc ts user uid price time [raw]>文字</sc>`，默认录 | `<guard ts user uid level count [raw] />` | 醒目留言的 `price` 是元；礼物没有 `price` |
| blrec（`src/blrec/core/danmaku_dumper.py`、`danmaku/io.py`） | 写 | `<gift ts uid user giftname giftcount cointype price />`，免费礼物另有开关 | `<sc … price time>`，`price` = 元 × `rate`（1000） | `<guard … giftname count price level />` | 厘（千分之一元，金瓜子） |
| DanmakuFactory（`src/XmlFile.c:221-411`） | 读，转 ASS | 认 `<gift>`：`ts`、`user`、`uid`、`giftname`、`giftcount` 或 `count`、`price`、`cointype`、`raw` | 认 `<sc>`：`price`、`time`、文字；文件里有 `<BililiveRecorder` 时把 `price` 乘 1000 | 认 `<guard>`：按 `level` 定价格和时长，没有 `level` 时显示 0 秒 | 厘；`--giftminprice`（元）按它挡便宜礼物；同一时刻、同一人、同名礼物会加在一起 |
| PotPlayer、弹弹play 等播放器 | 读 | 只认 `<d>`，别的元素忽略 | 同 | 同 | — |

DanmakuFactory 解析的小毛病：`giftname` 读到空格就断（`getNextWord`），后面的属性会读乱；属性值最后紧跟 `/>`（没有空格）时最后一个值会带上 `/`。

## 定稿（2026-10-09，维护者按 D-003 选的）

用户授权维护者选（D-040、D-003），开发时定了下面这些，用户随时可以推翻：

1. **格式用录播姬的 `<gift>`、`<sc>`**（方案 A），和 `<d>` 在同一个文件、同一个时间起点（这次尝试的视频开头）。录播姬写、blrec 写、DanmakuFactory 读的都是这几个元素名和属性名，播放器只认 `<d>`、不会把礼物当弹幕飞过。不选另一种 `<d>` 模式（B）：所有播放器都会把它当普通弹幕飞。
2. **`price` 用厘（千分之一元）**，不是平台单位：这是 blrec 写的、DanmakuFactory 比较和显示的单位（哔哩哔哩的金瓜子正好是厘）。只给汇率固定在元的单位写（分、金瓜子、钻石、抖币、AC 币，和聊天列表“礼物价值换算成元”是同一组，A08.12；测试保证两边一样）；免费礼物写 `price="0"`（DanmakuFactory 和 blrec 都把银瓜子当 0）；海外币种和没核实的单位不写 `price`（DanmakuFactory 当成不知道价格，照样显示）。平台自己的数字和单位另写 `value`、`unit`（`LiveGiftUnit` 的名字，例如 `goldSeed`、`bits`），别的工具忽略。原方案写的“`price` 是 `totalValue`、单位写进 `unit`”因此改成这样。
3. **连击只写一条**（c2）：规则和聊天列表一样（D07.1 的 `giftComboKey`、`giftComboTotal`、`giftComboRestarted`、`giftIsComboSummary`，从应用的 `gift_combo.dart` 移到 `live_core` 的 `live_gift_combo.dart`，应用那边转出口，三处用同一份）。一个连击 5 秒没有新礼物就写，时间是它第一下的时间，数量是总数；哔哩哔哩的 `COMBO_SEND` 在连击结束后 15 秒内来时只补连击漏掉的部分（总数一样就什么也不写，D07.4）；连续送超过 30 秒的连击先把已有的写一条，后面的另起一条（不然后面的聊天要一直等）。DanmakuFactory 自己只合并同一时刻的礼物，所以写成每个包一条会在回放里刷屏、文件也大；聊天列表的“每秒 10 行”“最后 20 行”是显示的限制，录制不用。
4. **文件按时间排**：连击开着时，它第一下之后的聊天、醒目留言先留在内存里，等连击写出后按时间一起写；没有连击（开关关着）时每 2 秒照旧写出去。最长留 30 秒多一点，进程被杀最多丢这么多。
5. **醒目留言归同一个开关**（以前也不录：连接器只收 `chat`，写入器只认 `chat`）。礼物和醒目留言都是“谁花钱做了什么”，回放要看的是同一件事；录播姬把两者分开、醒目留言默认录，这里为了“默认关、老用户感觉不到变化”（D-040）放在同一个开关下，开关的说明写明“礼物和醒目留言”。写成 `<sc ts user price time>文字</sc>`：`time` 是平台显示的秒数；哔哩哔哩、斗鱼的价格是元，写成厘（`price="30000"`）；其他平台的价格单位不一（D07.2 正在整理），写平台的数字 `value` 和平台文字 `pricetext`，不写 `price`。进房时平台补发的旧醒目留言（`replayed`）不写；同一条只写一次。
6. **过滤**：礼物走直播间同一个礼物过滤（屏蔽用户、屏蔽词看“名称 ×数量”、去重闸门，D07.1），醒目留言照直播间不过滤；本地互动的礼物、没有 `LiveGift` 的礼物不写。开关每条消息都读，录制中途改了马上生效；关着时礼物根本不进过滤器，聊天的去重和以前一样。
7. **转义**：照现有的 `escape`（XML 1.0 不认的字符去掉）；礼物名里的空白换成不换行空格（U+00A0），因为 DanmakuFactory 读 `giftname` 遇到空格就断；每个元素以 ` />` 结尾（空格在 `/>` 前，和录播姬一样）。不写 `uid`：`<d>` 本来就只写用户编号的散列，礼物也不写真实编号。
8. **设置**：键名 `recordDanmakuGifts`（`live_store` 录制一节，默认关，跟备份和设备同步，D-018 只加不改），在录制设置“基础配置”组“同时录制弹幕”下面一行开关，图标用礼物行的 `AppIcons.chatGift`；不随“同时录制弹幕”变灰，因为每个任务可以单独开录弹幕。设置搜索能找到（目录里在“录制”一节登记了这一行）。
9. **“弹幕 N 条”只数聊天**（直播间录制面板），礼物和醒目留言不算进去。

## 验证

- 自动测试：`packages/live_record/test/chat_gifts_test.dart`（开关关时和 H01.8 之前的写入器逐字一样；格式、转义、连击、摘要、时间顺序、30 秒分段、醒目留言、20 分钟忙直播间的性能）；`apps/pure_live/test/features/recorder/recording_gifts_test.dart`（连接器开关、过滤、设置、搜索）；`record_settings_page_test.dart`（设置行）；`packages/live_store/test/record_gifts_setting_test.dart`（默认关、备份往返）。
- 真机：见 [verify.md](verify.md)。

## 留下的问题

- 舰长、会员没有单写 `<guard>`：`live_record` 只看得到 `LiveGift`，哔哩哔哩的舰长等级在 `live_danmaku` 的 `BilibiliGift` 里；`<guard>` 没有 `level` 时 DanmakuFactory 显示 0 秒。现在写成 `<gift giftname="舰长" giftcount="月数">`。要单写时把等级放进 `LiveGift`（E05 组）再改。
- 醒目留言的价格单位等 D07.2 给出平台单位后，可以给更多平台写 `price`。
- 虎牙、百度等礼物的价值单位没核实（`LiveGiftUnit.other`），只写 `value`。
