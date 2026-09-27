# NNNN 系统集成：后台播放、画中画与小窗、Windows 外壳

- 状态：提议（草稿，编号由负责人分配）
- 日期：2026-09-28

## 背景

`spec/product.md` §17–§19（F-WIN-01..07、F-PIP-01..03、F-BG-01、F-NEW-12）和 `spec/modules/playback.md` §2（INT-2..4）、§9（PIP-1..6）、§11（PERF-2）要求在 Android 和 Windows 上接入系统能力：后台播放和媒体通知、音频焦点、系统画中画、应用内小窗、单实例和新窗口、托盘、关闭行为、开机自启、窗口位置记忆、跟随主题的系统标题栏、SMTC。3.x 用了 audio_service、audio_service_win、audio_session、floating、flutter_floating、tray_manager、windows_single_instance、launch_at_startup、win32 等一串依赖，新窗口靠含明文 Cookie 的临时文件交接设置（REG-STORE-024）。

v4 的播放会话（`PlaybackSession`）已经提供挂起令牌、纯音频和可见性接口；直播间页面由另一条工作线负责，系统集成只能提供接口和挂钩点。

## 决定

1. **代码位置**：全部在 `apps/pure_live/lib/features/system/`，入口是 `systemIntegrationProvider`（`PureLiveApp` 监听）和 `MiniPlayerHost`（`MaterialApp.builder`）。平台相关的部分都在接口后面（`MediaControls`、`AudioFocusPort`、`PipPlatform`、`DesktopWindowOps`、`WindowsNative`），测试用假实现。直播间只通过 `nowPlayingProvider`、`pipProvider`、`miniPlayerProvider` 三个接口对接（见“影响”）。

2. **Android 后台播放用 audio_service 0.18.19 + audio_session 0.2.4（均为 MIT，同一作者，2026-06 发版）**。
   - audio_service 负责媒体会话、通知（播放/暂停/关闭）、锁屏和耳机线控、`mediaPlayback` 类型的前台服务，并在播放时持有部分唤醒锁；`MainActivity` 改为继承 `AudioServiceActivity`，服务和界面共用一个 Flutter 引擎。
   - audio_session 本来就是 audio_service 的依赖，改为直接依赖后用它申请音频焦点和接收“耳机拔出”，没有新增包。
   - 自写 Kotlin 只剩两块：画中画（`PictureInPicture.kt`）和 Wi-Fi 锁（`PlaybackLocks.kt`，`WIFI_MODE_FULL_HIGH_PERF`，低延迟模式只在前台生效）。
   - 通知只在“后台播放”开启且有直播间在播时出现；服务在前台播放时启动，暂停时仍留在前台（`androidStopForegroundOnPause: false`），这样后台被打断后恢复不需要重新启动前台服务（Android 12 起后台不能启动前台服务）。媒体会话通知不需要 `POST_NOTIFICATIONS` 权限。
   - 放弃：完全自写前台服务和 MediaSession（约 300 行没法在本机验证的 Kotlin）；audio_service_win（0.0.3，维护情况不明）。

3. **后台策略（INT-3、PERF-2、PIP-5）**：`BackgroundPlayback` 在应用隐藏 1.5 s 后才动作——画中画中不变；开启后台播放时关闭视频输出（`setAudioOnly(true)`，回前台再打开，用户自己选的纯音频不动）；应用内小窗在时继续播放；否则用 `SuspendReason.background` 令牌挂起，回前台用令牌恢复，令牌过期（换房、用户操作）就不恢复。Windows 最小化或隐藏到托盘同样适用，所以想在托盘里听直播要开“后台播放”。

4. **音频焦点（INT-4）**：用户想播放时持有焦点。短暂失去焦点用 `SuspendReason.audioFocus` 令牌挂起，焦点回来用令牌恢复；**永久失去焦点和耳机拔出按用户暂停处理**，因为之后不会再有“焦点归还”，挂起会让画面停在既不显示“暂停”也不显示“缓冲”的状态。短暂压低音量交给系统自动处理（Android 8+）。

5. **媒体控制的同步走独立通道（AUD-5）**：`MediaControlsBridge` 只保留最新一次待发状态，慢的平台调用不阻塞、不回滚播放。“关闭”= 暂停并收起控制，直到用户再次播放。Windows 的 SMTC 对每个在播直播间都显示，不受“后台播放”影响。

