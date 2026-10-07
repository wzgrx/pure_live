# O03 分享接收和快捷方式

系统分享、打开方式、剪贴板口令、桌面快捷方式、插件接入。

别的应用和系统交给纯粹直播的东西怎么进来（分享、“打开方式”、剪贴板里的分享口令、桌面图标长按的快捷方式、通知点开的页面），以及应用用到的第三方 Flutter 插件怎么接入（系统分享面板、文件选择、打开文件、网络类型、扫码、内置浏览器）。

## 范围

- 包括：
  - **接收**：`ShareIntakePlugin.kt`（通道 `pure_live/share_intake`）：`SEND`、`SEND_MULTIPLE` 的文字和文件、`VIEW` 打开的 `content:`/`file:` 文件、应用自己的 `com.mystyle.purelive.OPEN`（快捷方式和通知打开页面或房间）；文件复制到缓存；启动意图只读一次；剪贴板变化时间 `clipboardStamp`。Dart 一侧 `platform/share_channel.dart`、`app/intake/`（`share_intake.dart` 判断是什么、`clipboard_rooms.dart` 剪贴板口令、`system_intake.dart` 把它们接起来）。
  - **口令**：`shared/rooms/share_code.dart` 的生成和解码（3.x 和 4.x 的口令都认）；进房前的确认框 `shared/rooms/room_prompt.dart`（A06.3）。
  - **桌面快捷方式**：图标长按的“搜索直播”“录制中心”和最近看过的两个房间（动态快捷方式，`setRecentRooms`）；清单的 `share_targets.xml`。
  - **插件接入**：`platform/plugins.dart` 的钩子（share_plus、flutter_cache_manager、file_picker、open_filex、mobile_scanner、flutter_inappwebview）；网络类型 `app/network.dart`（connectivity_plus）；扫码 `shared/qr_scan.dart`；内置浏览器 `shared/in_app_web.dart`。
- 不包括（归哪里）：
  - 分享提示、确认框、权限说明框的样子 → A14.1（c10、c11）、A06.3。
  - 分享来的播放列表和节目单怎么导入 → L01、L02（`IptvImporter`）；链接怎么识别是哪个平台、哪个房间 → E（`LinkParser`）。
  - 权限的原生部分（`PermissionsPlugin.kt`）→ [O04](../O04-权限/README.md)；O03.2 一起做的权限说明写在那里。
  - 播放代理的规则 → Q02（O03.2 c5 做的 `PlaybackProxyPolicy` 在 `app/platforms.dart`）。
  - Windows 桌面外壳（标题栏、托盘、关闭询问、开机自启、窗口位置，`app/desktop/`）→ [X01](../../X-多端客户端/X01-Windows/README.md)；O03.1 当时一起做了，只在本子分类留记录。
  - 扫码登录、哔哩哔哩网页登录的账号逻辑 → K01；设备同步 → J05。

## 现状：做到哪、怎么工作的

用户看得到的（Android）：

- **别的应用分享到纯粹直播**：直播间链接 → 提示“正在打开分享的直播间…”后进房（短链接联网解析）；分享口令 → 先弹“打开分享的直播间”（副标题“收到别的应用分享的口令”，取消 / 进入直播间）；m3u、m3u8、txt → 导入网络电视；xml、gz、json → 导入节目单；平台已下线 → “该平台已下线…”；没有能识别的链接 → “分享的内容里没有能打开的直播间链接”；不认识的文件 → 单独一句提示。用“打开方式”打开 m3u 等文件同样处理。一次最多 20 个文件、单个最多 256 MB；多个文件只显示最后一条结果（同 3.x）。
- **剪贴板口令**（设置 → 通用 →“分享与剪贴板”，`detectClipboardRooms`，默认开）：启动后、每次回前台 1 秒后看一次剪贴板，是分享口令就弹同一个确认框；同一内容本次运行只问一次，自己复制、分享出去的口令不问；Android 先看剪贴板的变化时间，没变就不读内容（不触发系统的“已读取剪贴板”提示）。
- **桌面图标长按**：“搜索直播”“录制中心”和最近看过的两个房间（主播名，长标签带标题），点了直接进；录制通知、“录制已停止”提醒点开录制中心（提醒带任务 id，定位到那条任务）。
- **工具箱**：可以手动粘贴口令进房。
- **插件**：卡片菜单“分享”在手机上打开系统分享面板（桌面复制口令）；“清除图片缓存”清磁盘；网络电视导入、备份恢复、录制目录、下载目录用系统文档选择器（不申请所有文件权限）；网络电视卡片“打开文件”用 open_filex；移动数据时推荐页上方有流量提示、直播间首个清晰度用“移动数据清晰度”；设备同步和同步到电视的地址框旁有扫码；网页搜索和哔哩哔哩网页登录在内置浏览器里。

