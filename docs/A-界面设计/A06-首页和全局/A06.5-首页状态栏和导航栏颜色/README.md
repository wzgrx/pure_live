# A06.5 状态栏和导航栏的样式和 3.x 核对：设计（第 0 版，还没出图）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：Android 上应用自己画的页面（启动页、首页、二级页面、直播间不全屏时）顶上的状态栏和底下的系统导航栏：底色、图标深浅、分隔线；直播间全屏时隐藏系统栏的部分照旧（A07.4），只核对退出全屏后恢复的样子
- 对应：功能清点 [F-APP-23](../../../inventory/FEATURES.md)（边到边显示、透明状态栏和导航栏、四个方向可转，现状“没验证”）；真机清单 [CHECKLIST 1 第 19 条](../../../S-质量和验证/S02-真机验证/CHECKLIST.md)；相关任务 A06.1（手机首页）、A06.4（启动页）、A07.4（横屏全屏）、A14.1（系统界面）
- 评审页：还没有（要先在 K90 上截图确认有没有差别；有差别再出图和评审页，源文件放 `page.json`、`src/`）
- 来源：[V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md) 核对 F-APP-23 时发现 3.x 启动时的全局设置 v4 没有对应代码；上一次（没留下来的）核对记过一句“首页导航栏是主题色、3.x 是透明”

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A06.5-01 | 启动页的状态栏和导航栏 | 冷启动，设置“启动动画”开着（默认开） | 竖屏；浅色、深色 | 动画中 |
| A06.5-02 | 首页的状态栏和导航栏 | 离开启动页，或“启动动画”关着时直接进 | 竖屏、横屏；浅色、深色；手势导航、三键导航 | 默认 |
| A06.5-03 | 二级页面（设置、录制中心、搜索等）的状态栏和导航栏 | 首页进任何一页 | 竖屏；浅色、深色 | 默认 |
| A06.5-04 | 直播间（不全屏）的状态栏和导航栏 | 进直播间；全屏后退出 | 竖屏；浅色、深色 | 播放中、退出全屏后 |

## 3.x 的样子和问题

**3.x 怎么设的（`v3.2.11`）**

- 启动时全局设一次：`lib/common/global/initialized.dart:131` 调 `MobileManager.initialize()`（`lib/common/global/platform/mobile_manager.dart:7-27`）：`SystemUiMode.edgeToEdge`；状态栏、导航栏都透明（`:13-15`）；Android 再设导航栏透明、**导航栏分隔线透明**、**导航栏图标固定深色**（`:43-51`），并允许四个方向（`:53-58`）。
- 首页第一帧后再设一次：`lib/modules/home/home_page.dart:73-80`：状态栏透明，导航栏颜色取 `Theme.of(context).navigationBarTheme.backgroundColor`；3.x 的主题没有设 `navigationBarTheme`（全仓库只有这一处读它），所以这个值是 null，等于不改导航栏颜色，仍是启动时的透明。
- 退出全屏：`lib/player/utils/fullscreen.dart:306-311` 恢复系统栏，状态栏图标设成深色。
- `MobileManager.setStatusBarStyle`（`mobile_manager.dart:64-89`，按深浅色设图标）定义了但没有调用的地方。
- 原生：`android/app/src/main/res/values/styles.xml` 的 `NormalTheme` 设 `android:navigationBarColor` 透明。`targetSdk` 37（Android 15 起系统强制边到边，导航栏底色的设置不再生效，图标深浅仍生效）。

**问题**

- P1（3.x）：导航栏图标固定深色（`mobile_manager.dart:49`），深色主题下深色图标压在深色底上，三键导航的按钮看不清。
- P2（v4，待真机确认）：见下一节“v4 现在”，启动页把导航栏设成黑底、浅色图标，首页不改回来。

**v4 现在**

