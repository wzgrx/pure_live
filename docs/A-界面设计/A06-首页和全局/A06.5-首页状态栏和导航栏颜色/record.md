# A06.5 状态栏和导航栏的样式和 3.x 核对：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区；提交见登记表的 `commit`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 阶段 1 K90 截图核对 | 没做 | 本次不能用真机（不跑 adb）；维护者给的任务说明已认定差别（启动页留下黑色导航栏和浅色图标），按 X1、X2 的建议 A 直接改，截图放到真机验证 |
| c1 启动时和主题变化时设系统栏 | 做了 | 不是在启动时调一次 `SystemChrome`，而是在 `MaterialApp.builder` 里放整页的 `AnnotatedRegion`（`SystemBarsScope`）：Flutter 从第一帧起每帧按它设，主题变化时自动更新，不怕页面的 `AppBar` 或启动页把导航栏样式留在别的值上 |
| c2 启动页不再带黑色导航栏 | 做了 | 启动页的区域改用同一个 `systemBarsStyle` |
| c3 首页那一段 | 并进 c1 | 首页只留 `edgeToEdge` |

## 根因

- 启动页 `apps/pure_live/lib/features/splash/splash_page.dart:95-98`（改前）用 Flutter 的 `SystemUiOverlayStyle.light/dark`（Flutter SDK 3.47.5 `services/system_chrome.dart:316-330`：`systemNavigationBarColor: 0xFF000000`、`systemNavigationBarIconBrightness: Brightness.light`），浅色主题也是黑色导航栏、浅色图标。
- 离开启动页后没有人再设导航栏：首页 `home_page.dart:58-67`（改前）照 3.x 只设状态栏透明和 `navigationBarTheme.backgroundColor`（主题没设，`null` = 不改）；页面的 `AppBar` 样式不含导航栏字段；Flutter 每帧的 `_updateSystemChrome`（`rendering/view.dart`）在底部找不到区域时只发顶部的样式，导航栏字段是 `null`，系统保持原样。
- 3.x 在启动时全局设透明（`git show v3.2.11:lib/common/global/platform/mobile_manager.dart:11-15`、`:43-51`），4.x 没有对应代码；3.x 的导航栏图标固定深色（`:49`），深色主题看不清（P1，不照搬）。

## 改了哪些文件

- 新文件 `apps/pure_live/lib/app/system_bars.dart`（`systemBarsStyle`、`SystemBarsScope`）。
- `apps/pure_live/lib/app/app.dart`（`MaterialApp.builder` 里包一层 `SystemBarsScope`）。
- `apps/pure_live/lib/features/splash/splash_page.dart`（只改 `AnnotatedRegion` 的值）。
- `apps/pure_live/lib/features/home/home_page.dart`（去掉 `setSystemUIOverlayStyle`，留 `edgeToEdge`）。
- 测试：`test/features/splash/splash_page_test.dart`、`test/features/home/home_test.dart`。
- 文档：本文件夹 `README.md`（各版的经过、确认的改动、实现和验证）、`docs/inventory/FEATURES.md` 的 F-APP-23（写明新做法，状态仍是“没验证”，等 K90）。

## 新设置、翻译键、门禁基线

- 都没有。

## 测试

- 新增 2 个，改之前都失败（启动页导航栏是不透明黑色；首页在 Android 目标平台下导航栏字段是 `null`）。
- `apps/pure_live` 全部通过。

## 真机上要看的

- 任务书“真机验证”1～5：浅色、深色主题，手势导航和三键导航，启动页、首页、设置页、直播间双击全屏再退出、横屏首页：状态栏和导航栏透明、图标看得清、没有黑带或主题色带、没有分隔线；切主题不重启也对。截图放 `verify/`，写 `verify.md`。
- 三键导航时系统自己加的半透明遮罩（`systemNavigationBarContrastEnforced`）没动；截图如果难看，请维护者决定要不要关。
- 看完 F-APP-23 改“完成”。

## 停在哪（没做完时写）

- 代码做完；只差真机截图（阶段 1 的截图和改后的核对合成一次做）。
