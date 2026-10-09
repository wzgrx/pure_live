# A08.12 礼物开关和飞行弹幕里的礼物：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区 `worktree-agent-af7d6eb6bb59a7449`，从 master `10cdbe49a` 开始，含 A08.10、A08.11、A08.13、E05.5、D02.2、D07.1）
- 分支和提交：`worktree-agent-af7d6eb6bb59a7449`，提交见文末
- 任务书：[brief.md](brief.md)；设计：[README.md](README.md)（第 1 版，H1～H15 按 D-003 由维护者定）；真机步骤：[verify.md](verify.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 三个新设置 | 做了：`chatGiftsAboveTier`、`giftValueInYuan`、`danmakuShowGifts`，`section: 'danmaku'`，默认关，备份和设备同步都带；登记 `Settings.all`、`settings_defaults_test.dart`（`newInV4`）、`settings_audit_notes.py`、`OWNERS.toml`，重新生成了 J01.2 的 `settings.md` | 没有 |
| 2 只显示值钱的礼物 | 做了：合并器按连击总数过滤（H4），打开时去掉已有的普通平台礼物行；“在聊天列表显示礼物”关着时这一行变灰 | “换算成元”也跟着变灰（H1） |
| 3 价值换算成元 | 做了：金瓜子、钻石、抖币、分写成元（H6），礼物行和长按面板 | 没有 |
| 4 飞行弹幕显示礼物 | 做了：值钱以上飞过直播间画面、全屏横屏、小窗和画中画、多画面、电视；很值钱的顶部停 4 秒；连击最多飞两次；每秒最多 3 条；全屏时避开控制条（H12） | 电视和多画面格子不避让控制层（README“留下的问题”） |
| 5 三处同一个组件、搜索、翻译 | 做了：列表的两个在 `ChatListSettings`，飞行的在 `DanmakuSettingsContent`（多画面的弹幕设置也有）；设置搜索三条；翻译键 | “飞行弹幕显示礼物”放“显示范围”组（没有“显示”组，H2） |
| 阶段 | 两个阶段在同一个提交里 | 列表的过滤（合并器）和飞行的门槛共用搬到 `shared/` 的连击规则，`room_controller.dart` 的同一段改动两个阶段都用到，分开提交要拆同一处代码；两个阶段一起测、一起过门禁 |

## 根因（为什么以前做不到）

- 礼物不飞：`room_controller.dart` 的礼物分支只交给合并器进聊天列表（`_gifts.add`），从不进 `_flying`；而且“在聊天列表显示礼物”关着时整个分支直接返回，礼物连过滤都不走。
- 多画面看不到礼物：`multiview_controller.dart` 的 `_onDanmaku` 把 `LiveMessageType.gift` 和人数、醒目留言放在一起直接 `return`。
- 飞行弹幕层不认礼物：`DanmakuOverlay._add` 只按 `chatSegments` 画文字和表情，平台礼物会画成一条普通的“小心心 ×3”。
- 多画面不能直接用直播间的礼物文字和连击规则：门禁的界面结构检查（`tools/gate/check_ui_structure.py` 规则 1）不许 `features/multiview` 引用 `features/live_play` 里的文件，所以把纯文字和连击规则搬到 `shared/danmaku/`，原文件 `export`。

## 改了哪些文件

- 新：`apps/pure_live/lib/shared/danmaku/gift_flights.dart`（`GiftFlights`、`flyingGiftWords`）、`gift_words.dart`（从 `gift_line.dart` 搬来的礼物文字和数字，加了 `inYuan`、`giftYuanUnits`）、`gift_combo.dart`（从 `gift_combiner.dart` 搬来的 `CombinedGift`、连击键和总数，加了 `giftComboStart`、`giftComboRestarted`、`giftMessageWith`）。
- `apps/pure_live/lib/features/live_play/danmaku/gift_line.dart`：去掉搬走的函数并 `export`；`GiftLine.valueInYuan`、`giftLineOf(valueInYuan:)`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`：`ChatLineView.giftValueInYuan`，行缓存认它，`ChatList` 读设置。
- `apps/pure_live/lib/features/live_play/danmaku/message_panel.dart`：卡片的价值跟着换算。
- `apps/pure_live/lib/features/live_play/logic/gift_combiner.dart`：`minTier`、`GiftOutcome.belowTier`、后台计数的连击；`CombinedGift` 等搬走后 `export`。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（小改，和 D08.1 分开）：`_giftFlights`、`flyGifts`、`_onGiftTier` 和它的订阅、礼物分支（列表和飞行两个开关）、`dispose`。
- `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：`_giftFlights`，礼物分支接上，换弹幕连接时清掉。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`：`_bars()`（原来 `_flyingPoint` 里的控制条高度）和 `giftClearance`。
- `apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`：礼物的样子、顶部停留、避开控制条、画的顺序（停着的在上面）。
- `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`、`danmaku_settings_content.dart`：三行开关。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：搜索三条。
- `packages/live_store/lib/src/settings/settings.dart`：三个设置。
- `packages/live_ui/lib/src/theme/live_colors.dart`：`LivePalettes.danmakuGift`（任务书没列 `live_ui`；颜色只能来自 `live_ui`，门禁不许别处写颜色值）。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 文档工具：`tools/docs/settings_audit_notes.py`、`docs/inventory/OWNERS.toml`。
- 测试：见下。
- 文档：本文件夹 README、record、verify；`docs/tasks.toml`；生成的 STATUS、TASKS、A 组和 A08 的 README、OWNERS.md、J01.2 的 settings.md。
- 小窗 `compact_danmaku.dart` 和电视 `tv_live_play_page.dart` 没改：它们本来就转发直播间的 `flying`，开关一开就有礼物。

## 新设置、翻译键、门禁基线

- 新设置（都在 `danmaku` 一节、同步、默认关）：`chatGiftsAboveTier`、`giftValueInYuan`、`danmakuShowGifts`。
- 新翻译键（6 个，zh / en）：`danmaku_list_valuable_gifts`（只显示值钱的礼物 / Only valuable gifts）、`danmaku_list_valuable_gifts_desc`、`danmaku_list_gift_yuan`（礼物价值换算成元 / Gift values in yuan）、`danmaku_list_gift_yuan_desc`、`danmaku_show_gifts`（飞行弹幕显示礼物 / Gifts in flying danmaku）、`danmaku_show_gifts_desc`。
- 改了文字的键（1 个，键不变）：`live_play_show_gifts_desc`（原来写“不在画面上飞过”，现在礼物可以飞了，H14）。没有删键（D-024）。
- 门禁基线：没改。

## 测试

- `packages/live_store/test/gift_switches_test.dart`（新，2 个）：三个设置默认关、`danmaku` 一节、同步、新装不存；备份往返；3.x 的备份不带它们，读出来是关。`settings_defaults_test.dart` 的 `newInV4` 加了三个。
- `apps/pure_live/test/shared/gift_flights_test.dart`（新，9 个）：便宜、免费、没有价值、本地的不飞；文字（名字 + 礼物行的话，主播不写“送给”）；30 下的连击只在开头飞一次、结束飞总数（×30，档位按总数）；一个礼物只飞一次、平台的连击数是总数；1 元的连击到第 10 下才飞、结束飞 ×12；平台计数回退算新连击；每秒 3 条，第 4、5 条不飞，下一秒又能飞 3 条；`clear` 以后结束的不飞；定时扫描约 5 秒后自己飞出总数、没有连击时停。
- `apps/pure_live/test/shared/danmaku_overlay_test.dart`（加 8 个，A08.12 一组）：礼物的样子录一次（金色、≥600、比同样的字宽出框和图、不超过轨道高），同样的礼物再来走缓存，每帧画一次、和聊天一样滚动，小窗的“统一颜色”不改礼物；透明度和描边跟弹幕设置；很值钱的居中停 4 秒、第二个排在下一格、4 秒后没了；控制条：礼物在顶栏和底栏之间，聊天还走第一条轨道；显示范围太小时用能用的轨道、不出显示范围；“同屏最大弹幕条数”把礼物算进去，满了在队列里等；礼物图没加载完先画图标、加载完不重录、下一条带图；框的粗细两档不同。
- `apps/pure_live/test/features/live_play/gift_switches_test.dart`（新，13 个）：合并器的“只显示值钱的礼物”（便宜、免费、没价值的不出行；1 元的连击到 10 元出一行写 ×10，之后合并成 ×11；5 秒没有下一个就重新算；关掉照 D07.1）；换算成元的文字（金瓜子、钻石、抖币、分；0.01 元起；海外和红豆不变；银瓜子、不明单位不写）；礼物行在 360 和 280 宽、2 倍字下写“990 元”、不溢出；直播间控制器：默认所有礼物进列表、一个也不飞；打开“只显示值钱的礼物”马上去掉便宜的、本地礼物留着、新的便宜礼物不进；飞行：值钱的进 `flying`（“乙 送出 告白气球 ×1”）、便宜的不进、聊天照旧；列表关着也飞、屏蔽的人不飞；40 下连击只飞 1 次、列表合并成 ×40；同一秒 6 个飞机只飞 3 个；关掉后不飞。
- `apps/pure_live/test/features/live_play/gift_flying_room_test.dart`（新，3 个）：直播间页面默认不飞礼物；竖屏：值钱的飞、在顶栏下面，便宜的不飞；全屏横屏 852×393：`giftClearance` 是控制条的高度，很值钱的居中停在顶栏下面、1 秒后还在原地，滚动的在两条控制条之间。
- `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart`（加 1 个）：小窗默认不飞礼物；打开后飞“乙 送出 火箭 ×1”，“统一颜色”下礼物还是金色（小窗的透明度照样）。
- `apps/pure_live/test/features/multiview/multiview_controller_test.dart`（加 1 个）：多画面默认不飞；打开后选中格的值钱礼物飞，便宜的、屏蔽的人的不飞。
- `apps/pure_live/test/features/settings/settings_danmaku_test.dart`（加 4 个）：两行在“在聊天列表显示礼物”下面、默认关、点了生效，礼物关时变灰、点了不变；“飞行弹幕显示礼物”在“显示范围”里“暂停时的弹幕”后面、“样式”前面；2 倍字 360 宽不溢出；搜索“值钱”“换算成元”“飞行 礼物”各找到一条，在“弹幕 › 弹幕列表”“弹幕 › 显示范围”下。
- `apps/pure_live/test/features/live_play/live_play_tabs_test.dart`（加 1 个）：直播间标签和画面面板都有三行、顺序一样，标签里打开的在面板里也是开着。
- 合计新加 42 个；改之前的代码上，除了“默认不变”的几个，都会失败（没有设置、礼物不飞、多画面丢礼物）。
- 全部：`flutter test`（apps/pure_live）、`dart test`（live_store）通过；门禁见下。

## 真机上要看的

- 默认设置下和改之前完全一样（verify.md 第 1 步）。
- 全屏横屏时飞过的礼物不被顶栏、底栏盖住，停在顶部的在顶栏下面；金色字和框在亮画面、暗画面上都看得清（第 5、6 步）。
- 连击多的直播间（斗鱼荧光棒）画面上不刷屏：一个连击最多两次、每秒最多 3 条（第 7 步）。
- “只显示值钱的礼物”打开后荧光棒这类不再进列表、连击够了才出来；“换算成元”写“3 元”“198 元”（第 3、4 步）。
- 小窗、画中画、多画面也飞礼物，小窗“统一颜色”时礼物仍是金色（第 10、11 步）。
- K90 帧时间：开着和关着各量一次（第 13 步）。

## 门禁

- `bash tools/gate/gate.sh --all`：见文末。

## 提交

- 见文末（合并时由维护者补合并提交）。