- 没有 3.x `MobileManager` 那样的启动时全局设置（全 `apps/pure_live/lib` 搜 `setSystemUIOverlayStyle` 只有首页一处）。
- 启动页 `apps/pure_live/lib/features/splash/splash_page.dart:95-98`：`AnnotatedRegion<SystemUiOverlayStyle>`，值是 `SystemUiOverlayStyle.light`（深色主题）或 `.dark`（浅色主题）`.copyWith(statusBarColor: 透明)`。Flutter 的这两个常量（Flutter SDK 3.47.5 的 `packages/flutter/lib/src/services/system_chrome.dart:316-330`）都带 `systemNavigationBarColor: Color(0xFF000000)` 和 `systemNavigationBarIconBrightness: Brightness.light`，所以启动页期间导航栏是黑底、浅色图标，浅色主题也一样。
- 首页 `apps/pure_live/lib/features/home/home_page.dart:58-67`：照 3.x 设状态栏透明、导航栏颜色取 `navigationBarTheme.backgroundColor`（v4 的主题同样没设，是 null），然后 `edgeToEdge`。导航栏图标深浅没人设，启动页留下的“浅色图标”可能一直保留。
- 页面的 `AppBar` 按自己的底色设状态栏图标（Flutter SDK 的 `packages/flutter/lib/src/material/app_bar.dart:886-900`，只管状态栏，不管导航栏）。
- 直播间全屏：`apps/pure_live/lib/features/live_play/live_play_page.dart:550`、`:571` 进 `immersiveSticky`，`:595-606` 的 `_restoreSystemUi` 退回 `edgeToEdge`，不碰样式。
- 原生 `apps/pure_live/android/app/src/main/res/values/styles.xml:17`、`values-night/styles.xml:17` 同 3.x（导航栏透明）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 0 版 | 只有上面的代码核对，还没截图、没出图 | — |

## 对比页（按章节导出）

无：还没出评审页。K90 截图确认有差别后再做（PROCESS 第 4.1 节）。

## 单张图

无：同上。K90 截图放 `verify/`（3.x 的截图只能用维护者以前留下的，不能在手机上打开 3.x，D-019）。

## 确认的改动

还没确认。建议（待 K90 截图后定）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 启动时全局设一次系统栏样式（照 3.x `MobileManager.initialize`）：状态栏、导航栏透明，导航栏分隔线透明；**图标深浅跟主题**（不照 3.x 固定深色），主题切换时重设 | P1、P2 |
| c2 | 修改 | 启动页的 `AnnotatedRegion` 不再用 Flutter 的 `SystemUiOverlayStyle.light/dark` 常量（带黑色导航栏），改成只设状态栏和导航栏图标深浅、导航栏透明 | P2 |
| c3 | 保留 | 首页 `home_page.dart:58-67` 那一段照 3.x 留着（或并进 c1，去掉重复） | — |

## 按钮的作用和用法

无：系统栏不是本应用的控件。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 本任务的全部内容；手势导航和三键导航都要看 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | Android 平板同手机；Windows、Linux 没有系统栏，不涉及 |
| 电视 | 电视外壳全屏，不显示系统栏，不涉及 |
| 苹果平台差异 | 3.x 的 `_initializeIOS`（`mobile_manager.dart:29-41`）只设状态栏；以后做 iOS 时在 X04 处理 |

## 待选和决定

- X1：导航栏图标深浅。A（建议）跟主题（浅色主题深色图标、深色主题浅色图标）；B 照 3.x 固定深色。理由：B 是 P1，深色主题下三键导航看不清。
- X2（V03.3 报告里请维护者决定的）：K90 截图如果确认首页导航栏和 3.x 不同（例如一条黑带或主题色带，3.x 是透明），这个差别是不是有意的。A（建议）不是，照 c1、c2 改回透明；B 是有意的，保留现在的样子，把它写进“确认的改动”并在 F-APP-23 的备注里说明。截图前不能定。

## 实现和验证（开发后补）

- 还没开始。真机核对步骤和代码改动见 [brief.md](brief.md)。
