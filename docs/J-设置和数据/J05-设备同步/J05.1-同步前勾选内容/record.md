# J05.1 同步前勾选内容：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区 `worktree-agent-a5c01fdfb0fb20bec`，一个提交（`[J05.1]`：V01.6 的评估和设计、登记、代码、测试、文档），没有推送、没有合并
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；设计选择：[V01.6 README](../../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md) 文末 S1～S13

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 验收 1 发送前勾选，只发勾选的 | 做了 | 勾选框替代了原来“确定要将当前设备的全部配置发送到…吗”的确认框（少一步，原来那句话留给 3.x 设备用） |
| 验收 2 3.x、上游、旧 4.x 整份发 | 做了 | 靠 `/status` 里的 `syncParts` 判断；旧 4.x 其实能收部分包，但分不清它和 3.x，一律整份发（V01.6 S3） |
| 验收 3 主动接收时勾选 | 做了 | |
| 验收 4 对方发来时勾选 | 做了 | 原来只有“拒绝 / 允许”，现在和主动接收用同一个预览加勾选框（A12.6 留下的问题一起解决） |
| 验收 5 按 `sections` 过滤，没有就当全量 | 做了 | 过滤后先解析，坏包回 400，不弹框（原来要等用户同意后才失败） |
| 验收 6 配对码不变、不加设置、不记住、全不勾时主按钮变灰 | 做了 | |
| 提议的 c3“`BackupService.restoreAll` 加只恢复这些类的参数” | 没照做 | 改成在应用一侧拆包（`pickSyncParts`），再交给原来的 `restoreAll`：4.x 的恢复本来就只替换文件里有的部分，`live_store` 不用改 |
| 提议的 c4“拉取也走同样的勾选” | 做法不同 | 拉取时对方整份给（3.x 和旧 4.x 的 GET 不认识勾选），在本机预览里勾，只应用勾选的；没在 GET 里带勾选（V01.6 互通表） |
| V01.6 任务书的效果图和评审页 | 没做 | D-036 授权维护者定（V01.6 S13）；布局用 widget 测试固定，真机截图在 verify.md 里补 |

## 根因（为什么 3.x 只能整份发）

- 3.x 导入时缺的分区当空分区：`git show v3.2.11:lib/common/services/settings/backup_controller.dart` 的 `_importV2`（`:239-285`），例如 `fromJson(data['favorite'] ?? {})`（`:255`）；`FavoriteRoomController.fromJson`（`favorite_room_controller.dart:565-571`）从空分区解析出空的关注和屏蔽词。上游 `9483ccf03` 的接收端过滤也没生效（`remote_sync_service.dart:638-647` 在 `settings` 里找 `sections`），所以上游设备之间只勾一部分时会出同样的问题。
- 4.x 不会：`packages/live_store/lib/src/legacy/legacy_snapshot.dart` 的 `fromBackup` 对每个键看文件里有没有，`BackupService.restoreAll` 只替换有的部分。

## 改了哪些文件

- `apps/pure_live/lib/shared/backup/sync_parts.dart`（新）：`SyncPart` 和拆包函数。
- `apps/pure_live/lib/features/remote_receiver/remote_sync_protocol.dart`：`partsKey`、`settingsPacket(sections:)`、`sectionsOf`、`takesParts`。
- `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart`：`/status` 带 `syncParts`；`RemoteSyncChooseImport`、`chooseImport`；`_settings` 按 `sections` 过滤、先解析、问勾哪些、只恢复勾选的；`outgoing`、`takesParts`、`send(parts:)`、`apply(parts:)`；`_request` 可以不带配对码、换路径。
- `apps/pure_live/lib/features/remote_receiver/remote_receiver_page.dart`：`_send`、`_receive`、`_chooseIncoming`、`_previewDialog`、`_SyncPartsDialog`；删掉了 `_confirmReceive` 和 `_confirm`。
- `apps/pure_live/assets/translations/zh.json`、`en.json`。
- 测试：`apps/pure_live/test/shared/sync_parts_test.dart`（新）、`apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`。
- 文档：V01.6 README（评估结论、互通表、设计选择、经过）；本文件夹 README、brief、record、verify；J05 README（线上格式、完成度、代码地图、测试、已知问题、路线）；`docs/tasks.toml`（V01.6 改“已确认”、`to = ["J05.1"]`；新登记 J05.1，“待真机”）；`python3 tools/docs/docs.py` 生成的文件。

