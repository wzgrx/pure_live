# I08 小页面

五个小页面背后的逻辑：工具箱（粘贴链接进直播间、获取直链）、启动页（什么时候出现、等多久、去哪）、关于（入口和版本号），以及历史上由 I08.1 一起重构的版本页（检查更新、安装包和下载源）和设备同步（远程接收）——这两块后来各有专门的归属（Y02、J05），这里只记 I08.1 做的那部分和它们现在在哪。

## 范围

- 包括：
  - 工具箱：`apps/pure_live/lib/features/toolbox/toolbox_actions.dart`（`ToolboxController`：一次一件事、每个平台请求 12 秒、取消；`jump`、`directLink`；`toolboxLinksProvider`、`toolboxSiteProvider`）、`toolbox_page.dart` 里打开时读剪贴板填空框（`toolboxClipboardProvider`、`_fillFromClipboard`）和路由参数；`apps/pure_live/lib/shared/links/supported_platforms.dart` 的 `linkPlatforms`（有链接规则的平台，工具箱和“链接访问”共用）。
  - 启动页：`features/splash/splash_page.dart` 的 `splashInitialLocation`（设置 `showSplashPage`）、1 秒后或点按 / 任意键离开、离开前最多等 350 毫秒首轮关注核验（`AppStartup.followCheck`）。
  - 关于：`features/about/about_page.dart`（按路径 `kAbout` / `kVersionHistory` 分两页、版本号来自编译常量）。
  - 历史记录：I08.1 做的版本页和更新检查（`features/version/`）、设备同步（`features/remote_receiver/`）的第一版——现在的归属见下一条。
- 不包括（归哪里）：
  - 这几个页面**长什么样** → [A15.1 工具箱](../../A-界面设计/A15-小页面/A15.1-工具箱/README.md)、[A15.2 关于和版本](../../A-界面设计/A15-小页面/A15.2-关于和版本/README.md)、[A06.4 启动页](../../A-界面设计/A06-首页和全局/A06.4-启动页/README.md)、[A06.3 全局弹窗](../../A-界面设计/A06-首页和全局/A06.3-全局弹窗/README.md)（新版本对话框、下载对话框）、[A12.6 设备同步](../../A-界面设计/A12-账号和数据界面/A12.6-设备同步/README.md)。
  - 版本检查、更新文件（`assets/version.json`、`releases.json`）、下载源、应用内下载和安装（`features/version/update_feed.dart`、`update_prompt.dart`、`update_download.dart`、`download_directory_dialog.dart`；`lib/app/downloads.dart`）→ [Y02 更新通道](../../Y-发布和运营/Y02-更新通道/README.md)；版本号本身（`features/version/app_version.dart`）→ [Y01](../../Y-发布和运营/Y01-版本签名和发布/README.md)。
  - 设备同步的协议、服务、mDNS 发现（`features/remote_receiver/remote_sync_protocol.dart`、`remote_sync_service.dart`、`mdns_peers.dart`）→ [J05 设备同步](../../J-设置和数据/J05-设备同步/README.md)；扫码 `shared/qr_scan.dart`（mobile_scanner）→ O03.1。
  - 链接解析 `LinkParser`、直链取流 → [E04](../../E-直播平台/E04-链接解析和分享口令/README.md)、E；启动时检查更新和首帧后核验的时机 → [I01](../I01-首页外壳和全局/README.md)（`home_page.dart:71`、`startup.dart:84`）。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - **工具箱**（首页搜索菜单“链接访问”或 `/tool_box`）：一个链接框、“进入直播间”“获取直链”两个按钮。打开时框是空的且剪贴板里有平台链接，就填进去并提示（不发请求）；路由参数是字符串时直接填入。进入：解析链接（含分享文字里的链接、短链）→ 进直播间；已下线平台提示“已下线”。获取直链：取详情 → 未开播或封禁提示“主播未开播” → 取清晰度 → 只有一个就直接用、否则选 → 取线路 → 只有一条就直接用、否则选 → 复制；需要应用内会话的源（`inputRecipe`）提示不能导出。每个平台请求 12 秒超时（超时单独提示）；取消、改链接（文字变了才算，点光标不算）、离开页面都安静结束。下面是可展开的支持平台（平台图标 + 名字，来自平台登记，标题旁写个数）。
  - **启动页**（设置“启动页”默认开）：主题色背景、图标和“欢迎使用”淡入放大、进度条；1 秒后（或点一下、按任意键）进首页，离开前最多等 350 毫秒首轮关注核验。关掉设置时直接从首页开始。
  - **关于**（左上菜单“关于”）：图标、名字、版本号（编译进程序的常量，不再是 3.x 启动 2 秒前的 `0.0.0`）、在线更新、历史版本、开源许可证、项目主页、项目声明（去掉了 Firebase 那一句）。
  - 版本页、历史版本、新版本对话框、应用内下载：见 Y02、A15.2、A06.3。设备同步：见 J05、A12.6。