6. **Windows SMTC、托盘、单实例、开机自启、标题栏颜色都写在 runner 的 C++ 里**，走一个通道 `purelive/windows`（`system_bridge.cpp`）。
   - SMTC 用 WRL 调 WinRT ABI（`ISystemMediaTransportControlsInterop::GetForWindow`），不抛异常，符合 runner 的 `_HAS_EXCEPTIONS=0`；按钮事件从 WinRT 线程 `PostMessage` 回窗口线程再发给 Dart；链接 `runtimeobject.lib`。
   - 托盘用 `Shell_NotifyIconW`，菜单文字由 Dart 传入，Explorer 重启后（`TaskbarCreated`）自动重新添加。
   - 放弃：tray_manager 0.7.0（改为基于 nativeapi，构建时要编译一整套 C++ 原生库，而且锁在落后的 nativeapi ^0.3.0）；smtc_windows（构建需要 Rust 工具链）；launch_at_startup（为一个注册表值引入 win32_registry 等依赖）；windows_single_instance。
   - window_manager 继续负责窗口大小、位置、最大化、全屏、置顶、无边框和关闭拦截；screen_retriever（window_manager 已依赖）改为直接依赖，用来取各屏幕的工作区。

7. **单实例（F-WIN-01）**：主实例持有 `Local\PureLive.v4.Primary` 互斥量，主窗口挂窗口属性 `PureLive.v4.PrimaryWindow`。第二次启动在创建 Flutter 引擎之前用 `WM_COPYDATA` 把参数转给主实例（最多等 5 s 主窗口出现），然后退出；主实例把窗口带到前台，Dart 准备好之前参数在 C++ 里排队。互斥量名和 3.x 不同，预览版可以和 3.x 同时运行。

8. **新窗口（F-WIN-02）**：启动器只写 `--instance --open-room=平台:房间号` 两个参数，解析时只接受这两种写法（平台必须是已知平台，房间号 1–64 位字母数字和 `_ . -`），其余一律忽略；不再有设置交接文件。新进程打开**同一个数据根目录**：同一个 SQLite 库（WAL）和同一个加密密钥库（DPAPI 按当前用户），所以关注、设置和 Cookie 天然一致。新窗口没有托盘、不参与单实例转发、不记忆窗口位置，关闭即退出。

9. **关闭行为（F-WIN-04）**：设置 `exit.dontAsk` + `exit.choice`（对应 3.x 的 `dontAskExit`、`exitChoose`）。没选“不再询问”时弹窗（最小化到托盘 / 退出 + “不再询问”）；退出前先关闭小窗、硬释放当前播放（SURF-2 的释放顺序在播放器内部完成），再删托盘图标、销毁窗口。

10. **开机自启（F-WIN-05）**：写 `HKCU\…\Run`，值名在预览期为 `PureLiveNext`，不碰 3.x 的 `PureLive`；正式替换 3.x 的版本改回 `PureLive`。设置默认关，每次主实例启动按设置重写一次（exe 位置变了也能跟上）。

11. **窗口位置记忆（F-WIN-06）**：新增 `window.position`（`x,y`）和 `window.maximized`。恢复时要求标题栏至少有一段落在某个屏幕的工作区内，否则居中（屏幕被拔掉的情况）。最大化状态通过通道告诉 runner，由 runner 第一次显示窗口时用 `SW_SHOWMAXIMIZED`，因为首帧前最大化会被 runner 的 `Show()` 还原。小于最小窗口 360×400 的尺寸一定是画中画窗口，不记忆。

12. **系统标题栏跟随应用主题（principles §5.4）**：Dart 按主题设置（跟随系统时按系统亮度）通知 runner 设置 `DWMWA_USE_IMMERSIVE_DARK_MODE`；系统强调色变化时 runner 重新应用应用的选择。window_manager 的 `setBrightness` 只能在系统本身是深色时变深，不能用。

13. **画中画（F-PIP-01/02，PIP-1/2/3）**：`PipController` 先把界面切成只有画面的布局，等两帧后再请求进入；系统上报的状态优先于请求的返回值；关闭或换房时取消进行中的进入；接受了但 3 s 内没有上报就退回普通布局。比例取提交的几何，其次是解码尺寸，限制在 1:2.35–2.35:1（Android 上限 2.39）；之后比例变化不到 0.004 不更新。Android 12+ 用 `setAutoEnterEnabled`，更早的系统在 `onUserLeaveHint` 里进入；“离开应用时自动画中画”默认关（principles §6.1），只在直播间页面正在播放时生效。画中画窗口的播放/暂停是 `RemoteAction`。Windows 画中画把主窗口变成无边框小窗（长边 480，屏幕右下角，保持比例，可选置顶，默认关），拖动画面移动，双击退出，退出时还原大小、位置、最大化和全屏；关闭播放时先还原主窗口（SES-6）。

