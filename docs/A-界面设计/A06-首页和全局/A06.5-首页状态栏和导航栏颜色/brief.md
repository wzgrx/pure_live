# A06.5 状态栏和导航栏的样式和 3.x 核对：任务书

## 背景

- 来源：V03.3（2026-10-03 功能清点核对）。功能清点 F-APP-23“边到边显示、透明状态栏和导航栏、四个方向可转”核对时发现：3.x 启动时用 `MobileManager.initialize` 全局设了一次系统栏样式，v4 没有对应代码；上一次（没留下来的）核对记过“首页导航栏是主题色、3.x 是透明”。
- 现象（待 K90 确认）：读代码推断，启动页的 `AnnotatedRegion` 用了 Flutter 的 `SystemUiOverlayStyle.light/dark`，它们带黑色导航栏和浅色导航栏图标；离开启动页后首页没有改回来。可能看到的是：浅色主题下三键导航的按钮是浅色、看不清，或者导航栏一块和页面颜色不一样。
- 为什么现在做：第二档；首页是用户每次都看到的页面，F-APP-23 的“没验证”靠本任务关掉。
- 已经做过的：A06.1（手机首页）、A06.4（启动页）、A14.1（系统界面）都没有专门处理系统栏样式。

## 目标和验收

1. 在 K90 上截下启动页、首页、一个二级页面（设置）、直播间退出全屏后的状态栏和导航栏，浅色、深色主题各一套，手势导航和三键导航各一套，写进本文件夹的 `verify.md`（照 `docs/templates/verify.md`），截图在 `verify/`。
2. 和 3.x 的写法对照（README“3.x 的样子和问题”），写清有没有差别。没有差别：README 写结论，F-APP-23 改“完成”，任务结束，不改代码。
3. 有差别：按 README 的 c1、c2 改（`待选和决定` X1 按建议 A：图标深浅跟主题），改完再截一遍：所有页面的导航栏都透明、图标在浅色主题是深色、深色主题是浅色；分隔线不出现。
4. 切换深浅色主题（设置 → 主题）后不重启也对。
5. 门禁通过。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/features/splash/splash_page.dart:95-98`：`AnnotatedRegion<SystemUiOverlayStyle>(value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: colors.surface.withValues(alpha: 0)))`。Flutter 的常量见 `flutter/lib/src/services/system_chrome.dart:316-330`：两者都是 `systemNavigationBarColor: Color(0xFF000000)`、`systemNavigationBarIconBrightness: Brightness.light`。
- `apps/pure_live/lib/features/home/home_page.dart:58-67`：第一帧后 `SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(statusBarColor: 透明, systemNavigationBarColor: Theme.of(context).navigationBarTheme.backgroundColor))`（主题没设 `navigationBarTheme`，这里是 null），再 `setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`。全应用只有这一处调 `setSystemUIOverlayStyle`。
- `AppBar` 自己按底色设状态栏图标（Flutter `material/app_bar.dart:886-900`，不含导航栏）。
- 直播间：`apps/pure_live/lib/features/live_play/live_play_page.dart:550`、`:571` 进全屏（`immersiveSticky`）；`:595-606` 的 `_restoreSystemUi` 退出时回 `edgeToEdge`。
- 主题：`apps/pure_live/lib/app/app.dart` 的 `MaterialApp`（主题由 `packages/live_ui` 给出；设置项 `themeMode`、`themeColorSwitch`、`pureBlackTheme`）。
- 原生：`apps/pure_live/android/app/src/main/res/values/styles.xml:17`、`values-night/styles.xml:17` 的 `android:navigationBarColor` 透明；`apps/pure_live/android/app/build.gradle.kts` 的 `targetSdk = 37`（Android 15 起强制边到边，导航栏底色设置不生效，图标深浅和 `systemNavigationBarContrastEnforced` 仍生效）。

## 3.x 基线

- `git show v3.2.11:lib/common/global/initialized.dart`：`:131` 启动时调 `MobileManager.initialize()`。
- `git show v3.2.11:lib/common/global/platform/mobile_manager.dart`：`:11` `edgeToEdge`；`:13-15` 状态栏、导航栏透明；`:43-51` Android 导航栏透明、分隔线透明、导航栏图标固定深色；`:53-58` 四个方向都允许。`:64-89` 的 `setStatusBarStyle`（按深浅色设图标）没有调用的地方。
- `git show v3.2.11:lib/modules/home/home_page.dart:73-80`：和 v4 首页同一段。
- `git show v3.2.11:lib/player/utils/fullscreen.dart:306-311`：退出全屏恢复系统栏，状态栏图标设深色。
- 要保留的：边到边、状态栏和导航栏透明、四个方向可转（v4 不调 `setPreferredOrientations` 时默认就是四个方向，直播间按需锁方向，A07.4）。不保留的：导航栏图标固定深色（3.x 的问题 P1）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面任务、第 5 节分阶段、第 8 节合并审查、第 10 节真机、第 14 节规则）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节（原则）、第 4 节（客户端）。
3. 本文件夹的 `README.md`；`docs/A-界面设计/A06-首页和全局/A06.4-启动页/README.md`（启动页的样子）；`docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏/README.md`（全屏时的系统栏）。

## 范围

- 可以改：`apps/pure_live/lib/features/splash/splash_page.dart`（只改 `AnnotatedRegion` 的值）、`apps/pure_live/lib/features/home/home_page.dart`（那一段系统栏设置）、`apps/pure_live/lib/app/`（加一个启动时和主题变化时设系统栏的小函数）；对应测试；本文件夹。
- 不能改：直播间全屏的进出逻辑（A07.4）；主题颜色（A11.2）；原生 `styles.xml`（除非真机证明必须，先写进 README 再改）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。不加设置项。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | K90 上截图核对（验收 1、2） | `verify.md`、`verify/`、README 的“各版的经过” | 截图齐；结论写明有没有差别。没有差别就到此结束，F-APP-23 改“完成” |
| 2 | c1、c2：启动时和主题变化时设系统栏；启动页不再带黑色导航栏 | `app/`、`splash_page.dart`、`home_page.dart`、测试 | 验收 3、4；门禁通过 |

## 测试

- 阶段 2 改之前会失败的测试：在 `apps/pure_live/test/features/splash/` 里取启动页的 `AnnotatedRegion<SystemUiOverlayStyle>`，断言 `systemNavigationBarColor` 不是不透明黑色、`systemNavigationBarIconBrightness` 在浅色主题是 `Brightness.dark`（现在是 `Brightness.light`）。
- 启动时设样式的函数：用 `TestDefaultBinaryMessengerBinding` 截 `SystemChrome.setSystemUIOverlayStyle` 的平台消息，断言浅色、深色主题各发的值。
- 测试里的定时器至少 1 秒；不访问真实平台。`apps/pure_live` 跑 `flutter analyze`、全部 `flutter test`、`dart format --output=none --set-exit-if-changed .`；`python3 tools/gate/check_ui_structure.py`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 主题选浅色；系统设置里用手势导航；冷启动（启动动画开） | 启动页：状态栏透明、图标深色；底部手势条看得清 |
| 2. 等进首页，截图；进设置页截图；进一个直播间，双击全屏再退出，截图 | 状态栏透明、图标深色；导航栏和页面底色一致（不是一条黑色或主题色的带），手势条看得清 |
| 3. 系统设置切到三键导航，重复 1、2 | 三个按钮在浅色主题是深色、看得清；没有分隔线 |
| 4. 设置 → 主题选深色（不重启），重复 2、3 | 图标变浅色，看得清 |
| 5. 横屏看首页 | 同上，导航栏在侧边时一样 |

## 风险和注意

- Android 15 起强制边到边：导航栏底色设了也不生效，判断要看截图，不要只看代码。
- 三键导航下系统可能自己加半透明遮罩（`systemNavigationBarContrastEnforced`），不要为了“完全透明”去关它，除非截图证明遮罩难看并在 README 写明。
- 只点测试包；3.x 的样子只能用以前留下的截图或代码推断，不能在手机上打开 3.x（D-019）。
- 可能冲突的文件：`home_page.dart`（A06.1）、`splash_page.dart`（A06.4）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A06.5` 或本机工作区；提交信息以 `[A06.5]` 开头（英文）；不推 master。
- 提交前：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`（`apps/pure_live`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

截图结论（有没有差别、差在哪）；做了哪些改动、测试数量；F-APP-23 改成了什么；要在真机上再看的；需要维护者决定的（例如三键导航的遮罩要不要关）。
