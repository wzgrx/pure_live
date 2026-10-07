# A12 账号和数据界面

账号、登录和 Cookie、云账号说明、备份、WebDAV、设备同步。

一句话：用户管理“我的数据”的几个页面长什么样：平台账号列表和每个平台的登录 / Cookie 页、云端账号停用说明、备份与恢复（含扫码同步电视）、WebDAV 网盘、局域网设备同步。

## 范围

- 包括：
  - 平台账号（A12.1）：“国内平台”“海外平台”两组九个平台、每行状态文字和颜色、退出确认、读不出 Cookie 的提醒。
  - 登录和 Cookie（A12.2）：通用 Cookie 页（虎牙、抖音、快手、YY、Twitch、SOOP、网易 CC、哔哩哔哩）、斗鱼页（续期组、强制续期）、哔哩哔哩扫码页（六种覆盖层、“扫不了？”）、网页登录页、舍弃和退出确认。
  - 云端账号停用说明（A12.3）：三个旧路由 `kSignIn`、`kMine`、`kUserManage` 落到的一页。
  - 备份与恢复（A12.4）：“云端和其他设备”“本地备份”“目录中的备份”“备份目录”四组、文件行的小菜单、恢复前预览、扫码页（`shared/qr_scan.dart`，设备同步也用）、日志页（从设置的“日志管理”进）。
  - WebDAV（A12.5）：路径、文件列表、文件和文件夹的小菜单、上传按钮、服务器抽屉、配置对话框、帮助页。
  - 设备同步（A12.6）：我的设备、发现的设备、手动输入，配对码、接收预览、对方请求。
- 不包括（归哪里）：
  - 登录、Cookie 加密存储、核验和续期的逻辑在 [K 账号和登录](../../K-账号和登录/README.md)；备份格式、WebDAV 协议、设备同步协议在 [J 设置和数据](../../J-设置和数据/README.md)（J03～J05）。
  - 设置总览里的入口行在 [A11.1](../A11-设置界面/A11.1-设置总览/README.md)；日志页的入口行在 A11.5，页面在这里（A12.4）。
  - 电视的账号、备份、同步页在 [A17.9](../A17-电视界面/A17.9-电视设置/README.md)；电视端的“同步TV数据”接收页（网页遥控）在 A17.9。

## 现状：做到哪、怎么工作的

- **用户看得到的**：
  - 平台账号：标题“平台账号”，顶部一句说明（读不出 Cookie 时换成红色提醒卡），每行平台图标 24、名字 15、状态 12（正常主色、提醒黄、失效红、未设置灰，可以两行），已存的平台行尾有退出按钮。点任何一行进那个平台的页面；哔哩哔哩没登录直接进扫码页。
  - Cookie 页：标题“{平台}账号”，顶部状态卡（和列表同一套文字），说明加“打开 xx 网页”，多行输入框下“粘贴”“清空”，没改动时保存变灰，哔哩哔哩和抖音先核验再存，页内“退出登录”先确认。
  - 备份：一次只做一件事（正在做的那行转圈，其他备份行变灰），恢复前先预览会变什么；手机点“同步TV数据”直接扫码，电脑弹输入地址。
  - WebDAV：标题下写当前服务器，顶栏服务器、刷新、⋮；点备份文件预览后恢复，⋮ / 右键 / 长按同一个小菜单；子目录里按返回直接离开（照 v3）。
  - 设备同步：接收先拉取对方配置、预览、再写入；所有按钮“接收（描边）· 发送（实心）”；宽 ≥840 且不是横屏手机时两列。
  - 所有页面内容最宽 720（设备同步两列时 1120）居中，横屏手机顶栏 48 高。
- **内部怎么工作**：
  - 账号：`accountPlatforms`（`features/account/account_platforms.dart:87`）列出九个平台和核验方式；`accountStatus`（`account_state.dart:115`）把存储里的 Cookie、核验结果、斗鱼会话变成一句状态文字和颜色，列表和状态卡共用；核验、扫码、续期的服务从 `account_services.dart` 的 provider 来（测试可替换）。
  - 备份：`shared/backup/backup_data.dart` 的 `previewRestore`（:248）算出恢复前后的差别，`backup_preview_dialog.dart` 的 `restoreWithPreview`（:140）给备份页、WebDAV、设备同步共用；文件名、默认目录、大小和时间文字在 `backup_files.dart`；网络电视的播放列表单独一段 `backup_iptv.dart`。
  - 扫码：`QrScanPage`（`shared/qr_scan.dart:141`）只管相机和取景，相机是接口 `QrCamera`（:24，应用里是 mobile_scanner，测试用 `test/shared/fake_qr_camera.dart`）；扫到后的状态（发送中、成功、失败、相机不可用）由调用方给 `QrScanStatus`（:361）。
  - 设备同步：`RemoteSyncService`（`features/remote_receiver/remote_sync_service.dart:76`）拆成 `fetch`（拉取）和 `apply`（写入），页面在两步之间弹预览；发现设备用 mDNS（`mdns_peers.dart`）。
