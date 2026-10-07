# R02 刷新率

30～240 Hz 屏幕上应用用什么刷新率：“界面刷新率”三档（省电 / 均衡 / 最高）怎么请求、播放中怎么按视频帧率选（帧率匹配）、系统把应用压在 60 Hz 时怎么提示，以及 Android 原生一侧怎么把请求交给系统。

## 范围

- 包括：
  - `packages/live_ui/lib/src/widgets/refresh_rate.dart`：`RefreshRateMode`、`AdaptiveRefreshRateController`（三档的规则：均衡档按下和滚动时最高，停下 1.5 秒回落，进后台释放）、`AdaptiveRefreshRateScope`（把指针、滚动、生命周期喂给控制器）。
  - `apps/pure_live/lib/platform/display_mode.dart`：`DisplayModeInfo`、`PlaybackRefresh`、`normalizeFrameRate`、`frameRateMultiples`、`playbackRefreshRate`（播放中的选法）、`DisplayMode`（通道 `pure_live/display_mode`、`limited` 限制检测）。
  - `apps/pure_live/lib/features/live_play/logic/room_refresh_rate.dart`：`RoomRefreshRate`（直播间把“播什么、什么档”交给 `DisplayMode`）。
  - Android `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt` 的 `applyRefreshRate`、`applySurfaceFrameRate`、`displayModeInfo`；清单不声明 `appCategory=game`。
  - 设置 `refreshRateMode`（3.x 键，旧的 `enableHighRefreshRate` 迁移成它）、`matchVideoFrameRate`（4.x 新加）的行为；设置“界面刷新率”一行下面的限制提示的显示条件。
- 不包括（归哪里）：
  - 设置页里两行和对话框的样子 → A11.1；直播间、小窗、画中画里刷新率怎么交接（画中画保持）的系统部分 → O05（O05.1 常亮、刷新率在同一子分类的另一面）。
  - 视频帧率从哪来（`MpvEngine` 读 `container-fps`、`estimated-vf-fps`）→ [G01](../../G-播放/G01-引擎/README.md)；弹幕帧率取刷新率的整数分之一 → D03.1、D05.1。
  - 刷新率对耗电的影响的测量 → [R05](../R05-耗电/README.md)；帧时间 → [R01](../R01-基准和测量/README.md)。
  - Windows、Linux、macOS 只读显示器刷新率（不改系统设置）→ X 组；电视的“匹配内容帧率” → X03、A17。

## 现状：做到哪、怎么工作的

- 用户看得到的（Android）：
  - 设置 → 通用 → 显示：“界面刷新率”（省电默认 / 均衡 / 最高，行上显示“当前 / 最高 Hz”），下面是“播放时匹配视频帧率”（默认开；设备只有一个刷新率时变灰，写“这台设备只有 60 Hz，用不上”）。系统把应用压在 60 Hz（请求 ≥90 Hz、用户在操作、当前 ≤60 连续 3 秒并再读一次确认）时，“界面刷新率”下面出现黄色提示“系统把本应用限制在 60 Hz，可以在系统设置 → 显示 → 屏幕刷新率里调高”，省电档不显示，恢复后消失。
  - 不播放时：省电交给系统；均衡档按下、滚动时最高，松手 1.5 秒回落；最高档在前台一直最高。
  - 播放中（开着帧率匹配、前台或画中画、播放或缓冲）：按 D-010——省电档只声明视频本身的帧率、系统选；均衡档空闲时取不超过 60 的整数倍（30/60 帧 → 60），操作中和最高档取整数倍里最高（K90 上 60 帧 → 120）；没有整数倍时取设备最高（K90 上 24/25/50 帧 → 120）。暂停、离开直播间、进后台、关开关时撤掉声明。
