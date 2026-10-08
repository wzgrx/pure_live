# D02.2 记录：正则屏蔽、屏蔽纯表情和超长弹幕、本场屏蔽计数

- 任务书和设计：同一文件夹的 `brief.md`、`README.md`（登记提交 `68ceeeb44`，和这次的分支同时合并；这个分支里还没有这两个文件，所以这里只有记录）。来源 V03.6 第 3.3 节、第 4 节 E11、第 5.6 节做法 A；用户 2026-10-09（D-040）。
- 本机工作区任务：提交在当前分支，不推送、不合并。设计里要选的按 D-003 由维护者定（见“做法和理由”）。
- 状态：阶段 1、2 都做完，自动测试和门禁通过，**待真机**。登记表（`docs/tasks.toml`）里 D02.2 的条目在登记分支上，这个分支没有它，所以没有改状态；合并后把 D02.2 改成“待真机”、阶段 1、2 记为完成。

## 根因（现在为什么做不到）

| 要做的 | 现在的代码（改动前，master `595a2385e`） | 为什么做不到 |
|---|---|---|
| 正则屏蔽 | `packages/live_danmaku/lib/src/filters/block_list.dart:35-40`（`DanmakuBlockList.blocks`：整名相同或 `text.toLowerCase().contains(word)`）；屏蔽词在构造时全部小写（`:23-26`） | 只有“包含”；就算按正则读，小写以后 `\D`、`\S`、`\W` 也会变成意思相反的 `\d`、`\s`、`\w` |
| 添加时提示写法不对 | `apps/pure_live/lib/shared/danmaku/block_manager.dart:14`（`blockKeywordMaxLength = 40`）、`:243`（输入框 `maxLength`）、`_add` `:166-182`；长按面板第二页 `features/live_play/danmaku/message_panel.dart:74`、`:265`（`keywordMaxLength = 40`）、`_submit` `:250` | 两处都只判断空和重复，不知道正则；40 字放不下稍长的正则 |
| 屏蔽纯表情、超长 | `message_filter.dart:104-110`（`accepts`：闸门 → 屏蔽表 → 重复 → 相似度）；`DanmakuFilterSettings`（`:11-50`）只有 3.x 的 8 项；`noEmojiMode` 只在画面上去掉表情图（`shared/danmaku/danmaku_overlay.dart:422-429`），整条照样显示 | 过滤链里没有这一步，也没有设置 |
| 本场屏蔽计数 | `features/live_play/logic/room_controller.dart:1129`（`if (!_filter.accepts(message)) return;`） | `accepts` 只回答真假，分不出“被屏蔽”和“重复包、合并重复、相似”；控制器也没有地方记 |
| 从直播间屏蔽正则后去掉已有的行 | `room_controller.dart:1249-1257`（`blockKeyword`：`line.text.toLowerCase().contains(lower)`） | 正则会被当成普通词去找，已有的匹配行留在列表里 |

## 做法和理由（D-003，维护者定）

1. **正则就是以 `/` 开头、以 `/` 结尾的屏蔽词**（README 做法 A，不做单独的“正则”表）：屏蔽表格式、备份（`shieldList`）、3.x 导入都不变，覆盖回 3.x 时它只是一个普通词。`/` 和 `//` 仍是普通词（要有东西夹在中间）。不分大小写（`caseSensitive: false`），正则的原文**不小写**（理由见根因）。
2. **防止慢正则拖住界面**：Dart 的 `RegExp` 不能中途停下，过滤又在界面线程上逐条跑，所以按代价从低到高四层（`packages/live_danmaku/lib/src/filters/block_pattern.dart` 的 `DanmakuBlockPattern`，说明写在类注释里）：
   - 正则连斜杠最多 **200 字**（普通词仍 40），每条弹幕只拿**前 200 个字**去匹配（普通词照旧看整条，3.x 的行为）。
   - **括号整体重复时，括号里不能再有重复或 `|`**（`(a+)+`、`(a|aa)*`、`(.*x){5}` 这类“嵌套重复”，时间随长度指数增长；实测 `(a+)+b` 在 20 个字上 140 ms、24 个字 2.3 s）。这是静态检查，便宜，所以**添加时和建表时都做**：备份、3.x 导入、别的设备同步来的这种正则也不会跑。会误拒的写法（如 `(哈|呵)+`）提示改成 `[哈呵]+`；屏蔽词里很少需要“整组重复里再分支”，安全优先。
   - **只编译一次**：`DanmakuBlockList` 构造时编译（设置或屏蔽表变化时重建），不在每条弹幕上编译；编译不过的跳过、不抛异常、也不当普通词。
   - **添加时试跑**：用正则自己的字（和 `a`、`1`、`哈`、空格）拼出 8、12、18……200 字的文本，末尾放一个几乎不会匹配的字，逐级加长去跑；一次超过 **2 ms** 就拒绝（刚过线的再跑一次，排除回收停顿）。逐级加长保证拒绝之前最多慢一级（实测 `.*.*.*.*.*.*x` 不到 0.1 s 就被拒）。试跑只在人添加的地方做（屏蔽管理、长按面板第二页），20 条常见正则一起检查共 4～6 ms。
   - 不选“把匹配放到别的 isolate”：每条弹幕都要跨 isolate 往返，直播间的过滤链要变成异步，改动大、延迟高；有了前三层，界面线程上每条弹幕的正则代价很小（见基准）。
