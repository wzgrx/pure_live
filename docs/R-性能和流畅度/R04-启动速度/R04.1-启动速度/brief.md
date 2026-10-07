# R04.1 启动速度：任务书

## 背景

- 来源：[specs/UI.md](../../../specs/UI.md) 第 9.4 节“冷启动到首帧：中端机不超过 v3 的 60%”；PLAN 第二档“K90 上跑基准、启动速度”；2026-10-02 登记（旧编号 T14e.1）。
- 现象：没有具体的用户报告；启动时间从来没测过，不知道第一帧前哪一步慢。
- 为什么现在做：第二档；先测量，数字证明值得才改。
- 已经做过的：4.0.0 发布前的“启动失败时显示原因”（`app/launch_failure.dart`）；第一帧后才做的工作（`AppStartup`，I01.x）；R01.1 c3（启动时读内存设图片缓存）。

## 目标和验收

阶段 1（测量）：

1. 打点代码合并：冷启动时写一行 `startup-timing …`（字段见“方案”），进应用日志并 `debugPrint`；温启动（进程还在）不写。
2. `reportFullyDrawn` 合并：首页第一页房间出现（关启动页时）或启动页离开后首页第一页房间出现时调用一次；logcat 能看到 `Fully drawn com.mystyle.purelive.v4dev/...: +XXXms`。
3. `record.md` 有现状表：冷启动、温启动各 10 次 × 开 / 关启动页的 `TotalTime`、`Fully drawn` 中位数和 P90，以及 `startup-timing` 各段的中位数；写设备状态（刚开机多久、电量、温度）。
4. （可选）v3bench 包（改包名的 v3.2.11）的同样数字；做不了写原因。

阶段 2（改进）：

5. 只做阶段 1 证明值得的改动（单段 ≥50 毫秒且能并行或挪后），每个改动单独提交、有测试；行为不变（首页数据、3.x 迁移、语言、字体都和以前一样，启动失败页照旧）。

阶段 3（真机对比）：

6. 同样的矩阵再测，改前改后对比表；冷启动 `main` → 第一帧至少少 20%（阶段 1 后按数字可以调整目标，写明理由）；有 3.x 数字时冷启动 `TotalTime` ≤3.x 的 60%，达不到写原因。
7. 每个阶段测试和门禁通过。

## 现状（读代码得出，写文件:行）

- `apps/pure_live/lib/main.dart`：`main`（`:22-28`：`FlutterError.onError`、`AppLog.instance.install()`、`_launch`）；`_launch`（`:33-54`：`launchOrExplain(_prepare, show: runApp, ...)`，成功后 `runApp(ProviderScope(...PureLiveApp))`，再 `SystemIntake.start`）；`_prepare`（`:69-81`：`AppBootstrap.start` → `_finish`）；`_finish`（`:83-114`：`installPluginHooks`、`await AppLog.instance.attach`（打开日志文件）、`AppLanguage.resolve`、`await AppStrings.load`、`FontLibrary(...)` 和 `await legacyHiveFiles()`（主窗口）、`await fonts.restore`、`await DesktopShell.start`）。
- `apps/pure_live/lib/app/bootstrap.dart`：`AppBootstrap.start`（`:98-137`）：`WidgetsFlutterBinding.ensureInitialized()`；`configureDecodedImageCache`（`:100-103`，Android 同步读 `/proc/meminfo`）；`await TvDevice.detect()`（`app/ui_mode.dart`）；`LaunchArgs.parse`；`await resolveDataRoot()`；`platformSecretCipher()`；`await LiveStore.open(dataRoot, cipher:, shared: true)`；主窗口：`await legacyHiveFiles()`、`await LegacyMigration.importHiveFiles`（`packages/live_store/lib/src/legacy/legacy_import.dart:137`，按“路径 | 大小 | 修改时间”指纹跳过导入过的）、`await LegacyReloginNotice.record`、`await LegacyIptvMigration.importDatabases`；`wire`（`:142-249`：同步建 HTTP、代理、Cookie、原生通道、网络电视导入器、平台登记、弹幕登记、录制；后台 `_moveFollows`、`_warmUp`、`_iptvAutoSync`、`recording.start()`）。注意 `legacyHiveFiles()` 在 `start` 和 `_finish` 各调用一次。
- `apps/pure_live/lib/app/app.dart:96-97`：第一帧后 `appStartupProvider.start()`；`app/startup.dart:69-91`：自动退出、封面刷新、本地网络、显示模式、打码昵称清理、关注第一次检查（`followCheck`）、1 秒后哔哩哔哩登录检查。
- `apps/pure_live/lib/features/splash/splash_page.dart`：`splashInitialLocation`（`:13-17`）；`SplashPage`（`:31`，`duration` 1 秒 `:33`，`animation` 0.4 秒 `:42`，计时 `:62`，离开前 `Future.any([check, delayed(splashFollowWait)])` `:79`）。
- 原生：`apps/pure_live/android/app/src/main/AndroidManifest.xml:64-71`（`LaunchTheme`、`NormalTheme`）；`MainActivity.kt` 的通道 `pure_live/app`（`setSplashTheme` `:253`、`:570`），没有 `reportFullyDrawn`。
- 首页热门的第一页：`features/popular/popular_catalog.dart:51-57`（`RoomFeed`，断网预检后请求平台）。