14. **应用内小窗（F-PIP-03，PIP-4/5/6）**：`MiniPlayerHost` 放在路由之上，有弹出路由（对话框、底部弹层、菜单）时整个小窗 Offstage（REG-PLAY-017）；每个导航器（根和四个分支）各挂一个 `PopupRouteObserver`。只有有画面、没有错误、不是纯音频时才接管；接管后 session 归小窗所有，小窗先等房间页卸载再挂自己的 `LiveVideoView`（一个会话一个表面，SURF-5），关闭时先卸载画面再释放会话（PIP-6）。点小窗回房时先卸载画面再打开房间，房间页用 `reclaim` 取回同一个会话（SES-9）。尺寸长边桌面 350、手机 220。

15. **新增设置**（`live_store` 注册表，均为 `device` 作用域）：`player.miniPlayerOnLeave`（3.x `floatPlay`）、`player.autoPip`、`player.pipAlwaysOnTop`（3.x `windowsPipAlwaysOnTop`）、`window.position`、`window.maximized`、`exit.dontAsk`、`exit.choice`；`values.dart` 新增 `CloseAction`。

## 备选方案与放弃理由

- 完全自写 Android 媒体服务：依赖更少，但几百行 Kotlin 只能等到最终构建才第一次编译，风险高；audio_service 是 PLAN §04 保留的依赖，维护正常。
- 新窗口继续用临时文件交接设置：3.x 的做法把 Cookie 明文写进临时目录（REG-STORE-024），而且每个窗口一个数据目录，关注会分叉。
- 托盘、SMTC 用现成插件：见决定 6。
- 小窗和画中画共用系统悬浮窗（`SYSTEM_ALERT_WINDOW`）：需要额外权限，3.x 也只做应用内小窗。
- 永久失去音频焦点时也挂起：焦点不会归还，界面会停在没有提示的状态；按暂停处理和其他播放器一致。

## 影响

**直播间页面要接的挂钩**（`lib/features/room/*` 由直播间工作线修改）：

1. 打开房间后 `ref.read(nowPlayingProvider.notifier).attach(NowPlaying.fromDetail(session, detail))`；自己关闭会话时 `detach(session)`。后台策略、音频焦点、通知/SMTC、画中画参数都跟着它走。
2. 进入房间时（`initState`）先 `ref.read(miniPlayerProvider.notifier).reclaim(room)`：返回值不为空就复用其中的会话，并在 `surfaceReleased` 完成后再挂 `LiveVideoView`；为空才创建新会话。
3. 离开房间：在 `initState` 里保存 `ref.read(miniPlayerProvider.notifier)`，在 `State.dispose` 里调用 `adopt(nowPlaying)`；返回 true 时不要关闭、释放或 `detach` 会话。`playbackSessionProvider` 的 `onDispose` 要改为 `if (!mini.owns(session)) session.dispose()`。
4. 画中画按钮：`ref.read(pipProvider.notifier).enter(session, sourceRect: 画面在窗口中的物理像素矩形)`；按钮只在 `ref.watch(pipProvider).supported` 时显示。页面用 `PipAwareLayout(session:, video:, builder:)` 包住布局，画中画时只显示画面（Windows 上自带拖动、双击退出和悬停按钮）；控制层在 `pipProvider.videoOnly` 时隐藏。桌面快捷键 P 同样调用 `enter`。
5. “新窗口打开”菜单：`if (newWindowSupported) ref.read(newWindowProvider)(room)`。
6. 返回键缩为小窗（principles §6.1）不需要额外代码：页面照常出栈，`dispose` 里的 `adopt` 决定是否变成小窗。

**第一次构建时要检查**：

- Android：`MainActivity` 继承 `AudioServiceActivity` 后，分享进应用（冷启动和引擎仍在时的新 Activity）、Keystore 通道正常；前台服务类型 `mediaPlayback` 在 Android 14+ 启动不报错；锁屏、耳机、通知按钮；来电打断后恢复；画中画进出 20 次无黑块（PIP-2）；Android 11 及以下的自动画中画；R8 发布构建保留 `ic_launcher_monochrome`（通知小图标）。
- Windows：新文件在 `/W4 /WX` 下编译（本机用 clang-cl 按 MSVC 14.52 和 Windows SDK 10.0.28000 的头文件做过语义检查，没有链接）；`runtimeobject.lib` 链接；SMTC 显示标题、主播、封面，媒体键可用；托盘左键显示/隐藏、右键菜单、Explorer 重启后图标恢复；第二次启动转发参数并置前；`--instance` 新窗口共用数据；最大化状态首次显示；深浅色标题栏切换；退出时无 0xc0000409。
- 两个进程同时写同一个 SQLite 库可能遇到 `SQLITE_BUSY`：`LiveStore.open` 目前只设了 WAL，建议加 `PRAGMA busy_timeout`（`live_store` 的事）。

**建议补进规格**：INT-4 写明永久失去焦点按用户暂停处理；F-WIN-02 写明新窗口共用数据根目录；PIP-3 写明 Windows 画中画窗口长边 480。
