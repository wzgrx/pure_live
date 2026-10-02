# R02.1 刷新率和帧率匹配

- 日期：2026-10-02
- 设计：[docs/R-性能和流畅度/R02-刷新率/R02.1-刷新率和帧率匹配/README.md](README.md)（第 1 版，用户已确认；I1～I3 按建议 A）
- 同批：D03.1、O05.1、D05.1、A08.4
- 改动的文件：`apps/pure_live/lib/platform/display_mode.dart`、`features/live_play/logic/room_refresh_rate.dart`（新）、`live_play_page.dart`、`features/settings/settings_catalog.dart`（一行设置）、`packages/live_player`（帧率）、`packages/live_store`（新设置）、`packages/live_ui`（一个图标）、Android `MainActivity.kt`、翻译
- `flutter build apk --debug` 通过（只编译，没有安装）

## 逐条对照

| 编号 | 做到 | 怎么做的 / 偏差 |
|---|---|---|
| c1 三档照旧 | ✅ | `AdaptiveRefreshRateController` 没动：默认省电、均衡 1.5 秒回落、进后台释放、画中画保持 |
| c2 新开关“播放时匹配视频帧率”，默认开 | ✅ | 设置键 `matchVideoFrameRate`（v4 新增，3.x 没有，不影响 3.x 数据）；行放在“通用 → 显示”紧跟“界面刷新率”（I3 选 A），只在 Android 显示 |
| c3 最高档、均衡档操作时用“视频帧率整数倍里最高” | ✅ | `playbackRefreshRate`：省电 0（系统选）；均衡不操作时整数倍里不超过 60 的（30/60 帧 60，25/50 帧 50），操作时整数倍里最高；最高档整数倍里最高（144 Hz 的屏看 60 帧用 120）。没有整数倍时照 v3 |
| c4 只在无缝时切换；暂停、退出、进后台撤掉 | ✅（有偏差） | Flutter 画面的 `Surface.setFrameRate(帧率, FIXED_SOURCE, CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)`；`RoomRefreshRate` 只在播放或缓冲中、开关开、前台或画中画（Flutter 报 inactive）时声明，暂停、关开关、进后台、离开直播间都撤掉。**偏差：只在 Android 12 起声明**（设计写 Android 11 起）：Android 11 的接口没有“只在无缝时切换”这个参数，可能黑一下，所以 11 只改“希望的刷新率” |
| c5 弹幕帧率跟着屏幕 | ✅ | 照 D03.1 的 c3：弹幕层用 `DisplayMode.info` 的当前刷新率算整数分之一，刷新率变了立即重算，速度不变 |
| c6 只有一个刷新率时开关变灰 | ✅ | 写“这台设备只有 60 Hz，用不上”（数字按设备） |

帧率来源：`MpvEngine` 每次打开后 2 秒读 mpv 的 `container-fps`，读不到（直播 FLV 常报 1000，当作没有）就每 2 秒读一次 `estimated-vf-fps`，两次相差 1% 以内才算，最多 4 次；放进 `PlaybackState.frameRate`，换线路、停止时清掉。23.976、29.97、59.94 归成 24、30、60。

## 新设置

| 键 | 类型 | 默认 | 3.x |
|---|---|---|---|
| `matchVideoFrameRate`（section `app`） | 开关 | 开 | 没有（新增），3.x 的设置键名和含义都没动 |

## 原生改动（`MainActivity.kt`）

- `setHighRefreshRate` 多一个可选参数 `refreshRate`：有它时窗口希望的刷新率取同分辨率里最接近它的模式（0 = 系统决定），没有时照 v3。
- 新方法 `setVideoFrameRate {fps}`：Android 12 起在 `FlutterActivity.FLUTTER_VIEW_ID` 下找到 Flutter 的 `SurfaceView`，对它的 Surface 声明帧率；0 清掉。显示变化、回到前台时重新声明（新 Surface 会忘掉）。
- 仍然只改刷新率提示，不指定显示模式 id（照 v3，避免厂商的重模式切换）。

## 测试

新增 6 个（`apps/pure_live/test/features/live_play/room_refresh_rate_test.dart`）：帧率归整和整数倍、三档的选法（4 个）、通道上发什么（声明帧率 + 希望的刷新率，撤掉时两个都清）、直播间（没帧率不发、播放发、改档位重发、画中画保持、后台撤掉、暂停撤掉、关开关撤掉、离开撤掉）。设置行 1 个（`test/features/settings/match_frame_rate_test.dart`：位置、只在 Android、默认开、一个刷新率时变灰和文字、能切换）。`packages/live_player` 新增 3 个（`container-fps` 优先且 1000 不算、估计值稳定才算且换了打开就不算、会话带上帧率且停止时清掉）。

## 没验证的

- K90 支持哪些刷新率、`FIXED_SOURCE` 声明和窗口“希望的刷新率”同时存在时系统怎么取舍（设计“拿不准”第 2 条）、进出直播间闪不闪屏、耗电：都要真机看（第 9.4 节）。
- `estimated-vf-fps` 等多久：现在最多 2 + 8 秒；FLV 直播实际要几秒稳定没量过。
- v4 的 Android 嵌入是 SurfaceView（默认渲染模式）时才能声明；如果以后改成 TextureView，只剩“希望的刷新率”。

## 合并时注意

- `settings_catalog.dart`：任务书说“只在 `settings_model.dart` 里加一行定义”，但设置行的定义都在 `settings_catalog.dart`（`settings_model.dart` 只有数据结构），所以这一行加在 `settings_catalog.dart` 的 `refresh_rate` 后面（一个 `..add(...)`，带变灰的写法），文件头多一个 `platform/display_mode.dart` 的导入。A11.3～A11.5 改设置页时请把它挪到新写法里。
- `packages/live_ui` 只加了图标 `AppIcons.matchFrameRate`。