内部怎么工作：

```text
启动 main → SystemIntake.start（app/intake/system_intake.dart:32，只在主窗口）
  ├─ ClipboardRoomWatcher（clipboard_rooms.dart:34）：start 时查一次；回前台 resumeDelay=1 秒后查
  │     stamp（ShareIntakePlugin.clipboardStamp，:185）没变 → 不读；读到 → decodeRoomShareCode（share_code.dart:69）
  │     → showRoomPrompt（room_prompt.dart:25）→ 进入 → AppNavigator.toLiveRoomDetail
  ├─ ShareChannel.listen（share_channel.dart:90）→ 原生 listen 回答之前积下的，之后逐个 shared{…}
  │     原生 receive（ShareIntakePlugin.kt:221）：OPEN 只放行 /search、/record_mannager（:73）；
  │     SEND/VIEW → 工作线程把文件复制到 cache/share_intake/<随机>/<名字>（stage :318）→ shared{text, files}
  │     → ShareIntake.ingest（share_intake.dart:105）：路由（再按 openableRoutes :75 检查一次）→ 房间 → 口令 → 文件 → 链接
  └─ 观看历史变化 → recentRoomShortcuts → setRecentRooms → setShortcuts（ShareIntakePlugin.kt:139，动态快捷方式）
```

