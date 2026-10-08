# H01.7 录映客默认录的是 HEVC 的“原画”，不看“优先 H.264”

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：[G01.3 记录](../../../G-播放/G01-引擎/G01.3-映客默认播HEVC/record.md)“录制选档”
- 相关：[G01.3](../../../G-播放/G01-引擎/G01.3-映客默认播HEVC/README.md)（播放这边同样的规则）

## 目标

开着“优先 H.264”（默认开）时，录制和播放一样：任务没指定清晰度，就不先录 HEVC 档，只要房间还有别的档。

## 3.x 和现状

| 方面 | 现在 | 要做到 |
|---|---|---|
| 选档 | `packages/live_record/lib/src/resolver.dart:296-324` `orderQualities` 先按平台的 `sort` 排（映客“原画”`sort: 1`、FLV `0`），再按名字找录制偏好（默认“原画”），不看“优先 H.264”。映客的“原画”只有即构的 HEVC 线路，存成 FLV（codec 12，不是标准写法），别的播放器多半打不开 | 跳过 HEVC，取最近的别的档（同样近取更好的一档）；只剩 HEVC 时照录 |
| 手动选档 | 录制面板“这次录制”选了清晰度（`qualityOverride`）就按选的录 | 不变：手动选了 HEVC 照录 |
| 面板显示 | “这次录制”默认显示的清晰度来自同一个排序（`record_state.dart` `recordDefaultQuality`） | 跟着变，显示实际会录的档 |
| 3.x | 没有编码提示，也不看“优先 H.264” | — |

## 方案

- `orderQualities(…, preferH264:)`：选出排第一的档之后，若是 HEVC 且开着，就换成最近的非 HEVC 档（和 `apps/pure_live/lib/shared/rooms/play_quality.dart` `defaultQualityIndex` 同一规则）。
- `RecordSettings.preferH264`（取自 `Settings.preferH264`，默认开）；录制器三处 `resolve` 都传 `task.qualityOverride == null && settings().preferH264`。

## 验证

- 自动测试：`packages/live_record/test/recorder_test.dart`（排序、录制器选线）、`apps/pure_live/test/features/live_play/live_play_popups_test.dart`（面板默认档）。
- 真机：K90 映客开了原画的直播间，录制面板“这次录制”显示 FLV；录 1 分钟停止，MP4 用系统播放器能放（H.264）；面板手动选“原画”再录，录到的是 HEVC。