- 内部怎么工作：

```text
ToolboxPage（toolbox_page.dart）→ ToolboxController（toolbox_actions.dart:45）
  _run（:155）：同一时间一件事；空链接提示；CancelToken；出错按 (动作, 错误) 选提示（:175）
  _resolve（:194）：LinkParser.parse → 已下线平台 → platform_retired；认不出 → toolbox_parse_failed
  jump（:99）→ openRoom（AppNavigator.toLiveRoomDetail）
  directLink（:108）：getRoomDetail → 未开播 → discoverPlayQualities → 选 → resolvePlayUrls → 选 → copy
  _timed：每步 12 秒（timeout :53）
App 建路由：buildAppRouter(initialLocation: splashInitialLocation(settings))（app/app.dart:119）
SplashPage（splash_page.dart:31）：Timer(1 s) 或点按 / 按键 → _leave（:72）
  → Future.any([AppStartup.followCheck, 350 ms]) → offAllNamed(kInitial)
```

- 完成度（和 3.x 对照）：
  - 一致的：工具箱的两个动作、选清晰度和线路、进行中可取消、打开时读剪贴板、`inputRecipe` 的提示；启动页 1 秒、等关注核验 350 毫秒、`showSplashPage`；关于页的各项和历史版本。
  - 确认过的改动：I08.1 问题 4（支持列表从平台登记生成，3.x 写死的还列着已下线的 Kick）、问题 5（声明去掉 Firebase）、问题 9（点光标不取消）、问题 10（未开播单独提示）、问题 11（超时单独提示）、问题 2（版本号是常量）；两个输入框合成一个、只有一个清晰度或线路时不弹框（I08.1 界面改进，A15.1 定稿）；启动页用主题色、可点击跳过（A06.4）。
  - 当时缺、后来补上的：启动页的接线和启动时检查更新（I08.1 写“需要协调者接上”，现在 `app/app.dart:119`、`features/home/home_page.dart:71`）；应用内下载和安装（I01.3、A06.3、A15.2）；扫码（O03.1 `shared/qr_scan.dart`）；和 3.x 设备互相发现（I01.3 `mdns_peers.dart`）。
  - 还缺：无（本子分类管的部分）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/toolbox/toolbox_actions.dart`（226 行） | `ToolboxAction`（`:14`）、`toolboxLinksProvider`（`:23`）、`toolboxSiteProvider`（`:28`）、`ToolboxChooser`、`ToolboxCancelled`；`ToolboxController`（`:45`：`timeout` 12 秒 `:53`、`cancel` `:85`、`jump` `:99`、`directLink` `:108`、`_run` `:155`、`_resolve` `:194`、`_check` `:223`） |
| `features/toolbox/toolbox_page.dart`（375） | `toolboxClipboardProvider`（`:14`）、路由参数（`:59`）、`_fillFromClipboard`（`:88`）；其余是界面（A15.1） |
| `apps/pure_live/lib/shared/links/supported_platforms.dart`（71） | `linkPlatforms`（`:12`，有链接规则的平台）、`SupportedPlatformsCard`（`:21`，界面） |
| `features/splash/splash_page.dart`（177） | `splashInitialLocation`（`:16`）、`SplashPage`（`:31`，1 秒 `:33`）、`_leave`（`:72`，等关注核验）、`_onKey`（`:84`） |
| `features/about/about_page.dart`（228） | `AboutPage`：`kAbout` 和 `kVersionHistory` 两页的入口和版本号；界面归 A15.2 |
| `features/version/`（8 个文件 2952 行）、`features/remote_receiver/`（4 个文件 1595 行） | 现在归 Y02、Y01、J05（见“范围”）；I08.1 写的第一版见 [I08.1 README](I08.1-小页面/README.md) |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/toolbox/toolbox_page_test.dart`（10） | 分享文字里的链接进直播间；选清晰度、线路后复制；取消选择安静结束；空链接、无法解析、已下线、未开播的提示；剪贴板自动填入和支持平台列表；平台列表只含有链接规则的平台；A15.1 的布局 |
| `test/features/splash/splash_page_test.dart`（7） | 起始路由跟随设置；1 秒后进首页；点一下跳过；A06.4 的画面 |
| `test/features/version/version_page_test.dart`（18）、`update_dialogs_test.dart`（9） | 版本页、关于页、历史版本、新版本对话框、下载（Y02、A15.2、A06.3） |
| `test/features/remote_receiver/remote_sync_test.dart`（12） | 设备同步（J05、A12.6） |

