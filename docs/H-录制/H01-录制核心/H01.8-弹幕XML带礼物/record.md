# H01.8 录制的弹幕 XML 带礼物：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-a37c3b422c990c6ce`）
- 分支和提交：`worktree-agent-a37c3b422c990c6ce`，基于 master `e562e5233`（D07.6 合并之后，含 E05.5、D07.1～D07.4、D07.6、A08.11、A08.12）；代码一次提交，文档一次提交（见文末）
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)（格式调研和设计选择写在“别的工具认什么”“定稿”两节）；真机：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 新设置，关着时逐字一样 | 做了：`Settings.recordDanmakuGifts`（录制一节，默认关，同步）；关着时连接器不送礼物、写入器走原来的路 | 测试里的期望文本是改之前的写入器（master `e562e5233`）对同一组消息写出来的，逐字比对 |
| 验收 2 `<gift>`，同一个文件按时间排，屏蔽的不写 | 做了 | `price` 改成厘（千分之一元，DanmakuFactory 和 blrec 的单位），平台的数字和单位放 `value`、`unit`（README 定稿第 2 条）；为了按时间排，连击开着时后面的条目在内存里等（定稿第 4 条） |
| 验收 3 设置行、翻译、搜索 | 做了：录制设置“基础配置”组“同时录制弹幕”下面；zh、en 各两个键；设置目录在“录制”一节登记一行给搜索用 | 开关不随“同时录制弹幕”变灰（任务可以单独开录弹幕） |
| c2 连击只写最终一条 | 做了：规则和聊天列表同一份（移到 `live_core`） | 连续超过 30 秒的连击分段写（定稿第 3 条）；`COMBO_SEND` 只补漏掉的 |
| 醒目留言（本次任务说明要求查） | 以前不录；归同一个开关，写 `<sc>` | 定稿第 5 条 |

## 根因（为什么以前没有礼物）

- 连接器只收聊天：`apps/pure_live/lib/app/recording.dart:63`（`DanmakuReceived` 的条件是 `message.type == LiveMessageType.chat && filter.accepts(message)`）。
- 写入器也只认聊天：`packages/live_record/lib/src/chat.dart:321`（`_onMessage` 里 `message.type != LiveMessageType.chat` 直接返回）。醒目留言同样被这两处挡掉。
- （行号是 master `e562e5233` 的。）

## 格式怎么选的

读了三个工具的源码（2026-10-09，表在 README）：录播姬写 `<gift>`、`<sc>`、`<guard>`，礼物默认不录、醒目留言默认录；blrec 写同样的元素，`price` 用厘；DanmakuFactory 读这三种元素，`price` 当厘、按 `--giftminprice` 挡便宜礼物，只合并同一时刻的礼物。PotPlayer 等播放器只认 `<d>`。所以选录播姬的元素名和属性名、blrec 和 DanmakuFactory 的价格单位，再加两个别的工具忽略的属性 `value`、`unit` 留平台自己的数字。DanmakuFactory 读 `giftname` 遇空格就断，所以礼物名里的空白换成不换行空格；元素用 ` />` 结尾。

## 改了哪些文件

- `packages/live_core/lib/src/live_gift_combo.dart`（新）：`giftComboKey`、`giftComboTotal`、`giftComboStart`、`giftComboRestarted`、`giftIsComboSummary` 从应用的 `shared/danmaku/gift_combo.dart` 移过来，加 `giftValueOfCount`（原来是 `CombinedGift._value`）；`live_core.dart` 导出。
- `apps/pure_live/lib/shared/danmaku/gift_combo.dart`：去掉这几个函数，改成从 `live_core` 转出口（聊天列表、飞行礼物的代码不用改）。
- `packages/live_record/lib/src/chat.dart`：`RecordChatWriter` 写 `<gift>`、`<sc>`（连击、等待队列、`recordYuanUnits`、`recordYuanSuperChats`、`recordGiftThousandths`），`open` 多一个 `platform`；`RecordChatRecorder` 收礼物和醒目留言。
- `packages/live_record/lib/src/settings.dart`：`RecordSettings.recordDanmakuGifts`。
- `packages/live_store/lib/src/settings/settings.dart`：`Settings.recordDanmakuGifts`，加进 `Settings.recorder`（录制设置页跟它刷新）。
- `apps/pure_live/lib/app/recording.dart`：连接器在开关开着时送礼物（过礼物过滤）和醒目留言；`RecordSettingsStore` 的 `of`、`fromValues`、`toValues` 带上新键。
- `apps/pure_live/lib/features/record_settings/record_settings_page.dart`：一行开关。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：“录制”一节一行（给搜索用）。
- 翻译：`zh.json`、`en.json` 各加 `record_danmaku_gifts`、`record_danmaku_gifts_desc`。
- 登记：`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`（`live_gift_combo.dart` 归 D07、`recordDanmakuGifts` 归 H01），重新生成 `OWNERS.md` 和 J01.2 的 `settings.md`（238 个设置）。
- 文档：本任务 README（调研、定稿）、本记录、verify.md；H01 README 的代码地图；`docs/tasks.toml`；docs.py 生成的文件。

## 新设置、翻译键、门禁基线

- 设置：`recordDanmakuGifts`（Bool，默认 `false`，section `recorder`，synced）；`settings_defaults_test.dart` 的 `newInV4` 加了一行。
- 翻译键：`record_danmaku_gifts`“录制弹幕时包含礼物”、`record_danmaku_gifts_desc`“弹幕文件里也记下礼物和醒目留言，连击只记一条；有的播放器不认礼物，会忽略它们”（en 同）。没有删键（D-024）。
- 门禁基线没动。

