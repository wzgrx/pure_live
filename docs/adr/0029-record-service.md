# 0029 Android 后台录制：specialUse 前台服务，按活跃任务数保活

- 状态：已接受
- 日期：2026-09-28

## 背景

录制在 Dart 里运行（`live_record`，ADR 0021）。Android 上用户锁屏、切走或划掉应用后，进程会被降到后台：Android 14 起缓存进程几秒后被冻结，没有前台服务的进程随时可能被回收；Flutter 引擎由 audio_service 缓存，AudioService 在没有 Activity 时被销毁会连带销毁引擎（`AudioServicePlugin.disposeFlutterEngine`）。3.x 用一个 `dataSync` 类型的前台服务、唤醒锁、Wi-Fi 锁和对 AudioService 的绑定解决这些问题（`RecorderForegroundService.kt`、`RecorderBackgroundPlugin.kt`，共约 800 行，按代次隔离、各有 15 s 启动和停止超时）。

规格和产品清单里留着一个待确认（product F-REC-06、record.md §16.1、诊断 08 ①）：应用目标 Android 17（targetSdk 37），而从目标 Android 15 起系统限制 `dataSync` 前台服务的运行时间。调研结论（Android 开发者文档“Foreground service timeouts”“Foreground service types”“Changes to foreground services”，2026-09-28 查阅）：

- `dataSync` 和 `mediaProcessing` 两种类型在 24 小时内合计只能运行 6 小时；两种类型分别计时，同类型的所有服务共用一个额度。
- 到时系统调用 `Service.onTimeout(int, int)`，此后服务不再算前台服务，必须在几秒内 `stopSelf()`，否则应用崩溃（`RemoteServiceException: A foreground service of type … did not stop within its timeout`）。
- 额度用完后，在用户把应用切到前台之前，启动同类型服务会抛 `ForegroundServiceStartNotAllowedException`（“Time limit already exhausted for foreground service type dataSync”）；用户把应用切到前台会重置计时。
- 目标 Android 15 起，`dataSync` 也不能从 `BOOT_COMPLETED` 启动（本应用不涉及）。
- Android 16 起前台服务里启动的后台作业要守各自的配额；官方为“用户发起的数据传输”推荐 UIDT 作业。
- `specialUse` 覆盖其它类型都不适用的正当用途，没有运行时间上限；要求 manifest 里用 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` 写明用途，上架 Google Play 时由审核员查看。

一场直播常常超过 6 小时，开播监控再加过夜录制更长；到 6 小时服务被停，进程失去保活，录制就断了。

## 决定

1. **服务类型用 `specialUse`**。manifest 写子类型说明“直播录制：把用户选择录制的直播流写成本地文件，直到下播或用户停止”。Android 14 起 `startForeground(id, notification, FOREGROUND_SERVICE_TYPE_SPECIAL_USE)`，更早的系统调用不带类型的 `startForeground`（使用 manifest 里的类型）。本应用只在 GitHub 等渠道发布，不受 Google Play 审核约束；以后上架时用途说明已经写好。
2. **独立的原生文件 `RecordService.kt`**，方法通道 `purelive/record`：
   - `update(title, text)`：第一次调用时获取部分唤醒锁和高性能 Wi-Fi 锁、绑定 audio_service 的 AudioService（`BIND_AUTO_CREATE`，保住共用的 Flutter 引擎）、`startForegroundService`；之后只刷新通知。返回 false 表示系统拒绝启动（Android 12 起从后台启动会被拒），此时锁和绑定照常保留。
   - `stop`：停止服务，释放锁，解绑 AudioService。
   - 原生回调 `onTimeout`：服务收到 `onTimeout` 时立即 `stopForeground` + `stopSelf`，唤醒锁再保留最多 45 s，通知 Dart。
   - 服务在 `onStartCommand` 里立刻 `startForeground`；按启动代次忽略旧服务迟到的 `onDestroy`。Android 13 起第一次启动时若应用在前台，请求一次通知权限；拒绝也照常录制。
3. **Dart 按活跃任务数驱动**（`lib/core/recording.dart` 的 `RecordKeepAlive`，只在 Android 上创建）：订阅 `RecordManager.activeCountChanges` 和任务快照，计算通知（“正在录制 N 个直播间”+ 主播名；只剩收尾时“正在处理录制文件”），有变化才调用 `update`；活跃数归零时先 `RecordManager.flush()` 把终态落盘，再 `stop`。一个进程级状态，不按任务发租约，所以旧会话结束不会停掉新会话的保活。
4. **系统超时仍然处理**（`specialUse` 不会触发，作为防御）：Dart 收到 `onTimeout` 后对全部活跃任务 `interruptAll`（有界收尾，标失败“后台运行时间被系统用尽”），再 `stop`；应用回到前台之前不再启动服务（与系统“切回前台才重置”一致）。
5. **不改 `MainActivity.kt` 和 `AndroidManifest.xml` 之外的东西**：注册只需在 `configureFlutterEngine` 里加一行 `RecordKeepAlive.attach(this, messenger)`；manifest 需要 `FOREGROUND_SERVICE_SPECIAL_USE`、`POST_NOTIFICATIONS` 两个权限和服务声明（`WAKE_LOCK`、`FOREGROUND_SERVICE` 已有）。

## 备选方案与放弃理由

- **继续用 `dataSync`，到 6 小时有界收尾并标失败**（3.x 的做法）：长录制必然在 6 小时处断掉，用户只能回到前台手动重开；过夜录制和开播监控基本不可用。
- **`dataSync` 到时自动切到另一个服务**：额度按类型共享，同类型换服务没用；在后台也不能启动新的前台服务。
- **`mediaProcessing`**：同样 6 小时上限，而且语义是转码类的本地处理。
- **`mediaPlayback`**：没有时间限制，但语义是播放；Google Play 政策也不允许非播放用途，将来上架会被拒。audio_service 的播放服务已经用这个类型，混用会让两种通知和生命周期纠缠。
- **UIDT（用户发起的数据传输作业）**：必须由用户在前台的操作当场启动，面向有明确大小和进度的传输；开播监控触发的录制、一场没有尽头的直播都不符合；作业也不保活 Flutter 引擎。
- **沿用 3.x 的两个文件和代次状态机**：启动和停止各 15 s 超时、按任务租约计数，是为了应对 `dataSync` 的超时和并发启动；按活跃数驱动一个进程级状态后这些都不需要，一个文件约 300 行（含注释）。
- **开播监控期间也运行服务**：`specialUse` 允许，能让后台监控可靠；但要常驻通知并持有唤醒锁，耗电明显。规格 §16.1 暂定只在有活跃会话时运行，留作待确认，第 5 阶段真机评估。

## 影响

- `spec/modules/record.md` §16.1 按本决定改写，§23 第 7 项关闭并新增“后台监控是否运行服务”；`spec/product.md` F-REC-06 和待确认第 1 项关闭。
- 主会话需要在 `AndroidManifest.xml` 加两个权限和服务声明，在 `MainActivity.configureFlutterEngine` 加一行注册（见实现提交说明）。
- 真机验收（第 5 阶段）：锁屏录制 ≥ 7 小时不中断（跨过 6 小时）；录制中从最近任务划掉应用，录制继续、通知在，全部结束后通知消失、进程可被回收；Android 13+ 拒绝通知权限时照常录制；Android 12+ 后台开播触发录制时服务被拒的表现；在调试构建里直接调用服务的 `onTimeout` 验证有界收尾（3.x 的 `debugInjectTimeout` 做法）。
