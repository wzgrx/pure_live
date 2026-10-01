# F.1b 竖屏流的画面比例预判

- 日期：2026-10-02
- 任务：[F.1b/README.md](../F.1b/README.md)
- 改动：`packages/live_core`（`play_line.dart`、`live_site.dart`、`sites/douyin/douyin_api.dart`）、`packages/live_player`（`state.dart`）、`features/live_play/`（`live_play_page.dart`、`logic/mini_window.dart`、`mini/floating_window.dart`、`mini/room_mini_window.dart`、`player/player_view.dart`）

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 线路带宽高 | ✅ | `LivePlayLine` 加可选 `width`、`height` 和 `declaredAspectRatio`；`normalizePlayLines` 保留。抖音 `DouyinApi.pictureSize` 照 v3 的顺序：`main` 的 width/height → `sdk_params` 的 width/height → `sdk_params.resolution` → `options.qualities[]` 的 resolution → 是默认档时 `default_quality.resolution`；120～16384、比例 0.30～3.50 之外不算。同 URL 的别名档（如 `uhd` → `full_hd1`）把宽高并给留下的那档。按 `quality.data` 播的未知档不填 |
| c2 播放状态 | ✅ | `PlaybackState.declaredAspectRatio`（只在打开、播放、暂停、出错时，停止和空闲不算，正在播的是线路时才有）、`expectedAspectRatio`（解码优先）、`expectsPortrait`；`isPortrait` 不变 |
| c3 直播间用它 | ✅ | 直播间的竖屏判断、应用内悬浮窗、画中画（进入和自动进入）、桌面小窗、“均衡”模式的缩放都改用预判；解码器报了尺寸以解码为准 |

X1 按 A：只有抖音（照 v3）。

## 根因

M7.1 搬抖音解析时 `sdk_params`、`options.qualities` 只拿来起清晰度名字，宽高没有放到线路上；`live_player` 的 `PlaybackState` 只有解码尺寸，打开源时清空，第一帧前一律当 16:9。

## v3 → v4

`player/core/live_stream_geometry_hint.dart` → `DouyinApi.pictureSize`（按档算，每档的线路都带上，天然满足 v3“地址对得上才给”的规则）；`player_manager.dart:830-857` 的“提示当暂定值，解码为准” → `PlaybackState.expectedAspectRatio`。v3 没选地址时的默认档、多数一致回退（`:100-153`）实际用不到，没搬。v3 的稳定计时、置信度不搬（v4 没有那套识别器）。

## 设置

无。

## 测试

- `packages/live_core`：2 个（三个录制样本每档的宽高、别名档、未知档不填、规范化保留；v3 的取值顺序和范围）。
- `packages/live_player`：1 个（打开时用线路声明、解码覆盖、停止后不算、没声明的线路没有）。
- 直播间（`test/features/live_play/room_extras_test.dart`）：2 个（声明竖屏时第一帧前就是竖屏面板、解码横屏后换回 16:9；不声明时照旧）。

## 要在 K90 上看的

TASKS 第 5 节 5.1 第 8 条：进抖音竖屏主播，起播时直接是竖屏面板，第一帧出来时不跳。顺便看横屏主播、游戏直播（原画没写分辨率）起播仍是横屏。

## 合并时注意

- `LivePlayLine` 加了两个可选参数：别的包自己 `new LivePlayLine(...)` 复制线路的地方（`room_controller.dart` 的 `_iptvLine`、`live_media` 的 FC2 配方）不带宽高，这些平台本来就没有，不影响。
- `PlaybackState.isPortrait` 没改；以后新加的布局判断请用 `expectsPortrait`。
