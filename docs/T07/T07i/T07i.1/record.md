# T07i.1 页面：工具箱、远程接收、关于、版本、启动页

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/toolbox/`、`remote_receiver/`、`about/`、`version/`、`splash/`（路由、类名和构造参数不变）
- v3 来源：标签 `v3.2.11` 的 `lib/modules/toolbox/`（611 行）、`remote_receiver/`（1758 行）、`about/`（1164 行）、`version/`（587 行）、`splash/`（172 行），以及它们用到的 `common/utils/version_util.dart`、`release_asset_urls.dart`、`githup_mirror.dart`、`plugins/update.dart`、`plugins/race_http.dart`、`common/models/release_model.dart`、`routes/app_pages.dart` 的启动页路由、`modules/home/home_page.dart` 的启动时检查更新
- 用到的包：`live_core`（`LinkParser`、平台登记、`LiveSiteCalls`）、`live_net`（`GitHubMirror`、`raceJson`、`raceFirst`）、`live_store`（设置、`BackupService`）、`live_ui`（设置卡片积木、`QrCodeWidget`、`AppStatusView`、`PlatformLogo`、文字样式）

## 做法

| 文件 | 内容 |
|---|---|
| `toolbox/toolbox_actions.dart` | `ToolboxController`（`ChangeNotifier`）：一次只做一件事，每个平台请求 12 秒超时（同 v3），取消、改链接、离开页面都安静地结束。链接解析用 `LinkParser`（`toolboxLinksProvider`），平台用 `toolboxSiteProvider`；直链流程：`getRoomDetail` → `discoverPlayQualities` → 选清晰度 → `resolvePlayUrls` → 选线路 → 复制。`linkPlatforms` 从平台登记取有链接规则的平台 |
| `toolbox/toolbox_page.dart` | 页面：一个链接框（粘贴/清除按钮）、“链接跳转”“获取直链”两个按钮、进行中文字和取消、可展开的支持平台（平台图标 + 名字）。打开时剪贴板里有平台链接就填进空框（不发请求）；路由参数是字符串时直接填入 |
| `version/update_feed.dart` | 更新数据：`UpdateFeed` 经 `GitHubMirror` 的镜像竞速读 `assets/version.json`（`raceJson`，10 秒）和 `assets/releases.json`（15 秒），设置 `useGitHubOriginForUpdates` 时只读 GitHub；`UpdateInfo`（按平台覆盖顶层，同 v3 `selectPlatformVersionData`）、`ReleaseInfo`/`ReleaseFile`（同 v3 `ReleaseModel`，也认 GitHub API 的字段名）、`PackageKind`（同 v3 `ReleaseAssetUrls` 的挑选规则）、`downloadSources`（同 v3 `getMirrorUrls` 的 17 个下载镜像）。`updateFeedProvider` 供测试替换 |
| `version/app_version.dart` | 已安装版本：Flutter 编进程序的 `appBuildName`/`appBuildNumber`（没有时用 `pubspec.yaml` 的值，测试核对两者一致）；`isNewerVersion`、`compareVersions` 同 v3 |
| `version/version_page.dart` | 版本页：状态卡（有新版本/已是最新、当前和最新版本号、预发布标记）、本平台安装包（Android 按 `android_abis`，Windows 安装包/MSIX/便携包，macOS），每个包列出全部下载源，点开后“下载”（系统浏览器）或“复制链接”；没有安装包时给发布页面按钮；更新日志 |
| `version/update_prompt.dart` | 启动时检查更新 `checkForUpdateOnStartup` 和新版本对话框 `NewVersionDialog`（项目链接、更新日志、取消、更新 → 版本页） |
| `version/markdown_text.dart` | 更新日志的 Markdown：标题、列表（含缩进和编号）、引用、分隔线、表格、代码块，行内粗体、代码、链接（外部浏览器打开）；可选中复制 |
| `about/about_page.dart` | `AboutPage` 按路径分两页：`kAbout` 是关于（标志动画、名字、版本、在线更新、历史版本、开源许可证、项目主页、项目声明），`kVersionHistory` 是历史版本 |
| `about/release_history_view.dart` | 历史版本：手机上是列表、点开是对话框；宽于 760 时左列表右详情；刷新（失败保留旧列表并提示）、发布页面、每个文件的复制链接和下载 |
| `remote_receiver/remote_sync_protocol.dart` | 同步协议，和 3.x 一字不差（端口、路径、配对码请求头、二维码 `purelive://ip:port/sync?code=`、数据包），3.x 和 v4 设备可以互相同步 |
| `remote_receiver/remote_sync_service.dart` | 同步服务（页面打开期间运行）：39888 起找空闲端口开 HTTP 服务；读、写设置都要配对码和本机用户同意；设置按 3.x 备份格式（`BackupService.exportAll/restoreAll`），账号 Cookie 只在打开开关时带；发送、接收对方设备；UDP 广播（39889）互相发现 |
| `remote_receiver/remote_receiver_page.dart` | 页面：本机（二维码、地址和复制、配对码、同步账号开关、服务状态）、发现的设备（接收/发送）、手动输入（地址或二维码文字） |
| `splash/splash_page.dart` | 启动页：主题色渐变、标志淡入放大、“欢迎使用”、进度条，1 秒后（或点一下）进首页；`splashInitialLocation(settings)` 按设置 `showSplashPage` 给出起始路由 |