## 3.x 基线

- `git show v3.2.11:lib/common/global/initialized.dart`：`AppInitializer.initialize`（`:51` 起）在第一帧前做的事（见 README 的表）；注释写着 `InitialServices.init` 必须在 `MyApp.build` 前完成（首次升级时的竞态）。`lib/main.dart:91` 初始化全局播放器编排器。
- 启动页 `lib/modules/splash`（停 1 秒）。
- 3.x 在 K90 上是用户的正式包，不能拿来测；可选的对比包：在独立工作区 `git worktree add <路径> v3.2.11`，`android/app/build.gradle` 的 `applicationId` 改成 `com.mystyle.purelive.v3bench`、应用名改“纯粹直播 v3bench”，本机构建 profile 包，测完卸载（和 G03.1 共用这个包）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.3 节、第 5 节、第 10 节、第 14 节）。
2. `docs/specs/UI.md` 第 9.4 节；`docs/specs/ENGINEERING.md`。
3. 本文件夹的 `README.md`；`docs/R-性能和流畅度/R04-启动速度/README.md`；`docs/A-界面设计/A06-首页和全局/` 下 A06.4 启动页的说明；`docs/J-设置和数据/J06-3.x数据迁移/README.md`（迁移在启动时做什么）。
4. 代码：上面“现状”列的文件。

## 范围

- 可以改：`apps/pure_live/lib/main.dart`、`app/bootstrap.dart`、`app/startup.dart`、`app/app.dart`（只为打点、`reportFullyDrawn` 和启动顺序）；`features/popular/`（只为“第一页房间出现”的信号）；`android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt`（只在 `pure_live/app` 通道加 `reportFullyDrawn`）；对应测试（`apps/pure_live/test/`）；可以新建 `tools/perf/startup_timing.py`（汇总日志）；本文件夹的 `record.md`。
- 不能改：启动页的停留时间和样子（A06.4）；3.x 导入的逻辑和结果（J06）；数据库格式；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

登记表的阶段：`["测量", "改进", "真机对比"]`。

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 测量 | c1 打点：`main` 入口起一个 `Stopwatch`，记 `binding`、`imageCache`、`tvDetect`、`dataRoot`、`store`、`legacy`（Hive + IPTV）、`wire`、`log`、`strings`、`fonts`、`desktop`、`runApp`、`firstFrame`（`waitUntilFirstFrameRasterized`）、`home`（首页第一帧）、`firstPage`（热门第一页房间出现）；c2 `reportFullyDrawn`；c3 K90 测量（可选 v3bench） | `main.dart`、`bootstrap.dart`、`app.dart`、`popular` 的一个回调、`MainActivity.kt`；测试；`record.md` | 验收第 1～4 条 |
| 2 改进 | c4 按数字选做：`TvDevice.detect` 和 `LiveStore.open` 并行；3.x 导入、网络电视导入挪到第一帧后（首页在导入完成前读到的数据要和以前一样：先确认第一次启动时首页需要哪些导入结果）；`AppStrings.load` 和 `fonts.restore` 并行；`AppLog.attach` 不阻塞；`legacyHiveFiles()` 只算一次；`wire` 里第一屏用不到的服务（录制器等）延后建 | 同“范围” | 验收第 5 条；每个改动单独提交 |
| 3 真机对比 | c5 同样的矩阵再测 | `record.md` | 验收第 6 条 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。