3. **两个新开关只看平台弹幕**（本地弹幕不拦，和相似度一样），放在屏蔽表之后、合并重复之前，被它们拦下的也算“屏蔽”。
   - “只有表情”：表情图（平台自带列表的 `[笑哭]` 等、消息自己带的表情代码）和 Unicode emoji（含肤色、国旗、键帽、零宽连接）以外只有空白，至少有一个表情。数字、`#`、`*` 不算 emoji（它们在 Unicode 里是键帽的组成部分）。
   - 应用里用聊天列表和飞行弹幕**同一次解析**（`chatSegments`，按消息缓存）来判断，画成图的才算表情，各处一致；平台列表还没读到时只认消息自带的代码和 emoji（`shared/danmaku/emotes.dart` 的 `chatTextShaper`）。
   - “超过 N 字”：按字（码点）数，一个表情图算一个字；N 默认 30、10～100。
4. **计数**：过滤链新增 `judge`，回答“显示 / 重复包 / 屏蔽 / 合并重复 / 相似”（`DanmakuVerdict`），`accepts` 不变。只有“屏蔽”计数（屏蔽表、两个新开关），重复包和合并、相似不算——它们不是用户的屏蔽规则。计数在直播间控制器（`BlockedCount`，`features/live_play/logic/blocked_count.dart`），不存；换直播间是新控制器，从 0 开始。数字马上变，界面每帧最多听一次（和聊天列表 B08 同一个调度），热门直播间每秒 200 条也不会每条重建。
5. **计数显示在“屏蔽管理”标签的第一行**“本场已屏蔽 N 条”，不做标签角标：角标在“弹幕列表”上表示“没看的新消息”，同一排再放一个会被当成未读；设置页的“弹幕屏蔽”没有这一行（不在直播间）。
6. **开关放在屏蔽管理组件里**（照 A08.3：关键词 → 用户 → **按内容屏蔽** → 平台过滤 → 相似过滤），不放弹幕设置的“重复弹幕”组：它们是“屏蔽”，和屏蔽词一起管；设置页“弹幕屏蔽”和直播间标签是同一个组件，两处都有。设置搜索“正则”“只有表情”“纯表情”“超长”“字数”能找到“弹幕屏蔽”。
7. **多画面同样生效**（各处一致）：屏蔽表本来就共用，两个开关和平台表情也接进多画面的过滤（`multiview_controller.dart`）。录制弹幕照旧只用闸门和屏蔽表（正则也生效），两个开关不用——录制文件要记下说过的话，和合并重复、相似一样。

### 已知限制

- 屏蔽表按“小写后相同”去重（`block_lists.dart` 的 `folded` 列，格式不能改）：`/\d/` 和 `/\D/` 会被当成同一条，后加的那条提示“已经在屏蔽列表里”。很少见，写进这里。
- 本来就以 `/` 开头和结尾的普通词（极少）现在按正则读；3.x 里存的这种词如果编译不过，就不再屏蔽任何东西（以前是“包含”）。
- 从备份、导入、同步来的正则不做“试跑”（只做长度、嵌套重复和编译）；多项式慢的正则（例如很多个 `.*` 连在一起）理论上还能进来，有前 200 字的限制兜底。
- 长按面板第二页照旧可以提交超过 40 字的普通词（框里预填的是整条弹幕，3.x 一样），这次没改。

## 改了哪些文件

