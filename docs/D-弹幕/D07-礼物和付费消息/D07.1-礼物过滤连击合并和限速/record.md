# D07.1 礼物过滤、连击合并、限速和行数上限：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-ac26846778bde57ce`）
- 分支和提交：`worktree-agent-ac26846778bde57ce`，基于 master `f28cee592`（含 E05.5、A08.10、A08.13）；阶段 1、阶段 2 各一次提交，再一次提交文档（见文末）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（设计选择写在“定稿”一节）；真机：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 过滤 | 做了：平台礼物过去重闸门和屏蔽表（屏蔽用户看名字，屏蔽词看“名称 ×数量”）；控制器的礼物分支调 `_filter.accepts`；醒目留言、本地礼物不过滤 | 闸门的键多加礼物的平台累计数（README 定稿第 2 条），不然斗鱼连击被当成重复；点“屏蔽关键词”时列表里的平台礼物行也去掉（任务书没写，和屏蔽用户一致） |
| c2 合并 | 做了：`GiftCombiner`（`features/live_play/logic/gift_combiner.dart`），5 秒、最后 20 行；`ChatFeed.replace` 换行，跟随时到最下面，定住时原地改数字 | 平台累计数和逐条相加取大的（定稿第 5 条）；中途进房显示平台累计数 |
| c3 限速 | 做了：每秒 10 条新礼物行、500 行里最多 150 行礼物 | 超出时付费礼物累计到同一连击的行（不管多远），值钱以上的礼物照样加行（定稿第 7 条，任务书没写） |
| c4 基准 | 做了：房间页基准加“每秒 200 条聊天 + 50 条礼物”；另加只跑 `ChatFeed` 和合并的“每秒 200 条礼物、20 个连击”（有、没有聊天两种），和“一条礼物一行”对比 | 帧时间是 WSL 调试模式、机器上同时有别的构建，只能看大概（见“基准”） |
| c5 开关关着 | 做了：关着时不过滤、不合并；关掉时合并的记忆一起清掉 | |
| 哔哩哔哩每条都报 | 做了：去掉 `_isRepeatedCombo`，`COMBO_SEND` 的 `total_num` 同时是 `comboTotal` | 任务书把它放在 D07.4，V03.5 第 7 节和这次的分工放在 D07.1；D07.4 第 1 阶段的这一项因此做完了（登记表 D07.4 的说明写了） |

## 根因

- 礼物不过屏蔽、不去重：`DanmakuMessageFilter.accepts` 第一行 `if (message.type != LiveMessageType.chat) return true;`（`packages/live_danmaku/lib/src/filters/message_filter.dart:105`），控制器的礼物分支也不调过滤（`apps/pure_live/lib/features/live_play/logic/room_controller.dart:1148-1151`）。
- 一条礼物一行、和聊天共用 500 行：控制器直接 `chat.add(ChatLine.gift(message))`（同上 `:1151`），`ChatFeed` 只有 500 行的总上限（`apps/pure_live/lib/features/live_play/danmaku/chat_feed.dart:107`），没有改一行的办法。
- 哔哩哔哩连击的数字停在第一下：连接只报一个 `batch_combo_id` 的第一条（`packages/live_danmaku/lib/src/sites/bilibili.dart:170`、`:182-188` 的 `_isRepeatedCombo`），后面的 `SEND_GIFT`、`COMBO_SEND` 都丢了。
- （行号是 master `f28cee592` 的。）

## 合并规则（各平台）

| 平台 | 合并的键 | 数字 | 样本 |
|---|---|---|---|
| 斗鱼 | `comboKey` = 送礼人 uid:礼物（E05.5 在 `hits` 有值时填） | `hits` 是礼物个数的累计（`gfcnt` × 第几下），直接用；漏了一下（120 → 140）也对；同一个人新开一次连击（`hits` 变小）开新行 | `S13-live` 按录制时间回放：125 条 `dgb` → 26 行，0 条丢掉；61721176 的连击停在最后的 `hits` |
| 虎牙 | 还没有连击号（D07.6），按送礼人 + 礼物编号 | `iItemGroup` 数的是送了几下，和逐条相加取大的；漏了一下（17 → 19）显示 19；`iItemGroup` 回到 1 是新的一次，开新行 | `S18-gift`：27 条 → 10 行，“虎粮 ×19”一行；同一个人分开送的“×10”“×5”两行 |
| 哔哩哔哩 | `comboKey` = `batch_combo_id`；没有时按送礼人 + 礼物 | `SEND_GIFT` 逐条相加；`COMBO_SEND` 的 `total_num` 是整个连击，取较大的 | 没有录到连击，按协议写的帧过解析器：4 条 `SEND_GIFT` → “×4”，`COMBO_SEND` `total_num` 5 → “×5”，再一条 → “×6”；价值 5000 金瓜子 |
| 其他（猫耳、克拉克拉、百度、niconico、YouTube、Kick） | 送礼人 + 礼物编号（没有编号用名字） | 逐条相加 | 只有单元测试（D07.6 补连击号） |