- 内部怎么工作：
  1. 应用 `app/app.dart:66` 建 `AdaptiveRefreshRateController(applyHighRefreshRate)`，`:236` 用 `AdaptiveRefreshRateScope` 包住整个应用（Android）；控制器把“要不要高刷”排队交给 `DisplayMode.applyHighRefreshRate`（`display_mode.dart:250`），同一时刻只发最新的请求。
  2. 直播间 `live_play_page.dart:235` 建 `RoomRefreshRate(session:, settings:)..start()`：听会话状态、两个设置和生命周期，算出 `PlaybackRefresh(frameRate, mode)` 或 null，变了才发（`room_refresh_rate.dart:49-64`）→ `DisplayMode.setPlayback`（`display_mode.dart:260`）。
  3. `DisplayMode._applyRate`（`:279-299`）：没有播放时只发 `{enabled}`；播放中按 `playbackRefreshRate`（`:142-148`）算出声明值，发 `{enabled, frameRate, refreshRate}`（省电档 `frameRate` 是视频本身的帧率）。
  4. 原生 `applyRefreshRate`（`MainActivity.kt:784-840`）：播放中 Android 12+ 只在 Flutter 的 `SurfaceView` 上 `setFrameRate(rate, FIXED_SOURCE, CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)`，窗口提示清零（Android 文档：声明过帧率的画面会忽略窗口提示）；Android 8～11 用窗口的 `preferredRefreshRate`；不播放、要高刷时 Android 16+ 声明 `AT_LEAST` 最高、8～15 用窗口提示；其余全部清掉。只改刷新率提示，不指定显示模式 id（3.x 的经验：厂商的重模式切换）。返回 `displayModeInfo`（`:875`）。
  5. 显示变化（换显示器、改分辨率）时原生报 `displayModeChanged`，`DisplayMode.publish`（`:220`）在支持的刷新率变了时重新选；`limited` 只在用户操作（按着或松手 1.5 秒内）时计时（`_watchPointers` `:301`、`_checkLimit` `:327`、`_confirmLimit` `:339`）。
- 完成度（和 3.x 对照）：
  - 一致：三档和默认省电、1.5 秒回落、进后台释放、画中画保持；只改刷新率提示不指定模式 id。
  - 确认过的改动：R02.1（帧率匹配、开关、只有一个刷新率时变灰；I1～I3 按建议 A）；R02.2（播放中只用帧率声明、没有整数倍取最高、限制提示、只投数值不投类别，D-010）；顺带恢复了被误删的三条档位说明（翻译键，D-016 的起因之一）。
  - 还缺：**两个任务都没有 K90 结果**（R02.1 登记“完成”，但它的真机项和 R02.2 一起在 R02.2 的 verify.md 里）；R02.2 待真机。

## 代码地图