- **完成度**：6 个任务全部完成（2026-10-01～02 合并）。3.x 的功能一项不少；去掉的只有 Firebase 云端账号（A12.3 c1、c2，v4 不再有云端服务）和“退出全部账号”（A12.1 K3，v4 自己加的）。这几页都还没在真机上看过：S02.3 记录写明“账号页没在真机上看”，备份、WebDAV、设备同步、扫码登录在 S02.4 里（未开始）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/account/account_page.dart` | 账号路由入口 `AccountPage`（:26）：没有平台参数时列表，有时进该平台的页面 |
| `apps/pure_live/lib/features/account/account_list_view.dart` | 平台账号列表（:24）：两组、说明或提醒卡、行尾退出、哔哩哔哩启动核验失效时提示并退出 |
| `apps/pure_live/lib/features/account/account_platforms.dart` | 九个平台的顺序、名字、核验方式 `AccountCheckKind`（:7）、Cookie 提示和网址（:87）；按路由找平台（:154） |
| `apps/pure_live/lib/features/account/account_state.dart` | 状态和颜色 `AccountTone`（:8）、`accountStatus`（:115）、斗鱼会话（:211、:224）、粘贴内容清理和判断（:255～:261） |
| `apps/pure_live/lib/features/account/account_services.dart` | 核验、扫码、斗鱼续期的接口和 provider（:29～:53）、退出等动作 `AccountActions`（:71） |
| `apps/pure_live/lib/features/account/account_widgets.dart` | 状态卡 `AccountStatusCard`（:20）、提醒（:70）、说明横幅（:99）、打开网页（:166）、确认框和退出确认（:176、:200） |
| `apps/pure_live/lib/features/account/cookie_editor.dart` | Cookie 页的框架 `CookieEditorScaffold`（:110：粘贴、清空、保存、舍弃确认、Ctrl+S）、输入框 `AccountField`（:58） |
| `apps/pure_live/lib/features/account/platform_cookie_view.dart`、`douyu_cookie_view.dart` | 通用 Cookie 页（:24）；斗鱼页（:29，续期组、强制续期、passport Cookie 只取 LTP0 / dy_did） |
| `apps/pure_live/lib/features/account/bilibili_qr_login.dart`、`bilibili_web_login.dart` | 扫码登录（六个阶段 `BilibiliQrPhase` :17、页面 :183、二维码卡片和覆盖层 :309）；网页登录（:46，标题栏“二维码登录”、核验盖层、底部红条） |
| `apps/pure_live/lib/features/auth/auth_page.dart` | 云端账号停用说明 `AuthPage`（:22）：停用卡、“同步与备份”三行、“平台账号”一行 |
| `apps/pure_live/lib/features/backup/backup_page.dart` | 备份与恢复（:57）：四组、正在做的事 `_Action`（:45）、文件行和小菜单（:465、:470）、选目录（`backupPickerProvider` :38） |
| `apps/pure_live/lib/features/backup/tv_sync.dart` | 同步电视：地址规范化（:13）、发送（:49）、输入地址对话框（:64）、扫码后发送的页面 `TvSyncScanPage`（:151） |
| `apps/pure_live/lib/features/backup/log_page.dart`、`file_browser.dart` | 日志页 `LogPage`（:28，路由 `RoutePath.kLogs`）；没有系统选择器时的应用内文件浏览对话框 |
| `apps/pure_live/lib/shared/backup/backup_data.dart`、`backup_preview_dialog.dart`、`backup_files.dart`、`backup_iptv.dart` | 恢复范围和预览（:19、:248）、确认对话框（:31、:140）、备份文件名和默认目录、网络电视数据的备份段 |
| `apps/pure_live/lib/shared/qr_scan.dart` | 扫码页 `QrScanPage`、相机接口、手电筒三种状态 `QrTorch`（:10）、状态面板 `QrScanStatus`、给输入框用的扫码按钮（:464） |
| `apps/pure_live/lib/features/web_dav/web_dav_page.dart` | WebDAV 页（:40）：顶栏、路径、文件行 `_EntryRow`（:662）、小菜单、上传、服务器抽屉、出错和空状态 |
| `apps/pure_live/lib/features/web_dav/web_dav_config_dialog.dart`、`web_dav_help.dart` | 配置对话框（:22，测试连接、显示密码）；帮助页（:12，看大图 :156） |
| `apps/pure_live/lib/features/web_dav/web_dav_client.dart`、`web_dav_auth.dart` | WebDAV 请求和 PROPFIND 解析、摘要认证（逻辑，属于 J04） |
| `apps/pure_live/lib/features/remote_receiver/remote_receiver_page.dart` | 设备同步页（:38）：两列分界（:24）、设备卡片、配对码对话框（:667，六个格子）、接收预览、对方请求 |
| `apps/pure_live/lib/features/remote_receiver/remote_sync_service.dart`、`remote_sync_protocol.dart`、`mdns_peers.dart` | 同步服务（`fetch` / `apply`）、协议、mDNS 发现（逻辑，属于 J05） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/account/account_page_test.dart` | 列表两组和顺序、状态文字和颜色、退出确认、核验失效、读不出的提醒；Cookie 页各部分、斗鱼页、扫码覆盖层、“扫不了？”、网页登录提醒、宽屏 720；停用说明页三个路由 |
| `apps/pure_live/test/features/backup/backup_page_test.dart` | 四组九行、创建后列出、恢复时其他操作变灰、小菜单三种打开方式、删除确认、选目录、手机扫码 / 电脑输入地址、横屏和宽屏；扫码页四种状态 |
| `apps/pure_live/test/features/web_dav/web_dav_page_test.dart`、`web_dav_auth_test.dart` | 顶栏、⋮ 菜单、路径从左开始、文件行、出错和“编辑配置”、抽屉、上传失败重试、返回直接离开、宽屏 720；摘要认证 |
| `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart` | 三组标题、设备卡片和按钮顺序、拿不到地址、发送和接收（预览后才写入）、对方请求、扫码、宽屏两列、横屏一列；服务本身的发送接收和配对码 |
| `apps/pure_live/test/shared/backup_extras_test.dart`、`test/plugins_test.dart` | 备份的附加段（搜索记录、多画面、网络电视）；电视地址对话框的扫码按钮 |

