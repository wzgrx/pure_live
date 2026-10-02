# R02.2 记录：刷新率——播放中统一用帧率声明、没有整数倍时取最高、厂商限制提示

- 任务单：[tasks/P01.md](brief.md)；依据：[调研报告](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 1 节（R1～R4、R6）
- 日期：2026-10-02；本地 worktree 任务（不建 `cloud/` 分支、不推送、不开 PR），基于 master `3c1aa45ee`
- 新旧策略对比已写进 [R02.1 README 的“4.0.x 修订”](../R02.1-刷新率和帧率匹配/README.md#40x-修订p012026-10-02)

## 逐条对照

| 条 | 做了没有 | 说明 |
|---|---|---|
| c1 R1 | 做了 | 播放中只在 Flutter 画面上声明（Android 12+，`FIXED_SOURCE`，只在无缝时切换），窗口提示清零；均衡档操作中声明整数倍里最高（K90 60 帧 → 120），松手 1.5 秒后回到空闲值（60）。不播放时：均衡档操作中和最高档，Android 16+ 用 `setFrameRate(最高, AT_LEAST)`、窗口提示清零；8～15 保留窗口提示。`setVideoFrameRate` 和 `setHighRefreshRate` 合成一次调用，原生只剩一个 `applyRefreshRate` |
| c2 R2 | 做了 | `playbackRefreshRate` 不再返回 null：没有整数倍取设备最高（K90 25/50 帧 → 120）；24 帧在 K90 上唯一的整数倍是 120，空闲也取它（均衡空闲的规则补了一句：没有 ≤60 的整数倍就取最低的整数倍）。显示器换了（支持的刷新率变了）时播放中会重新选 |
| c3 R3 | 做了 | `DisplayMode.limited`：请求 ≥90 Hz、用户在操作、`currentRefreshRate` ≤60 连续 3 秒，再读一次确认后打开；看到当前刷新率 >60 就关。设置“界面刷新率”那一行下面出现“系统把本应用限制在 60 Hz，可以在系统设置 → 显示 → 屏幕刷新率里调高”（中英文），省电档不显示 |
| c4 R4、R6 | 做了 | 本来就只投具体数值；新测试检查清单里没有 `appCategory`/`isGame`，Kotlin 里没有 `FRAME_RATE_CATEGORY`、`setRequestedFrameRate`、`setFrameRateCategory` |
| c5 | 做了 | R02.1 README 末尾加“4.0.x 修订”：为什么改、新旧对比表、K90 上的表、手感和耗电的变化 |

### 偏差和原因

1. **c3 只在用户操作时计时（最高档也一样）。** 任务单写“均衡档操作中或最高档时”。最高档时请求一直是高的，但画面静止时不少机型的系统会因为空闲把刷新率降到 60（SurfaceFlinger 空闲计时器），这不是厂商限制；不加“在操作”这个条件，最高档用户停在设置页 3 秒就会看到误报。现在的“操作”是：手指按着，或者松手后 1.5 秒内（和均衡档回落时间一样），全局指针事件判断。
2. **c3 提示不在省电档显示。** 省电档不请求高刷新率，提示没有意义；标记本身保留，切回均衡或最高时如果还是限制状态会再出现。
3. **Android 8～11 播放中保留窗口提示。** 任务单说“播放中只用 `Surface.setFrameRate` 声明”。11 的 `setFrameRate` 不能指定“只在无缝时切换”，R02.1 就是因此只在 12+ 声明；这里不变，避免进出直播间黑屏。
4. **顺带修了一个回归：** 今天的 `00f5edf18`（“930 unused keys removed”）把 `refresh_rate_power_saving_desc` 等三条说明当成没用的键删了，因为代码里是拼出来的键名（`'${label}_desc'`）。结果“界面刷新率”对话框里每个选项下面显示的是键名本身。现在代码里写完整键名，文字恢复 v3 原文（中英文），加了测试。

## 根因

- **R1**：Android 文档写明，用 `Surface.setFrameRate` 声明过帧率的 Surface 会忽略窗口的 `preferredRefreshRate`。R02.1 播放时在 Flutter 画面上声明了视频帧率，均衡档操作时又把窗口提示改成“整数倍里最高”，后者对 Flutter 画面无效，操作时能不能到 120 只取决于系统的触摸加速（K90 1.5 秒）。
- **R2**：K90 只有 60/90/120 Hz，25/50 帧没有整数倍，24 帧只有 120；`playbackRefreshRate` 在这时返回 null 交给系统，系统多半给 60，25 帧 2、3 交替。
- **R3**：HyperOS 有 `PRIORITY_MIUI_REFRESH_RATE` 投票（`mAlwaysRespectAppRequest=false`），应用压不过；以前没有任何地方读回当前刷新率来判断。
- **R4**：K90 `frameRateCategoryRate high=90`，按类别投票只会到 90；我们一直投数值，这次加了防回退的测试。

## 改了哪些文件

- `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`：`applyPreferredDisplayMode` + `applyVideoFrameRate` → `applyRefreshRate` + `applySurfaceFrameRate`；通道 `setHighRefreshRate {enabled, frameRate?, refreshRate?}`，去掉 `setVideoFrameRate`
- `apps/pure_live/lib/platform/display_mode.dart`：新的 `playbackRefreshRate`；`_applyRate` 一次调用；`limited` 检测（全局指针事件、3 秒计时、再读一次确认）；换显示器时重新选
- `apps/pure_live/lib/features/settings/settings_editors.dart`：`RefreshRateTile` 下面的限制提示；选项说明用完整键名
- `apps/pure_live/assets/translations/zh.json`、`en.json`：4 个键
- 测试：`test/features/live_play/room_refresh_rate_test.dart`（改）、`test/platform/display_mode_test.dart`（新）、`test/features/settings/refresh_rate_limited_test.dart`（新）
- 文档：`docs/R-性能和流畅度/R02-刷新率/R02.1-刷新率和帧率匹配/README.md`（4.0.x 修订）、本记录
- `features/live_play/logic/room_refresh_rate.dart` 不用改（它只把“播什么、什么档”交给 `DisplayMode.setPlayback`）

## 新设置和翻译键

- 新设置：无（`refreshRateMode`、`matchVideoFrameRate` 的键名、含义、默认值都不变）。
- 新键：`settings_refresh_rate_limited`（带 `{rate}`）。
- 恢复的键：`refresh_rate_power_saving_desc`、`refresh_rate_balanced_desc`、`refresh_rate_performance_desc`（v3 原文）。

## 测试

新增和改动的测试共 20 个（新增 14 个）：

- `room_refresh_rate_test.dart`（12，原来 6）：24/25/30/50/60 帧 × 60/90/120、60/120/144、60/90/120/144/165 Hz 的表（均衡空闲、均衡操作中、最高、省电）；没有整数倍取最高；通道参数（播放、操作、松手回落、停止；省电声明视频本身；换显示器重新选）。
- `platform/display_mode_test.dart`（6，新）：操作中 60 Hz 满 3 秒才提示、再读一次确认、恢复后消失、显示变化的报告立刻关掉；画面静止或只点一下不误报；均衡档 3 秒内松开、请求只有 60 时不提示；清单里没有 `appCategory`/`isGame`，Kotlin 里没有帧率类别。
- `features/settings/refresh_rate_limited_test.dart`（2，新）：提示的出现和消失（均衡、最高显示，省电不显示，刷新率 >60 后消失）；对话框三个选项显示说明文字而不是键名（改之前会失败：键已被删）。

跑过的检查（本地任务，没跑完整门禁）：

- `apps/pure_live`：`dart format --output=none --set-exit-if-changed .` 通过；`dart analyze` 无问题；`flutter test` 全部 755 个通过。
- 根目录 `python3 tools/gate/check_ui_structure.py` 通过（颜色用 `LiveSemanticColors.warning`，没有新增直接写的颜色和图标）。
- Kotlin 没有单元测试，靠下面的真机步骤验证。

## 手感变化（前后对比）

| 情况 | 以前 | 现在 |
|---|---|---|
| 均衡档看 30/60 帧，拖聊天、面板 | 画面声明 30/60 + 窗口提示 120（对画面无效），靠系统触摸加速 | 画面声明 120，松手 1.5 秒回 60 |
| 均衡档看 24/25/50 帧，不操作 | 交给系统（多半 60，2、3 交替） | 120（25 帧 5、5、5、5、4），更匀，更耗电 |
| 144/165 Hz 屏，25/50 帧 | 交给系统 | 设备最高（144/165），更耗电 |
| 不播放，均衡档触摸、最高档（Android 16+） | 窗口提示最高 | 画面 `AT_LEAST 最高` |
| 省电档、最高档看 30/60 帧 | — | 不变 |

## 要在 K90 上看的（维护者做）

准备：装这次的 debug 包；开发者选项打开“显示刷新率”；`adb -s 192.168.1.2:5555 shell` 可用。

1. **均衡档播 60 帧直播（c1）**
   - 设置 → 通用 → 界面刷新率选“均衡”，“播放时匹配视频帧率”开着。进一个 60 帧直播间（B 站、斗鱼的直播一般是 60 帧；面板“统计信息”里能看到帧率）。
   - 不操作：右上角显示 60。
   - 拖聊天列表或竖屏面板：100 ms 内到 120；松手约 1.5 秒回 60。
   - 进出直播间各三次：不黑屏、不闪。
   - 操作中和不操作时各截一份：
     ```
     adb shell dumpsys SurfaceFlinger | grep -E "renderRate|activeMode="
     adb shell dumpsys display | grep -iE "mVotes|PRIORITY_|appRequest" -A2
     ```
     看 Flutter 画面（`SurfaceView[com.mystyle.purelive/...]`）那一层的投票：不操作时 60 `ExplicitExactOrMultiple`，操作时 120；窗口的 `preferredRefreshRate` 是 0。截图或文字贴进本记录下面的“实测”。
   - 想分清是我们的声明还是系统触摸加速：root 下 `setprop debug.sf.set_touch_timer_ms 0` 后重启 SurfaceFlinger（`stop; start`）再看一遍，测完恢复。没有 root 就看 `dumpsys SurfaceFlinger` 里那一层的投票值。
2. **24/25/50 帧（c2）**：网络电视导入一个 25 帧或 50 帧的源（或按报告 1.7 用 ffmpeg 生成带帧号的 HLS），均衡档不操作时右上角是 120，不是 60。
3. **不播放的页面（c1，Android 17 走 `AT_LEAST`）**：均衡档在首页列表上滑动，到 120；停 1.5 秒回落。最高档：在前台一直 120（静止时 HyperOS 可能自己降，属于系统行为）。`dumpsys SurfaceFlinger` 里 Flutter 那一层是 `ExplicitGte`（或 AT_LEAST 字样）120。
4. **限制提示（c3）**：系统设置 → 显示 → 屏幕刷新率改成“标准”（60）。回到应用，均衡档在设置页上下滑动 3 秒以上，“界面刷新率”下面出现黄色的“系统把本应用限制在 60 Hz……”。改回“高”，回到应用再滑一下，提示消失。省电档不显示这行。
5. **对话框**：点“界面刷新率”，三个选项下面是中文说明，不是 `refresh_rate_..._desc`。
6. **顺带观察**：HyperOS 看视频时会不会按场景把上限压到 60（报告 1.3 的推测）。如果均衡档播放中拖面板仍是 60，而列表页能到 120，就是这种情况，限制提示会在播放时出现——记下来，再决定提示的文字要不要区分“播放时”。

## 原生部分

`flutter build apk --debug --target-platform android-arm64`（WSL，compileSdk 37）编译通过，之后 `./gradlew --stop`。`FRAME_RATE_COMPATIBILITY_AT_LEAST` 和 `Build.VERSION_CODES.BAKLAVA` 都是 API 36，调用处已按版本判断。没有装到手机上。

## 需要维护者决定的

- 均衡档空闲时 25/50 帧在 144/165 Hz 屏上会一直用 144/165（规则“没有整数倍取最高”），比 60 明显耗电。如果嫌费电，可以改成“空闲时没有整数倍取不超过 120 的最高”，K90 不受影响。
- c3 只在操作时计时（偏差 1）。
- 顺带恢复的三条选项说明用的是 v3 原文（提到弹幕上限 60/30 FPS，和 v4 `resolvedDanmakuFps` 一致）。