- 完成度：清点第 2 节 F-AND-02（系统分享和打开方式）“完成”，K90 上从别的应用分享直播链接直接进房通过（S02.3）；F-AND-01（剪贴板口令）“没验证”，归 S02.6 第 3 阶段；分享 m3u、“打开方式”、长按快捷方式没在真机看。O03.1 的插件在 Android 上都没在真机逐项看过（记录“没在真机或 Windows 上验证的”），后来 S02.2、S02.3 用到了其中的分享面板、网络类型、内置浏览器（网页搜索没测）。
- 和 3.x 比：3.x 用 share_handler（本地 AGP 补丁），4.x 自己写插件；接收顺序、提示文字、口令格式照 3.x；剪贴板多了开关和“变化时间没变不读”；长按快捷方式是 4.x 新加的（A14.1 c15）；口令照 3.x 先确认再进房（分支里直接进房的做法没要，O03.2 X2）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/ShareIntakePlugin.kt`（385 行） | 通道 `pure_live/share_intake`：`listen`（积下的一次给完）、`clipboardStamp`（:185，API 26+ 读 `primaryClipDescription.timestamp`，空时 -1）、`setRecentRooms` → `setShortcuts`（:139，搜索、录制中心、最多两个房间）；`ACTION_OPEN`（:62）和 `openRoute`（:78，通知用）；`receive`（:221，标 `HANDLED` 防重复）；文件：`sharedUris`（:293）、`stage`（:318，工作线程、限 20 个 / 256 MB / 名字 120 字）、`displayName`、`safeName`；引擎启动时清掉上次留下的缓存 |
| `apps/pure_live/android/app/src/main/AndroidManifest.xml` | `VIEW`（:81-98：`mystyle`、`purelive`、`file`、`content` 和播放列表、节目单类型）、`SEND`（:100-111）、`SEND_MULTIPLE`（:112-123）过滤器；`android.app.shortcuts` 指向 `share_targets.xml`（:124） |
| `apps/pure_live/android/app/src/main/res/xml/share_targets.xml` | 照 3.x 的 share-target 声明（类别 `com.mystyle.purelive.dynamic_share_target`）；没有发布带这个类别的快捷方式，所以系统分享面板里没有“直接分享到某个房间”的目标（3.x 也没有） |
| `.../res/values/strings.xml`、`values-en/strings.xml`；`res/drawable/ic_shortcut_*.xml` | 快捷方式文字（“搜索直播”“录制中心”）和图标 |
| `apps/pure_live/lib/platform/share_channel.dart`（148 行） | `SharedPayload`（:15，`route`、`task`、`room`、`text`、`files`）、`ShareChannel`（:75：`listen` :90、`clipboardStamp` :110、`setRecentRooms` :123）、`releaseSharedFile`（:140，导入后删缓存） |
| `apps/pure_live/lib/app/intake/share_intake.dart`（280 行） | `ShareOutcome`（:18）、`ShareIntake`（:52：`openableRoutes` :75、`ingest` :105）：照 3.x 的顺序判断，提示文字照 A14.1 c10、c11 |
| `apps/pure_live/lib/app/intake/clipboard_rooms.dart`（117 行） | `readClipboardText`（:13）、`ClipboardRoomWatcher`（:34：`resumeDelay` 1 秒 :42、`check` :88） |
| `apps/pure_live/lib/app/intake/system_intake.dart`（124 行） | `SystemIntake.start`（:32）：接剪贴板、分享、最近房间快捷方式、启动画面深浅色；`openOutsidePage`（:77，同一页已在最上面时替换，不叠两层）；`appNavigatorReady`（:111，等过了启动页再弹框，最多 10 秒） |
| `apps/pure_live/lib/shared/rooms/share_code.dart`（204 行） | `encodeRoomShareCode`（:19）、`decodeRoomShareCode`（:69，在文字里找候选 :82，MessagePack 解码 :114）；自己复制过、分享出去的文字 `OwnClipboardTexts`（:181） |
| `apps/pure_live/lib/shared/rooms/room_prompt.dart`（116 行） | `showRoomPrompt`（:25）、`RoomPromptDialog`（:44），A06.3 的确认框 |
| `apps/pure_live/lib/platform/plugins.dart`（147 行） | `installPluginHooks`（:37：系统分享面板、清图片磁盘缓存、打开文件、Android 打开目录、扫码相机、内置浏览器检测）、`pluginOverrides`（:49：网络电视、备份、录制目录、下载目录的系统选择器，手机上分享日志文件） |
| `apps/pure_live/lib/app/network.dart`（87 行） | `NetworkKind`、`networkProbeProvider`（connectivity_plus） |
| `apps/pure_live/lib/shared/qr_scan.dart`（475 行）、`shared/in_app_web.dart`（175 行） | 扫码页（mobile_scanner，ML Kit 模型打包进 APK）；内置浏览器（flutter_inappwebview 6.2.0-beta，只放行 http(s)） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/intake_test.dart`（15 个） | 口令（往返、夹在文字里、标准 Base64 和整数房间号、不可用的房间号）；剪贴板（只问一次、自己的不问、开关关了不读、变化时间没变不读、回前台 1 秒后才读）；分享（快捷方式和通知的页面和房间、口令先问、链接先提示再进房、短链接失败、平台下线、没有链接的文字、不认识的文件、播放列表导入）；最近两个房间；通道数据解析 |
| `apps/pure_live/test/plugins_test.dart`（8 个） | 图片缓存清除和定时刷新封面；网络类型；断网预检和移动数据提示；扫码按钮；窗口位置和自启项；标题栏；内置浏览器只放行 http(s)、哔哩哔哩网页登录的落地判断 |
| `apps/pure_live/test/features/toolbox/toolbox_page_test.dart` | 工具箱粘贴口令进房 |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 快捷方式文字中英文都有（:274） |

## 3.x 基线

