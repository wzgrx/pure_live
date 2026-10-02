# 4.0.0 发布前修复（2026-10-02）

发布前审查发现的问题，只管 Android。每条一次提交。

## 1. release 包删掉了媒体通知按钮的图标

- **根因**：release 打开了资源压缩（`isShrinkResources = true`）。`raw/keep.xml` 只保留了 `ic_stat_playback`。媒体通知的按钮（`background_playback.dart` 的 `mediaControls`）用 `MediaControl.pause/play/stop.androidIcon`，即 `drawable/audio_service_pause`、`audio_service_play_arrow`、`audio_service_stop`；这些名字只出现在 Dart 里，audio_service 用 `getIdentifier` 按名字查，压缩器看不到引用就删了，查到的 id 是 0。Android 13 起 audio_service 把“停止”做成 `PlaybackStateCompat.CustomAction`，`CustomAction.Builder(..., 0)` 抛 `IllegalArgumentException`，媒体通知和前台服务都起不来。3.x 的 `keep.xml` 保留的正是这三个。
- **改动**：`keep.xml` 加回三个图标，和 `ic_stat_playback` 一起保留。
- **测试**：`test/platform/system_surfaces_test.dart`“every drawable named only from Dart survives the release resource shrinker”：从 `mediaControls` 取出全部图标名，加上通知小图标，逐个检查 `keep.xml` 里有。改之前失败（缺 `audio_service_*`）。
- **验证**：见文末“release 构建”。

## 2. 3.x 导入：加密失败时关注等都导不进来

- **根因**：`LegacyMigration.merge` 先写设置，接着 `secrets.writeAll`（Cookie 用 Android Keystore 加密），之后才写关注、历史、分组、屏蔽和 WebDAV；`importHiveFiles` 只捕获读文件的 `FileSystemException`，全部成功才记账本。AndroidKeyStore 坏掉的机器上 `seal` 抛异常，`merge` 中途退出、账本不记，每次启动都重来、每次都在同一处失败，关注等永远导不进来。WebDAV 服务器也一样：`WebDavStore.replaceAll` 先加密密码再写服务器。
- **改动**：
  - `merge` 先写不需要加密的：设置、关注、历史、关注分区、屏蔽词和用户、分组、WebDAV 服务器（地址、用户名，不带密码）、留给其他模块的 3.x 值；最后把 Cookie 和新服务器的密码合成一次 `secrets.writeAll`，单独 `try/catch`，失败时返回没存下的名字，不再抛出。
  - `LegacyImportReport.skippedSecrets` 带上这些名字，其余照常记账本（不会每次启动重试）。
  - `WebDavStore.replaceAll` 加 `withPasswords`（默认 true）；false 时不加密、不动已存的密码（删除服务器时照样删它的密码）。
  - 应用侧：启动时导入后若有 `skippedSecrets`，在 meta 记一条（`app.legacyReloginNotice`）；首帧后 1 秒（和哔哩哔哩登录检查同一时刻）提示一次“部分平台需要重新登录：从 3.x 导入的登录信息和 WebDAV 密码无法在本机加密保存。”，然后删掉记录。中英文都加了（`legacy_import_relogin`）。
- **测试**：
  - `packages/live_store/test/migration_test.dart`“a keystore that cannot encrypt: everything else is imported, the sign-ins are skipped once”：加密器 `seal`/`open` 都抛异常，导入后关注、历史、分区、分组、屏蔽、设置、WebDAV 地址和保留的 3.x 值都在，Cookie 和 WebDAV 密码在 `skippedSecrets` 里；第二次导入按账本跳过。改之前失败（`Bad state: KeyStore unavailable` 直接抛出）。
  - `apps/pure_live/test/services_test.dart`：有跳过才记，提示只出现一次。
- **验证**：live_store 全部测试、应用相关测试通过。

## 3. 播放会话释放时引擎还在创建

