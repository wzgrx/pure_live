# O04 权限

通知、电池优化、存储、本地网络。

应用向 Android 要的运行时权限和特殊权限：什么时候问、问之前说明什么、拒绝或永久拒绝后怎么办，以及原生怎么判断和申请。

## 范围

- 包括：
  - **通知和电池优化**：`PermissionsPlugin.kt`（通道 `pure_live/permissions`）和 Dart 一侧 `platform/system_permissions.dart`、`shared/permission_prompts.dart`（`BackgroundPermissions`、`RecordingPermissionPrompts`、`showPermissionDialog`）；设置开关的守门 `switchGateProvider`（`features/settings/playback_tiles.dart:72`）。
  - **本地网络（Android 17）**和**安装未知应用**：`SystemAccessPlugin.kt`（通道 `pure_live/system_access`）和 `platform/system_access.dart`（`SystemAccess`、`ensureLocalNetworkFor`、`LocalNetworkGuard`）；四个使用方：局域网代理（启动时和改代理设置后）、设备同步、投屏搜索、局域网直播源（直播间、网络电视回看、多画面）。
  - **存储（录制目录）**：`RecorderPlugin.kt` 的 `storageGranted`、`requestStorage`（Android 11+ 所有文件访问，10 及以下读写存储），Dart 的 `androidStorageAccess`（`platform/recording_platform.dart:322`）。
  - 清单里的权限声明（`AndroidManifest.xml:4-30`）和请求码的分配。
- 不包括（归哪里）：
  - 权限说明框、提示条的样子和文字 → A14.1 c12～c14。
  - 后台播放、助眠什么时候要通知权限 → C02；录制什么时候要 → H02；哪些代理地址算局域网 → Q02（`packages/live_net/lib/src/proxy.dart:121` 的 `isLocalNetworkProxyHost`）；网络状态和权限的网络层部分 → Q04。
  - 投屏协议 → N02；设备同步协议 → J05；应用内更新的下载 → Y02、I01.3（只有“安装未知应用”的判断在这里）。
  - 相机权限（扫码）由 mobile_scanner 插件自己申请 → O03（插件接入）。

## 现状：做到哪、怎么工作的

用户看得到的：

- **打开“后台播放”或“新直播间自动助眠”**（设置 → 视频）：通知没开时先弹说明“需要通知权限”（取消 / 去开启）→ 系统框；拒绝时开关保持关、不变红。永久拒绝（拒绝两次，或系统设置里关了）时说明框换成“通知权限已关闭”+“去设置”，从系统设置回来自动再查一次，开了就打开开关。接着问电池优化（说明 → 系统的“允许后台运行”框），不给也照样打开开关（同 3.x）。
- **第一次开始录制而通知关着**：在前台时说明一次（meta `permission.recordingNotifications` 记住），不等它就开始录。**录制目录要写公共目录而没有所有文件权限**：先说明，确定后跳系统的“所有文件访问”页，取消就不跳。
- **本地网络（Android 17，K90 就是）**：代理指向局域网（例如电脑上的 Clash）时，启动后和改完代理设置 1 秒后申请，一次运行只问一次，拒绝时提示“未获得「本地网络」权限，局域网代理（如电脑上的 Clash）无法连接。请在系统设置 → 应用 → 纯粹直播 → 权限中允许。”；投屏每次搜索前申请，拒绝提示“……无法搜索投屏设备……”；直播地址是局域网地址（家里的 IPTV 服务器）时先申请，拒绝提示“……局域网里的直播源……无法连接……”；设备同步开始前申请，拒绝时提示的是局域网代理那句（3.x 也是，见已知问题）。Android 16 及以下直接当已允许。
- **安装更新包**：版本页“下载并安装”前查“安装未知应用”，没有就打开系统页（I01.3、Y02）。

内部怎么工作：