| 文件 | 职责 |
|---|---|
| `packages/live_ui/lib/src/widgets/refresh_rate.dart` | `RefreshRateMode`（`:7`）、`AdaptiveRefreshRateController`（`:29`，`settleDelay` 1.5 秒 `:35`、`beginPointer`、`keepInteractive`、`endPointer`、`endScroll`、`pause`、`resume`、请求合并 `_request`/`_drain`）、`AdaptiveRefreshRateScope`（`:137`） |
| `apps/pure_live/lib/platform/display_mode.dart`（376 行） | `DisplayModeInfo`（`:12`）、`PlaybackRefresh`（`:92`）、`normalizeFrameRate`（`:111`）、`frameRateMultiples`（`:118`）、`playbackRefreshRate`（`:142`）、`DisplayMode`（`:171`：`limitDelay` 3 秒 `:179`、`info`、`limited`、`publish` `:220`、`applyHighRefreshRate` `:250`、`setPlayback` `:260`、`_applyRate` `:279`、指针和限制检测 `:301-356`、`refresh` `:375`） |
| `apps/pure_live/lib/features/live_play/logic/room_refresh_rate.dart`（77） | `RoomRefreshRate`（`:13`）：`start`（`:32`）、`_update`（`:49`，播放或缓冲、前台或画中画、非纯音频、有帧率）、`dispose`（`:67`） |
| `apps/pure_live/lib/app/app.dart` | `AdaptiveRefreshRateController`（`:66`）、`AdaptiveRefreshRateScope`（`:236`） |
| `apps/pure_live/lib/features/settings/settings_editors.dart` | `RefreshRateTile`（`:901`，当前 / 最高、限制提示、档位说明用完整键名） |
| `apps/pure_live/lib/features/settings/settings_catalog.dart:1344-1372` | “界面刷新率”和“播放时匹配视频帧率”两行（只在 Android） |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`（900） | 通道 `setHighRefreshRate`（`:217`）、`getDisplayModeInfo`（`:226`）；`applyRefreshRate`（`:784`）、`applySurfaceFrameRate`（`:842`）、`flutterSurfaceView`、`displayModeInfo`（`:875`）；显示变化和回到前台时重新声明并上报（`displayModeRefresh` `:134-141`），引擎配好时声明一次（`:337`） |
| `packages/live_store/lib/src/settings/settings.dart` | `refreshRateMode`（`:64`，默认 `powerSaving`）、`matchVideoFrameRate`（`:73`，默认开）；3.x 的 `enableHighRefreshRate` 迁移成 `refreshRateMode`（`legacy/legacy_snapshot.dart:409-410`） |
| `packages/live_player/lib/src/frame_rate.dart` | 视频帧率（G01 的文件，交给 `PlaybackState.frameRate`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/live_play/room_refresh_rate_test.dart`（10 个 `test`，部分按表循环） | 24/25/30/50/60 帧 × 60/90/120、60/120/144、60/90/120/144/165 Hz 的选法（均衡空闲、操作中、最高、省电）；没有整数倍取最高；通道参数（播放、操作、松手回落、停止、换显示器）；直播间什么时候发和撤 |
| `apps/pure_live/test/platform/display_mode_test.dart`（6） | 限制提示：操作中 60 Hz 满 3 秒才出、再读确认、恢复后消失、显示变化立即关；静止或只点一下不误报；清单没有 `appCategory`/`isGame`，Kotlin 没有帧率类别 |
| `apps/pure_live/test/features/settings/refresh_rate_limited_test.dart`（2）、`match_frame_rate_test.dart`（1） | 提示的显示条件（省电不显示）、档位说明不是键名；开关的位置、只在 Android、默认开、变灰 |
| `packages/live_ui/test/widgets_test.dart` | `AdaptiveRefreshRateController` 的三档规则（3.x 用例） |

## 3.x 基线

- `git show v3.2.11:lib/common/widgets/adaptive_refresh_rate_scope.dart`：`AdaptiveRefreshRateController`（`:15`，静态状态，`settleDelay` 1.5 秒 `:21`），3.x 在滚动结束时也当手指抬起（4.x 修了：手指还按着时不开始回落）。
- `lib/common/services/display_mode_service.dart`：`DisplayModeInfo`（`:5`）、`DisplayModeService`（`:80`，`setHighRefreshRate` `:101`）。
- `android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt`：`setHighRefreshRate`（`:128`）、`applyPreferredDisplayMode`（`:311-340`，只改 `preferredRefreshRate`，注释写着同时钉 `preferredDisplayModeId` 会触发厂商的重模式切换）。
- 3.x 没有帧率匹配，播放中和平时一样按三档；没有限制提示。弹幕帧率按档位取上限（`lib/common/services/settings/danmaku_settings_controller.dart:135-158`）。
- 3.x 的设置键 `enableHighRefreshRate`（开关）→ 4.x 迁移成 `refreshRateMode`（开 = 均衡，关 = 省电）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| R02.1 登记“完成”但没有 K90 结果：它的记录“没验证的”列着 K90 支持哪些刷新率、声明和窗口提示怎么取舍、进出直播间闪不闪屏、耗电；前两条由 V03.2 调研只读测过（60/90/120，窗口提示对已声明的画面无效），后两条要和 R02.2 一起看 | [R02.1 记录](R02.1-刷新率和帧率匹配/record.md)“没验证的” | 不符合 PROCESS 3.2 | R02.2 的 verify.md 通过后，在 R02.1 记录补一句“K90 结果见 R02.2 verify.md” |
| R02.2 待真机 | [verify.md](R02.2-刷新率策略修正/verify.md) | — | 维护者在 K90 上看 |
| HyperOS 的 `PRIORITY_MIUI_REFRESH_RATE` 投票应用压不过；推测看视频时可能按场景压到 60 | V03.2 调研 1.3 节 | 均衡档播放中拖面板可能仍是 60 | 做不到绕过；限制提示会出现；R02.2 verify 第 9 步观察 |
| 144/165 Hz 屏上 25/50 帧空闲时也用最高刷新率（规则“没有整数倍取最高”） | `display_mode.dart:146` | 比 60 明显耗电；K90 不受影响 | R02.2 记录“需要维护者决定的”：可改成“空闲时没有整数倍取不超过 120 的最高”；等维护者表态 |
| 只有 Flutter 用 `SurfaceView`（默认渲染模式）时才能声明；以后改成 `TextureView` 只剩窗口提示 | `MainActivity.kt` 的 `flutterSurfaceView` | 暂无影响 | 记下；改渲染模式的任务要同时看这里 |
| R02.2 记录的真机步骤写“面板‘统计信息’里能看到帧率”，4.x 没有统计信息面板 | [R02.2 记录](R02.2-刷新率策略修正/record.md)“要在 K90 上看的”第 1 条 | 按记录找不到 | R02.2 的 verify.md 改用“省电档时 `dumpsys SurfaceFlinger` 里 Flutter 那一层声明的就是视频帧率” |
| specs/UI.md 第 9.1 节写“Android 11 起对视频画面声明内容帧率”“25/50 帧选 50 或 100 赫兹”，实际是 Android 12 起（11 不能限定只在无缝时切换）、没有整数倍时取最高（D-010） | `docs/specs/UI.md` 第 9.1 节 | 规范和实现不一致 | 报告给维护者（specs 不在本组的写作范围） |
| 代码注释里的旧编号（U.2i、P01）、坏链接式的注释 `docs/README.md/research-smoothness-2026-10-02.md 1.4` | `display_mode.dart:140-141` 等 | 找文档先查 MAPPING；那个路径不存在（应为 V03.2 调研报告） | Z 组统一替换 |