- `packages/live_danmaku/lib/src/filters/block_pattern.dart`（新）：`DanmakuBlockPattern`（`isPattern`、`compile`、`check`、`matchedPart`）、`DanmakuBlockPatternProblem`。
- `packages/live_danmaku/lib/src/filters/text_shape.dart`（新）：`DanmakuTextShape`、`danmakuTextShape`、`danmakuMessageShape`。
- `packages/live_danmaku/lib/src/filters/block_list.dart`：正则另存一张表，`matchesText`。
- `packages/live_danmaku/lib/src/filters/message_filter.dart`：三个新字段、`DanmakuVerdict`、`judge`、`shapeOf`。
- `packages/live_danmaku/lib/live_danmaku.dart`：导出两个新文件。
- `packages/live_store/lib/src/settings/settings.dart`：三个新设置，登记进 `Settings.all`（相似度设置后面）。
- `apps/pure_live/lib/shared/danmaku/block_manager.dart`：`blockKeywordMaxLengthOf`、`blockKeywordProblem`（两处添加共用）、正则说明、写错提示、“按内容屏蔽”一组、`blockedCount` 第一行。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：只改 `_KeywordPage`（长度跟着 `/`、提交前检查、错误显示在框下）和一个 import。
- `apps/pure_live/lib/features/live_play/danmaku/chat_panel.dart`：把计数交给屏蔽管理标签。
- `apps/pure_live/lib/features/live_play/logic/blocked_count.dart`（新）、`room_controller.dart`：`emotes`、`blocked`、`judge`、三个设置、`blockKeyword` 用同一个匹配。
- `apps/pure_live/lib/shared/danmaku/emotes.dart`：`chatTextShaper`。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`、`tv/room/tv_live_play_page.dart`、`features/multiview/multiview_page.dart`：各加一行把表情库交给控制器。
- `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：三个设置、表情判断。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：“弹幕屏蔽”一行带上三个设置和搜索词。
- 翻译 `zh.json`、`en.json`；`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`（三个键归 D02）；`docs/A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/README.md` 补一条；重新生成的 `J01.2/settings.md` 等。

## 新设置和翻译

| 键 | 默认 | 范围 | 说明 |
|---|---|---|---|
| `blockEmoteOnlyDanmaku` | 关 | — | 屏蔽只有表情的弹幕 |
| `blockLongDanmaku` | 关 | — | 屏蔽超长弹幕 |
| `blockLongDanmakuLength` | 30 | 10～100（超出夹到两端） | 最多字数，一个表情算一个字 |

都在 `danmaku` 一节、`synced`，进备份和设备同步；3.x 的备份没有它们，恢复后是默认值（关），老用户感觉不到变化（D-040）。

新翻译键 13 个（没有删键，D-024）：`block_pattern_hint`、`block_pattern_invalid`、`block_pattern_too_long`、`block_pattern_nested_repeat`、`block_pattern_too_slow`、`danmaku_content_block`、`danmaku_block_emote_only`、`danmaku_block_emote_only_desc`、`danmaku_block_long`、`danmaku_block_long_desc`、`danmaku_block_long_length`、`danmaku_block_long_length_value`、`danmaku_blocked_this_room`。

## 测试

新增 34 个：

- `packages/live_danmaku/test/block_pattern_test.dart`（17）：`/^\d+$/` 只拦纯数字；不分大小写、`\D` 不被小写；普通词照旧包含、`/` 和 `//` 是普通词；坏正则 `/[/` 跳过不抛、也不当普通词；只匹配前 200 字（普通词仍看整条）；超过 200 字和嵌套重复的不进表；`matchesText`；`check` 放过常见写法、分清四种问题、转义和方括号里的量词不算、多项式慢的被拒且很快；表情判断（emoji、肤色、国旗、数字不算、只有空白不算、消息自带代码）；两个开关默认关、开了拦、本地弹幕不拦、长度夹在 10～100；应用的判断函数生效；`judge` 分清五种结果。
- `packages/live_danmaku/test/block_benchmark_test.dart`（2）：基准（见下）和“20 条正则一起检查很快”。
- `packages/live_store/test/block_more_settings_test.dart`（3）：默认关、30、范围；备份往返、3.x 备份恢复后是默认值；正则屏蔽词存、备份、恢复、3.x 的 `shieldList` 导入都原样。
- `apps/pure_live/test/features/live_play/room_block_count_test.dart`（5）：直播间里正则拦、只数屏蔽（重复包和合并不算）；两个开关默认关、开了拦并计数、长度改了下一条生效、下一个直播间从 0 开始；平台自带表情算表情；从直播间屏蔽正则后去掉已有的匹配行（不分大小写）；`BlockedCount` 每帧最多通知一次、释放后不通知。
- `apps/pure_live/test/features/shield/block_patterns_test.dart`（4）：好正则加进去，坏的、嵌套重复的、太慢的在框下提示、不加进去、字留着，打字后提示消失；以 `/` 开头时上限 200、计数“4/200”，加完回到 40；“按内容屏蔽”的位置、默认关、滑块关着变灰、开关和滑块写进设置；直播间第一行“本场已屏蔽 N 条”跟着变，设置页没有。
- `apps/pure_live/test/features/live_play/keyword_page_pattern_test.dart`（1）：长按面板第二页：以 `/` 开头的上限 200；坏正则提示、面板不关、没加；改对了屏蔽并关闭。
- `apps/pure_live/test/features/multiview/multiview_blocks_test.dart`（1）：多画面里正则和两个开关同样生效。
- `apps/pure_live/test/features/settings/settings_block_search_test.dart`（1）：设置搜索“正则”“只有表情”“超长”“屏蔽 字数”找到“弹幕屏蔽”。
- 原有的 `settings_defaults_test.dart` 补了三个键（`newInV4`、`ranges`）。屏蔽管理原有的 7 个、直播间标签 13 个、长按面板的用例照旧通过。

