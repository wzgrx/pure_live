# J01.3 越界的设置值按 3.x 回到默认值：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（agent worktree），提交以 `[J01.3]` 开头
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 `IntSetting` 加参数 | 做了 | `packages/live_store/lib/src/settings/setting.dart:88-137`：`resetOutOfRange`（默认 `false`）越界时得 `defaultValue`；`step`（默认 1）夹紧后四舍五入到它的整数倍再夹一次（照 3.x `normalizeFontWeight` 的顺序）。都是常量默认值，其他 200 多个设置不变 |
| c2 6 个设置用上 | 做了 | `settings.dart`：`historyLimit`（`:138`）、`videoFitIndex`（`:272`）、`proxyPort`（`:881`）、`appProxyPort`（`:897`）加 `resetOutOfRange: true`；`danmakuFontWeight`（`:457`）、`pipDanmakuFontWeight`（`:595`）加 `step: 100`。键名、`section`、`backupKey`、默认值、`min`/`max` 都没改（D-018） |
| c3 对照表 | 做了 | `tools/docs/settings_audit_notes.py` 这 4 行改成“不一样，已改”，两个粗细的说明写上取整；`python3 tools/docs/settings_audit.py` 重新生成 [settings.md](../J01.2-设置项逐条核对/settings.md)：已改 18、待处理 0（其余行的变化是 master 上别的任务挪了读取位置的行号） |

## 根因

- `IntSetting.normalize`（原 `setting.dart:113-117`）只会夹到 `min`/`max`；3.x 对这几个设置的修法不是夹紧：
  - `historyLimit`：`v3.2.11:lib/common/services/settings/history_controller.dart:11-15` 负数回到 50（v4 夹成 0 = 不限）。
  - `videoFitIndex`：`player_settings_controller.dart:135-139` 越界回到 0“适应”（v4 把 7 夹成 5“缩小”）。
  - `proxyPort`、`appProxyPort`：`lib/core/common/proxy_routing.dart:9` 越界回到 7897（v4 夹到 1 或 65535）。
  - `danmakuFontWeight`、`pipDanmakuFontWeight`：`danmaku_settings_controller.dart:41-44` 夹紧后取整到整百（v4 不取整，550 存着，画的时候 `~/ 100` 截成 w500，设置页滑块也对不上）。
- 所有读法（`SettingsStore.get`、重新打开、`LegacySnapshot.fromHive`/`fromBackup`、`SettingsStore.set` 写入前的修正）都走 `Setting.read`/`normalize`，所以只改 `IntSetting` 一处。

## 改了哪些文件

- `packages/live_store/lib/src/settings/setting.dart`、`settings.dart`。
- `packages/live_store/test/stores_test.dart`：2 个用例。
- `tools/docs/settings_audit_notes.py`；J01.2 的 `settings.md`（生成）；`docs/J-设置和数据/J01-设置/README.md`（已知问题、路线、文件表的行号）。

## 新设置、翻译键、门禁基线

- 没有新设置、没有翻译键、门禁基线不变；`settings_defaults_test.dart` 的范围表不用改。

## 测试

- 新增 2 个，改之前都失败：
  - `J01.3: a whole number out of range goes back to the default, or rounds to its step`（新参数：回到默认值、只有下限时、取整 550 → 600、549 → 500、949 → 900、先夹再取整 49 → 100、字符串、没有新参数的照旧夹紧）：改之前编不过。
  - `J01.3: history limit, picture fit, proxy ports and danmaku weight out of range read as 3.x's`：6 个设置每个存越界值和边界值，`get`、重新打开后的 `get`、`LegacySnapshot.fromHive`、`LegacySnapshot.fromBackup`（v4 备份）都得 3.x 的结果。只撤回 `settings.dart` 时失败在第一条（`historyLimit` -1：期望 50，实际 0）。
- `packages/live_store` 全部 59 个通过；`apps/pure_live` 全部 988 个通过；两边 `dart analyze --fatal-infos` 无问题。

## 真机上要看的

- 不需要：只有存着越界值（坏数据、手改的备份）才会遇到，自动测试覆盖。

## 和其他任务的关系

- `localDanmakuFontWeight`（本地互动，400～900）不在本任务的 6 个里，3.x 读它时没有取整（`local_interaction_controller.dart:101` 的 `hiveInt`），v4 照旧只夹紧。