```text
通知：BackgroundPermissions.confirm（permission_prompts.dart:85）
  → SystemPermissions.notifications（system_permissions.dart:40）→ 原生 notificationState（PermissionsPlugin.kt:91）
       granted / askable（Android 13+ 还能弹框）/ blocked（问过一次且系统不再给理由、或设置里关了、或 12 及以下）
  → askable：说明框 → requestNotifications（:107，记 notificationsAsked）→ 系统框
  → blocked：说明框“去设置”→ openNotificationSettings（:149）→ nextResume 回来再查
  → 电池：batteryUnrestricted（:127）→ 说明 → requestBatteryUnrestricted（:133，ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS）
本地网络：ensureLocalNetworkFor(urls)（system_access.dart:56）只在有局域网地址时 → SystemAccess.requestLocalNetwork
  → 原生 requestLocalNetwork（SystemAccessPlugin.kt:118）：API < 37 或已允许直接 true；否则 requestPermissions(ACCESS_LOCAL_NETWORK, 20261003)
  LocalNetworkGuard（system_access.dart:67）：app/startup.dart:76 启动，跟 enableAppProxy/appProxyHost/enableProxy/proxyHost，settle 1 秒
存储：androidStorageAccess（recording_platform.dart:322）→ canWrite → explain → 原生 requestStorage（RecorderPlugin.kt:173）
```

