# O01.3 后台播放增强：记录

- 日期：2026-10-09
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区 `worktree-agent-a056a66757ca8b6b4`（从 master `d70f973ff` 开始）；提交见文末
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 一、根因审查（先审查，后动手）

行号是改之前的（master `d70f973ff`）；第三方插件的行号是 `~/.pub-cache/hosted/pub.dev/audio_service-0.18.19/`。

### 1. 现在后台播放是怎么工作的

- 开关：设置 → 视频 → 后台与助眠 →“后台播放”（`enableBackgroundPlay`，3.x 的键，`packages/live_store/lib/src/settings/settings.dart:21`）；打开时问通知权限、电池优化（`shared/permission_prompts.dart:85-103`，O04）。助眠会话（`enableAsmrSleepMode`）也算（`shouldContinueInBackground`）。
- 后台规则 `RoomBackgroundPolicy`（`apps/pure_live/lib/features/live_play/logic/background_playback.dart:405-569`，C02）：
  - 离开应用（`hidden`/`paused`/`detached`）：没开后台播放 → 1.5 秒后暂停（`:528-536`），回来继续；开着 → 拿唤醒锁和 Wi-Fi 锁（`:524-526`），继续播。
  - 媒体通知 `RoomMediaNotification`（`:299-396`，audio_service 0.18.19 的 `AudioService`，清单里是 `mediaPlayback` 前台服务）：只在前台第一次显示（`:465-471`，Android 12+ 不允许后台启动前台服务）；按钮“暂停/播放”“停止”（`mediaControls` `:276-294`；“停止”= 暂停 + 移除通知，`stop: _session.pause` `:480`，`_RoomAudioHandler.stop` `:267-270`）。
  - 锁：`BackgroundKeepAlive`（`:233-247`）→ `MainActivity.setPlaybackKeepAlive`（`MainActivity.kt:707-735`）：`PARTIAL_WAKE_LOCK` + Android 10 起 `WIFI_MODE_FULL_LOW_LATENCY`，以下 `HIGH_PERF`。
- 视频：离开应用只调 `setPresentationVisible(false)`（`:523`），它只关“画面卡住”的看门狗（`packages/live_player/lib/src/session.dart:506-519`），**视频继续解码**。手动“纯音频”（`room_controller.dart:840`）才关视频输出。
- 弹幕：后台规则不碰弹幕，**一直连着**（`room_controller.dart:1109` `_wantsDanmaku` 只看两个显示开关）。
- 音频焦点（G05.1，`features/live_play/logic/audio_focus.dart`）：来电暂停、结束后恢复，提示音压低，拔耳机暂停。
- 画中画（O02）：画中画里应用是 `inactive`，不算离开；`mayStartInBackground` 认画中画（`:439`）。
- 录制：自己的 `dataSync` 前台服务（`RecorderForegroundService.kt:93`），绑住媒体服务（`:306`），和后台播放互不影响。

### 2. 发现的问题和根因