## 新设置、翻译键、门禁基线

- 没有新设置（不记住勾选，V01.6 S7）。
- 新翻译键（zh、en 都加，按键名排序）：`remote_sync_part_accounts`（账号 Cookie）、`remote_sync_part_count`（{part}（{count}））、`remote_sync_part_settings`（设置）、`remote_sync_parts_all`（全选）、`remote_sync_parts_legacy`（对方是 3.x 或较早的版本……只能发送全部内容。）、`remote_sync_parts_send_named`（勾选要发送到“{name}”的内容……）、`remote_sync_preview_accounts_empty`（账号：对方没有登录信息，接收后本机的平台登录会被清空）。
- 改了文字：`remote_sync_preview_warning`（“接收会替换上面列出的内容”→“接收会替换勾选的内容，没勾的保持不变”）。
- `remote_sync_confirm_send_named` 还在用（发给 3.x 设备时）；没有翻译键变成没用的。
- 线上格式：`/status` 多 `syncParts`；设置包可选 `sections`。全勾时设置包和 3.x 一字不差（测试固定了键是 `type`、`version`、`settings`）。
- 门禁基线没动。

## 测试

- 新增 16 个：`sync_parts_test.dart` 5 个；`remote_sync_test.dart` 11 个（真 HTTP 6 个：v4 设备只收到勾选的而且错码仍被拒、3.x 的包当全量和上游带 `sections` 的包只读列出的、3.x 设备拿到整份包、全勾发 3.x 的包而少勾带 `sections`、对方发来时只应用勾选的和不勾就拒绝、`apply` 只恢复勾选的；页面 5 个：给 v4 设备发送时的勾选框和数量和“全选”、全勾就是全部而取消什么都不发、横屏 1.3 倍字号时能滚动且按钮在屏幕里、接收时每类一个框且只应用勾选的、对方发来时的勾选确认框）。
- 改了 4 个：发送（现在先出锁住的勾选框，验证 3.x 设备整份发）、接收（新的提示文字、只有一类时没有“全选”）、对方读取的确认框（改用 `export`，导入走新的勾选框）、扫码后发送（等勾选框出来）；另外测试替身 `_FakeSync` 记录 `parts`。
- `flutter test test/features/remote_receiver/ test/shared/sync_parts_test.dart`：29 个全过；`dart analyze --fatal-infos` 无问题；`bash tools/gate/gate.sh --all`：`gate: passed (all, 14 members)`。中间有一次跑时一个无关的计时测试失败（`live_play_controller_test.dart` 的“G03.1: entering the room leaves one timing line”，各段取整后的和差了 11 毫秒，机器忙时会这样），单独跑通过，再跑整个门禁通过；不是这次的改动引起的，没有改它。

## 真机上要看的

- 按 [verify.md](verify.md) 的 14 步，K90 测试包加另一台设备（电脑上的 Windows 版 4.x 或模拟器上的 4.x），3.x 对端只用模拟器上的 3.2.11（D-019）；和 S02.4 第 3 阶段一起做。
- 重点：
  1. 给 4.x 发送时只勾“关注的直播间”，对方确认框里只有这一类，允许后对方的屏蔽词和设置不变。
  2. 发给 3.2.11 时勾选框锁住、写着“对方是 3.x 或较早的版本……只能发送全部内容。”，3.x 收到后没有被清空的东西（和以前一样）。
  3. 3.2.11 发过来时，K90 的确认框能去掉某一类，去掉的那类不变。
  4. 主动接收时去掉“设置”，设置不变。
  5. 横屏、大字号、深色模式下勾选框能滚动，按钮不被挡。
  6. 打开“同步账号 Cookie”时多出“WebDAV 服务器”“账号 Cookie”两类；对方开了但没登录时，K90 的“账号”一行写“接收后本机的平台登录会被清空”（以前的预览这里写“本机账号不变”，其实会清空，现在写对了，也能不勾）。

## 可能冲突的文件

- `remote_receiver_page.dart`（A12.6 后续、O04.1 的权限提示）；`remote_sync_service.dart`（J05 路线第 2 条：设备同步专用的权限提示）；翻译文件。
