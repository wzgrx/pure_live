# D08.1 结构化的本地历史：本地弹幕进记录、重进房间放回：任务书

## 背景

- 来源：V03.6（`docs/V-需求和反馈/V03-审查和调研/V03.6-弹幕系统和本地互动体验/README.md`）第 2.2 节 P2、P3，第 4 节 E5（乙档），第 5.3 节做法 A；用户 2026-10-09（D-040）。
- 现象：自己发的本地弹幕离开直播间就没了；记录只有送礼和加币，存的是拼好的中文句子，换语言后还是旧语言，不能按直播间看、不能再发一次。
- 为什么现在做：第二档；D08.2、D08.3、D08.4 都要用它。
- 已经做过的：A08.2（本地互动全部界面，c12 记录）；J03（备份）、J05.1（同步前勾选内容）。

## 目标和验收

1. `live_store` 有 `local_events` 表（字段见 README c1），`schemaVersion` 升到 2，老数据库能迁移；最多 2000 条。
2. 发本地弹幕、送礼、加币各写一条；`localInteraction.history` 照旧写（覆盖回 3.x 时有记录）。
3. 第一次启动把旧的 30 条句子转成 `legacy` 记录，只做一次，原键不删。
4. 备份带这张表，恢复后记录还在；设备同步里是一类可选内容，默认不勾。
5. 面板和设置页的记录：分段“全部 / 弹幕 / 礼物 / 币”、时间、直播间名、点一条“再发一次”；设置页“导出到剪贴板”。
6. 新设置“进房放回之前发的本地弹幕”（`localInteraction.replayOnEnter`，默认开）：24 小时内同一个直播间最多 20 条放在列表顶上、标“之前发的”、不飞过；关掉和现在一样。
7. 文字走翻译。

## 现状（读代码得出）

- `packages/live_store/lib/src/database.dart`：表名 `StoreTables`、建表语句（`:45-55`）、`schemaVersion => 1`（`:85`）。
- `packages/live_store/lib/src/settings/settings.dart`：`localInteraction.history`（`:1294`，`StringListSetting`）。
- `apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart`：`recharge`（`:219`）、`clearHistory`（`:228`）、`_withHistory`、`createChat`、`sendGift`；`logic/local_catalog.dart` 的 `historyLimit`（30）。
- `logic/local_room_session.dart`：`sendChat`、`sendGift`、`_deliver`（`:97`）。
- 界面：`local_interaction/local_interaction_panel.dart` 的 `LocalHistory`（`:447-527`）、设置页 `local_interaction_settings_page.dart:159`。
- 进房：`features/live_play/live_play_page.dart` 建 `LocalRoomSession`（V03.6 写 `:326`）；`room_controller.dart:1159` `addLocal`。
- 备份：`packages/live_store/lib/src/backup/`；同步：`features/remote_receiver/`、J05.1。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/local_interaction/local_interaction_controller.dart` 的 `:905-910`：30 条句子。要保留：`localInteraction.history` 的键和含义（D-018），覆盖回 3.x 时它照样能读。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`（`live_store` 的分层）；`docs/specs/UI.md` 第 3、7 节。
3. 本文件夹 `README.md`；`docs/D-弹幕/D08-本地互动/README.md`；`docs/A-界面设计/A08-弹幕界面/A08.2-本地互动/README.md`；J03、J05 的 README。

## 范围

- 可以改：`packages/live_store/lib/src/`（`database.dart`、新 `local_events.dart`、备份）；`features/live_play/local_interaction/`（logic 和记录的界面）；`live_play_page.dart` 或 `room_controller.dart`（进房放回）；同步的内容类（J05）；`settings.dart`（新设置）、`settings_catalog.dart`；`docs/inventory/OWNERS.toml`；翻译文件；对应测试；A08.2 README 补一条。
- 不能改：29 个 3.x 键的含义；清空的行为（A08.13）；本地互动的其他界面；版本号。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1 表和迁移、c2 写入、c3 旧记录迁移、c4 备份和同步 | `live_store`、`logic/local_interaction.dart` | 存储、迁移、备份测试通过；界面不变 |
| 2 | c5 记录分段、再发一次、导出 | `local_interaction_panel.dart`、设置页 | 界面测试通过 |
| 3 | c6 进房放回（新设置，默认开） | 进房的地方、设置 | 测试通过 |

## 测试

- `packages/live_store/test/`：建表、从 1 升到 2 的迁移（老数据库文件）、2000 条上限、备份往返、旧句子迁移只做一次、原键不变。
- `apps/pure_live/test/features/live_play/local_interaction_test.dart`：发弹幕、送礼、加币都写一条；分段过滤；再发一次（礼物扣币、余额不够提示）；导出的文字；进房放回 20 条、24 小时外的不放、标“之前发的”、不进飞行弹幕；关掉设置不放回。
- 定时器至少 1 秒；“现在”用假时钟。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 在一个直播间发 3 条本地弹幕，退出再进 | 列表顶上有这 3 条，标“之前发的” |
| 2. 互动面板的记录，点“弹幕” | 只有弹幕，有时间和直播间名；点一条再发一次 |
| 3. 切英文界面 | 记录是英文 |
| 4. 备份、清数据、恢复 | 记录还在 |

## 风险和注意

- 数据库升版本：迁移要能从任何 1 版的库升上来；测试用真实的旧库文件。
- 放回的消息不要算进“N 条新弹幕”，也不要过平台过滤。
- 同一组同时只开一个开发（D07、D08、D02 排队）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；`packages/live_store` `dart test`；`apps/pure_live` 全部 `flutter test`；推送前 `bash tools/gate/gate.sh --all`。
- 分支 `ai/D08.1`；每个阶段一次提交，信息以 `[D08.1]` 开头（英文）；不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；表结构和迁移；新设置和翻译键；测试数量；改了哪些文件；真机上要看的。
