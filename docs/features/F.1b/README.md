# F.1b 竖屏流的画面比例预判

- 状态：开发中
- 档位：应该；规模：中
- 功能点：F-ROOM-22（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`packages/live_core`（`play_line.dart`、`live_site.dart`、抖音 `douyin_api.dart`，只添加字段）、`packages/live_player`（`state.dart`，只添加）、`features/live_play/`
- 依赖：—
- 来源：M7.1、M7.2“放到其他模块的部分”，M13.17 任务说明第 8 项
- 评审页：只把 v3 的行为补回来，按授权直接开发（X1 按 A）
- 记录：[records/F.1b.md](../records/F.1b.md)（开发后）

## v3 的行为（`~/ref/v3ref/lib`，v3.2.11）

| 行为 | 位置 |
|---|---|
| 只有抖音给提示（`resolve` 按平台分，其他平台 null） | `player/core/live_stream_geometry_hint.dart:31-37` |
| 按正在播的地址找回它的 sdk_key，依次取：`stream_data.data[key].main` 的 width/height → `sdk_params` 的 width/height → `sdk_params.resolution` → `options.qualities[sdk_key].resolution` → 是默认档时 `default_quality.resolution` | `:49-93` |
| 地址对不上任何档：不给提示（宁可没有，也不拿别的档的比例） | `:95-98` |
| 宽高要在 120～16384、比例 0.30～3.50 之间才算 | `:265-277` |
| 每换一个源（进房、换清晰度、换线路）都从“未知”开始，提示当作暂定值；解码器报了尺寸就以解码为准 | `player/core/player_manager.dart:830-857`、`:1396-1399`、`:2118` |
| 没选地址时用默认档或多数一致的比例（`:100-153`）——v3 的调用都带了地址，这段实际用不到 | 同上 |

## v4 现在

- `PlaybackState.isPortrait` 只看解码出的宽高，不知道时当 16:9（`packages/live_player/lib/src/state.dart:118-126`）；每次打开源都清空尺寸（`session.dart:426-440`）。
- 直播间按它决定竖屏排版（`features/live_play/live_play_page.dart:209-212`、`:315-317`）；应用内小窗、画中画同样（`mini/floating_window.dart:136-140`、`mini/room_mini_window.dart:102-105`）。
- 抖音解析读了 `sdk_params` 和 `options.qualities`，只拿来起清晰度名字（`douyin_api.dart:741-760`），线路（`LivePlayLine`，`play_line.dart:41-61`）没有宽高。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 抖音竖屏主播起播时先按 16:9 排版，第一帧出来才换成竖屏面板，画面跳一下 | 平台数据里的宽高没带到线路上（M7.1 留下），播放状态只有解码尺寸 |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | `LivePlayLine` 加可选的 `width`、`height`（只添加），`normalizePlayLines` 保留；抖音 `resolution()` 按 v3 的顺序和范围给每条线路填上它那一档的宽高（档是按 sdk_key 分的，所以“地址对得上”天然成立；对不上的线路不填） | P1 |
| c2 | 补上 | `PlaybackState` 加 `declaredAspectRatio`（正在打开或播放的线路声明的比例，停止后不算）、`expectedAspectRatio`（解码优先）、`expectsPortrait`（只添加，`isPortrait` 不变） | P1 |
| c3 | 补上 | 直播间、应用内小窗、画中画、桌面小窗改用 `expectsPortrait` / `expectedAspectRatio`：第一帧之前按平台的宽高排版，解码器报了尺寸以解码为准 | P1 |

## 需要选的

- X1 哪些平台给宽高：**A（建议，按 A 做）只有抖音**，照 v3；B 加上 TikTok（`sdk_params.resolution` 同样有，但海外平台在 K90 上要开代理才能验证，v3 也没有）。

## 测试和验证

- `live_core`：竖屏样本（`S04-enter-live-portrait`）每档线路带 1088×1920 等；横屏样本 1920×1080；游戏样本原画没写分辨率 → 不填；`sdk_params` 里的 width/height 优先于 resolution；超范围不填；对不上档的地址不填。
- `live_player`：线路声明的比例在打开时生效、解码尺寸覆盖它、停止后不算。
- 直播间：竖屏线路在第一帧之前就是竖屏面板；声明竖屏但解码是横屏时换回横屏。
- K90：TASKS 第 5 节 5.1 第 8 条（进抖音竖屏主播，起播时不跳）。

## 风险和性能

- 只多两个整数字段，不加定时器和后台任务；3.x 的设置和数据不变。
- 平台声明错了：第一帧到了就以解码为准，最多和现在一样跳一次。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比；X1 按 A（只有抖音） |