## 3.x 基线

- 账号：`git show v3.2.11:lib/modules/account/account_page.dart`（288 行，列表、点已登录直接弹退出）；Cookie 页 `account/widgets/account_cookie_editor.dart`（261 行）和各平台的 `*_cookie_page.dart`；斗鱼 `account/douyu/douyu_cookie_page.dart`、`douyu_cookie_controller.dart`；哔哩哔哩扫码 `account/bilibili/qr_login_page.dart`、`qr_login_controller.dart`，网页登录 `web_login_page.dart`；选择登录方式对话框 `common/utils/utils.dart:447-505`（A12.1 K2 去掉）。
- 云端账号：`lib/modules/auth/`（`sign_in_page.dart`、`mine_page.dart`、`user_manage_page.dart`、Firebase 的 `utils/firebase_manager.dart` 等，v4 全部去掉，路由落到说明页）。
- 备份：`lib/modules/backup/backup_page.dart`（320 行，日志管理在 `:257-313`）、扫码 `backup/scan_page.dart`（317 行）；WebDAV `lib/modules/web_dav/web_dav_page.dart`（779 行）、`web_dav_help.dart`；设备同步 `lib/modules/remote_receiver/remote_sync_page.dart`（447 行）、`remote_sync_service.dart`（1138 行）。
- 必须保留：Cookie 的存储键和 `bilibiliUid`、`douyuCookieSavedAt`（D-018）；对方请求同步时不能点外面关（3.x 行为）；WebDAV 子目录里按返回直接离开（A12.5 R4 照 3.x）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 备份恢复、WebDAV、设备同步、扫码、扫码登录都没在真机上看过 | A12.2、A12.4～A12.6 | 相机、局域网发现、Keystore 解密只在测试里模拟 | [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)、[K02.1](../../K-账号和登录/K02-登录状态/README.md) |
| 设备同步分不清“没连网络”和“没给权限”，说明两种都提 | `remote_receiver_page.dart` | 用户要自己判断 | 有需要时改服务（J05），Android 17 本地网络权限见 O04.1 |
| macOS 正式版没有 `com.apple.security.network.server` 权限（v4 没有 macOS 工程） | 以后的 `macos/Runner/Release.entitlements` | 以后在 Mac 上设备同步收不到连接 | 建 macOS 工程时加（[X04.1](../../X-多端客户端/X04-iOS和iPadOS/README.md) 构建任务里要写进去） |
| 设备同步不能选同步哪些内容 | `remote_receiver_page.dart` | 只能全部发送或接收 | [V01.6](../../V-需求和反馈/V01-新功能提议/README.md) 提议 |
| 哔哩哔哩只能存一个账号 | 账号页 | 多账号要来回粘贴 | [V01.2](../../V-需求和反馈/V01-新功能提议/README.md) 提议 |