## 改了哪些文件

- 阶段 1：`packages/live_danmaku/lib/src/filters/message_filter.dart`、`message_gate.dart`；`apps/pure_live/lib/features/live_play/logic/room_controller.dart`（礼物分支调过滤、`blockKeyword`）；测试 `packages/live_danmaku/test/message_filter_test.dart`、`apps/pure_live/test/features/live_play/live_play_more_test.dart`。
- 阶段 2：`apps/pure_live/lib/features/live_play/logic/gift_combiner.dart`（新）；`danmaku/chat_feed.dart`（`ChatLine.revision`、`replacement`、`latest`；`ChatFeed.giftCapacity`、`replace`、`linesAfter`、`giftLines`、`replacements`；`added` 不再等于编号计数）；`danmaku/chat_list.dart`（只加 3 行：定住时把旧行换成 `latest`）；`room_controller.dart`（`ChatFeed(giftCapacity: 150)`、礼物交给 `GiftCombiner`、关掉开关时清掉）；`packages/live_danmaku/lib/src/sites/bilibili.dart`；测试 `gift_combiner_test.dart`（新）、`chat_list_follow_test.dart`、`live_play_more_test.dart`、`chat_benchmark_test.dart`、`packages/live_danmaku/test/sites/bilibili_test.dart`。
- 文档：本任务的 README（定稿）、本记录、verify.md；`docs/tasks.toml`（D07.1、D07.4 的说明）；`docs/inventory/OWNERS.toml`（`gift_combiner.dart` 归 D07）；重新生成的 OWNERS.md、TASKS 和 J01.2 设置表（只是行号）。

## 给 A08.11 的接口（礼物行的样子）

- 合并时列表里是一个**新的** `ChatLine`（新对象、新编号），旧行的 `replacement` 指向它；`line.revision > 0` 表示“这一行的数字刚变了”，“×N 跳一下”看它就行（新行的部件是新建的）。
- 数字从 `line.message!.gift!.count` 取（合并后是 `CombinedGift`，`count` 是总数、`last` 是最新一条的平台礼物、`sends` 是合并了几条）；`line.text` 也是“名称 ×总数”。价值 `totalValue` 和档位 `tier` 已经按总数算。
- `chat_list.dart` 里礼物行的代码一行没改；本任务在 `_onLines` 里加了 3 行（定住时换成 `latest`）。

## 新设置、翻译键、门禁基线

- 都没有（任务书：本任务不加设置）。常量在 `GiftCombiner`：`comboWindow` 5 秒、`comboLines` 20、`linesPerSecond` 10、`maxGiftLines` 150。

## 测试

- 新增：`gift_combiner_test.dart` 17 个（5 秒窗口、送礼人 + 礼物、连击键、最后 20 行、平台累计数和新连击、`totalOf`、换行的编号和通知、价值和档位、没有 `LiveGift` 的礼物、每秒 10 行、超出时付费累计免费丢、值钱的照加、150 行、去掉以后不再合并；斗鱼 `S13-live`、虎牙 `S18-gift` 按录制时间回放，哔哩哔哩过解析器）；`message_filter_test.dart` 6 个（屏蔽用户和屏蔽词、编号闸门和年龄、累计数不算重复、重复折叠和相似度不管礼物、醒目留言不过滤、斗鱼 125 条录制的 `dgb` 全部通过）；`live_play_more_test.dart` 2 个（控制器过滤和屏蔽词去行；合并、开关关着不过滤不合并）；`chat_list_follow_test.dart` 1 个（跟随时到最下面、定住时原地改数字、不算新弹幕）；基准 3 个。
- 改了：`bilibili_test.dart` 的“一个连击只报一次”改成“每条都报、`COMBO_SEND` 带累计数”；“其他类型不过滤”的用例去掉礼物。
- `packages/live_danmaku` 和 `apps/pure_live` 的全部测试在门禁里跑过（见文末）。

## 基准

WSL、调试模式（D04 的规则：只能前后比，不能和手机的 profile 比）；机器上同时有别的 AI 在构建（负载 5～17），帧时间抖得厉害，所以前后交替跑了 5 轮。“前”是 master `f28cee592` 的代码加同一个基准文件。

**1. 房间页：每秒 200 条聊天 + 50 条礼物，10 秒，120 Hz**（`chat_benchmark_test.dart`，`--dart-define=CHAT_BENCH_SECONDS=10`；礼物一半是 5 个人连击“粉丝荧光棒”，一半是各不相同的礼物）