| 编号 | 问题 | 根因（文件:行） | 影响 |
|---|---|---|---|
| R1 | **后台重连时丢掉前台服务，之后起不来**（最主要的“后台播着播着停了”） | `_syncNotification` 只把 `playing`/`buffering` 当“在播”（`background_playback.dart:461`）。后台里 session 的恢复是 `opening`（`ReconnectWatch` 也这么认，`reconnect_watch.dart:39-41`），重新加载先 `stop` 再 `opening`，断流是 `error`，下播是 `idle`——都走 `:485-489` `_show(playing: false)`。audio_service 收到 `playing=false`：`setState`（`AudioService.java:559-563`）→ `exitPlayingState`（`:715-719`）→ `androidStopForegroundOnPause` 默认 true（`androidNotificationOngoing: true` 要求它为 true，`audio_service.dart:3523-3526`）→ `stopForeground` 并放掉它自己的唤醒锁（`:721-724`）。恢复时 `enterPlayingState`（`:705-713`）在后台调 `startForegroundService`/`startForeground`：Android 12+ 不在豁免名单（电池优化白名单等）时抛 `ForegroundServiceStartNotAllowedException`，没有 catch，Flutter 通道把它当错误回给 Dart（`AudioServicePlugin.java:998`），只记日志 | 没有前台服务的后台进程：Doze 里没网、唤醒锁被忽略（AOSP 只放过 `PROCESS_STATE_FOREGROUND_SERVICE` 及以上）；HyperOS 会马上冻结（红薯助手的 K90 经验：被拉起的后台进程立刻 `cgroup.freeze=1`），Dart 的定时器（重试、60 秒刷新）全停。表现：网络抖一下、主播重推流、锁屏久了，后台播放就停，回到应用才继续 |
| R2 | 来电后恢复也会丢前台服务 | G05.1 在后台来电时 `session.pause()`（`audio_focus.dart` `_pauseForFocus`）→ `paused` → 同 R1 停前台服务；挂断后从后台 `resume` → 同 R1 起不来。Android 15 起拿音频焦点还要求“顶层应用或有前台服务” | 打完电话直播不继续，或者继续了但很快被冻结 |
| R3 | 用户在后台暂停后仍拿着锁 | `onHidden` 只看“开着后台播放”就拿锁（`:524-526`），回到前台（`:547`）、离开直播间（`:565`）才放 | 通知栏/锁屏暂停、拔耳机、助眠到时之后，唤醒锁和 Wi-Fi 锁一直拿着，白耗电 |
| R4 | Wi-Fi 锁后台不起作用（Android 10～13） | `MainActivity.kt:719-730` 在 API 29+ 只拿 `WIFI_MODE_FULL_LOW_LATENCY`；按 Android 文档低延迟锁只在应用位于前台且亮屏时生效。API 29～33 上 `HIGH_PERF` 后台仍有效；API 34 起系统把 `HIGH_PERF` 换成低延迟锁 | Android 10～13 锁屏后 Wi-Fi 进省电，偶尔卡顿 |
| R5 | 后台断流后不再重试 | session 自己只重试两轮（`SessionTimings.liveRetryDelays` 750 ms、2 s，`session.dart:71`），用完 `_publishError` 停下（`:1404-1410`）；前台有“重试”按钮，后台没人点。60 秒一次的 `refreshDetail`（`room_controller.dart:478`）只在“直播间不在播且出错”时重载（`:1056-1064`），主播还在播、只是流断了的不管 | 地铁、电梯、Wi-Fi 换移动数据、CDN 抖动超过十几秒，后台播放就永远停了。断网本身 session 会一直探测（`:1414-1520`，`networkLostCode`），前提是进程没被冻结（R1） |
| R6 | 网络切换不触发重试 | 直播间不看网络变化（`app/network.dart:55` 的 `networkChangesProvider` 只有列表页用）；Wi-Fi 换移动数据靠 session 的 4 秒/12 秒卡住判断发现（`SessionTimings.stallNotice`/`bufferingStall`）；报错停下后网络回来也不管 | 同 R5 |
| R7 | 后台还在解码视频 | 见第 1 节 | 硬解 1080p/4K 白耗电、发热（3.x 一样） |
| R8 | 后台弹幕一直连着 | 见第 1 节 | socket、解析、聊天列表白跑；没开后台播放、已经暂停的直播间也收（3.x 一样） |
| R9 | 关掉画中画后仍在后台出声 | 开着后台播放时，画中画窗口的 ✕ 或拖走让 Activity `onStop`（hidden），后台规则当成“切到后台”继续播（`:524-526`） | 很多人关小窗的意思是“不看了”（3.x 一样） |
| R10 | 通知按钮 | 只有“暂停/播放”“停止”；“停止”= 暂停 + 移除通知；没有“下一个直播间” | 不改“停止”的意思（3.x 一样）；不加切房间（README S6） |
| R11 | 厂商系统的后台限制没有引导 | 只有打开开关时的通知和电池优化框（`permission_prompts.dart:85-103`）；厂商去掉了电池优化框时直接当“没给”（`PermissionsPlugin.kt:139-147`）；小米自启动/省电策略、OPPO 自启动/耗电保护/后台冻结、vivo 后台高耗电、华为应用启动管理、三星休眠应用都没有入口；读得到的状态（媒体通知类别被单独关、Android 9 的“受限”、流量节省）没读 | 用户不知道还要改哪里，以为应用有 bug |
| R12 | 清单和权限 | 不缺：`AudioService` 声明 `foregroundServiceType="mediaPlayback"`（`AndroidManifest.xml:128-134`）和 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`（`:7`），满足 Android 14 的类型要求；`POST_NOTIFICATIONS`（`:8`）有运行时申请；`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（`:28`）3.x 就有；`mediaPlayback` 在 Android 15 没有 6 小时上限（只有 `dataSync`、`mediaProcessing` 有） | 不用改清单 |
| R13 | 引擎在后台停定时器？ | Flutter 后台只停帧回调和 Ticker，Dart 的 `Timer` 照跑；session、刷新、助眠、录制都用 `Timer`；`FloatingRoom._release` 已给帧回调配了 1 秒兜底（`room_runtime.dart:176-189`）。真正让定时器停下的是进程被冻结（R1） | 修好 R1 即可 |
| R14 | 回到前台会不会两份声音 | 同一个 `RoomRuntime`、同一个 session；`onResumed`（`:541-555`）只恢复自己暂停的、C01.5 回来再开 | 没有问题；新加的重试、纯音频、断开弹幕都要在回到前台时撤销（已测） |
| R15 | 录制在后台 | 见第 1 节；`dataSync` 每天 6 小时上限是已知限制（O01 已知问题） | 本任务不改 |
| R16 | 画中画和后台 | 画中画不算离开：不暂停、不拿锁、能启动前台服务（可见）；只有关掉画中画（R9）才进入真正的后台 | 新的“离开应用时”开关在画中画显示时不生效（已测） |

