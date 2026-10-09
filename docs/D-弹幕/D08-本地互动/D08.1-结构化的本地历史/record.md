# D08.1 结构化的本地历史：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并）
- 分支和提交：工作区分支 `worktree-agent-aab6a298eb9e594fc`（从 master `f28cee592` 开始），提交 `[D08.1] …`：存储和备份一次、应用（记录、界面、进房放回，三个阶段的代码在同几个文件里，一起提交）一次、文档一次
- 任务书：[brief.md](brief.md)；设计、存储格式、维护者按 D-003 定的 s1～s16：[README.md](README.md)；来源：V03.6 第 2.2 节 P2、P3，第 4 节 E5，第 5.3 节做法 A；D-040

## 逐条对照（brief“目标和验收”）

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 `local_events` 表、`schemaVersion` 2、老库能迁移、最多 2000 条 | 做了 | 用真实的 4.0.0 库文件测（`packages/live_store/test/fixtures/store_v1.db`，由改动前的代码写出） |
| 2 发弹幕、送礼、加币各写一条；`localInteraction.history` 照旧写 | 做了 | 加币不记直播间（s9） |
| 3 旧的 30 条转成 `legacy`，只做一次，原键不删 | 做了 | 在第一次用到本地互动时转，不在打开数据库时（s2：3.x 的导入在打开数据库之后） |
| 4 备份带这张表；设备同步一类可选、默认不勾 | 做了 | 没有记录时不写这一节（s13）；只同步这一类时 `LegacySnapshot` 也认这个文件 |
| 5 分段、时间、直播间名、再发一次、导出 | 做了 | 另加“只看本直播间”（s8）和“显示更多”（s6）；“再发一次”是每条右边的按钮（s7） |
| 6 `localInteraction.replayOnEnter` 默认开；24 小时、20 条、顶上、“之前发的”、不飞过 | 做了 | 用现在的身份显示（s10） |
| 7 文字走翻译 | 做了 | 新键见下面 |

## 根因（为什么以前做不到）

- P2：`apps/pure_live/lib/features/live_play/local_interaction/logic/local_interaction.dart` 的 `recharge`、`sendGift` 只往 `localInteraction.history`（`StringListSetting`，`packages/live_store/lib/src/settings/settings.dart`）写拼好的中文句子，所以换语言、按房间看、再发一次都无从谈起。
- P3：`LocalRoomSession.sendChat`（`logic/local_room_session.dart`）只调 `createChat` 再 `room.addLocal`（`features/live_play/logic/room_controller.dart` 的 `addLocal`），本地弹幕只进当场的 `ChatFeed`，没有任何地方存它；离开直播间 `ChatFeed` 跟着控制器一起没了。

## 改了哪些文件

- `packages/live_store`：
  - `lib/src/database.dart`：`StoreTables.localEvents`、建表和索引、`schemaVersion` 2、`onUpgrade`（从 1 来只加表）。
  - `lib/src/local_events.dart`（新）：`LocalEventKind`、`LocalEvent`（JSON 往返）、`LocalEventStore`（`all`、`watch`、`recentChats`、`add`、`addAll`、`clear`、`replaceAll`、`adoptLegacyHistory`、`inBackup`）。
  - `lib/src/live_store.dart`、`lib/live_store.dart`：`LiveStore.localEvents`，导出。
  - `lib/src/backup/backup_service.dart`：`exportAll` 写 `localEvents` 一节（有记录才写），`restoreAll` 整表替换。
  - `lib/src/legacy/legacy_snapshot.dart`：只有 `localEvents` 一节的文件也算备份（设备同步只勾了这一类）。
  - `lib/src/settings/settings.dart`：`localInteractionReplayOnEnter`（不进 3.x 的 29 个键的列表，单独放进 `Settings.all`）。
- 应用逻辑：
  - `local_interaction/logic/local_interaction.dart`：`LocalPlace`、`LocalHistoryCleared`、`LocalHistoryFilter`；`LocalInteraction` 加 `events`、`start`（转旧记录、跟着表变）、`recordChat`、`describe`（按现在的语言说一条）、`replayed`、`replayOnEnter`；`sendGift` 多一个 `place`；`clearHistory` 返回句子和记录，`restoreHistory` 两样都放回；`LocalProfile.replayedIn`。
  - `local_interaction/logic/local_room_session.dart`：`place`；`sendChat`、`sendGift` 记直播间；建会话时放回（`events`、`now` 可注入，`replayWindow` 24 小时、`replayCount` 20）。
  - `local_interaction/logic/local_catalog.dart`：`giftById`。
  - `local_interaction/local_interaction_scope.dart`：provider 把表交给 `LocalInteraction`，`start` 在 `adoptLegacyValues` 之后。
