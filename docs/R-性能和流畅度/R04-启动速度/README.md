# R04 启动速度

从点图标到首页可用要多久：Android 的启动画面、Flutter 引擎和 Dart 的启动、`main` 里打开数据库和建服务、第一帧、启动页（默认显示 1 秒）、首页第一屏内容。specs/UI.md 第 9.4 节的目标是“冷启动到首帧：中端机不超过 v3 的 60%”。

## 范围

- 包括：
  - 启动路径上的代码：`apps/pure_live/lib/main.dart`（`main`、`_launch`、`_prepare`、`_finish`）、`app/bootstrap.dart` 的 `AppBootstrap.start` 和 `wire`、`app/launch_failure.dart`（启动失败时的页面）、`app/app.dart`（`PureLiveApp`，第一帧后启动 `AppStartup`，`:96-97`）、`app/startup.dart`（`AppStartup`：第一帧之后才做的事）、`features/splash/splash_page.dart`（启动页的停留和离开条件）。
  - Android 一侧：启动主题 `LaunchTheme`（`android/app/src/main/res/values/styles.xml:4-7`，`launch_background`）、`NormalTheme`、Android 13 起的启动画面主题（`MainActivity.kt` 的 `setSplashTheme`，`:570`）。
  - 测量方法：`am start -W`、logcat 的 `Displayed`、应用自己的打点、`reportFullyDrawn`（首页可用）。
- 不包括（归哪里）：
  - 启动页长什么样、停多久、能不能点掉 → A06.4（3.x 停 1 秒，4.x 照旧，可以点或按键跳过）；首页外壳 → A06、I01。
  - 3.x 数据迁移（第一次启动时导入 Hive）本身的正确性 → J06；本组只看它对启动时间的影响。
  - 点进直播间到第一帧 → [G03](../../G-播放/G03-起播速度和弱网/README.md)；列表滑动帧率 → R01。

## 现状：做到哪、怎么工作的

- 用户看得到的：点图标 → 系统启动画面（应用图标）→ 应用的启动页（图标和“欢迎使用”0.4 秒淡入放大、进度条，停 1 秒，`showSplashPage` 默认开）→ 首页（热门）→ 第一页房间。启动页可以点一下或按任意键跳过；设置里能关掉启动页（直接进首页）。
- 启动路径（冷启动，按代码顺序）：
  1. `main`（`main.dart:22-28`）：装错误处理和应用日志；`_launch` → `launchOrExplain(_prepare)`（失败时显示原因、“重试”“导出日志”，不卡在启动画面）。
  2. `AppBootstrap.start`（`bootstrap.dart:98-137`）：`WidgetsFlutterBinding.ensureInitialized`；按 `/proc/meminfo` 设图片缓存（`:100-103`，同步读一个小文件）；`await TvDevice.detect()`（`app/ui_mode.dart`，问一次原生“是不是电视”）；解析命令行、`resolveDataRoot`；`await LiveStore.open`（打开数据库，`packages/live_store/lib/src/live_store.dart:100`）；主窗口：`await legacyHiveFiles()` + `await LegacyMigration.importHiveFiles`（`legacy_import.dart:137`：按“路径 | 大小 | 修改时间”的指纹记账，导入过的只 `stat` 一下就跳过）、`await LegacyIptvMigration.importDatabases`；然后 `wire`（`:142-249`：HTTP 客户端、代理、Cookie、平台登记、弹幕登记、录制、`MediaOpener`；后台启动关注迁移、虎牙 UA、网络电视自动同步 3 秒后、录制）。
  3. `_finish`（`main.dart:83-114`）：`installPluginHooks`；`await AppLog.instance.attach`（打开日志文件）；`await AppStrings.load`（读语言 JSON）；`await fonts.restore`（注册用户选的应用字体和弹幕字体，可能从 3.x 的字体目录拿）；`await DesktopShell.start`（电脑上的窗口，手机上基本是空的）。
  4. `runApp(ProviderScope(PureLiveApp))`（`main.dart:42-51`）→ 第一帧 → `addPostFrameCallback` 里 `AppStartup.start`（`app.dart:96-97`、`startup.dart:69-91`）：自动退出计时、定时刷新封面、本地网络权限、刷新显示模式、打码昵称清理一次、**关注的第一次检查**（网络）、1 秒后检查哔哩哔哩登录和 3.x 迁移提示。
  5. 启动页（`splash_page.dart`）：停 1 秒（`:33`），离开前最多等关注的第一次检查 350 毫秒（`startup.dart:21`，`splash_page.dart:79`）；然后换成首页。
  6. 首页热门：`PopularCatalog` 的 `RoomFeed` 先做断网预检，再请求平台第一页（网络）。