### 3. 各家系统会怎么停后台（和本任务的对策）

| 系统 | 会停掉后台播放的东西 | 应用能不能读到 | 对策 |
|---|---|---|---|
| 所有 Android 12+ | 后台不能启动前台服务；Doze 断网、忽略唤醒锁 | — | R1、R2：后台时一直保持前台服务 |
| Android 13+ | 通知权限（`POST_NOTIFICATIONS`）；没有它媒体通知不显示（服务照跑） | 能 | 检查页“通知”；打开开关时已经问（O04） |
| Android 14+ | 前台服务必须声明类型 | — | 清单已有 `mediaPlayback`（R12） |
| Android 9+ | 设置里“受限”（`isBackgroundRestricted`） | 能 | 检查页“后台限制”（只在受限时出现） |
| 所有 | 流量节省（Data Saver）不让后台用移动数据 | 能 | 检查页“流量节省”（只在限制时出现） |
| 所有 | 电池优化（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`） | 能 | 检查页“电池优化”：先系统框，厂商去掉了就打开列表页，再不行打开应用信息 |
| 小米 HyperOS/MIUI | 自启动；省电策略（HyperOS“电量消耗”）不是“无限制”；一键清理；HyperOS 冻结没有前台服务的后台进程 | 不能 | 自启动页（`com.miui.securitycenter/...AutoStartManagementActivity`）、省电策略页（`com.miui.powerkeeper/...HiddenAppsConfigActivity`，带包名和应用名）、最近任务锁定说明；冻结靠 R1 |
| OPPO/一加/realme ColorOS | 自启动；耗电保护、后台冻结、异常耗电自动优化 | 不能 | 自启动页（`com.coloros.safecenter` 两个版本、`com.oppo.safe`）、耗电页（`com.coloros.oppoguardelf/...PowerUsageModelActivity`）、锁定说明 |
| vivo/iQOO OriginOS/Funtouch | 后台高耗电；自启动 | 不能 | 后台高耗电页（`com.vivo.abe/...ExcessivePowerManagerActivity`、`com.iqoo.powersaving`）、自启动页（`com.vivo.permissionmanager`、`com.iqoo.secure`）、锁定说明 |
| 华为 EMUI/HarmonyOS、荣耀 MagicOS | 应用启动管理（自动管理会清理） | 不能 | 启动管理页（`com.huawei.systemmanager` 三个版本；荣耀 `com.hihonor.systemmanager`）、锁定说明 |
| 三星 One UI | 休眠应用、深度休眠应用；电池“受限” | 部分（“受限”能读） | 应用信息 → 电池；电池页（`com.samsung.android.lool` 两个版本） |
| 魅族 Flyme | 后台管理 | 不能 | 后台管理页（`com.meizu.safe/...SmartBGActivity`） |

每一项的页面都按顺序试，最后一个都是“应用信息”（`ACTION_APPLICATION_DETAILS_SETTINGS`）；打开的是应用信息时提示“已打开应用信息，请在里面找‘某某’”，什么都打不开时提示去系统设置里手动改。

## 二、逐条对照（任务书）

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 后台保活（R1、R2、R3） | 做了 | 新类 `BackgroundKeeper`（`features/live_play/logic/background_keeper.dart`）决定离开应用时保持什么；后台规则用它决定通知的“在播”和锁 |
| c2 后台断流重试、网络切换（R5、R6） | 做了 | 节奏和上限见 README S2 |
| c3 Wi-Fi 锁（R4） | 做了 | Android 10～13 另拿一个 `HIGH_PERF` 锁；没在真机测 |
| c4 来电（R2） | 做了 | `RoomAudioFocus.pausedUntilInterruptionEnds`、`forgetResume`；通知上按暂停取消来电结束后的恢复 |
| c5 后台只播声音（R7） | 做了 | 新设置，默认关 |
| c6 后台断开弹幕（R8） | 做了 | 新设置，默认关 |
| c7 关闭画中画时暂停（R9） | 做了 | 新设置，默认关；两种回调顺序都处理 |
| c8 后台播放设置页（R11） | 做了 | 新子页面、新原生通道 `pure_live/background_guide` |
| c9 打开后台播放后的一次提示 | 做了 | 只在有厂商项的手机上、只一次（`LiveStore.meta` 的 `backgroundGuide.offered`） |
| c10 清单（R12） | 不用改 | 见 R12 |
| c11 通知“下一个直播间” | 没做 | README S6 |

## 三、改了哪些文件

- Dart
  - `apps/pure_live/lib/features/live_play/logic/background_keeper.dart`（新，O01）：`BackgroundKeeper`、`KeeperInput`、`BackgroundHold`；时钟和定时器可注入。
  - `apps/pure_live/lib/features/live_play/logic/background_playback.dart`（C02）：`RoomBackgroundPolicy` 用 keeper 决定通知的“在播”和锁；通知的暂停和停止走 `_userPause`；`online` 网络流；`interrupted`、`onUserPause` 接音频焦点；“离开应用时”三个开关；`BackgroundKeepAlive` 加 `debugLog`、`debugReset`，在别的平台也记下状态（测试用）。
  - `apps/pure_live/lib/features/live_play/logic/audio_focus.dart`（G05）：`pausedUntilInterruptionEnds`、`forgetResume`、`_pausingToResume`（session 先发“暂停”事件，再设 `_pausedByFocus`）。
  - `apps/pure_live/lib/features/live_play/logic/room_controller.dart`（C01）：`setDanmakuSuspended`、`danmakuSuspended`。
  - `apps/pure_live/lib/features/live_play/live_play_page.dart`：接网络流、音频焦点。
  - `apps/pure_live/lib/platform/background_guide.dart`（新，O01）：品牌和系统识别、每家的步骤和系统页、通道。
  - `apps/pure_live/lib/features/settings/background_guide_tiles.dart`（新，A11）：视频页的入口行、检查块、打开后台播放后的提示。
  - `apps/pure_live/lib/features/settings/settings_model.dart`、`settings_catalog.dart`（J01）：`SettingsSubpage.backgroundPlay`；入口行 `background_guide`；子页面的 `background_guide_checks` 和三个开关；搜索词（各家名字）；分组说明。
  - `apps/pure_live/lib/features/settings/playback_tiles.dart`（A11）：“后台播放”打开后调 `offerBackgroundGuide`。
  - `packages/live_store/lib/src/settings/settings.dart`（J01）：三个新设置。
  - `packages/live_ui/lib/src/icons/app_icons.dart`：12 个新图标，每个都用到了（见下）。
- Kotlin
  - `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/BackgroundGuidePlugin.kt`（新，O01）：`status`（`Build`、厂商属性——反射 `SystemProperties.get`，不行就一次 `getprop`，只读一次；通知、媒体通知类别、电池优化、`isBackgroundRestricted`、`restrictBackgroundStatus`、`isPowerSaveMode`），`open`（按 Dart 给的顺序试，`ActivityNotFoundException`、`SecurityException`、其他 `RuntimeException` 都试下一个）。
  - `MainActivity.kt`：注册插件；`setPlaybackKeepAlive` 在 Android 10～13 多拿一个 `HIGH_PERF` Wi-Fi 锁（`playbackBackgroundWifiLock`）。
- 清单：没改。
- 翻译：`zh.json`、`en.json` 各加 53 个键（`background_*`、`pause_on_pip_close*`），按键名排序、4 空格；没删键（D-024）。
- 文档和登记：`docs/tasks.toml`（O01.3）、`docs/inventory/OWNERS.toml`（3 个文件、1 个通道、3 个设置归 O01）、`tools/docs/settings_audit_notes.py`、本任务文件夹、O01 说明；生成的文件由 `docs.py`、`owners.py`、`settings_audit.py` 写。

## 四、新设置、翻译键、图标、门禁基线

| 设置（`app` 节） | 默认 | 说明 |
|---|---|---|
| `backgroundAudioOnly` | `false` | 开着后台播放时，离开应用 1.5 秒后（不在画中画）关视频输出；重新打开流后再关一次；回来恢复（用户自己开的“纯音频”不动） |
| `backgroundPauseDanmaku` | `false` | 离开应用 1.5 秒后（不在画中画）断开弹幕；回来重连，这段时间的弹幕不补（没有平台提供） |
| `pauseOnPipClose` | `false` | 开着后台播放（或助眠）时关掉系统画中画窗口就暂停（不再后台出声）；回到应用继续 |

- 都是新键，3.x 没有（D-018）；默认值和现在一样（D-040）；跟着备份走（`app` 节）。
- 图标（`AppIcons`）：`settingsBackgroundGuide`（入口行）、`settingsBackgroundAudioOnly`、`settingsBackgroundDanmaku`、`settingsPipClosePause`（三个开关）、`backgroundGuideDevice`（手机行）、`backgroundGuideNotifications`、`backgroundGuideBattery`、`backgroundGuidePowerSaving`（各家省电）、`backgroundGuideRestricted`、`backgroundGuideDataSaver`、`backgroundGuideAutostart`（自启动、应用启动管理）、`backgroundGuideLockRecents`；全部用在 `background_guide_tiles.dart` 或目录里，测试按行查图标。
- 门禁基线没改。没有新依赖。

## 五、测试

- 新增：
  - `test/features/live_play/background_keeper_test.dart`（14，假时钟 `fake_clock.dart`）：前台什么都不保持；暂停放掉；重连和打开仍算在播；离开时没在播的不保持也不试（C01.5）；5、10、20、30、60、60 秒重试；播起来后节奏重来；30 分钟放弃；断网时不自己试；网络回来立刻试；下播等 10 分钟；详情失败当断流试；来电保持；通知暂停停止重试；回前台全部取消。
  - `test/features/live_play/background_play_test.dart`（14，后台规则 + 真的控制器和 session）：离开应用通知在播、拿锁，回来放；通知暂停放锁、再播拿锁；断流时通知不变“暂停”、5 秒后重试并播起来；前台不自动重试；网络回来立刻试；断流时通知暂停停止重试；来电保持通知和锁、通知暂停让音频焦点忘掉恢复；后台只播声音（重新加载后再关、回来恢复）；用户自己的纯音频保留、开关默认关；后台断开弹幕（断开、回来重连一次）；画中画显示时三个开关不生效；关闭画中画暂停（两种顺序）、默认关时照播、放大回来不暂停。
  - `test/features/settings/settings_background_test.dart`（17）：视频页入口在“后台播放”后、图标、“2 项待处理”；小米页面的手机行、步骤顺序和状态文字、说明、图标、三个开关；开关默认关并保存；厂商页先试、退到应用信息时的提示、都打不开时的提示；电池优化先系统框再列表页；通知先系统框再设置页；媒体通知类别单独关时打开类别页；Pixel 没有厂商项；OPPO、vivo、华为、荣耀、三星各自的步骤；打开后台播放后只提示一次、“去设置”进页面；没有厂商项的手机不提示；搜“HyperOS”找到页面。
  - `test/platform/background_guide_test.dart`（26）：16 种品牌和系统的识别和版本；没有属性时的名字；Android 版本；步骤顺序和状态；受限、流量节省只在适用时出现；媒体通知类别；每家的页面列表最后都是应用信息；小米省电页带包名和应用名；通道读状态、缺值当正常、发送页面、出错不抛、非 Android 不问。
  - `test/features/live_play/audio_focus_test.dart`（+2）：来电暂停时从“暂停”事件起就告诉后台；通知暂停后来电结束不恢复。
- 改了：`test/features/live_play/live_play_more_test.dart` 的 2 个（C01.5 组）：下播后在后台等开播时通知不再变“暂停”（R1 的有意改动）。
- 范围：`apps/pure_live` 全部 `flutter test`、`packages/live_store`、`packages/live_ui` 的测试；结果见“六、门禁”。
- Kotlin：项目没有 Kotlin 单元测试的设置（没有 `src/test`），不新建；原生代码只做读状态和按顺序打开页面，逻辑都在 Dart 里测。按要求没有构建 APK；用 Gradle 缓存里的 Kotlin 2.4.10 编译器、`android-37.2` 的 `android.jar`、Flutter 嵌入层 jar 和 audio_service 的类，把 `android/app/src/main/kotlin` 下全部 9 个文件（加一个假的 `R`）单独编译了一遍：没有错误，只有 `MainActivity.kt` 原有的一个弃用警告（`SHOW_IMPLICIT`）。lint 没跑（要 Gradle）。

## 六、门禁

- 见文末“门禁结果”。

## 七、真机上要看的（K90，HyperOS，Android 17，测试包 `com.mystyle.purelive.v4dev`）

逐条写在 [verify.md](verify.md)。要点：

1. 设置 → 视频 → 后台与助眠：“后台播放”下面有“后台播放设置”；打开“后台播放”后弹“还要在系统里设置一下”（只一次），“去设置”进页面。
2. 页面第一行是“Xiaomi <型号>”“HyperOS 3.0 · Android 17”（看实际版本号）；通知、电池优化显示“已设置/去设置”和实际一致；小米三项能跳到自启动页、省电策略页（HyperOS 上很可能退到应用信息并提示“省电策略”）。从系统页回来状态自动刷新。
3. 后台播放核心：开后台播放进直播间，Home，锁屏 30 分钟以上：一直有声音；`adb shell dumpsys activity services com.mystyle.purelive.v4dev | grep -i isForeground` 一直是前台；`dumpsys power | grep -i purelive` 有唤醒锁。
4. 后台断网：锁屏播放时关 Wi-Fi 和移动数据（`svc wifi disable; svc data disable`）1 分钟再开：几秒内自己接上；期间通知一直是“暂停”按钮（=在播），前台服务一直在。
5. 后台换网：Wi-Fi 换移动数据（`svc wifi disable`），十几秒内接上。
6. 主播下播再上（找经常断流的房间或用录播间）：10 分钟内回来自动接上。
7. 通知栏点“暂停”：几秒后 `dumpsys power` 没有本应用的唤醒锁；再点“播放”：能继续（HyperOS 冻结了的话记录现象——这是 R1 修不了的一种，需要用户把省电策略设为无限制）。
8. 来电（另一部手机打）：响铃时暂停，挂断后继续；整个过程前台服务一直在。
9. 三个开关：后台只播声音（`dumpsys media.metrics` 或 CPU/温度对比，回来画面 3 秒内恢复）；后台断开弹幕（回来聊天区出现“正在连接弹幕服务器”）；关闭画中画时暂停（画中画点 ✕ 后没有声音，回到应用继续）。
10. 回到前台：只有一份声音；纯音频、弹幕都恢复。

## 八、要别的手机看的

- OPPO/一加/realme（ColorOS 13～15）：自启动页、耗电管理页能不能直接打开（组件名在不同版本会变）；“后台冻结”开着时后台播放 30 分钟；预测返回问题在 O06.1。
- vivo/iQOO（OriginOS 4/5）：后台高耗电页、自启动页；不允许后台高耗电时多久被停。
- 华为（HarmonyOS 4，鸿蒙 NEXT 不是 Android，不适用）、荣耀（MagicOS 8/9）：应用启动管理页；手动管理三项都开后锁屏 30 分钟。
- 三星（One UI 6/7）：电池页、休眠应用；“受限”时检查页出现“后台限制”。
- 魅族（Flyme 10）：后台管理页组件名没核实。
- Android 10～13 的任何手机：锁屏后 Wi-Fi 锁（`dumpsys wifi | grep -i lock` 看到 `backgroundPlaybackScreenOff`）和卡顿。
- 没开电池优化豁免的 Android 12+ 手机：后台断网 1 分钟再恢复，前台服务还在、声音回来（R1 的修复不靠豁免）。

## 九、提交

- 见下（合并审查时补全）。
