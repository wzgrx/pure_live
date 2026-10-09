# D07 礼物和付费消息

平台礼物、醒目留言（付费留言）、上舰和开会员这几类“花钱的消息”的数据和规则：统一的礼物数据怎么从各平台的解析器来、礼物过不过屏蔽、连击怎么合并、忙的直播间怎么限速、价值按什么单位算、哪些平台有醒目留言、礼物表从哪取。用户 2026-10-09 要“所有平台的礼物都要有自己的显示设计，并且可以打开和关闭”，设计按 [V03.5](../../V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md) 的方案 A 做（D-040）。

## 范围

- 包括：
  - 礼物进来以后的规则：直播间控制器的礼物分支（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:1148-1151`，B-21 加的“礼物进聊天列表”）、礼物过不过过滤（`packages/live_danmaku/lib/src/filters/message_filter.dart:105` 现在对非聊天直接放行）、连击合并和每秒上限、礼物在 500 行聊天记录里的上限（D07.1）。
  - 醒目留言的平台表 `superChatPlatforms`（`packages/live_core/lib/src/live_site.dart:73`）、价格单位（`chat_list.dart:918-919` 的 `superChatPrice` 兜底 `￥`）、上舰和会员进醒目留言、六间房付费飞屏（D07.2）。
  - 各平台解析器里**和礼物、醒目留言有关的部分**（`packages/live_danmaku/lib/src/sites/`）：斗鱼礼物表（D07.3）、哔哩哔哩（D07.4）、抖音（D07.5，受阻）、已有样本的平台（D07.6）、要先录样本的平台（D07.7）。
  - 礼物的样本：`fixtures/<平台>/danmaku/` 里新录的礼物帧和冻结输出（`expected.json`）。
- 不包括（归哪里）：
  - 统一礼物模型 `LiveGift` 本身（`packages/live_core`）→ [E05](../../E-直播平台/E05-平台框架和模型/README.md) 的 E05.5；D07 的任务都依赖它。
  - 礼物行、醒目留言卡片长什么样，礼物的开关和飞行弹幕里礼物的样子 → [A08](../../A-界面设计/A08-弹幕界面/README.md)（A08.11、A08.12；名字的样子在 A08.10）。分工照 D 组的规则：长什么样归 A08，数据从哪来、什么规则、多快归 D07。
  - 平台弹幕的连接、聊天和其他消息的解析 → [D01](../D01-平台弹幕协议/README.md)（同一批 `sites/*.dart` 文件，礼物以外的改动开在 D01）；屏蔽表本身和过滤链的其他规则 → [D02](../D02-过滤和屏蔽/README.md)；`ChatFeed` 的数据流和每帧通知 → [D04](../D04-数据流和性能/README.md)。
  - 录制的弹幕 XML 带礼物 → H01.8；本地互动里的“本地礼物”（只有自己看得到的，不是平台礼物）→ [D08](../D08-本地互动/README.md)。

## 现状：做到哪、怎么工作的

（2026-10-09，读 V03.5 第 0、2、4 节，代码 master `87dd63729`；行号开工前按名字再核一次。）

- 用户看得到的：礼物只在聊天列表里一行（礼物图标 `AppIcons.chatGift` + 名字 + 第三色的一句文字，`apps/pure_live/lib/features/live_play/danmaku/chat_list.dart:657-689`），“在聊天列表显示礼物”（`showChatGifts`，默认开）可以关；一条礼物一行，不合并、没有礼物图、没有价值；飞行弹幕、多画面、录制、电视都没有礼物。醒目留言进醒目留言标签和列表一行（`chat_list.dart:690-700`）。
- 内部：

```text
平台解析器（sites/*.dart）→ LiveMessage(type: gift, message: 一句拼好的文字, data: 平台自己的礼物类)
  → LiveRoomController._onDanmaku
      gift：showGifts 关或文字空 → 丢；否则 chat.add(ChatLine.gift)（room_controller.dart:1148-1151），不过 _filter
      superChat：_addSuperChats + chat.add(ChatLine.superChat)（:1134-1138）
  多画面 multiview_controller.dart:1002 丢掉礼物；录制 app/recording.dart:63、live_record chat.dart:321 只写聊天
```

- 数据：上报礼物的 9 个平台各有自己的类（`BilibiliGift`、`DouyuGift`、`HuyaGift`、`MissevanGift`、`KilakilaGift`、`NiconicoGift`、`YouTubeGift`、`BaiduLiveGift`，Kick 没有类），字段不统一，应用只用 `message`；克拉克拉、niconico、Kick 的文字带送礼人，礼物行前面又印一次名字。协议里有礼物、匿名能收到、4.x 丢掉的 13 个（V03.5 第 2 节“数一下”）；连击号（虎牙 `lComboSeqId`、猫耳 `combo.id`、斗鱼 `hits`）都没用上。
- 和 3.x 比：3.x 从来没显示过平台礼物（只有枚举，`v3.2.11:lib/common/models/live_message.dart:6`），礼物显示是 4.x 的新功能（B-21）；醒目留言 3.x 只有哔哩哔哩、斗鱼、虎牙，价格 `￥`。

## 代码地图

| 文件 | 和礼物有关的部分 |
|---|---|
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | `showGifts`（`:268`）、开关改了时去掉礼物行（`:807-817`）、`_onDanmaku` 的 `superChat`（`:1134`）和 `gift`（`:1148`）分支、`addLocal`（`:1159`，本地礼物不受开关影响） |
| `packages/live_danmaku/lib/src/filters/message_filter.dart` | `accepts`（`:104`）：非聊天直接放行（`:105`） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart` | `ChatFeed`（`capacity` 500，`:107`）：礼物和聊天共用 |
| `packages/live_core/lib/src/live_site.dart` | `superChatPlatforms`（`:73`）、`hasSuperChats`（`:63`） |
| `packages/live_core/lib/src/live_message.dart` | `LiveMessageType.gift`（`:8-9`，注释还写着 “not shown yet”） |
| `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart` | 礼物行（`:657-689`）、醒目留言行（`:690-700`）、`superChatPrice`（`:918`）——样子归 A08 |
| `packages/live_danmaku/lib/src/sites/bilibili.dart` | `BilibiliGift`（`:20`）、连击只报第一条（`:73-74`、`:179-186`）、`_gift`（`:757`）、`_guard`（`:784`）、`_superChat`（`:835`） |
| `packages/live_danmaku/lib/src/sites/douyu.dart`、`douyu_api.dart` | `dgb` 分发（`:182`）、`gift`（`:301`）；`betard` 已请求（`packages/live_core/lib/src/sites/douyu/douyu_api.dart:346`），不读 `room_gift` |
| `huya.dart`、`missevan.dart`、`kilakila.dart`、`niconico.dart`、`youtube.dart`、`baidulive.dart`、`kick.dart` | 各自的礼物类和解析（行号见 V03.5 第 3 节） |
| `features/multiview/logic/multiview_controller.dart`、`app/recording.dart`、`packages/live_record/lib/src/chat.dart` | 不要礼物的三处（`:1002`、`:63`、`:321`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `packages/live_danmaku/test/sites/`、`fixtures/<平台>/danmaku/S*/expected.json` | 各平台的冻结输出，礼物的字段改了这里跟着改 |
| `packages/live_danmaku/test/message_filter_test.dart` | 过滤链（礼物过滤要加的用例在这里） |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart` | 每秒 200 条的基准（D04.1），D07.1 加礼物 |