- **根因**：`PlaybackSession.dispose()` 只释放已经有的 `_engine`；`_engineNow()` 在 `await` 引擎创建之后不看 `_disposed`。打开直播间后很快离开（引擎还在创建）时，`dispose()` 先结束，随后创建好的引擎被接上并订阅事件，再也没人释放（原生播放器和纹理泄漏）。
- **改动**（`packages/live_player/lib/src/session.dart`）：`_engineNow()` 等到引擎后先检查会话还在，已释放就不接上（抛出，`open` 那边会话已过期，直接忽略）；`dispose()` 若有正在创建的引擎，等它完成，没被接上就释放它，创建失败则忽略，然后照常释放。
- **测试**：`packages/live_player/test/session_test.dart`“disposed while the engine is still being created: dispose waits for it and releases it”（假引擎用 `Completer` 延迟创建，期间 `dispose`：`dispose` 要等到创建完成，引擎被释放、没有打开过、`session.engine` 为空；改之前失败，`dispose` 提前结束）；“disposed while the engine creation fails: dispose still completes”。
- **验证**：live_player 全部测试通过。

## 4. Android 17 本地网络权限：投屏和局域网直播源没有申请

- **根因**：`AndroidManifest.xml` 声明了 `ACCESS_LOCAL_NETWORK`（targetSdk 37），但只有局域网代理（`LocalNetworkGuard`）和设备同步会申请。投屏对话框（`stream_dialogs.dart` 的 `CastDialog`）打开就搜 SSDP，局域网 IPTV 源（`192.168.x`、`10.x`、`.local` 等）直接交给播放器；Android 17 上没有权限时套接字被拒，用户只看到“搜索失败”或播放失败，不知道原因。
- **改动**：
  - `platform/system_access.dart` 加 `isLocalNetworkUrl`（用 live_net 的 `isLocalNetworkProxyHost` 判断地址的主机，回环地址不算）和 `ensureLocalNetworkFor(urls)`：其中有局域网地址才调用 `SystemAccess.requestLocalNetwork()`，被拒时提示“未获得「本地网络」权限，局域网里的直播源（如家里的 IPTV 服务器）无法连接……”。
  - 投屏：每次搜索（打开时和点刷新）先申请，被拒时提示“未获得「本地网络」权限，无法搜索投屏设备……”，这次搜索按失败处理（显示“DLNA 设备搜索失败”，可以点刷新再申请）。
  - 播放：直播间 `RoomController` 打开线路前和 IPTV 回看打开前、多画面打开线路前都先 `ensureLocalNetworkFor`；被拒照常打开（会按原来的方式报错），只是多了原因提示。不是局域网地址的不调用原生。
  - 中英文各加两条提示（`local_network_denied_cast`、`local_network_denied_stream`）。
- **测试**：
  - `services_test.dart`：局域网地址判断；公网地址不申请；有局域网地址时申请，被拒提示一次，允许后不再提示。
  - `live_play_more_test.dart`“IPTV on the local network: local-network access is asked before it opens”：`192.168.1.8` 的频道在第一次打开前就申请，被拒有提示。改之前失败（没有申请）。
  - `live_play_more_page_test.dart`“cast: the search asks for local-network access first; refused, it says so”：被拒时不搜索、有提示、显示搜索失败；允许后点刷新搜到设备。改之前失败（直接搜索）。
- **验证**：上述测试和应用全部测试通过。没在真机上试（Android 17 以下 `localNetworkGranted` 直接为 true，不弹窗）。

## 5. 两个插件用同一个权限请求码

- **根因**：`PermissionsPlugin.kt` 的通知权限和 `SystemAccessPlugin.kt` 的本地网络权限都用 `20261001`。Flutter 把每个权限结果交给所有插件的监听器，两个请求同时在等时，一个插件会拿另一个的结果答复自己的请求（例如通知被拒，本地网络也当成被拒）。
- **改动**：本地网络改成 `20261003`（通知 `20261001`、电池 `20261002`、录制存储 `20260907` 不变；依赖插件用的都是小数值，不冲突）。
- **测试**：`system_surfaces_test.dart`“the plugins' permission and activity request codes are unique”扫描 `android/app/src/main/kotlin` 里所有 `*_REQUEST` 常量，值不能重复。改之前失败（`NOTIFICATION_REQUEST reuses 20261001`）。
- **验证**：release 构建编译通过（见文末）。没有装到手机上试。

## 6. 外部意图可以打开任意页面