- 分享接收：`git show v3.2.11:lib/main.dart`（:105-131，share_handler 的初始和后续分享）、`lib/common/utils/shared_media_intake.dart`（:71-148，按扩展名分流和提示）、`lib/common/utils/shared_live_link_opener.dart`（:30-63，链接进房）；插件 `share_handler`（`pubspec.yaml:175`，Android 部分 `plugins/built_in_kotlin/share_handler_android` 本地补丁，`:217-218`）。
- 剪贴板：`lib/common/global/platform/desktop_manager.dart:595-625`（启动后第一帧、回前台 1 秒后读，所有平台，没有开关）；`lib/common/utils/share_command_handler.dart:85-88`、`:137-164`（只认口令、同一内容只问一次、自己的不问）；对话框 `share_command_import_dialog.dart:58-66`。
- 清单：`android/app/src/main/AndroidManifest.xml:103`（同一个 `share_targets.xml`），“打开方式”只列了 `audio/x-mpegurl`（4.x 加了其他播放列表和节目单类型）。
- 3.x 没有图标长按的快捷方式。
- 必须保留：口令格式（3.x 生成的口令 4.x 能解，4.x 生成的 3.x 能解）；分享来的口令先确认再进房。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 剪贴板口令没在真机看过，特别是 HyperOS 上回前台会不会每次出现“已读取剪贴板”的系统提示 | `ShareIntakePlugin.kt:185`、`clipboard_rooms.dart:34` | 提示频繁会让用户以为应用在偷看剪贴板 | S02.6 第 3 阶段（CHECKLIST 第 4 节第 11 条） |
| 分享 m3u 文件、“打开方式”打开文件、长按快捷方式没在真机看 | 清单 :81-123；`ShareIntakePlugin.kt:139` | 不知道厂商的文件管理器给的 `content:` 地址能不能读、启动器显不显示快捷方式 | S02.6 第 3 阶段（文件分享）；快捷方式没有任务，回归时看 |
| 多个文件一起分享只提示最后一个的结果 | `share_intake.dart` 的 `ingest` | 有一个失败时用户可能不知道 | 照 3.x，不做 |
| share-target 声明了但没有发布对应的直接分享目标 | `res/xml/share_targets.xml` | 系统分享面板里没有“分享到某个房间”这一类快捷入口（3.x 一样） | 不做 |
| O03.1 的插件在 Android 上没逐项真机看（文档选择器、open_filex、扫码相机权限、哔哩哔哩网页登录的 Cookie） | `platform/plugins.dart`、`shared/qr_scan.dart`、`shared/in_app_web.dart` | 厂商系统上可能有差异 | 扫码和备份目录在 S02.4；哔哩哔哩网页登录在 S02.6 第 3 阶段 |

## 相关决定和规范

- D-004（只做 Android）、D-018（新设置 `detectClipboardRooms` 只加不改，3.x 的键不动）、D-019（真机只点测试包）。
- A14.1 c3、c5、c15（快捷方式和通知打开页面）、c10、c11（分享的提示文字）；A06.3（确认框）；O03.2 的 X2（剪贴板只认口令）。
- 安全：`MainActivity` 是导出的（启动器要用），任何应用都能发 `com.mystyle.purelive.OPEN`；能打开的页面只放行两个（原生 `OPENABLE_ROUTES` 和 Dart `openableRoutes` 各查一次），录制任务 id 限 200 字、只用来定位；改这里时保持两边一致。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/intake_test.dart test/plugins_test.dart test/features/toolbox/toolbox_page_test.dart`。原生的意图分派、文件复制、快捷方式、剪贴板时间只能在真机看。
- 真机：CHECKLIST 第 1 节第 14 条（分享）、第 4 节第 11 条（剪贴板口令和文件分享）；用 `adb shell am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT "<链接或口令>" com.mystyle.purelive.v4dev/com.mystyle.purelive.MainActivity` 模拟分享。

## 路线

- 这个子分类没有未完成的登记任务。剪贴板口令和文件分享的真机在 S02.6 第 3 阶段。
- 以后：设备同步和 3.x 互相发现（mDNS，O03.1 记录里的 bonsoir 接线）已由 I01.3 做完；新的接收方式（例如从浏览器分享网页直接识别更多平台）先在 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [O Android系统集成](../README.md)。

- 代码：`ShareIntakePlugin.kt`、`app/intake/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| O03.1 | 插件接入和 Windows 桌面外壳 | 功能 | 完成 | 2026-10-01 | 9ded26f50 | [设计或说明](O03.1-插件接入和Windows桌面/README.md)、[记录](O03.1-插件接入和Windows桌面/record.md) |
| O03.2 | 接回半成品：后台播放和助眠的权限、系统分享和打开方式、剪贴板口令、播放代理 | 功能 | 完成 | 2026-10-02 | 8cf3c21b7 | [设计或说明](O03.2-接回半成品/README.md)、[记录](O03.2-接回半成品/record.md) |

<!-- docs:生成结束 -->