## 基准

`BLOCK_BENCH_SECONDS=60 dart test test/block_benchmark_test.dart`（`packages/live_danmaku`，WSL 测试机，不是手机；每种跑三次取最快）。每秒 200 条、共 12000 条，相似度过滤开（3.x 默认 85、3 秒、100 条）：

| 配置 | 每秒耗时 | 每条 | 被屏蔽 |
|---|---|---|---|
| 只有相似度（改动前的基线） | 11.55 ms | 57.8 µs | 0 |
| + 20 个普通词 | 11.56 ms | 57.8 µs | 0 |
| + 20 条正则 | 5.65 ms | 28.3 µs | 4001 |
| + 20 条正则 + 只有表情 + 超过 30 字 | 6.20 ms | 31.0 µs | 4001 |
| 只算屏蔽表：20 个普通词 | — | 0.6 µs | — |
| 只算屏蔽表：20 条正则 | — | 3.2 µs | — |

- 读法：20 条正则本身每条弹幕多 2.6 µs（每秒 200 条约 0.5 ms，界面一帧 8.3 ms 的 6%）；两个开关每条约 0.5 µs。整条链反而更快，是因为被正则拦下的弹幕不再做相似度比较（相似度才是大头）。
- 20 条常见正则一起做添加时的检查（含试跑）：4～6 ms。

## 门禁和生成

- `python3 tools/docs/settings_audit.py`、`docs.py`、`owners.py` 重新生成；`docs.py --check`、`owners.py --check` 通过。
- `bash tools/gate/gate.sh --all` 通过（日志 `gate: passed`，见提交说明里的日志位置）。

## 真机上要看的（K90）

1. 进一个热门直播间（斗鱼或虎牙），打开下面“屏蔽管理”标签：第一行是“本场已屏蔽 0 条”；关键词输入框下面有“以 / 开头和结尾的按正则匹配……”。
2. 输入 `/^[0-9]+$/` 点“添加”：加进去；纯数字的弹幕（“666”“111”）不再出现，“本场已屏蔽 N 条”在涨（停在这个标签上看，数字跟着变，不卡）。“主播666”照样显示。
3. 输入 `/[/` 点“添加”：框下面红字“正则写法不对，没有加进去”，框里的字还在，列表里没有它。再试 `/(a+)+/`：提示“这样写可能很慢……”。
4. 打开“屏蔽只有表情的弹幕”：只有表情（`[笑哭][笑哭]`、😂😂）的弹幕不见了，带字的表情弹幕照常；计数在涨。关掉恢复。
5. 打开“屏蔽超长弹幕”，把“最多字数”拖到 10：长弹幕不见了；关着时滑块是灰的。
6. 长按一条弹幕 → “屏蔽关键词…” → 把框里的字改成 `/[0-9/` 点“屏蔽”：框下提示写法不对，面板不关；改成 `/[0-9]+/` 再点：面板关闭，含数字的行从列表里去掉。
7. 换到另一个直播间（上下滑或从关注进）：“本场已屏蔽”从 0 开始。
8. 设置 → 视频 → 弹幕屏蔽：同样有“按内容屏蔽”一组，没有“本场已屏蔽”；设置搜索“正则”能找到“弹幕屏蔽”。
9. 回归：普通词屏蔽、屏蔽用户、相似过滤和以前一样；多画面里正则和两个开关也生效。

## 可能和别的任务冲突的文件

- `packages/live_store/lib/src/settings/settings.dart`、`packages/live_store/test/settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`、`docs/J-设置和数据/J01-设置/J01.2-设置项逐条核对/settings.md`（A08.10 加 `showChatNames`；这里的三个键放在相似度设置后面，离 `showChatGifts` 远，冲突应只在生成文件里，合并时重新生成）。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`（A08.13 改“屏蔽关键词”对本地弹幕的显示；这里只动 `_KeywordPage` 和 import）。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（E05.5 `LiveGift` 可能改 `_onMessage` 的礼物分支；这里只动聊天分支、构造函数和屏蔽部分）。
- 翻译文件 `zh.json`、`en.json`（各任务都加键，按键排序，冲突时合并两边的键）。
- `apps/pure_live/lib/shared/danmaku/block_manager.dart`、`chat_panel.dart`（屏蔽管理组件）。