- **根因**：`MainActivity` 是启动图标的界面，必须导出，任何应用都能给它发 `com.mystyle.purelive.OPEN`。`ShareIntakePlugin.kt` 把 `route` 原样交给 Dart，`share_intake.dart` 直接 `openRoute` → `AppNavigator.toNamed`，别的应用因此能直接打开设置、备份、WebDAV 等任何页面。
- **改动**：只允许启动图标快捷方式（T13a.1 c15）和录制通知用到的两个页面：`/search`（搜索直播）、`/record_mannager`（录制中心）。Dart 侧 `ShareIntake.openableRoutes`，其他路由记日志后忽略（不提示）；Kotlin 侧 `OPENABLE_ROUTES` 在入口先丢掉，两边都挡。打开直播间的快捷方式（`platform` + `roomId`）不变，和分享链接一样。
- **测试**：`test/intake_test.dart`“an outside intent opens only the shortcut pages, anything else is ignored quietly”：`/settings`、`/backup`、`/web_dav`、`/live_play`、`/search/../settings` 都返回 `unsupported`、不导航、不提示；`/search` 照常打开。改之前失败（`/settings` 返回 `opened`）。
- **验证**：release 构建编译通过（见文末）。没有在手机上用 `am start` 试。

## 7. 启动链没有兜底

- **根因**：`main.dart` 直接 `await AppBootstrap.start(args)`，没有捕获。`LiveStore.open`（`bootstrap.dart`）在存储满、数据库损坏或被锁时抛异常，`main` 就此结束，`runApp` 从未调用，用户一直停在系统启动画面，日志也没处看。
- **改动**：
  - 新文件 `app/launch_failure.dart`：`launchOrExplain(start, show, retry, exportLog)` 运行启动；抛异常时写进应用日志（`startup`，含堆栈），语言设置还没读到时按系统语言加载文字，然后 `runApp` 一个简单的错误页 `LaunchFailureApp`：live_ui 的 `AppStatusView`，标题“纯粹直播没能启动”，原因（文件错误写出文件夹和系统给的原因，例如“无法读写数据文件夹 …：No space left on device。可能是存储空间不足，或者没有权限。”；其他写“应用数据无法打开：…”，过长截断）和“可以点‘重试’；一直这样的话，请导出日志反馈给我们。”，两个按钮“重试”“导出日志”。
  - `main.dart`：首帧前的步骤（服务、日志、文字、字体、桌面窗口）放进 `_prepare`，由 `launchOrExplain` 运行；后面的步骤失败时先关掉已打开的服务。“重试”重新走一遍启动，成功就换成正常的应用。“导出日志”沿用日志页的导出（`AppLog.export`）：手机上弹系统分享，桌面上存到临时文件夹并显示路径；失败提示“日志导出失败”。
  - 中英文各加 6 条（`launch_failed_*`）。
- **测试**：`test/launch_failure_test.dart`：启动抛 `FileSystemException`（空间不足）→ 返回 null、错误写进日志、错误页显示标题、路径和原因，点“重试”“导出日志”各调用一次并显示导出结果；其他错误的原因文字；启动成功时照常返回、不显示错误页。（新函数，改之前没法跑出失败。）
- **验证**：上述测试和应用全部测试通过。没在真机上制造启动失败。

## 8. 3.x 默认目录里的录像

- **根因**：3.x 默认录到 `<app_flutter>/PURE_LIVE/RECORDS`（`AppPathManager.dirRecords`，应用私有存储）；v4 默认录到外部私有目录 `Android/data/<包名>/files/Records`（`app/recording.dart` 的 `defaultRecordDirectory`），导入的 3.x 私有路径又被 `RecordStorage` 当作无效选择丢掉（`_isAndroidPrivate`）。升级后旧录像留在用户进不去的私有目录里，录制中心也看不到。
- **改动**（`app/recording.dart`）：
  - `legacyRecordDirectory()`：Android 上 3.x 的默认目录（`getApplicationDocumentsDirectory()/PURE_LIVE/RECORDS`），其他平台为 null。
  - `moveLegacyRecordings(meta, from, to)`：只做一次（meta `recorder.legacyRecordingsMoved`）。把成品文件按原来的相对路径移到 v4 的默认目录；不移的有：分段（`.ts`）、时钟日志（`.clock-v1.csv`）、`.partial`、隐藏文件（合并清单、目录标记），以及同目录里还有分段或日志的那次录制的其他文件（导入的任务可能还要在原处合并它们）。同名的加 `-1`、`-2`。先 `rename`，跨文件系统（私有存储 → 外部存储）时复制到 `.partial` 再改名、删原文件。移不动的留在原处，记日志。
  - `AppRecording.start()` 加载设置后在后台调用它（不耽误恢复任务），目标是默认目录（不需要权限；用户另选了目录时也移到默认目录）。
