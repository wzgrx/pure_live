# J05.1 同步前勾选内容：任务书

## 背景

- 来源：新功能提议 [V01.6](../../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md)，D-036 同意做（第三档）；上游 pure_live `9483ccf03`（发送、接收前勾选同步内容；上游同时去掉了配对码，我们保留）。
- 现象：设备同步只能整份同步；只想把关注同步到平板、只想同步屏蔽词时做不到。
- 为什么现在做：D-036 按 V01 路线逐个做；设计选择按 D-003 由维护者定（V01.6 README 文末 S1～S13）。
- 已经做过的：J05（协议和 3.x 一样，保留配对码）、A12.6（设备同步页、接收前预览）。

## 目标和验收

1. 发送：选好设备后先出勾选框，列出要发的几类和数量，默认全勾；对方是 4.x（`/status` 声明 `syncParts`）时只发勾选的，没勾的在对方那里保持不变。
2. 对方是 3.x、上游、旧 4.x，或者连不上：勾选框全勾并锁住，写明原因；发出的包和以前一字不差。
3. 主动接收：预览里每类一个勾选框，默认全勾；只应用勾选的。
4. 对方发来：确认框列出会改什么，每类一个勾选框，“拒绝 / 允许”，点外面不关；只应用勾选的。
5. 包里有 `sections` 时接收方只读列出的分区；没有就当全量（3.x 的包照旧）。
6. 配对码不变（错码照样被拒、错 10 次换码）；不加新设置，不记住上次的勾选；什么都没勾时主按钮变灰。

## 现状（读代码得出，写文件:行）

- 发送：`apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart` 的 `send` 整份导出 `BackupService.exportAll(includeSensitiveData: includeAccounts)`；页面 `remote_receiver_page.dart` 的 `_send` 先问“确定要将当前设备的全部配置发送到…吗”。
- 接收：`fetch` → `previewRestore` → `apply` 整份恢复；对方发来时服务端 `_settings` 用 `confirm('import', …)` 只问“允许 / 拒绝”。
- 协议：`remote_sync_protocol.dart` 的 `settingsPacket` 只有 `type`、`version`、`settings`。
- 4.x 恢复按“有才替换”（`packages/live_store/lib/src/legacy/legacy_snapshot.dart` 的 `fromBackup`）。

## 3.x 基线

- `git show v3.2.11:lib/common/services/settings/backup_controller.dart`：`_importV2`（`:239-285`）把缺的分区当空分区导入，等于重置成默认；所以给 3.x 设备只能整份发。
- 要保留：和 3.x 设备互发；配对码；“同步账号 Cookie”默认关；GET 时整份给。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 6 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 7 节（弹窗：对话框里的字不小于 14 号）。
3. V01.6 README（评估结论、互通表、设计选择）；本文件夹 `README.md`；`docs/J-设置和数据/J05-设备同步/README.md`。

## 范围

- 可以改：`apps/pure_live/lib/features/remote_receiver/`、`apps/pure_live/lib/shared/backup/`（新文件）、翻译文件、对应测试；J05、V01.6、本文件夹的文档；`docs/tasks.toml`。
- 不能改：`packages/live_store` 的备份格式和 `BackupService`；备份页和 WebDAV 页；配对码规则；3.x 的设置键名；版本号。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c5（一个阶段：协议、拆包、服务、两个对话框、翻译） | 见 README“结果” | 自动测试全过，门禁通过 |

## 测试

- `apps/pure_live/test/shared/sync_parts_test.dart`：拆包、按键拆 `favorite`、全勾原样、平铺的旧文件原样、按 `sections` 过滤。
- `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`：真 HTTP 下只勾关注时对方只多了关注、设置不变；错码仍被拒；3.x 的包当全量、上游带 `sections` 的包只读列出的；3.x 设备拿到整份包；对方发来时只应用勾选的、不勾就拒绝；页面的勾选框、“全选”、锁住的样子、横屏 1.3 倍字号。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)。

## 风险和注意

- 给 3.x 发部分包会清空对方的数据：只对声明 `syncParts` 的设备拆包（V01.6 S3）。
- `remote_receiver_page.dart` 和 A12.6 的后续改动冲突。

## 环境和提交

- `source ~/tools/purelive-env.sh`；新工作区先 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`。
- 提交信息以 `[J05.1]` 开头；`bash tools/gate/gate.sh --all` 通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；翻译键；要在真机上看的。