## 与 v3 的功能对照

| v3 | v4 | 说明 |
|---|---|---|
| 工具箱：直播间跳转（链接框、解析、进直播间） | 有 | 和直链共用一个链接框 |
| 工具箱：获取直链（选清晰度、选线路、复制） | 有 | 只有一个清晰度或一条线路时不再弹选择框 |
| 工具箱：进行中按钮转圈、取消、改链接即取消 | 有 | |
| 工具箱：需要应用内会话的源提示不能导出 | 有 | `resolution.inputRecipe` |
| 工具箱：打开时检测剪贴板并自动填入 | 有 | 用户已经输入过就不填 |
| 工具箱：支持解析列表（固定文字） | 改 | 从平台登记生成，见界面改进 |
| 关于：标志、名字、版本、在线更新、历史版本、开源许可证、项目主页、项目声明 | 有 | 声明文字改了，见 v3 问题 5 |
| 历史版本：列表/双栏、刷新、详情、发布页面、复制链接、下载 | 有 | 下载在系统浏览器里进行，见留给后续 |
| 版本页：按平台列出安装包和全部下载源、下载/复制、更新日志、失败重试 | 有 | 下载同上 |
| 首页 2 秒后检查更新、有新版本弹框（开关 `enableAutoCheckUpdate`） | 有函数，未接 | `checkForUpdateOnStartup` 由首页调用，见“需要协调者接上” |
| 设备同步：本机地址、二维码、配对码、同步账号开关、服务状态、开始/停止 | 有 | |
| 设备同步：来访请求确认框、发送、接收、手动地址 | 有 | 手动框也认二维码文字（带配对码） |
| 设备同步：自动发现（mDNS `_purelive-sync._tcp`，bonsoir） | 部分 | v4 之间用 UDP 广播发现；和 3.x 设备互相发现要 mDNS，见留给后续（3.x 设备仍可用地址或二维码文字同步） |
| 设备同步：扫码（mobile_scanner） | 无 | 缺依赖，见留给后续；可把二维码里的文字粘贴到手动框代替 |
| 启动页：渐变、标志、欢迎、进度条、1 秒后进首页 | 有 | 起始路由由 `splashInitialLocation` 决定，需要协调者接上 |
| 启动页：等待关注刷新最多 350 毫秒再进首页 | 无 | 关注刷新属于关注页（M13），关注页做好后再看是否需要 |

