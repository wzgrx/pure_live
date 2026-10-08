# J01.2 设置项逐条核对：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（agent worktree），提交以 `[J01.2]` 开头
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；对照表：[settings.md](settings.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 出表 | 做了 | 脚本 `tools/docs/settings_audit.py`（只读，不进门禁）：取注册表、`git archive v3.2.11 lib`、设置页目录和读取位置，写 `settings.md`。手写的部分（3.x 的表达式默认值、范围、结论）放在 `tools/docs/settings_audit_notes.py`，表可以随时重新生成。219 行（A08.6 加了 `showChatGifts`）。脚本把常量键（`historyLimitKey`、`autoSyncHoursIntervalKey`、`RecorderKeys.*`）和同一文件的常量都解开了，所以分法和清点第 15 节的“172 / 106 / 2 / 64 / 46”不同：自动取到 166 个，手工展开 32 个，新加 21 个 |
| c2 展开常量 | 做了 | 64 个里同一文件的常量（弹幕、字体、刷新、录制等）脚本直接解开；跨文件的常量和表达式 32 个手工展开，每个写了 3.x 文件:行 |
| c3 46 个非 `hive*` | 做了 | 新加 21 个各写来源任务；录制 19 个对 `recorder_config.dart`（9 个经 `RecorderConfig` 的 getter、8 个经录制设置页的 `hiveBool`、2 个手工）；常量键 7 个都对过 |
| c4 范围 | 做了 | 76 个数值设置：注册表、3.x（启动修正和导入修正）、设置页三处都写了。14 个注册表比 3.x 宽，已改；4 个越界修法不同，开 J01.3 |
| c5 生效位置 | 做了 | 每行写了设置页以外的读取位置（最多 3 处）和生效时机（脚本按 `watchSetting`、`.watch(`、`== Settings.` 判断“立即”，监听列表和定时器的手工改）；抽查结果见 README“结果”。目录登记：`SettingsEntry.settings` 现在没有使用方（J01 说明里“已修改计数按它算”不对，已改正）；屏蔽页入口补登记 5 个过滤设置 |
| c6 处理 | 做了 | 改注册表 14 个设置的 `min`/`max`；目录 1 行的 `settings:`；开 J01.3。没有改默认值，没有要加的决定（3 个确认改动已有依据：UPGRADES X-1、A11.2 C-3、J02.1） |
| c7 测试 | 做了 | `packages/live_store/test/settings_defaults_test.dart` |

## 根因

- 弹幕和小窗弹幕的范围：J02.1 抄注册表时只照 3.x 的 `hive*` 默认值，3.x 的范围在 `onInit` 和 `parseConfig`/`extractConfig` 里（`danmaku_settings_controller.dart:115-127`、`:226-308`），小窗的只在导入时；注册表就漏了 `danmakuSpeed`、`danmakuFontSize`、`danmakuFontWeight` 的范围、`repeatedDanmakuWindowSeconds` 的上限和小窗的 8 个（`settings.dart` 原来的 `:428-434`、`:510-515`、`:552-584`）。界面的滑块是对的（A08 照 3.x 做的），所以只有存着越界值（3.x 数据、备份、手改）时才会读出 3.x 不会有的值，例如速度 0 让弹幕不动、小窗透明度 0 看不见。
- 小窗窗口宽高：3.x 的 `normalizePipGeometry`（`window_size_controller.dart:277-313`）夹到 0～16384，注册表没写。
- 越界修法：v4 的 `IntSetting` 只会夹紧，3.x 的几个设置是“回到默认值”或“取整到整百”（见 J01.3）。

## 改了哪些文件

- `packages/live_store/lib/src/settings/settings.dart`：14 个设置加 `min`/`max`（键名、默认值、`section`、`backupKey` 不变）。
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：`video_block_list` 行加 `settings:`。
- `packages/live_store/test/settings_defaults_test.dart`（新）、`packages/live_store/test/stores_test.dart`、`apps/pure_live/test/features/settings/settings_page_test.dart`。
- `tools/docs/settings_audit.py`、`tools/docs/settings_audit_notes.py`（新）。
- 文档：本文件夹的 `settings.md`（生成）、`README.md`、`record.md`；`docs/J-设置和数据/J01-设置/README.md`（已知问题、测试、路线）；J01.3 的 `README.md`、`brief.md`；`docs/tasks.toml`。

## 新设置、翻译键、门禁基线

- 没有新设置、没有翻译键、门禁基线不变。

## 测试

- 新增 6 个用例：`settings_defaults_test.dart` 4 个，`stores_test.dart` 1 个，`settings_page_test.dart` 1 个；先写、改之前失败（范围表、越界夹紧、目录登记三处），改了以后通过。
- `packages/live_store` 全部 54 个通过；`apps/pure_live` 全部 959 个通过。

## 真机上要看的

- 没有：没有改默认值；改范围只影响越界的存值，测试覆盖。

## 和其他任务的关系

- 同时在做的 K02.2、J06.2（账号、迁移报告）可能也动 `packages/live_store`；本任务只改 `settings.dart` 里 14 个设置的 `min`/`max`，不碰 `legacy/` 和 `secrets`。
- J01.3（第三档）：越界值按 3.x 回到默认值、弹幕粗细取整，需要给 `setting.dart` 的 `IntSetting` 加参数（本任务不能改）。
