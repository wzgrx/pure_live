# C01.4 直播间清晰度显示平台实际给的档

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：H01.3 记录“没做的”第 1 条（[记录](../../../H-录制/H01-录制核心/H01.3-合并进度/record.md)）：录制已经改成按平台确认的编号命名实际画质，“直播间播放遇到‘确认的编号不在列表里’仍显示‘原画?’（`resolveAppliedPlayQuality` 不变，`room_controller.dart` 不在本任务目录）”。V03.3 核对时发现没有任务管它。
- 相关：H01.3（录制的 `servedQuality`）；E06.1 c5（`LivePlayUrlResolution.appliedQuality`）；E06.2 的“实际清晰度”阶段（刷新后显示新档，改同一处，最好一起做）；升级 C-4（“按平台实际给的画质显示并提示”）

## 目标

哔哩哔哩游客请求“原画”、平台实际给“超清”（编号 250）而列表里只有“原画”时，直播间的清晰度按钮和菜单显示“超清”，并提示一次“平台实际返回 超清，已按真实画质播放”；和同一个直播间里录制面板、录制通知写的“超清”一致。现在直播间显示“原画?”，录制显示“超清”，同一路流两个说法。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 播放时的画质名 | `common/utils/play_quality_label.dart:6-8`：平台没确认时显示“未确认 · 原画”；`modules/live_play/widgets/video_player/video_controller_panel.dart:1224` | `packages/live_core/lib/src/live_site.dart:223-239` 的 `resolveAppliedPlayQuality`：确认的编号在列表里 → 那一项；是 `appliedQuality` → 它；否则请求的那项并标未确认；直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:491`、多画面 `features/multiview/logic/multiview_controller.dart:592` 调它；菜单在 `buttons/stream_menu.dart:51` 给未确认的加“?” | 确认的编号不在列表里时按平台编号命名（“超清”），算确认 |
| 录制时的画质名 | `recorder/pages/recorder/recorder_controller.dart:905`：`playbackLabel`（“未确认 · 原画”） | `packages/live_record/lib/src/resolver.dart:334-350` 的 `RecordStreamResolver.servedQuality`：同样的情况用 `LiveQualityLabel.normalize(platform:, id:)` 命名（H01.3） | 直播间和录制用同一个规则 |
| 画质受限的提示 | 无 | 直播间只在用户自己点的档和实际不同、且实际档在列表里时提示（`room_controller.dart:492-497`，`quality_limited_to`）；录制提示一次（H01.3 c2） | 直播间进房时实际档和请求不同也提示一次 |

## 方案

- c1 把 `servedQuality` 的规则搬到 `live_core`（例如 `live_site.dart` 里 `resolveServedPlayQuality({platform, qualities, requested, resolution})`，内部先调 `resolveAppliedPlayQuality`），`live_record` 的 `servedQuality` 改成调它（行为不变，H01.3 的测试照旧通过）。
- c2 直播间 `_openQuality`（`room_controller.dart:462-530`）和多画面（`multiview_controller.dart:592`）改用新函数；实际档不在列表里时把它放进 `_qualities[playing]`（现在的写法 `:497` 已经是替换那一项），按钮和菜单就显示“超清”。
- c3 提示：进房（`userChoice: false`）时实际档和请求不同也提示一次，文字用已有的 `quality_limited_to`；同一个直播间只提示一次（重连、刷新不再提示，照 H01.3 的规则）。

## 性能任务：测量

无：显示逻辑，不涉及性能。

## 验证

- 自动测试：`packages/live_core/test/` 加新函数的用例（编号在列表里、不在列表里、平台没确认、`appliedQuality`）；`apps/pure_live/test/features/live_play/` 用哔哩哔哩游客样本（`fixtures/bilibili/S07-guest-qn10000`，以及 H01.3 用过的“`qn=0` 只列 10000、请求 10000 给 250”的改写样本）进房，断言清晰度按钮是“超清”、提示一次。
- 真机：待真机（brief 的真机步骤）。

## 留下的问题

- E06.2 的“实际清晰度”阶段（`_refreshPlan` 恢复后更新显示）和本任务改同一段代码，先做哪个都行，后做的要合并对方的改动。