- **测试**：`test/features/recorder/recorder_centre_test.dart`“3.x's default folder: the finished recordings move once, sub-folders kept”：临时目录模拟两边，成品 MP4 和弹幕 XML 带子目录移过去；未完成那次录制的分段、日志、XML、清单、`.partial` 和目录标记留下；同名改成 `old-1.mp4`；目标路径被文件占住的那个留在原处、计为失败；第二次不再移动。（这是新加的函数，改之前测试编译不过，没法先跑出“失败”。）跨文件系统的复制分支没有单独测（同一文件系统上 `rename` 就成功了）。
- **验证**：上述测试和应用全部测试通过。没在真机上试。
- **已知不足**：导入的 3.x 任务里的“上次文件”路径（`lastOutputPath`）没改，录制中心点这个任务的“打开文件夹”仍指向旧的私有目录。

## 9. 重叠的 stop 留下空闲释放定时器（追加）

- **根因**：`PlaybackSession.stop()` 在 `await` 输入关闭和 `engine.stop()` 之后直接 `_idleTimer = Timer(45 s, _releaseEngine)`。两次 `stop` 重叠时，第二次把第一次的定时器引用覆盖掉，第一次的定时器再也取消不了；之后 `open` 只取消第二个，45 秒后第一个触发，把正在播放的引擎释放掉。`stop` 还没结束就 `open`（换线、切房间）也一样：`stop` 在 `open` 之后才设定时器。T05h.1 开发时发现，页面那边用“停止排队”绕开了，包本身没修。
- **改动**（`packages/live_player/lib/src/session.dart`）：`stop` 记下自己的会话代数，`await` 回来后只有它仍是最新的（期间没有新的 `stop`/`open`）才设定时器，设之前先取消已有的；定时器触发时再确认会话代数没变、状态仍是 `stopped` 才释放。
- **测试**：`session_test.dart`“overlapping stops, then an open: no idle release of the playing engine”（两次重叠 `stop`，再 `open`，过 46 秒引擎没被释放、仍在播放）和“a stop still finishing when the next open starts arms no idle release”。两条改之前都失败（`engine.disposed` 为 true）。原有的“stop 后 45 秒释放引擎”测试照常通过。
- **验证**：live_player 全部测试通过。

## release 构建（第 1、5、6 条的原生改动之后）

- 命令：`apps/pure_live` 下 `flutter build apk --release --split-per-abi --target-platform android-arm64`（没有 `key.properties`，用调试密钥签名），提交 `e975d3915` 之上。结果 `✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (110.3MB)`。
- lint：`checkReleaseBuilds = true`、`abortOnError = true`，构建里跑了 `lintVitalAnalyzeRelease` / `lintVitalReportRelease`，报告 `No issues found.`、返回值 0，没有让构建失败。
- `aapt2 dump resources`（build-tools 37.0.0）：
  - `drawable/audio_service_pause`（0x7f070073）、`drawable/audio_service_play_arrow`（0x7f070074）、`drawable/audio_service_stop`（0x7f070077）都在，各有 mdpi～xxxhdpi 五个 PNG，mdpi 文件大小和 audio_service 原图一致（168/285/114 字节，不是压缩器的占位图）；
  - `drawable/ic_stat_playback`（0x7f0700b7）在；
  - 没保留的 `audio_service_skip_next`、`audio_service_fast_forward` 等不在资源表里，说明压缩器确实会删掉没保留的 audio_service 图标（改之前这三个也是这样被删的）。
- 构建后 `gradlew --stop` 停了 Gradle 守护进程，Kotlin 编译守护进程也已退出。

## 检查（最后一次提交前）

- `apps/pure_live`：`flutter analyze` 无问题，`dart format` 无改动，`flutter test` 729 个全部通过（开始前 721 个）。
- `packages/live_player`：analyze、format 通过，34 个测试通过；`packages/live_store`：analyze、format 通过，44 个测试通过。
- `tools/gate/check_ui_structure.py`、`check_deps.py` 通过。没跑完整门禁。