## 3.x 基线

- 3.x 不上报、不显示平台礼物；醒目留言：`v3.2.11:lib/core/danmaku/bilibili_danmaku.dart:415`、`douyu_danmaku.dart:146-148`、`huya_danmaku.dart:252`，价格 `￥`。所以礼物的开关和默认值不受“3.x 用户的习惯”约束，但已经有的“在聊天列表显示礼物”（默认开）不改；新设置按 D-040 默认保持现在的样子。
- 上游 pure_live `11a47144e` 照 4.x 加了哔哩哔哩的三种礼物，**对礼物查屏蔽**（`upstream/master:lib/domains/live/presentation/playback/controllers/danmaku_controller.dart:230`），没有样式、合并和开关。flame_barrage 的 `ComboAnimation`（`lib/src/animation/combo_animation.dart`）可以借连击数字的做法。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有统一的礼物数据，文字格式各平台不同，名字出现两遍 | `live_message.dart:8`；`kilakila.dart:341`、`niconico.dart:452`、`kick.dart:178` | 做不出统一的礼物行和合并 | E05.5 |
| 礼物不过屏蔽、不去重 | `message_filter.dart:105`、`room_controller.dart:1148-1151` | 屏蔽的人的礼物照样出现；重连补发重复 | D07.1 |
| 礼物一条一行，和聊天共用 500 行 | `chat_feed.dart:107` | 热门直播间（斗鱼样本 60 秒 125 条 `dgb`）把聊天挤掉 | D07.1 |
| `superChatPlatforms` 少 7 个平台；价格兜底 `￥` | `live_site.dart:73`、`chat_list.dart:918-919` | 醒目留言页空着时说“这个平台没有醒目留言”；虎牙等单位不对 | D07.2 |
| 哔哩哔哩访客收不到 `SEND_GIFT`，只收到不解的 `SEND_GIFT_V2` | `bilibili.dart` | 访客只看得到上舰 | D07.4 |
| 抖音匿名网页端收不到礼物 | E01.4 记录 `:284` | 抖音没有礼物 | D07.5（受阻） |
| 快手（C-16）、YY（C-20）、LiveMe、TikTok、CC 的礼物 | 平台限制 | — | 不做或受阻，理由见 V03.5 第 7 节最后一段 |

