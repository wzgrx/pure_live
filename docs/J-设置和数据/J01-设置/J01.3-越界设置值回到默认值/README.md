# J01.3 越界的设置值按 3.x 回到默认值：历史条数、画面比例、代理端口，弹幕粗细取整

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：J01.2 逐条核对（[对照表](../J01.2-设置项逐条核对/settings.md)里“不一样，待处理”的 4 行和 `danmakuFontWeight` 的取整）
- 相关：J01.2；决定 D-018（含义不变）；任务书 [brief.md](brief.md)

## 目标

存着的值（3.x 的数据、3.x 或 v4 的备份、手改的数据库）超出范围时，修成 3.x 修成的值。现在 v4 的数值设置一律夹到 `min`/`max`，而 3.x 对下面几个是“回到默认值”或“取整到整百”，结果不同。只有数据本身坏了才会遇到，所以排第三档。

## 3.x 和现状

| 设置 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| `historyLimit` | 负数回到 50（`lib/common/services/settings/history_controller.dart:11-15`，启动时 `:73`） | 夹到 0，也就是“不限”（`settings.dart` 的 `historyLimit`，`min: 0`）；只有经 `rooms.dart:218` 写入时负数才变 50 | 读到负数得 50 |
| `videoFitIndex` | 不在 0～5 时回到 0“适应”（`player_settings_controller.dart:135-139`） | 夹到 0 或 5（7 变成 5“缩小”） | 越界得 0 |
| `proxyPort`、`appProxyPort` | 不在 1～65535 时回到 7897（`lib/core/common/proxy_routing.dart:9`） | 夹到 1 或 65535 | 越界得 7897 |
| `danmakuFontWeight`、`pipDanmakuFontWeight` | 夹到 100～900 后四舍五入到整百（`danmaku_settings_controller.dart:41-44`，550 → 600） | 夹到 100～900（J01.2），不取整；画的时候 `~/ 100` 截断（`danmaku_overlay.dart:770`，550 → w500），设置页滑块的名字查不到 550 | 读出来就是整百 |

## 方案

- c1 `packages/live_store/lib/src/settings/setting.dart` 的 `IntSetting` 加两个可选参数：越界时回到默认值（而不是夹紧），和取整的步长（`step: 100` 时四舍五入到整百再夹）。`DoubleSetting` 不用改。
- c2 `settings.dart` 里这 6 个设置用上新参数（键名、默认值、范围不变）。
- c3 J01.2 的对照表重新生成（`python3 tools/docs/settings_audit.py`），把 `tools/docs/settings_audit_notes.py` 里这几行的结论改成“不一样，已改”。

## 验证

- 自动测试：`packages/live_store/test/stores_test.dart` 加用例：每个设置存一个越界值，`get`、重新打开后的 `get`、`LegacySnapshot.fromHive` 都得 3.x 的结果；`setting.dart` 的单元测试覆盖两个新参数。`settings_defaults_test.dart` 的范围表不变。
- 真机：不需要（只有坏数据才会遇到）。

## 留下的问题

- 无。
