# D07.1 礼物过滤、连击合并、限速和行数上限（含基准）：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 0 节第 3、4 条，第 4 节 F-4、F-5，第 6.4、6.8 节，第 7 节 D07.1；用户 2026-10-09，D-040 同意方案 A。
- 现象：屏蔽了的用户送礼照样出现在礼物行；重连补发的礼物重复；斗鱼热门直播间每秒几条“粉丝荧光棒 ×1”，聊天被挤出 500 行。
- 为什么现在做：第二档；礼物一多就影响看聊天，是礼物行（A08.11）能用的前提。
- 已经做过的：E05.5 给了 `LiveGift`（`comboKey`、`comboTotal`、`free`、`count`）——**开工前确认 E05.5 已合并**。

## 目标和验收

1. 屏蔽用户、屏蔽词、去重闸门对礼物生效（单元测试：屏蔽的用户送礼不进列表；同一条礼物重放两次只进一次）。
2. 同一连击 5 秒内、还在最后 20 行里时只改那一行的数量，不加新行；跟随时这一行移到最下面，定住时不移动。
3. 每秒最多 10 条新礼物行；免费礼物超出时丢掉；礼物行在 500 行里最多 150 行，超出先丢最老的礼物行，聊天一条不丢。
4. `ChatFeed` 仍然每帧最多通知一次（D04.1 的测试照过）。
5. 基准加“每秒 50 条礼物”，前后对比写进 record.md。
6. “在聊天列表显示礼物”关着时行为和现在一样。

## 现状（读代码得出）

- `packages/live_danmaku/lib/src/filters/message_filter.dart:104-110`：`accepts` 第一行 `if (message.type != LiveMessageType.chat) return true;`，后面是 `gate.accepts`、`_blockList.blocks`、`repeated`、`similarity`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：聊天分支 `:1129-1131`（`_filter.accepts` → `chat.add` → `_flying.add`）；礼物分支 `:1148-1151`（只看 `showGifts` 和空文字）；`showGifts` `:268`；开关改了时去掉礼物行 `:807-817`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart:107`：`ChatFeed(capacity: 500)`，每帧最多通知一次（`scheduleChatFlushForNextFrame`）。
- 屏蔽表 `packages/live_danmaku/lib/src/filters/block_list.dart:35`（`blocks`：整名相同或包含屏蔽词）；打码昵称 `apps/pure_live/lib/shared/danmaku/masked_blocks.dart`。

## 3.x 基线

- 3.x 不显示平台礼物，没有要保留的行为；过滤链对聊天的行为一点不变（D02）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 9.2（列表局部刷新）、9.4 节。
3. 本文件夹 `README.md`；`docs/D-弹幕/D04-数据流和性能/README.md`（`ChatFeed` 的规则）、`docs/D-弹幕/D02-过滤和屏蔽/README.md`。

## 范围

- 可以改：`message_filter.dart`；`room_controller.dart` 的礼物分支（新的合并和限速放进一个单独的类，例如 `features/live_play/logic/gift_combiner.dart`）；`chat_feed.dart`（只加替换一行和礼物计数，不改原有行为）；`chat_benchmark_test.dart` 和对应测试。
- 不能改：聊天的过滤规则；礼物行的样子（A08.11）；设置（本任务不加设置）；平台解析器；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 礼物过屏蔽用户、屏蔽词、去重闸门；控制器的礼物分支调过滤 | `message_filter.dart`、`room_controller.dart` | 过滤测试和控制器测试通过 |
| 2 | c2 合并、c3 限速和 150 行、c4 基准、c5 开关关着不运行 | 新的合并类、`chat_feed.dart`、`room_controller.dart`、基准 | 测试和基准通过，record.md 有前后数字 |

## 测试

- `packages/live_danmaku/test/message_filter_test.dart`：屏蔽用户的礼物被拦；礼物名含屏蔽词被拦；同一 `id` 的礼物第二次被闸门拦；醒目留言不受影响。
- 合并类的单元测试（新文件，假时钟，间隔用秒级，D-017）：5 秒内同键合并、第 6 秒新开一行；不在最后 20 行时新开一行；`comboTotal` 优先于累加；没有 `comboKey` 时按送礼人 + 编号。
- 限速：同一秒 15 条不同礼物只加 10 行；免费礼物超出被丢；礼物到 151 行时最老的礼物行被丢，聊天行数不变。
- `apps/pure_live/test/features/live_play/` 控制器或列表测试：定住时合并不移动行、跟随时移到最下面；每帧仍只通知一次。
- `chat_benchmark_test.dart`：加礼物的场景。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 斗鱼热门直播间，打开礼物 | “粉丝荧光棒”连击只有一行、数字往上涨；聊天照常滚 |
| 2. 往上翻定住，等连击 | 那一行的数字变，位置不动 |
| 3. 屏蔽一个正在送礼的用户 | 他之后的礼物不出现 |
| 4. profile 构建，开着性能叠加层看 30 秒 | 界面线程没有明显变红（数字记进 verify.md） |

## 风险和注意

- 合并改的是已经在列表里的行：`ChatFeed` 的反转列表（D04.1）和“N 条新弹幕”的计数不能因为替换而乱；合并不算“新弹幕”。
- 哔哩哔哩：D07.4 第 1 阶段把“只报第一条”改成每条都报，要在本任务第 2 阶段合并之后（否则会出现一下一行）。D07.6 阶段 1 的连击键可以先合并（没有合并时只是多填一个字段）。
- 定时器至少 1 秒；测试用假时钟，不等真时间。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`packages/live_danmaku` 跑 `dart test`，`apps/pure_live` 跑全部 `flutter test`；`python3 tools/docs/docs.py --check`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D07.1`；提交信息以 `[D07.1]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；合并和限速的常量；测试数量；基准前后数字；改了哪些文件；要在真机上看的；和 D07.4、A08.11 可能冲突的地方。