| | 加进列表的行 | 合并（换行） | 最后 500 行里礼物 / 聊天 | 行部件构建 | 帧时间平均 / P90（毫秒，5 轮） |
|---|---|---|---|---|---|
| 前（一条礼物一行） | 2502 | 0 | 100 / 400 | 2502 | 9.7 / 13.6、11.2 / 15.2、32.6 / 53.0、18.2 / 27.7、14.9 / 20.2 |
| 后 | 2173～2311 | 94～165 | 35～49 / 451～465 | 2338～2405 | 17.7 / 28.4、16.0 / 20.6、26.4 / 38.7、13.8 / 19.6、15.2 / 20.7 |

- 每帧最多通知一次、列表每帧最多建一次（1200 帧 1200 次）、整页每帧约 45 个部件，前后一样；行部件少建约 5%。帧时间同一轮里前后差不出规律（第 3～5 轮只跑礼物这一项：前 32.6 / 18.2 / 14.9，后 26.4 / 13.8 / 15.2），在噪声里；真机 profile 的数字在 verify.md 第 6 步记。
- “后”的行数每次不同，因为房间页的控制器用真时钟（每秒 10 行的额度按墙上时间算），下面第 2 项用假时钟。

**2. 只跑 `ChatFeed` 和合并：每秒 200 条礼物、20 个连击，10 秒，假时钟**（每个连击每 0.1 秒一下，每下 10 个，平台累计数往上加）

| | 新礼物行 | 合并 | 丢掉 | 最后礼物行 / 聊天行 | 每帧通知最多 | 每条礼物的耗时 |
|---|---|---|---|---|---|---|
| 只有礼物，前 | 2000 | 0 | 0 | 500 / 0 | 1 | 2.0～2.5 微秒 |
| 只有礼物，后 | 20 | 1880 | 100 | 20 / 0 | 1 | 3.4～6.2 微秒 |
| 再加每秒 200 条聊天，前 | 2000 | 0 | 0 | 250 / 250 | 1 | 0.6～0.8 微秒 |
| 再加每秒 200 条聊天，后 | 100 | 900 | 1000 | 30 / 470 | 1 | 3.7～10 微秒 |

- 只有礼物时：20 个连击各一行，第 1 秒只能开 10 行，另外 10 个连击的头 1 秒（100 条）被丢掉，之后都合并。
- 加上聊天时：每个连击两下之间过去约 40 行，超出“最后 20 行”，只能开新行；每秒 10 行的额度被已经有行的连击用掉，另一半连击一直拿不到行（1000 条只计数）。这是规则（20 行、10 行/秒）本身的结果，README“留下的问题”记了；聊天一条没被礼物挤掉（470 + 30 = 500）。
- 合并每条礼物多花几微秒，每秒 200 条也不到 2 毫秒（分散在 120 帧里），对界面线程可以忽略。

## 真机上要看的

- 见 [verify.md](verify.md)：
  1. 斗鱼热门直播间：“粉丝荧光棒”连击只有一行、数字往上涨，聊天照常滚。
  2. 往上翻定住，等连击：那一行原地改数字，“N 条新弹幕”不因为连击加数。
  3. 点“N 条新弹幕”：连击那一行在最下面。
  4. 哔哩哔哩登录后看连击：数字涨到总数（以前停在“×1”）。
  5. 屏蔽一个正在送礼的人（长按他的弹幕）、屏蔽词加一个礼物名：之后的礼物不出现。
  6. profile 构建开性能叠加层看 30 秒，记界面线程 P90。
  7. 关掉再打开“在聊天列表显示礼物”。

## 提交和门禁

- `6bacb5293` [D07.1] Filter platform gifts: blocked viewers and words, the duplicate gate（阶段 1）
- `a550d861d` [D07.1] Merge gift combos into one line, limit new gift lines, cap gift lines（阶段 2）
- 之后一次提交加本记录、verify.md、README 定稿、登记表和生成的文档。
- `bash tools/gate/gate.sh --all` 在最后一次提交上跑（结果见维护者的合并审查；本分支交出时通过，日志里有 `gate: passed`）。
- 和别的任务可能冲突的文件：`chat_list.dart`（A08.11 改礼物行，本任务只在 `_onLines` 加 3 行）、`room_controller.dart` 的过滤（D02.2；本任务只改礼物分支和 `blockKeyword`）、`message_filter.dart`（D02.2；本任务只加 `_acceptsGift` 一个分支）、`bilibili.dart`（D07.4）、`docs/tasks.toml` 和生成的文档（合并后重新运行 docs.py）。