## 相关决定和规范

- D-010：播放中只用帧率声明；没有整数倍时取设备最高刷新率；系统把应用限制在 60 Hz 时在设置里提示。
- D-003：R02.1 的 I1～I3 按建议 A。
- D-016、D-024：清理翻译键前先列运行时拼出来的键（R02.2 恢复了被误删的三条档位说明）。
- D-018：`refreshRateMode` 是 3.x 的含义（迁移自 `enableHighRefreshRate`）；`matchVideoFrameRate` 新加。
- [specs/UI.md](../../../specs/UI.md) 第 9.1 节（刷新率，见上面的不一致）；[V03.2 调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 第 1 节。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/live_play/room_refresh_rate_test.dart test/platform/display_mode_test.dart test/features/settings/refresh_rate_limited_test.dart test/features/settings/match_frame_rate_test.dart`；`cd packages/live_ui && flutter test test/widgets_test.dart`。Kotlin 没有单元测试，靠真机。
- 真机：[R02.2 的 verify.md](R02.2-刷新率策略修正/verify.md)（开发者选项“显示刷新率”、`dumpsys SurfaceFlinger`、`dumpsys display`）；[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 18 条。

## 路线

1. 维护者按 R02.2 的 verify.md 在 K90 上看；通过后 R02.2 改“完成”，R02.1 记录补真机出处。
2. 维护者对“144/165 Hz 屏空闲时的上限”表态；改的话开小任务（本子分类）。
3. 耗电对比在 R05.1（省电档不高于 3.x、均衡档的代价）。
4. 以后：Windows 只读刷新率（X01）；电视“匹配内容帧率”（X03）；iOS ProMotion（X04）。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [R 性能和流畅度](../README.md)。

- 代码：`platform/display_mode.dart`、`logic/room_refresh_rate.dart`
- 进度：`███████████████████░` 95%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| R02.1 | 刷新率和帧率匹配 | 性能 | 完成 | 2026-10-02 | b8462638a | [设计或说明](R02.1-刷新率和帧率匹配/README.md)、[记录](R02.1-刷新率和帧率匹配/record.md)、[评审页](R02.1-刷新率和帧率匹配/page/01-说明.jpg) |
| R02.2 | 刷新率策略修正：播放中只用帧率声明、没有整数倍取最高、系统限速提示 | 性能 | 待真机 | 2026-10-02 | 584da6662 | [任务书](R02.2-刷新率策略修正/brief.md)、[记录](R02.2-刷新率策略修正/record.md) |

<!-- docs:生成结束 -->