## 审查发现的 v3 问题及处理

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 检查更新只在启动时真正联网：`VersionUtil.checkUpdate` 把 `version.json` 存在静态变量里，版本页的“重试”和再次进入都用这份旧数据，应用开着时发布的新版本看不到 | `version_util.dart:77-90` | 版本页每次都重新读取 |
| 2 | 关于页的版本号在首页 2 秒后的检查之前是 `0.0.0`（`initPackageInfo` 在那时才调用） | `version_util.dart:63-70`、`home_page.dart:198-200` | 版本号是编译进程序的常量 |
| 3 | 关闭“自动检查更新”后启动时仍然联网读更新文件（只是不弹框） | `home_page.dart:198-206` | 关闭时不联网 |
| 4 | 工具箱的支持列表是写死的文字：还列着 3.2.11 已下线的 Kick，又漏掉 niconico、YouTube、TikTok 等十几个能解析的平台 | `zh.json` `toolbox_support_content` | 从平台登记生成；已下线平台的链接提示“已下线” |
| 5 | 项目声明说“登录及云同步功能由 Firebase 提供”，v4 已去掉 Firebase（T07a.1 问题 10） | `zh.json` `app_legalese` | 新键 `about_legalese`，去掉 Firebase 一句 |
| 6 | 同步配对码 6 位数字，答错不限次数，局域网里可以穷举 | `remote_sync_service.dart:503-511` | 连续答错 10 次换新码 |
| 7 | 发送、接收没有超时，对方设备不响应时按钮一直不能用 | `remote_sync_service.dart:985-1120` | 连接 5 秒超时，整次 2 分钟（对方要等用户确认） |
| 8 | 收到的设置先问用户再检查格式：坏数据也会弹确认框，确认后才回 400 | `remote_sync_service.dart:503-600` | 先检查数据包，再问 |
| 9 | 工具箱的链接框监听器把光标移动也当成“改了链接”，点一下输入框就取消正在进行的解析 | `toolbox_controller.dart:24-25,46-54` | 只在文字变化时取消 |
| 10 | 主播未开播时获取直链提示“读取直链失败,无法读取清晰度” | `toolbox_direct_link_flow.dart:37-41` | 先看详情状态，提示“主播未开播” |
| 11 | 工具箱超时和解析失败是同一句提示 | `toolbox_controller.dart:84-86` | 超时单独提示 |
| 12 | `receiveFromAddress`、`syncByAddress`、`RemoteSyncDevice.copyWith`、`LocalAddress` 没有调用者 | `remote_receiver/` | 不搬 |

## 界面改进

1. 工具箱：两个卡片各一个输入框合成一个链接框 + 两个按钮（同一个链接本来就要输两遍），框里有粘贴/清除按钮，进行中显示“正在解析链接…/正在读取直播流地址…”。
2. 工具箱：支持平台从平台登记生成，平台图标 + 名字，默认收起，标题旁显示平台数。
3. 工具箱：只有一个清晰度或一条线路时直接用，不弹选择框；未开播、超时、已下线平台各有自己的提示。
4. 版本页：顶部状态卡，直接说“发现新版本 vX”或“已在使用最新版本”，并列出当前和最新版本号、预发布标记；下载源里最后一个（原始地址）标成“GitHub 官方源”；包名旁显示大小；没有本平台安装包时给“打开发布页面”。
5. 版本页、历史版本：标题栏有刷新按钮；检查中显示文字而不是空白转圈。
6. 历史版本：已安装的版本标“当前安装”；列表行显示日期和安装包大小。
7. 关于：标题栏加“关于”标题；在线更新一行加说明“检查新版本并下载安装包”（原来右边的版本号小块和上方重复，去掉）。
8. 设备同步：发送和接收前都先确认（v3 只有接收确认）；手动框也认二维码文字，带配对码时不用再输；同步中标题栏下有进度条；二维码不可用时显示占位图标；地址旁有复制按钮。
9. 启动页：背景用当前主题色（v3 固定青色，深色模式也是写死的蓝灰），点一下可以跳过。
10. 更新日志的 Markdown 改用页面内的小渲染器（v3 用 markdown_widget）：表格、链接可用，文字可选中复制。

## 需要协调者接上（不在本页目录）