## 相关决定和规范

- D-040：V03.5 方案 A 同意做；设计里要选的按 D-003 由维护者定；新设置默认保持现在的样子，任务书写明的例外除外（D07.2 的“上舰和开会员进醒目留言”默认开）。
- D-017（测试不访问真实平台、样本时间固定）、D-018（新设置只加不改）、D-013（打码昵称）、D-005（平台给的中文、日文句子不再拼进 `message`，文字走翻译）。
- [specs/UI.md](../../specs/UI.md) 第 9.3 节（不用动画和阴影表示档位）、第 9.4 节（界面线程 ≤3 毫秒/帧）；[specs/ENGINEERING.md](../../specs/ENGINEERING.md) 的样本隐私规则。

## 测试和验证

- 自动：平台任务按样本对照测试（录真实样本、脱敏、冻结输出）；D07.1 的合并和限速有单元测试和基准；所有测试不访问真实平台、定时器至少 1 秒。
- 真机：每个任务的 `verify.md`；国内五大的礼物并入 S02.6 的弹幕阶段一起看。

## 路线

1. **E05.5**（统一礼物模型）先做，D07 的任务都依赖它。
2. **D07.1**（过滤、合并、限速）和 **D07.6** 第 1 阶段（虎牙、猫耳、克拉克拉的连击键）一起排，合并才有平台的连击号；**D07.4** 第 1 阶段（哔哩哔哩每条都报）要和 D07.1 同时或之后合并。
3. **D07.2**（醒目留言）、**D07.3**（斗鱼礼物表）：第二档，和 A08.11 礼物行并行。
4. **D07.6** 余下的阶段（AcFun、17LIVE、BIGO、海外的订阅和 Bits）。
5. 第三档：**D07.7**（先录样本）、**D07.5**（解除受阻后）。
6. 同一组同时只开一个开发（PROCESS 第 5.1 节）：D07、D08、D02 都在 D 组，排队做。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [D 弹幕](../README.md)。