## 测试

- 新增 `packages/live_record/test/chat_gifts_test.dart` 10 个：开关关时逐字一样（钉住改之前的输出，含转义、颜色、时间、空文字）；单条礼物的格式和各种单位（金瓜子、银瓜子免费、分、Bits、未知单位、没有价值）；转义（名字、礼物名、空白换成 U+00A0）；斗鱼 `hits` 连击一条、累计数回落另起一条、不同送礼人分开；哔哩哔哩连击写出后 `COMBO_SEND` 只补漏掉的、总数相同不写、很久以后另起；连击开着时聊天在后面等、每次写完都是完整文件、按时间排；连续 45 秒的连击在 30 秒处分成两条；醒目留言（元写成厘、其他平台写 `value` 和 `pricetext`、`replayed` 不写、同一条只写一次）；`RecordChatRecorder` 只写聊天、礼物、醒目留言；20 分钟忙直播间的性能。
- 新增 `apps/pure_live/test/features/recorder/recording_gifts_test.dart` 5 个：关着只送聊天；开着送礼物（屏蔽用户、屏蔽词、本地礼物、没有 `LiveGift` 的都不送）和醒目留言，中途关掉马上停；设置读写和 pre-M8.1 对象往返、`toValues` 的键和 `Settings.recorder` 一样；`recordYuanUnits` 和 `giftYuanUnits` 一样、连击函数是同一个；设置搜索“礼物 录制”“醒目留言”“xml”找得到。
- `record_settings_page_test.dart` 加 1 个（行的位置、图标、说明、默认关、点一下存上、不变灰）；新增 `packages/live_store/test/record_gifts_setting_test.dart` 2 个（默认关、同步、在 `Settings.recorder` 里；备份往返、3.x 备份不带它）。
- 跑过：`live_record`、`live_store`、`live_core` 全部；应用的 `test/features/recorder`、`test/features/record_settings`、`test/features/settings`、礼物合并和飞行礼物的测试；门禁见文末。

### 性能（20 分钟的忙直播间，WSL、`dart test`）

每秒 100 条聊天 + 20 条礼物（5 个人一直连击、10 个各送一次），每 2 秒写一次，和只有聊天的同样 20 分钟比：

| | 消息 | 用时 | 每条 |
|---|---|---|---|
| 只有聊天（开关关的样子） | 120 000 | 544～1784 毫秒 | 4.5～15 微秒 |
| 聊天 + 礼物 | 144 000 | 1189～2266 毫秒 | 8.3～15.7 微秒 |

- 两次的差别是机器上同时有别的构建。礼物 24 000 条写成 12 190 条 `<gift>`（一次性的 12 000 条，5 个连击每 30 秒一条）；每个礼物都在文件里正好一次（`giftcount` 加起来是 24 000）；文件按时间排；每 5 分钟看一次，写出的最后一条离“现在”不到 36 秒。
- 录弹幕和界面在同一个线程上跑：每秒 120 条、每条十几微秒，一秒不到 2 毫秒，分散在一秒的各帧里，可以忽略；每 2 秒排一次序的只有连击开着时等着的条目（最多 30 秒多一点的量）。

## 真机上要看的

- 见 [verify.md](verify.md)：
  1. 默认设置录 1 分钟：XML 只有 `<d>`。
  2. 设置搜索“礼物 录制”找得到。
  3. 录制设置页的那一行。
  4. 开开关录斗鱼热门：连击一条、总数对、按时间排。
  5. 哔哩哔哩登录后：`price` 金瓜子、`COMBO_SEND` 不重复、醒目留言 `<sc>`、上舰。
  6. 屏蔽送礼的人、屏蔽礼物名：之后不写。
  7. 中途关掉开关：之后不写。
  8. DanmakuFactory 转 ASS：礼物和醒目留言在消息框里，`giftminprice` 挡免费礼物。
  9. PotPlayer 或弹弹play：礼物不当弹幕飞。

## 和别的任务可能冲突的文件

- `apps/pure_live/lib/shared/danmaku/gift_combo.dart`（D07.x、A08.12 改过；本任务只把五个函数换成转出口）。
- `packages/live_core/lib/live_core.dart`（加了一行导出）。
- `packages/live_store/lib/src/settings/settings.dart`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`、翻译文件、`settings_catalog.dart`（别的任务也加设置时，两边的行都保留）。
- `docs/tasks.toml` 和生成的文档（合并后重新运行 docs.py、owners.py、settings_audit.py）。
- 没碰 D07.2（`super_chats.dart`、各平台适配器）和 D08.3 的文件。

## 提交和门禁

- `165d7b607` [H01.8] Recorded chat XML can carry gifts and super chats (new switch, off)
- `6b96914d7` [H01.8] Record the format research, the design choices and the real-device steps; mark it 待真机
- `05aada7a2` [H01.8] No-break spaces in a super chat's price text too (DanmakuFactory ends a value at a blank)
- `618c5ac3a` [H01.8] fail() in the settings search test (analyzer)
- 之后一次提交写门禁结果（本节）。
- `bash tools/gate/gate.sh --all` 在 `618c5ac3a` 上通过：日志最后是 `gate: passed (all, 14 members)`（日志在本机 scratchpad 的 `h018-1791527747/gate.log`）。