## 3.x 基线

- `~/ref/v3ref/lib/modules/toolbox/`（`git show v3.2.11:lib/modules/toolbox/...`，611 行）：`toolbox_controller.dart`（链接框监听器把光标移动也算改了 `:24-25`、`:46-54`；超时和失败同一句 `:84-86`）、`toolbox_direct_link_flow.dart`（未开播时“读取直链失败,无法读取清晰度” `:37-41`）、`toolbox_page.dart`、`toolbox_action_scope.dart`；支持列表是翻译里写死的 `toolbox_support_content`。
- `lib/modules/splash/splash_screen.dart`（172 行，固定青色渐变、2 秒淡入）；启动页路由和等关注核验 `lib/routes/app_pages.dart`；`initialRoute` 在 `lib/main.dart:197`。
- `lib/modules/about/`（`about_page.dart`、`version_history.dart`、`widgets/`，1164 行）；`lib/common/utils/version_util.dart`（版本号在首页检查更新时才读 `:63-70`；更新文件存在静态变量里 `:77-90`）。
- `lib/modules/version/`（587 行）、`lib/modules/remote_receiver/`（1758 行）：现在归 Y02、J05。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：无专门条目；第 17 条（回到前台识别剪贴板口令）是 O03 的，工具箱只在打开时读剪贴板。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 工具箱的“打开时读剪贴板”和全局的“回到前台识别剪贴板口令”（O03）都读剪贴板：从后台回来直接到工具箱时，可能先弹口令提示、框里又填同一个链接 | `toolbox_page.dart:88`；`app/intake/clipboard_rooms.dart` | 同一个链接两处反应 | 没有在真机上看过；S02.6 第 3 阶段看剪贴板口令时顺带看，有问题开 O03 任务 |
| 设备同步（J05）子分类说明还没写、没有任务；`features/remote_receiver/` 同时在 J05（逻辑）和 A12.6（界面） | [J05](../../J-设置和数据/J05-设备同步/README.md) | 改设备同步时找不到说明 | 写进本单元报告（归 J 组的写作单元） |
| 新版本对话框以 A06.3 还是 A15.2 的设计为准，没有定、没有登记 | [A15.2 README](../../A-界面设计/A15-小页面/A15.2-关于和版本/README.md)“留下的问题” | 现在用的是 A06.3 的（`update_prompt.dart:108`） | 已定以 A06.3 为准（D-037） |
| I08.1 记录和代码不符：`release_history_view.dart` 从 `about/` 挪到了 `version/`；新增 `update_download.dart`（643）、`download_directory_dialog.dart`（83）；下载改成应用内；`mdns_peers.dart`（122）由 I01.3 加；`linkPlatforms` 挪到 `shared/links/supported_platforms.dart`；“需要协调者接上”的两条已接上；扫码已有 | [I08.1 记录](I08.1-小页面/record.md) | 只是记录过时 | I08.1 README 已注明 |
| I08.1 登记“完成”，没有 K90 记录；工具箱、启动页在 S02.2 冒烟里走过，设备同步、应用内下载归 S02.4 | — | 部分没有真机证据 | S02.4 已列设备同步和应用内更新；工具箱的“获取直链”建议并入 S02.6 第 3 阶段（写进本单元报告） |

## 相关决定和规范

- D-015（`assets/version.json`、`releases.json` 必须留在 master：版本页和 3.x 的更新检查都从 master 读）、D-008（4.0.0 覆盖发布，同版本换包收不到提示 → Y02.1）、D-018（`showSplashPage`、`enableAutoCheckUpdate`、`useGitHubOriginForUpdates` 照 3.x 的键）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“说明文字”（项目声明、支持平台说明）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/toolbox test/features/splash`（17 个）；版本和设备同步的测试见上表（归 Y02、J05）。缺的：工具箱和全局剪贴板口令同时出现的情况。
- 真机：S02.2 冒烟走过启动页和工具箱“进入直播间”；“获取直链”、启动页关闭后的冷启动没有记录。

## 路线

本子分类没有未完成的任务。

1. 维护者决定新版本对话框以哪个设计为准（A15.2 记的待决项），需要改时在 A06 或 A15 开任务。
2. J05 补子分类说明，把设备同步从这里完全接走。
3. 新想法（工具箱加“复制分享口令”“批量导入关注”）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/toolbox/`、`about/`、`version/`、`splash/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I08.1 | 小页面：工具箱、远程接收、关于、版本、启动页 | 功能 | 完成 | 2026-10-01 | d5a0a060a | [设计或说明](I08.1-小页面/README.md)、[记录](I08.1-小页面/record.md) |

<!-- docs:生成结束 -->