- 完成度：清点第 2 节 F-AND-03（后台播放的权限）“完成”，K90 上打开后台播放时的说明、通知权限、电池页都看过（S02.2）；F-AND-04（Android 17 本地网络）“没验证”，归 [O04.1](O04.1-Android17本地网络权限/README.md)。永久拒绝后“去设置”回来、录制的通知说明和所有文件权限说明没在真机看。
- 和 3.x 比：3.x 用 permission_handler（`pubspec.yaml:126`），4.x 自己写两个插件；行为照 3.x（通知被拒不打开开关、电池不阻止）。多了：说明框（A14.1 c12～c14）、永久拒绝时去设置并回来再查、第一次录制的通知说明、所有文件权限先说明；投屏和局域网直播源也申请本地网络（4.0.0 发布前 Y01.1 第 4 节加的，3.x 只有代理和设备同步）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/PermissionsPlugin.kt`（205 行） | 通道 `pure_live/permissions`；请求码 `NOTIFICATION_REQUEST` 20261001、`BATTERY_REQUEST` 20261002（:43-44）；`SharedPreferences` `pure_live_permissions` 的 `notificationsAsked`（:45-46）；`notificationsAllowed`（:77，Android 13+ 先看运行时权限，再看 `areNotificationsEnabled`）、`notificationState`（:91）、`requestNotifications`（:107）、`batteryUnrestricted`（:127）、`requestBatteryUnrestricted`（:133，厂商去掉了这个框时回答 false）、`openNotificationSettings`（:149，先通知设置页再应用详情）；结果回调（:166-185） |
| `.../SystemAccessPlugin.kt`（143 行） | 通道 `pure_live/system_access`：`canInstallPackages`（:88）、`openInstallSettings`（:93）、`localNetworkGranted`（:106，API < 37 返回 true）、`requestLocalNetwork`（:118，同时只允许一个请求）、请求码 20261003（:42）；Activity 分离时把挂着的请求按当前状态回答（:70-75）。另有 `sensorLandscape`（:112，属 O05） |
| `.../RecorderPlugin.kt`（242 行） | `storageGranted`（:163，Android 11+ `isExternalStorageManager`）、`requestStorage`（:173，先本应用的所有文件访问页，没有就总列表页；10 及以下申请读写存储）；请求码 20260907 |
| `apps/pure_live/android/app/src/main/AndroidManifest.xml` | `POST_NOTIFICATIONS`（:8）、`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（:28）、`WRITE_EXTERNAL_STORAGE`（≤29）、`READ_EXTERNAL_STORAGE`（≤32）、`MANAGE_EXTERNAL_STORAGE`（:12-16）、`ACCESS_LOCAL_NETWORK`（:21）、`REQUEST_INSTALL_PACKAGES`（:25）、`READ_MEDIA_AUDIO`/`VIDEO`（:29-30，照 3.x 声明，4.x 没有申请它们的代码） |
| `apps/pure_live/lib/platform/system_permissions.dart`（74 行） | `NotificationPermission`（granted / askable / blocked）、`SystemPermissions`（:26）：非 Android 或原生出错时一律当允许 |
| `apps/pure_live/lib/shared/permission_prompts.dart`（217 行） | `showPermissionDialog`（:30，通用说明框）、`nextResume`（:49）、`BackgroundPermissions`（:72，`confirm` :85）、`RecordingPermissionPrompts`（:146：`notificationsOnce` :168、`explainStorage` :207） |
| `apps/pure_live/lib/platform/system_access.dart`（125 行） | `SystemAccess`（:12，非 Android 一律允许，测试用 `debugCall`）、`isLocalNetworkUrl`（:47）、`ensureLocalNetworkFor`（:56）、`LocalNetworkGuard`（:67，settle 1 秒，`_asked` 一次运行只问一次） |
| `apps/pure_live/lib/features/settings/playback_tiles.dart` | `switchGateProvider`（:72，默认用 `BackgroundPermissions`）、开关守门的结果 `SwitchGateResult`（取消时 `cancelled`，开关不变红） |
| 本地网络的使用方 | `app/startup.dart:76`（`LocalNetworkGuard` 启动）；`features/live_play/logic/room_controller.dart:489`（取流）、`:691`（网络电视回看）；`features/multiview/logic/multiview_controller.dart:590`；`features/live_play/dialogs/stream_dialogs.dart:336`（投屏搜索）；`features/remote_receiver/remote_sync_service.dart:180`（设备同步） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/shared/permission_prompts_test.dart`（7 个） | 已允许不问；通知和电池两个说明（通用对话框布局）；取消、拒绝、电池不阻止；永久拒绝去设置后回来再查；`switchGateProvider` 的映射；录制的通知说明（只在前台、只一次）；所有文件权限先说明、取消不跳 |
| `apps/pure_live/test/services_test.dart` | 局域网代理只问一次（:336）；局域网直播源先申请、拒绝时提示（:366） |
| `apps/pure_live/test/features/live_play/live_play_more_test.dart`、`live_play_more_page_test.dart` | 局域网源打开前先申请（`live_play_more_test.dart:214`）；投屏搜索前先申请（`live_play_more_page_test.dart:233`） |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 各插件的请求码全应用唯一 |
| `apps/pure_live/test/features/settings/settings_playback_test.dart` | 取消说明后开关不打开、不变红 |

## 3.x 基线

- `git show v3.2.11:pubspec.yaml`：`permission_handler: ^13.0.1`（:126）。
- 通知和电池：`lib/player/core/live_audio_service.dart:207-227`（打开后台播放时问通知，没给就不打开；再问电池，不给也打开）、`lib/modules/settings/pages/video_settings_page.dart:327-371`（开关的接线）。录制不问通知。
- 本地网络：`lib/common/services/local_network_access.dart`（42 行）：`ensureForProxies`（代理指向局域网时，一次运行只问一次）、`ensure`（设备同步 `lib/modules/remote_receiver/remote_sync_service.dart:154`）；`proxy_settings_controller.dart:41-51` 改代理后防抖申请。3.x 的投屏和局域网直播源不申请。
- 清单：3.x `android/app/src/main/AndroidManifest.xml:21` 同样声明 `ACCESS_LOCAL_NETWORK`，`targetSdk = 37`（`android/app/build.gradle.kts:55`）。
- 必须保留：通知被拒时“后台播放”开关不打开；电池优化不阻止；`enableBackgroundPlay`、`enableAsmrSleepMode` 键和含义不变（D-018）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| Android 17 本地网络权限没在真机走过（K90 就是 Android 17） | `SystemAccessPlugin.kt:106-130`；四个使用方 | 不知道系统框什么时候出、拒绝后会不会每次都弹、各处提示对不对 | [O04.1](O04.1-Android17本地网络权限/README.md) |
| 设备同步被拒时提示的是“局域网代理（如电脑上的 Clash）无法连接” | `features/remote_receiver/remote_sync_service.dart:180-181` 用 `local_network_permission_denied` | 用户在设备同步里看到讲代理的话，会以为设置错了（3.x 一样，`remote_sync_service.dart:154` 调同一个 `ensure()`） | O04.1 真机确认后，建议加一句设备同步专用的提示（新翻译键，例如 `local_network_denied_sync`），小改动，没有任务 |
| 本地网络被永久拒绝后没有“去设置”按钮，只有提示文字 | `system_access.dart:56-61`、`:106-116` | 用户要自己找系统设置 | 照 3.x，暂不做；O04.1 看实际体验 |
| 永久拒绝通知后“去设置”再回来的分支、录制的两个说明没在真机看 | `permission_prompts.dart:85`、`:168`、`:207` | — | 没有专门的任务；建议 S02.5 第二阶段（录制）和第四阶段（设置和通知）顺带 |
| 清单声明了 `READ_MEDIA_AUDIO`、`READ_MEDIA_VIDEO`、`FOREGROUND_SERVICE_REMOTE_MESSAGING`，4.x 没有用到 | `AndroidManifest.xml:27`、`:29-30` | 应用商店审核或用户查看权限时多几项（照抄 3.x） | 不做；以后上架时再评估（Y） |
| 厂商系统去掉了“允许后台运行”框时，电池优化直接回答“没给” | `PermissionsPlugin.kt:139-147` | 用户不知道要自己去设置 | 照 3.x，不阻止开关；不做 |

## 相关决定和规范

- D-004（只做 Android）、D-018（权限相关的设置键不变）、D-019（真机只点测试包，测完恢复系统设置）。
- A14.1 c12（通知说明）、c13（永久拒绝去设置）、c14（录制的说明）；O03.2 c4、c6。
- 请求码全应用唯一：每个监听者都会收到所有权限和 Activity 结果（`SystemAccessPlugin.kt:39-42` 的注释），新加请求码时查一遍三个插件。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/shared/permission_prompts_test.dart test/services_test.dart test/platform/system_surfaces_test.dart`。系统框、权限状态、AppOps 只能在真机看。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 1 节第 10 条（后台播放的权限）、第 5 节第 8 条（本地网络）。重置权限：`adb shell pm revoke com.mystyle.purelive.v4dev android.permission.POST_NOTIFICATIONS`、`… android.permission.ACCESS_LOCAL_NETWORK`；清掉“不再询问”：`adb shell pm clear-permission-flags com.mystyle.purelive.v4dev <权限> user-set user-fixed`；电池：`adb shell dumpsys deviceidle whitelist -com.mystyle.purelive.v4dev`。

## 路线

1. **O04.1**（第二档，小）：K90 上验证本地网络权限的四个使用方；顺带确认设备同步的提示文字问题，结果决定要不要加提示键。
2. S02.5 第二、四阶段顺带：永久拒绝通知后“去设置”回来、录制的通知说明和所有文件权限说明。
3. 以后：Android 新版本加新的运行时权限时（例如更细的后台限制），在这里登记验证任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`PermissionsPlugin.kt`、`SystemAccessPlugin.kt`、`platform/`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| O04.1 | Android 17 本地网络权限在 K90 上验证：局域网代理、设备同步、投屏、局域网直播源 | 验证 | 未开始 | — | — | [设计或说明](O04.1-Android17本地网络权限/README.md) |

## 还没完成的

- **O04.1 Android 17 本地网络权限在 K90 上验证：局域网代理、设备同步、投屏、局域网直播源**（未开始，第二档，规模 小）
  - 说明：K90 就是 Android 17（S02.2 记录），不用另找设备；投屏和局域网直播源的申请是 Y01.1 第 4 节加的（V03.3 核对）

<!-- docs:生成结束 -->