- 代码：`logic/room_controller.dart` 的礼物分支、`packages/live_danmaku/lib/src/sites/` 的礼物部分
- 进度：`████████░░░░░░░░░░░░` 40%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| D07.1 | 礼物过滤、连击合并、限速和行数上限（含基准） | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](D07.1-礼物过滤连击合并和限速/README.md)、[任务书](D07.1-礼物过滤连击合并和限速/brief.md)、[记录](D07.1-礼物过滤连击合并和限速/record.md)、[真机验证](D07.1-礼物过滤连击合并和限速/verify.md) |
| D07.2 | 醒目留言的平台表和价格单位；舰长、会员进醒目留言；六间房飞屏 | 功能 | 待真机 | 2026-10-09 | — | [设计或说明](D07.2-醒目留言平台表和价格单位/README.md)、[任务书](D07.2-醒目留言平台表和价格单位/brief.md)、[记录](D07.2-醒目留言平台表和价格单位/record.md)、[真机验证](D07.2-醒目留言平台表和价格单位/verify.md) |
| D07.3 | 斗鱼礼物目录（betard）和礼物字段 | 平台 | 待真机 | 2026-10-09 | — | [设计或说明](D07.3-斗鱼礼物目录和字段/README.md)、[任务书](D07.3-斗鱼礼物目录和字段/brief.md)、[记录](D07.3-斗鱼礼物目录和字段/record.md)、[真机验证](D07.3-斗鱼礼物目录和字段/verify.md) |
| D07.4 | 哔哩哔哩礼物补全：游客的 SEND_GIFT_V2、图标、舰长等级 | 平台 | 待真机 | 2026-10-09 | — | [设计或说明](D07.4-哔哩哔哩礼物补全/README.md)、[任务书](D07.4-哔哩哔哩礼物补全/brief.md)、[记录](D07.4-哔哩哔哩礼物补全/record.md) |
| D07.5 | 抖音礼物（受阻：先确认登录后能不能收到） | 平台 | 受阻 | — | — | [设计或说明](D07.5-抖音礼物/README.md)、[任务书](D07.5-抖音礼物/brief.md) |
| D07.6 | 已有样本的平台补礼物：AcFun 目录、17LIVE、BIGO、连击键、Twitch Bits、CHZZK 订阅、YouTube 贴纸 | 平台 | 未开始 | — | — | [设计或说明](D07.6-已有样本的平台补礼物/README.md)、[任务书](D07.6-已有样本的平台补礼物/brief.md) |
| D07.7 | 要先录样本的平台补礼物：SOOP、SHOWROOM、TwitCasting、PandaTV、FC2、酷狗、六间房、LOOK、Kick | 平台 | 未开始 | — | — | [设计或说明](D07.7-要先录样本的平台补礼物/README.md)、[任务书](D07.7-要先录样本的平台补礼物/brief.md) |

## 还没完成的

- **D07.5 抖音礼物（受阻：先确认登录后能不能收到）**（受阻，第三档，规模 中）
  - 阶段：确认登录后会不会推 WebcastGiftMessage（录样本） → 按 3.x 的字段号解礼物和连击
  - 说明：受阻：匿名网页端收不到 WebcastGiftMessage（E01.4 实测约 2000 条消息、D01 录的 5 个房间 150 秒都没有）；要登录态的样本才能开工；依赖 E05.5
  - 来源：V03.5 第 2、3 节抖音、第 7 节；用户 2026-10-09（D-040）
- **D07.6 已有样本的平台补礼物：AcFun 目录、17LIVE、BIGO、连击键、Twitch Bits、CHZZK 订阅、YouTube 贴纸**（未开始，第二档，规模 大）
  - 阶段：连击键：虎牙 lComboSeqId、猫耳 combo、克拉克拉 no → AcFun 礼物表 gift/list、礼物和香蕉 → 17LIVE 礼物 13、BIGO 760969 → Twitch Bits 和送订阅合并、CHZZK 订阅、YouTube 贴纸
  - 说明：依赖 E05.5；连击键要在 D07.1 之前或同时合并，合并才有平台的连击号可用；每个阶段一个平台组、一次合并
  - 来源：V03.5 第 2、3 节、第 7 节；用户 2026-10-09（D-040）
- **D07.7 要先录样本的平台补礼物：SOOP、SHOWROOM、TwitCasting、PandaTV、FC2、酷狗、六间房、LOOK、Kick**（未开始，第三档，规模 大）
  - 阶段：国内：酷狗 601、六间房 201、LOOK 102 → 韩国：SOOP 星气球和订阅、PandaTV 후원 → 日本：SHOWROOM 礼物、TwitCasting gift=1 → 其他：FC2 打赏和礼物、Kick Kicks
  - 说明：依赖 E05.5；每个平台先录真实样本（海外开代理，按 fixtures/README.md 脱敏），字段确认了再写解析；可以按阶段拆成单独的任务
  - 来源：V03.5 第 2、3 节、第 7 节；用户 2026-10-09（D-040）

<!-- docs:生成结束 -->