- 完成度：3.x 和 4.x 都没测过启动时间；4.x 的结构（启动前只做必要的事，第一帧后再做关注检查等）和 3.x 类似（3.x `AppInitializer.initialize` 在第一帧前做得更多：Hive、设置迁移、GetX 服务注册、FFmpeg 预热、图片缓存管理器、`DesktopManager`/`MobileManager`）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/main.dart`（114 行） | `main`（`:22`）、`_launch`（`:33`）、`_exportLog`（`:58`）、`_prepare`（`:69`）、`_finish`（`:83`，日志、语言、字体、桌面窗口） |
| `apps/pure_live/lib/app/bootstrap.dart`（273） | `AppBootstrap.start`（`:98`：图片缓存、电视检测、数据目录、打开数据库、3.x 导入）、`wire`（`:142`：建服务、后台任务）、`iptvSyncDelay` 3 秒（`:95`）、`_warmUp`（虎牙 UA） |
| `apps/pure_live/lib/app/launch_failure.dart` | `launchOrExplain`：第一帧前失败时显示原因、重试、导出日志 |
| `apps/pure_live/lib/app/app.dart`（302） | `PureLiveApp`；第一帧后 `AppStartup.start`（`:96-97`）；刷新率控制器（`:66`） |
| `apps/pure_live/lib/app/startup.dart`（131） | `splashFollowWait` 350 毫秒（`:21`）、`bilibiliCheckDelay` 1 秒（`:25`）、`AppStartup`（`:55`，`start` `:69`） |
| `apps/pure_live/lib/features/splash/splash_page.dart`（177） | `splashInitialLocation`（`:13-17`，`showSplashPage` 决定先到启动页还是首页）、`SplashPage`（`:31`，停 1 秒 `:33`、动画 0.4 秒 `:42`、离开前等关注检查 `:79`） |
| `apps/pure_live/lib/app/ui_mode.dart` | `TvDevice.detect`（第一帧前问一次原生） |
| `packages/live_store/lib/src/live_store.dart:100`、`legacy/legacy_import.dart:137` | 打开数据库；3.x 导入的指纹记账 |
| `apps/pure_live/android/app/src/main/res/values/styles.xml`、`AndroidManifest.xml:64-71`、`MainActivity.kt:570` | 启动主题、正常主题、Android 13 启动画面 |

测试：`apps/pure_live/test/launch_failure_test.dart`（启动失败页）、`apps/pure_live/test/features/splash/splash_page_test.dart`（启动页停留、点击跳过、等关注检查）、`apps/pure_live/test/services_test.dart`（`wire` 建出的服务）。没有启动时间的测试或基准。

## 3.x 基线

- `git show v3.2.11:lib/main.dart`（210 行，`:91` 初始化全局播放器编排器）和 `lib/common/global/initialized.dart` 的 `AppInitializer.initialize`（`:51` 起）：第一帧前依次 `ensureInitialized`、图片缓存、Windows 单实例、`AppPathManager`、`EasyLocalization`、`Hive.initFlutter`、`HivePrefUtil.init`、`SettingsUpgradeMigration.migrate`、`InitialServices.init`（注释写着这些必须在第一帧前完成）、代理配置、`CustomImageCacheManager`、Android 上 FFmpegKit 预热、`DesktopManager`/`MobileManager`。
- 启动页：`lib/modules/splash`（停 1 秒，2 秒淡入）；路由 `app_pages.dart`。
- 3.x 在 K90 上是用户的正式包，不能拿来测；要对比只能装改包名的 v3.2.11 构建（`com.mystyle.purelive.v3bench`，和 G03.1 共用）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有任何启动时间的数字（3.x、4.x 都没测） | — | specs/UI.md 9.4 的目标没判定 | R04.1 |
| 第一帧前顺序 `await` 的步骤多：电视检测、数据库、3.x 导入的指纹检查、网络电视导入、日志文件、语言、字体 | `bootstrap.dart:98-137`、`main.dart:83-114` | 每一步都推迟第一帧（量级待测） | R04.1 阶段 1 打点后决定哪些能并行或挪到第一帧后 |
| 启动页固定停 1 秒（照 3.x），“首页可用”至少多 1 秒 | `splash_page.dart:33` | 默认开着启动页的用户每次多等 1 秒 | 3.x 行为，A06.4 确认过；要不要“首页准备好就离开”需要维护者或用户决定，不在 R04.1 里擅自改 |
| 没有 `reportFullyDrawn`：系统不知道应用什么时候“可用”，`am start -W` 只给到第一帧（启动画面） | `MainActivity.kt` | 没法用系统工具量“首页可用” | R04.1 c1 |

## 相关决定和规范

- [specs/UI.md](../../specs/UI.md) 第 9.4 节：冷启动到首帧中端机不超过 v3 的 60%。
- D-019：不碰 3.x 和正式包；D-017。
- A06.4（启动页的设计，停 1 秒、可跳过）。

## 测试和验证

- 自动测试：现有的启动失败、启动页用例；R04.1 加打点的单元测试。
- 真机：R04.1 的测量矩阵（冷启动、温启动，开 / 关启动页，各 10 次）；没有 CHECKLIST 条目，R04.1 完成后建议加一条。

## 路线

1. R04.1（第二档）：先测量（打点 + `reportFullyDrawn` + `am start -W`），再按数字改第一帧前的顺序，最后真机对比。
2. 启动页“首页准备好就离开”这类行为变化先请维护者决定（A06.4）。
3. 以后：Windows 的启动（单实例、窗口恢复）在 X01。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [R 性能和流畅度](../README.md)。

- 代码：`apps/pure_live/lib/app/`
- 进度：`██████░░░░░░░░░░░░░░` 30%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| R04.1 | 启动速度：冷启动到首页可用的时间测量和优化 | 性能 | 开发中 | — | — | [设计或说明](R04.1-启动速度/README.md)、[任务书](R04.1-启动速度/brief.md)、[记录](R04.1-启动速度/record.md) |

## 还没完成的

- **R04.1 启动速度：冷启动到首页可用的时间测量和优化**（开发中，第二档，规模 中）
  - 阶段：✓ 测量 → 改进 → 真机对比
  - 接着做：K90 测量（阶段 1 第 3 条）：profile 包冷启动、温启动各 10 次 × 开 / 关启动页，记 TotalTime、Fully drawn、startup-timing，填 record.md 的现状表
  - 分支：worktree-agent-a181fd89d52eb7f5c
  - 说明：阶段 1 的代码（打点、reportFullyDrawn）做完，测量待真机

<!-- docs:生成结束 -->
