# A08.12 礼物开关和飞行弹幕里的礼物：任务书

## 背景

- 来源：V03.5（`docs/V-需求和反馈/V03-审查和调研/V03.5-全平台礼物、醒目留言和弹幕/README.md`）第 6.6～6.8 节、第 7 节 A08.12；用户 2026-10-09（D-040）。
- 现象：礼物只能整体开关；全屏横屏、小窗、多画面里看不到礼物；价值只有平台单位。
- 为什么现在做：第二档；用户要“可以打开和关闭”。
- 已经做过的：A08.11（礼物行）、D07.1（合并和限速）——开工前确认都已合并；D05.2（同屏条数）、D03.4（按住停住）。

## 目标和验收

1. 三个新设置（键名建议见 README，开发时定），都在 `section: 'danmaku'`，默认关，跟备份和设备同步；关着时和现在完全一样。
2. “只显示值钱的礼物”开着时聊天列表只有 `tier` ≥ 值钱的礼物；“在聊天列表显示礼物”关着时这一行变灰。
3. “礼物价值换算成元”开着时国内固定汇率的单位显示成“N 元”。
4. “飞行弹幕显示礼物”开着时值钱以上的礼物飞过直播间画面、全屏横屏、小窗和画中画、多画面；很值钱的在顶部停 4 秒；连击只飞第一下和最终总数；每秒最多 3 条。
5. 三处设置（直播间标签、画面面板、设置 → 弹幕）同一个组件；设置搜索能找到；文字走翻译。

## 现状（读代码得出）

- 设置组件 `apps/pure_live/lib/shared/danmaku/chat_list_settings.dart`（`showChatGifts` 一行 `:68-74`）、弹幕设置正文 `shared/danmaku/danmaku_settings_content.dart`（“显示”组）。
- 飞行弹幕：`room_controller.dart:1131`（只有聊天进 `_flying`）；`shared/danmaku/danmaku_overlay.dart`（队列：等待 120 条、最多等 5 秒、每帧进 4 条 `:221-228`；`LiveMessagePlacement`；表情图 `ChatEmoteSegment`）。
- 多画面 `features/multiview/logic/multiview_controller.dart:1002` 丢掉礼物；小窗 `features/live_play/mini/compact_danmaku.dart`。
- 设置存储 `packages/live_store/lib/src/settings/settings.dart`；搜索 `features/settings/settings_catalog.dart`。

## 3.x 基线

- 3.x 没有平台礼物；飞行弹幕的样式、轨道、队列规则不变（D03）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/UI.md` 第 3 节第 6 条（三处同一个组件）、第 9.3 节；`docs/specs/ENGINEERING.md`。
3. 本文件夹 `README.md`；A08.11、D07.1 的 README；`docs/D-弹幕/D03-飞行弹幕引擎/README.md`。

## 范围

- 可以改：`chat_list_settings.dart`、`danmaku_settings_content.dart`、`settings_catalog.dart`；`room_controller.dart` 的礼物分支（进 `_flying`）；`danmaku_overlay.dart`（礼物样式的一条，录进 Picture）；`multiview_controller.dart`、`compact_danmaku.dart`；`settings.dart`（新设置，登记 `Settings.all`、`settings_defaults_test.dart`、`tools/docs/settings_audit_notes.py`）；`docs/inventory/OWNERS.toml`；翻译文件；对应测试。
- 不能改：聊天弹幕的样式和轨道规则；`showChatGifts` 的键和含义；3.x 的设置键；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 列表的两个设置：只显示值钱的礼物、价值换算成元 | 设置、组件、列表、搜索 | 测试通过 |
| 2 | 飞行弹幕显示礼物：直播间、全屏横屏、小窗、多画面；每秒 3 条；顶部停留 | 控制器、弹幕层、多画面、小窗 | 测试通过；K90 帧时间记进 verify.md |

## 测试

- `packages/live_store/test/`：三个设置默认关、备份往返、3.x 备份不带它们。
- `apps/pure_live/test/features/live_play/`：只显示值钱时普通礼物不进列表；换算成元的文字；开飞行弹幕后值钱的礼物进 `flying`、普通的不进；每秒第 4 条不上画面；很值钱的放顶部；连击只飞两次。
- `apps/pure_live/test/shared/danmaku_overlay_test.dart`：礼物样式录进 Picture，不增加每帧开销。
- 多画面、小窗各一个用例。
- `live_play_tabs_test.dart`、`settings_danmaku_test.dart`：设置行的位置、变灰、搜索。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 默认设置进热门直播间 | 和改之前一样 |
| 2. 打开“飞行弹幕显示礼物”，全屏横屏 | 值钱的礼物飞过，很值钱的在顶部停 |
| 3. 小窗、多画面 | 一样 |
| 4. 打开“只显示值钱的礼物” | 荧光棒这类不再进列表 |

## 风险和注意

- 飞行弹幕变多：门槛（值钱以上）和每秒 3 条控制；和同屏条数（D05.2）一起算。
- 礼物图进 Picture：图没加载完时先不画图，不重录。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`apps/pure_live` 全部 `flutter test`；`python3 tools/docs/owners.py --check`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/A08.12`；提交信息以 `[A08.12]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；新设置和翻译键；测试数量；帧时间；改了哪些文件；真机上要看的。