- 界面（照 A08.2 的样子，在 A08.2 README 补了一条）：
  - `local_interaction/local_interaction_panel.dart`：`LocalHistory` 改成有状态的组件（分段、只看本直播间、两行的条目、再发一次、显示更多、导出）；`localHistoryDetail`、`localHistoryLine`。
  - `local_interaction/local_interaction_settings_page.dart`：“进房放回”开关；记录可导出。
  - `local_interaction/local_chat_line.dart`：“之前发的”胶囊。
- 进房的钩子（和其他任务分开，各只加一处）：
  - `features/live_play/logic/room_controller.dart`：`addLocal` 下面加 `replayLocal`（一个控制器只放一次）。
  - `features/live_play/danmaku/chat_feed.dart`：`addOldest`（放在最前、负数 id、不算新消息）。
  - `features/live_play/live_play_page.dart`：建 `LocalRoomSession` 时传 `events: store.localEvents`。
- 备份和同步（J03、J05）：`shared/backup/backup_data.dart`（`RestorePartKind.localEvents`，恢复前的预览列出它）、`shared/backup/sync_parts.dart`（`SyncPart.localEvents`、`optIn`、整节一类、条数）、`features/remote_receiver/remote_receiver_page.dart`（`optIn` 的勾选框一开始不勾；不勾时其他没有勾选框的部分照旧跟着走）。
- `packages/live_ui/lib/src/icons/app_icons.dart`：`localReplay`（`Icons.history_toggle_off_rounded`）。
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`。
- 文档和登记：`docs/tasks.toml`（D08.1）、`tools/docs/settings_audit_notes.py`（新设置）、生成的 J01.2 `settings.md`、`docs/inventory/OWNERS.md`（`localInteraction` 一节默认归 D08，`OWNERS.toml` 不用改）、本文件夹 README 和本记录、D08 子分类 README（代码地图、已知问题）、A08.2 README。

## 新设置、翻译键、门禁基线

- 新设置：`localInteraction.replayOnEnter`，`BoolSetting`，`localInteraction` 一节，默认 `true`（D-040 写明的例外），跟备份和设备同步的“设置”走；3.x 没有这个键。
- 新翻译键（zh、en 都加，按键名排序、4 空格缩进；没有删键）：`backup_part_local_events`、`local_history_again`、`local_history_export`、`local_history_exported`、`local_history_filter_all`、`local_history_filter_chat`、`local_history_filter_coins`、`local_history_filter_gift`、`local_history_legacy`、`local_history_level`（给 D08.3 用）、`local_history_more`、`local_history_sent_again`、`local_history_this_room`、`local_replay_on_enter`、`local_replay_on_enter_desc`、`local_replayed_tag`。
- 新图标：`AppIcons.localReplay`。门禁基线不变。
- 数据库：`schemaVersion` 1 → 2；`meta` 新键 `localEvents.legacyAdopted`。

## 测试

- `packages/live_store/test/local_events_test.dart`（新，7 个）：新库有表、新的在前、`AUTOINCREMENT` 的 id 不复用、清空后按原 id 放回；2000 条上限从旧的删；进房查询（同房间、同平台、只弹幕、时间窗、最近 N 条、从旧到新）；真实的 4.0.0 库文件升到 2（设置、关注都在，旧句子转一次、第二次不转、原键不变，重新打开还是 2）；备份往返（没记录不写这一节、恢复整表替换、恢复后不再转旧记录、没有这一节的文件不动记录）；备份里坏的条目跳过；JSON 往返。
- `packages/live_store/test/settings_defaults_test.dart`：`newInV4` 加 `localInteraction.replayOnEnter: true`。
- `apps/pure_live/test/features/live_play/local_history_test.dart`（新，9 个）：
  - 逻辑（假时钟）：弹幕、礼物、加币各写一条，带直播间、时间和样式；3.x 的句子照旧写；旧句子转一次（再启动不重复）；换英文后同一条记录变英文、旧句子不变；分段的条数。
  - 清空连表一起清，撤销后按原 id 回来（中间新加的一条留在上面）。
  - 进房放回：竖屏、横屏手机（852×393）、宽屏（1280×800）各一个：24 小时内同房间的 2 条在列表顶上（在平台消息上面）、标“之前发的”、不飞过（画面上只有平台的那一条）、没有“N 条新弹幕”、25 小时前的、别的房间的、礼物都不放回。
  - 关掉“进房放回”：和以前一样。
  - 发 3 条、离开、再进：3 条按顺序回来；这次发的不重复。
  - 面板：5 条（含旧记录，写“旧记录”、没有“再发一次”）；“弹幕”“礼物”“币”分段；“时间 · 主播”；只看本直播间；弹幕再发一次（提示“已再发一次”、多一条记录）；礼物再发一次扣 10 币；余额不够“体验币余额不足”。
  - 设置页：同一份记录、没有“再发一次”和“只看本直播间”；导出到剪贴板的 5 行；“进房放回”默认开、点了存成关。
- `apps/pure_live/test/features/live_play/local_interaction_test.dart`：改了 2 个（`clearHistory` 的返回值；面板清空撤销后记录也回来）。
- `apps/pure_live/test/shared/sync_parts_test.dart`：加 1 个（本地记录是单独一类、`optIn`、条数、恢复预览、不勾时这台的记录不动、只勾它时替换）。
- `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`：加 1 个（发送对话框里“本地互动记录（1）”一开始不勾，发出去的部分里没有它、其他照旧）。
- `packages/live_ui/test/design_system_test.dart`：图标对照表加 `localReplay`。
- 门禁：`tools/gate/gate.sh --all` 通过（见下面“门禁”）。

## 真机上要看的

只用测试包 `com.mystyle.purelive.v4dev`（不碰 3.x）；每次点按前看前台是不是测试包。

| 步骤 | 期望 |
|---|---|
| 1. 覆盖安装到已经用过本地互动（送过礼、加过币）的测试包上，打开设置 → 本地用户与互动 | 记录里原来的句子都在，写“旧记录”；条数和以前一样 |
| 2. 进一个直播间，在列表下的输入框发 3 条本地弹幕，退出再进同一个直播间 | 列表顶上是这 3 条（从旧到新），每条有“本地”和灰色的“之前发的”，不在画面上飞；没有“N 条新弹幕” |
| 3. 横屏（全屏）和宽屏各看一次第 2 步 | 同上 |
| 4. 换一个直播间进 | 不放回别的房间的 |
| 5. 互动面板 → 往下到记录，点“弹幕” | 只有弹幕，每条下面“时间 · 主播名”；点“只看本直播间”只剩这个房间的；点“再发一次”：列表和画面上多一条，提示“已再发一次” |
| 6. 点“礼物”，“再发一次” | 扣币、横幅出来；币不够时“体验币余额不足” |
| 7. 设置 → 语言切英文，再看记录 | 弹幕原文；礼物、加币是英文（“sent Spicy snack ×1”“Added local experience coins +500”）；旧记录还是原来的中文句子 |
| 8. 设置页“导出到剪贴板”，粘贴到别处 | 一行一条“日期 时间 · 主播 · 弹幕 · 内容” |
| 9. 清空记录，4 秒内点“撤销” | 记录全部回来；再退出重进直播间，第 2 步的放回照旧 |
| 10. 设置页关掉“进房放回之前发的本地弹幕”，退出再进 | 不放回 |
| 11. 备份 → 清除测试包数据 → 恢复备份 | 记录还在（条数、时间、直播间名一样）；不多出重复的“旧记录” |
| 12. 设备同步（两台 v4）：发送时看勾选框 | 多一项“本地互动记录（N）”，一开始不勾；不勾发过去，对方的记录不变 |

## 门禁

- `bash tools/gate/gate.sh --all`：`gate: passed (all, 14 members)`（提交 `ed1c8582c` 上跑的；日志 `/tmp/claude-1000/-home-wzgrx/79949b22-868f-4748-bbdd-3bd3eeb9db12/scratchpad/d081-1791509225/gate.log`）。`apps/pure_live` 全部 1196 个测试通过，`live_store` 83 个、`live_ui` 217 个。