- **启动页**：`lib/app/app.dart` 建路由时传 `buildAppRouter(initialLocation: splashInitialLocation(services.store.settings))`（`ref.read(appServicesProvider).store.settings`），`app_router.dart` 的注释同步改掉。
- **启动时检查更新**：首页第一帧后等 `startupUpdateCheckDelay`（2 秒）调用 `checkForUpdateOnStartup(context, settings: store.settings, feed: ref.read(updateFeedProvider))`（`lib/home/home_page.dart`，只在主窗口）。

## 留给后续

- **应用内下载和安装**：v3 有下载对话框（进度、断点续传、选下载目录、Android 安装权限、下载完自动安装/打开文件夹，`download_apk_dialog.dart` 等约 950 行）；v4 现在交给系统浏览器下载。需要：下载目录设置的页面（M13 设置）、Android 安装 APK 的原生入口（FileProvider + 安装权限）、Windows 打开文件。
- **扫码**：需要扫码依赖（v3 用 mobile_scanner）和相机权限。
- **和 3.x 设备互相发现**：3.x 用 bonsoir 的 mDNS（`_purelive-sync._tcp`，TXT 里有 id、name、platform、version、ip）。要么加 bonsoir 依赖，要么在 Dart 里实现 mDNS 的查询和应答；Android 要持有组播锁（`MulticastLock`，已有）。v4 之间的 UDP 广播发现在 Android 上也应持有组播锁，实机未验证。
- **实机检查**：Android、Windows 上的同步（防火墙、端口、广播）、启动页、版本页的下载源，本次只在 WSL 上跑了测试。
- 旧键 `toolbox_support_content`、`toolbox_room_jump`、`toolbox_get_parse`、`toolbox_detect_link`、`app_legalese` 不再使用，留在翻译文件里没有删。

## 已批准的升级（docs/specs/UPGRADES.md）

表里没有属于这几页的条目（“说明文字改成用户看得懂的中文”一条：本块新加的文字都按此写，项目声明已改）。

## 新加的翻译键

zh、en 各 19 个，追加在文件末尾、按字母序：`about_installed_version`、`about_legalese`、`about_update_subtitle`、`remote_sync_manual_hint`、`toolbox_link_subtitle`、`toolbox_link_title`、`toolbox_opening`、`toolbox_paste`、`toolbox_reading_stream`、`toolbox_room_offline`、`toolbox_support_count`、`toolbox_support_hint`、`toolbox_timeout`、`version_checking`、`version_download_in_browser`、`version_installed`、`version_newest`、`version_no_packages`、`version_prerelease`。

## 测试

21 个（`flutter test`，加速流程，只覆盖主要路径）：

| 测试文件 | 内容 |
|---|---|
| `test/pages/toolbox/toolbox_page_test.dart`（6） | 分享文字里的链接进直播间；选清晰度、线路后复制直链；取消选择安静结束；空链接、无法解析、已下线平台、未开播的提示；剪贴板自动填入和支持平台列表；平台列表只含有链接规则的平台 |
| `test/pages/version/version_page_test.dart`（8） | 已安装版本和 `pubspec.yaml` 一致；用仓库自己的 `version.json`、`releases.json` 解析（平台覆盖、排序、安装包挑选、版本比较、下载源）；版本页显示新版本、安装包和日志并复制下载源；失败和重试（重新联网）；启动检查只在开关打开且有新版本时弹框，“更新”进版本页；关于页的版本号、没有 Firebase、进版本页；历史版本列表和详情对话框；宽窗口双栏和切换 |
| `test/pages/splash/splash_page_test.dart`（3） | 起始路由跟随设置；1 秒后进首页；点一下跳过 |
| `test/pages/remote_receiver/remote_sync_test.dart`（4） | 3.x 的二维码和地址格式、配对码比较；两台设备（本机回环）发送、接收设置；错码拒绝、10 次换码、用户拒绝时不写入；页面显示地址（优先 192.168）、二维码、配对码，停止服务 |
