# J01.3 越界的设置值按 3.x 回到默认值：任务书

## 背景

- 来源：J01.2 逐条核对（2026-10-08）。对照表 [settings.md](../J01.2-设置项逐条核对/settings.md) 里“不一样，待处理”的 `historyLimit`、`videoFitIndex`、`proxyPort`、`appProxyPort`，以及 `danmakuFontWeight`、`pipDanmakuFontWeight` 的取整。
- 现象：没有用户报告。存着的值越界时（3.x 的 Hive 数据、3.x 或 v4 的备份、手改的数据库），v4 把它夹到范围的一端，3.x 回到默认值或取整到整百。例：备份里 `historyLimit` 是 -1，3.x 得 50 条，v4 得“不限”。
- 为什么现在做：第三档；只有数据坏了才会遇到。D-018 要求含义不变。
- 已经做过的：J01.2 把 14 个数值设置的范围改成和 3.x 一样（`settings.dart`），加了 `packages/live_store/test/settings_defaults_test.dart`。

## 目标和验收

1. `historyLimit` 读到负数得 50；`videoFitIndex` 读到 0～5 以外得 0；`proxyPort`、`appProxyPort` 读到 1～65535 以外得 7897。
2. `danmakuFontWeight`、`pipDanmakuFontWeight` 读到的值四舍五入到整百再夹到 100～900（550 → 600，949 → 900）。
3. 上面这些对 `SettingsStore.get`、重新打开后的读取、`LegacySnapshot.fromHive`、备份导入都成立（它们都走 `Setting.read`）。
4. 其他设置的行为不变；`settings_defaults_test.dart` 不用改范围表。
5. J01.2 的对照表重新生成，这几行的结论改成“不一样，已改”。

## 现状（读代码得出，写文件:行）

- `packages/live_store/lib/src/settings/setting.dart`：`Setting.read`（`:59`）= `decode` → `normalize`；`IntSetting.normalize`（`:113`）只夹紧。
- `packages/live_store/lib/src/settings/settings.dart`：`historyLimit`（`min: 0`）、`videoFitIndex`（`0～5`）、`proxyPort`、`appProxyPort`（`1～65535`）、`danmakuFontWeight`、`pipDanmakuFontWeight`（`100～900`）。
- `packages/live_store/lib/src/rooms.dart:218`：设历史条数时负数已经换成默认值，只是读的时候没有。
- 画弹幕时粗细按 `~/ 100` 截断：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart:770`、`packages/live_ui/lib/src/widgets/pip_danmaku_preview.dart:170`。

## 3.x 基线

- `git show v3.2.11:lib/common/services/settings/history_controller.dart`：`normalizeHistoryLimit`（`:11-15`）。
- `git show v3.2.11:lib/common/services/settings/player_settings_controller.dart`：`normalizeVideoFitIndex`（`:135-139`）。
- `git show v3.2.11:lib/core/common/proxy_routing.dart`：`normalizeStoredProxyPort`（`:9`）。
- `git show v3.2.11:lib/common/services/settings/danmaku_settings_controller.dart`：`normalizeFontWeight`（`:41-44`），启动时 `:120`、`:124`，导入时 `:244`、`:275`。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；J01.2 的 `README.md` 和 `record.md`。

## 范围

- 可以改：`packages/live_store/lib/src/settings/setting.dart`（`IntSetting` 加可选参数）、`settings.dart`（只给这 6 个设置加参数）、`packages/live_store/test/`、`tools/docs/settings_audit_notes.py`、J01.2 的 `settings.md`（重新生成）、本文件夹。
- 不能改：任何键名、`section`、`backupKey`、`scope`、默认值、`min`/`max`（D-018）；`legacy/` 的迁移规则；界面；其他组的代码；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c2、c3 | `setting.dart`、`settings.dart`、测试、对照表 | 验收 1～5，门禁通过 |

## 测试

- 先写会失败的用例（`packages/live_store/test/stores_test.dart`）：`historyLimit` 存 -1 读出 50；`videoFitIndex` 存 7 读出 0；`proxyPort` 存 0 和 70000 读出 7897；`danmakuFontWeight` 存 550 读出 600、存 949 读出 900；每个也用 `LegacySnapshot.fromHive` 读一次。
- `setting.dart` 新参数的单元测试：回到默认值、取整、和 `min`/`max` 一起用。
- 测试不访问真实平台；没有定时器。

## 真机验证（维护者在 K90 上做）

不需要：只有坏数据才会遇到，自动测试覆盖。

## 风险和注意

- `IntSetting` 是 `const` 构造，新参数要有常量默认值，不影响现有 200 多个设置。
- 可能冲突的文件：`settings.dart`（新设置的任务都会加行）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter。
- 分支 `ai/J01.3` 或本机工作区；提交信息以 `[J01.3]` 开头（英文）；不推 master。
- 提交前：`packages/live_store` 跑 `dart format --output=none --set-exit-if-changed .`、`dart analyze --fatal-infos`、`dart test`；`apps/pure_live` 跑全部 `flutter test`（读设置的地方多）；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；可能冲突的文件。
