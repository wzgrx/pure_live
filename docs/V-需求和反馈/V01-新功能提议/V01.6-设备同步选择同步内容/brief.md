# V01.6 设备同步在发送、接收前先勾选同步哪些内容（保留配对码）：任务书

## 背景

- 来源：上游 pure_live `9483ccf03`（2026-10-01：发送、接收前勾选同步内容，同时去掉配对码），W01.1 列为可借鉴的新功能（“我们保留配对码”），按 D-027 进 V01；旧任务清单 T09e.2。
- 现象：设备同步现在整份发、整份恢复；只想同步关注或屏蔽词时做不到。
- 为什么是第三档：新功能（D-026），规模小到中。
- 已经做过的：A12.6（设备同步界面，接收前先预览）、J05（同步逻辑，保留 3.x 协议和配对码）；本文件夹 `README.md` 的评估初稿（c1～c5，12 类勾选，保留配对码）。

## 目标和验收

本任务是**提议**：做到“用户能拍板”为止。

1. 评估补完：核对 README 的文件:行；读上游 `git show 9483ccf03`（`remote_sync_page.dart`、`remote_sync_protocol.dart`、`remote_sync_service.dart` 的改动），确认 `sections` 的段名和 4.x 备份文件的段名能不能对上（4.x 有上游没有的段：搜索记录 `search`、多画面 `multiview`、网络电视列表），写清 4.x 和上游设备之间互发时会怎样。
2. 出图：发送时的勾选页（12 类、数量、全选）、接收时带勾选框的预览页；竖屏和宽屏右栏。
3. 评审页：`page.json`（说明、对比现在和上游、改了什么、为什么保留配对码、需要你选的：做不做 / 接收方能不能少勾 / 备份恢复要不要也加），发布给用户；维护者改“待确认”。
4. 用户回复后：确认 → 建议的 DECISIONS 条目和目标组任务（J05 协议和发送 c1、c2、c4；J03 恢复过滤 c3；A12.6 界面）；否决 → V04 的说明。

## 现状（读代码得出，写文件:行）

- 发送：`apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart:379-383` 的 `send`：`BackupService(store).exportAll(includeSensitiveData: includeAccounts)` → `RemoteSyncProtocol.settingsPacket(settings: …)` → `POST /api/remote-sync/settings`。“同步账号”开关 `includeAccounts`（`:122`，默认关；页面 `remote_receiver_page.dart:505`）。
- 服务端：`:317-324` 配对码不对就 403、错满 10 次（`maxWrongCodes` `:100`）换码；`:326-340` 读包（`type` 必须是 `pure_live_sync`、`settings` 必须是对象），确认后应用；GET 时导出（`:352`）。
- 接收：`fetch`（`:395`）读、`remote_receiver_page.dart:150` 的 `previewRestore(…, BackupScope.all)` 出预览、`apply`（`:407`）调 `BackupService.restoreAll`（`packages/live_store/lib/src/backup/backup_service.dart:91`）整份恢复。
- 分类：`apps/pure_live/lib/shared/backup/backup_data.dart:120-150` 的 `RestorePartKind`（10 类）+ 设置、账号；预览 `RestorePreview`（`:196`）。
- 协议：`features/remote_receiver/remote_sync_protocol.dart`（端口 39888、发现 39889、`syncType`、`pairingHeader`、6 位配对码）。

## 3.x 基线

- `git show v3.2.11:lib/modules/remote_receiver/remote_sync_service.dart`：整份发送、整份导入、配对码；4.x 的协议照它（J05），和 3.x 设备能互发。
- 要保留：和 3.x 设备互发（没有 `sections` 的包当全量）；配对码；“同步账号”默认关。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 6 节）。
2. `docs/A-界面设计/A12-账号和数据界面/A12.6-设备同步/README.md`（确认的改动、实现）；`docs/J-设置和数据/J05-设备同步/README.md`；`docs/J-设置和数据/J03-备份恢复/README.md`。
3. 本文件夹 `README.md`。

## 范围

- 可以改：本文件夹。
- 不能改：代码；`docs/tasks.toml`、`docs/DECISIONS.md`；其他组文档。

## 方案和阶段

登记表没有阶段（规模小），按两步做：

| 步 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 | 补完评估（含和上游、3.x 设备的互通表）、出图、发评审页 | 报告给维护者改“待确认” |
| 2 | 用户回复后按 PROCESS 第 6 节第 3 步处理；实现任务完成后本任务改“完成” | 目标组任务登记好（或改“不做”） |

## 测试

- 本任务不写测试；README“验证”写了实现任务要加的（`apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`：只勾一类、没有 `sections` 当全量、配对码仍有效、3.x 格式照收）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机；实现后在 S02.4 第 3 阶段的两台设备上看） | — |

## 风险和注意

- 安全：不跟上游去掉配对码；评审页要写清原因（同步里可能带登录 Cookie）。
- 段名对不上时（上游或 3.x 设备不认识的段）对方会忽略：互通表里写清用户会看到什么。
- 接收方少勾时，发送方以为“同步成功”但对方只应用了一部分：回执里要不要带“应用了哪些”，评估里写。

## 环境和提交

- 出图：`tools/ui/mock/README.md`；`python3 tools/ui/mock/render.py docs/V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/src/`。
- 本机工作区或分支 `ai/V01.6`；提交信息以 `[V01.6]` 开头（英文）；不推 master。提交前 `python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已写的先提交；README 末尾写“停在哪”。

## 报告（中文，简洁）

评估结论（互通表、规模、涉及的组）；评审页地址；需要用户选的问题；建议的 DECISIONS 条目和目标组任务。