日志格式（c1）：

```text
startup-timing cold=true splash=on binding=12 imageCache=1 tvDetect=8 dataRoot=3 store=45 legacy=6 wire=30 log=4 strings=20 fonts=2 desktop=0 runApp=131 firstFrame=260 home=1420 firstPage=1980
```

`runApp` 以前各字段是这一步的耗时（毫秒），`runApp`、`firstFrame`、`home`、`firstPage` 是从 `main` 入口起的累计时间。

## 测试

- 阶段 1：
  - `apps/pure_live/test/`：`startup timing writes one line with every mark`（用 `AppBootstrap.wire` 的测试方式和假的计时源，断言一行、字段齐全、非负、累计值递增）；`reportFullyDrawn is called once`（假通道，热门第一页出来后调用 1 次，再刷新不再调用）。
- 阶段 2（改之前会失败的写明）：
  - 并行后：`the store opens without waiting for the television check`（假的 `TvDevice.detect` 卡住，断言数据库已经开始打开）。
  - 挪后的导入：`legacy import still runs once after the first frame and the home shows the imported follows`（假的 3.x 文件，第一帧后导入，关注列表最后有导入的数据）。
  - 启动失败页：现有 `launch_failure_test.dart` 不改断言照样通过。
- 定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

准备：profile 包（`com.mystyle.purelive.v4dev`）；Wi-Fi；亮度 50%；手机开机 10 分钟以上、不充电；`adb -s 192.168.1.2:5555 logcat -c` 后另开 `adb logcat | grep -E "Displayed|Fully drawn|startup-timing"`。

| 步骤 | 期望 |
|---|---|
| 1. 冷启动 10 次：`adb shell am force-stop com.mystyle.purelive.v4dev` → `adb shell am start -W -n com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity`，每次等首页第一页房间出来再进行下一次 | 每次一行 `TotalTime`、`Displayed`、`Fully drawn`、`startup-timing`；没有启动失败 |
| 2. 设置里关掉启动页，重复第 1 步 | 同上；`Fully drawn` 比开着时少约 1 秒 |
| 3. 温启动 10 次：按返回键退到后台，`am start -W` 同一命令 | `TotalTime` 明显小于冷启动；没有 `startup-timing` 行 |
| 4. （可选）v3bench 包做第 1、3 步（3.x 没有 `Fully drawn`，用录屏数帧量“首页出现”） | 记录对比 |
| 5. 阶段 2 合并后重复 1～3 | 改前改后对比；首页内容、关注、语言、字体和以前一样 |
| 6. 清除测试包数据后冷启动一次（模拟第一次启动，有 3.x 数据时会导入） | 能正常进首页；3.x 导入照旧（J06 的行为） |

## 风险和注意

- 冷启动时间受系统状态影响大：每组前等手机降温、关后台应用；取中位数，不看单次。
- 把导入挪到第一帧后可能让第一次启动时首页先显示空的关注再刷新——要先确认首页第一屏需要哪些数据，必要时只挪网络电视导入；有疑问写进报告由维护者决定。
- `reportFullyDrawn` 只调一次；调早了（首页还空着）会让数字失真。
- 3.x 的竞态教训：`InitialServices.init` 曾因为没等完就建界面导致首次升级时崩；挪后的任何服务，界面在它就绪前都不能用它。
- 可能冲突的文件：`main.dart`、`bootstrap.dart`（J06、H 组录制、I01）、`MainActivity.kt`（O 组、R02.2）、`popular/`（A09、E07）。
- 只点测试包（D-019）；v3bench 测完卸载。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/R04.1` 或本机工作区；提交信息以 `[R04.1]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。改了 Kotlin 时本机 `flutter build apk --debug` 编译一次，之后 `./gradlew --stop`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”（哪个阶段、测到哪、做了哪几个改动）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

现状表和改后表（`TotalTime`、`Fully drawn`、各段中位数）；最慢的几步和原因；做了哪些改动、各省多少；和 3.x 的对比（有的话）；测试数量（改之前失败几个）；改了哪些文件；要在真机上再看的；需要维护者决定的（例如启动页提前离开、导入挪后的影响）；可能冲突的文件。