## 相关决定和规范

- D-003（A12.1 K1～K3、A12.2 L1～L3、A12.3 X1～X2、A12.4 Q1～Q3、A12.5 R1～R4、A12.6 S1～S2 按建议 A）、D-013（哔哩哔哩打码昵称做登录引导，登录入口用 `RoutePath.kSettingsAccount` 加平台 id）、D-018（存储键不变）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（阅读型内容最宽 720）、第 7 节（文件行的更多操作用贴着按钮的小菜单，删除、退出用对话框）；[AGENTS.md](../../../AGENTS.md)（不把真实 Cookie、账号、地址写进仓库：这些页面的测试只用 `SESSDATA=ok`、`dav.test` 这类假值）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account test/features/backup test/features/web_dav test/features/remote_receiver test/shared/backup_extras_test.dart test/plugins_test.dart`。相机用假相机，网络用假服务，没有访问真实平台和服务器。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6～8 条（哔哩哔哩扫码登录、网页登录、登录后的原画）、第 5 节第 1～3 条（备份恢复、坚果云 WebDAV、设备同步）。都还没做（S02.4 未开始）。

## 路线

1. [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 和 [K02.1](../../K-账号和登录/K02-登录状态/README.md)：备份、WebDAV、设备同步、扫码、登录和 Cookie 加密在 K90 上逐项看（第二档）。
2. [J06.1](../../J-设置和数据/J06-3.x数据迁移/README.md)、[S04.1](../../S-质量和验证/S04-覆盖安装验证/README.md)：覆盖安装 3.x 后账号和备份数据都在（第一档）。
3. 新需求（多账号、同步时选内容）走 V01 提议，确认后再开这里的界面任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/account/`、`auth/`、`backup/`、`web_dav/`、`remote_receiver/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A12.1 | 账号总览 | 界面 | 完成 | 2026-10-01 | 587ccc3c7 | [设计或说明](A12.1-账号总览/README.md)、[记录](A12.1-账号总览/record.md)、[评审页](A12.1-账号总览/page/01-说明.jpg) |
| A12.2 | 登录和 Cookie | 界面 | 完成 | 2026-10-01 | 587ccc3c7 | [设计或说明](A12.2-登录和Cookie/README.md)、[记录](A12.2-登录和Cookie/record.md)、[评审页](A12.2-登录和Cookie/page/01-说明.jpg) |
| A12.3 | 云账号停用说明 | 界面 | 完成 | 2026-10-01 | a90c0502e | [设计或说明](A12.3-云账号停用说明/README.md)、[记录](A12.3-云账号停用说明/record.md)、[评审页](A12.3-云账号停用说明/page/01-说明.jpg) |
| A12.4 | 备份与恢复 | 界面 | 完成 | 2026-10-02 | 965d41956 | [设计或说明](A12.4-备份与恢复/README.md)、[记录](A12.4-备份与恢复/record.md)、[评审页](A12.4-备份与恢复/page/01-说明.jpg) |
| A12.5 | WebDAV | 界面 | 完成 | 2026-10-02 | 965d41956 | [设计或说明](A12.5-WebDAV/README.md)、[记录](A12.5-WebDAV/record.md)、[评审页](A12.5-WebDAV/page/01-说明.jpg) |
| A12.6 | 设备同步 | 界面 | 完成 | 2026-10-02 | 965d41956 | [设计或说明](A12.6-设备同步/README.md)、[记录](A12.6-设备同步/record.md)、[评审页](A12.6-设备同步/page/01-说明.jpg) |

<!-- docs:生成结束 -->
