# A12 账号和数据界面

用户管理“我的数据”的几个页面长什么样、怎么点、各状态怎么说：平台账号列表和每个平台的登录 / Cookie 页、云端账号停用说明、备份与恢复（含扫码同步电视和日志页）、WebDAV 网盘、局域网设备同步。

## 范围

- 包括：
  - 平台账号（A12.1）：`features/account/account_list_view.dart` 的列表——“国内平台”“海外平台”两组九个平台、每行状态文字和颜色、行尾退出和退出确认、读不出 Cookie 的提醒卡、哔哩哔哩启动核验失效时的提示。
  - 登录和 Cookie（A12.2）：通用 Cookie 页（虎牙、抖音、快手、YY、网易CC、Twitch、SOOP 和哔哩哔哩的 Cookie 页，`platform_cookie_view.dart` + `cookie_editor.dart`）、斗鱼页（续期组、强制续期，`douyu_cookie_view.dart`）、哔哩哔哩扫码页（六种覆盖层、“扫不了？”，`bilibili_qr_login.dart`）、网页登录页（`bilibili_web_login.dart`）、舍弃和退出确认。
  - 云端账号停用说明（A12.3）：三个旧路由 `kSignIn`、`kMine`、`kUserManage` 落到的一页（`features/auth/auth_page.dart`）。
  - 备份与恢复（A12.4）：“云端和其他设备”“本地备份”“目录中的备份”“备份目录”四组、文件行的小菜单、恢复前预览（`shared/backup/backup_preview_dialog.dart`，WebDAV、设备同步共用）、扫码页（`shared/qr_scan.dart`，设备同步也用）、同步电视（`features/backup/tv_sync.dart`）、日志页（`features/backup/log_page.dart`，从设置的“日志管理”进）。
  - WebDAV（A12.5）：路径、文件列表、文件和文件夹的小菜单、上传按钮、服务器抽屉、配置对话框、帮助页（`features/web_dav/` 的界面部分）。
  - 设备同步（A12.6）：我的设备、发现的设备、手动输入，配对码、接收预览、对方请求、扫码后选方向（`features/remote_receiver/remote_receiver_page.dart`）。
- 不包括（归哪里）：
  - 登录、Cookie 加密存储、核验和续期的逻辑（`AccountActions` 背后的 `LiveStore.secrets`、平台的核验接口、斗鱼续期）→ [K 账号和登录](../../K-账号和登录/README.md)（K01.1 已完成；Keystore 解密的真机验证 K02.1）；备份格式和 `BackupService`、WebDAV 请求和 Digest 认证（`web_dav_client.dart`、`web_dav_auth.dart`）、设备同步协议和服务（`remote_sync_service.dart`、`remote_sync_protocol.dart`、`mdns_peers.dart`）→ [J 设置和数据](../../J-设置和数据/README.md)（J03～J05）。A12 只管这些东西长什么样、怎么点、各状态怎么说。
  - 设置总览里的入口行（“账号和标签”组的“平台账号”、“数据”组的“备份与恢复”“日志管理”）→ [A11.1](../A11-设置界面/A11.1-设置总览/README.md)、[A11.5](../A11-设置界面/A11.5-数据/README.md)；日志页本身在这里（A12.4 Q1）。
  - 直播间、列表、弹幕列表里的“去登录”提示（`player_status.dart:225`、`shared/rooms/room_grid.dart:299`、`chat_list.dart:368-373` 的 `ChatNameHintBar`）→ A07.7、A09、D01.32；它们都跳 `RoutePath.kSettingsAccount`（D-013）。
  - 电视的账号、备份、同步页和电视端的“同步TV数据”接收页（网页遥控）→ [A17.9](../A17-电视界面/A17.9-电视设置/README.md)。
  - 苹果平台的差异（iOS 本地网络权限、macOS 的 `com.apple.security.network.server`）→ A18.1、A18.2，构建在 X04.1。

## 现状：做到哪、怎么工作的

- 用户看得到的（A12.1～A12.6 登记为完成，2026-10-01～02 合并；**都没有 K90 结果**，见“已知问题”）：
  - **平台账号**（设置 → 账号和标签 → 平台账号，`features/settings/settings_catalog.dart:555-561`）：标题“平台账号”；顶部一句说明，本机读不出某些平台的 Cookie 时换成红色提醒卡写明是哪几个（`account_list_view.dart:150-162`）；“国内平台”哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易CC，“海外平台”Twitch、SOOP（`account_platforms.dart:87-141`）。每行平台图标 24、名字 15、状态 12（正常主色加粗、提醒黄、失效红、未设置和核验中灰，不截断），存了 Cookie 的行尾是红色退出按钮（18，点击区 48，悬停“退出登录”），没存的是箭头（`:184-223`）。点任何一行进那个平台的页面；哔哩哔哩没存 Cookie 时直接进扫码页（`_open` `:97-114`，3.x 的“请选择登陆方式”去掉）。退出先确认（照 3.x 文字“退出登录 / 确定退出“{name}”账号吗？”，`account_widgets.dart:200`），进行中行尾转圈。哔哩哔哩打开列表时在线核验，平台说没登录就提示“哔哩哔哩登录已失效，请重新登录”并退出（`:86-91`，3.x `BiliBiliAccountService`）。
  - **Cookie 页**（`cookie_editor.dart:110` 的 `CookieEditorScaffold`）：标题“{平台}账号”；从上到下是状态卡（平台图标 32、和列表同一句状态，哔哩哔哩、抖音右边“重新核验”）→ 说明横幅（带“打开 xx 网页”，系统浏览器打开）→ “Cookie”多行输入框（3～7 行，`:83-84`）→“粘贴”“清空”两个描边小按钮 → 保存（48 高，没改动时变灰，`:346`）→ 页内“退出登录”（`:381`）。粘贴内容自动去掉“Cookie:”前缀（`account_state.dart:255`），不像 Cookie 的框下说明且不能保存（`:258`）；哔哩哔哩、抖音先核验再存（“正在核验并保存…”），核验请求本身失败时照存并写“已保存，暂时无法核验账号”；清空后保存等于退出，先确认。改了没保存就返回弹“舍弃 Cookie 修改？”（`:274-283`）；Ctrl+S、Cmd+S 保存（`:400-401`）。
  - **斗鱼页**（`douyu_cookie_view.dart:29`）：说明两段 + “打开 passport.douyu.com”；Cookie 框下面“续期”一组（LTP0、dy_did 两个带标签的框、“立即续期”和一句说明，`:201-255`），再下面单独一张卡“登录后强制续期”开关（设置键 `douyuForceRenew`，默认关，`:257-261`）；粘贴 passport Cookie 只取走 LTP0 / dy_did（`:72-79`），保存后框里是实际存下的登录 Cookie；会话状态（有效到几时、能否续期）常驻状态卡（`account_state.dart:211`、`:224`）。
  - **哔哩哔哩扫码**（`bilibili_qr_login.dart:183`）：没有重复的顶部说明；二维码 200（宽 ≥600 时 220，`:257-260`），加载、已扫描、失效、失败、核验中、核验成功六种状态盖在二维码上（`BilibiliQrPhase` `:17`，`QrCodeCard` 在 `packages/live_ui/lib/src/widgets/qr_code_widget.dart:99`），位置不跳；下面一行说明（已扫描时主色浅底，`_QrMessage` `:349`）；最下面“扫不了？”：网页登录（只在 Android、iOS 且有内置浏览器，`:243-244`）、填写 Cookie（进哔哩哔哩的 Cookie 页，返回回到扫码页）。确认后先核验，平台说没登录就不存（c13）。
  - **网页登录**（`bilibili_web_login.dart:46`）：内置浏览器打开 `passport.bilibili.com/login`；标题栏右边“二维码登录”（宽 <520 时只有图标，`:140`）；跳到主站时读 Cookie、核验，盖一层“正在核验账号…”（`:185`），出错底部红条（`:193-217`），成功后 `pop(true)`（`:125`）。没有内置浏览器时（Linux、没装 WebView2 的 Windows）旧网页登录地址显示哔哩哔哩的 Cookie 页加黄色提醒（`account_page.dart:39`、`platform_cookie_view.dart:140`）。
  - **云端账号说明**（`auth_page.dart:22`）：停用卡（主色 5% 底、圆角 20、`AppIcons.cloudOff`）→“同步与备份”WebDAV、设备同步、备份与恢复三行 →“平台账号”一行（X2 A，老用户容易把两种账号弄混），一栏最宽 720。
  - **备份与恢复**（首页 ≡ 菜单 `features/home/menu_button.dart:81`；设置 → 数据 `features/settings/settings_model.dart:102`）：四组——“云端和其他设备”（云端账号（已停用）→ 说明页、WebDAV、设备同步、同步TV数据，`backup_page.dart:289-325`）、“本地备份”（创建备份、恢复备份、仅导出关注列表、仅导入关注列表，`:326`）、“目录中的备份 · N”（每行“时间 · 大小 · 完整备份 / 仅关注列表”，点一下预览后恢复，⋮ / 右键 / 长按同一个小菜单 `showAppMenu`：恢复全部设置、仅恢复关注列表、红色删除，仅关注的文件没有“恢复全部设置”，`:363-408`、`:500-546`）、“备份目录”（没设过时写“备份目录（默认）”，设过才有“改回默认目录”，电脑多“打开备份目录”，`:410-440`）。一次只做一件事：正在做的那行转圈，其他备份行变灰（`_usable` `:270`），云端账号、WebDAV、设备同步照常能进。创建后提示“已备份到 purelive_….txt”，列表同时多一条。手机（有相机）点“同步TV数据”直接进扫码页，电脑和没相机时弹输入地址对话框（`_syncTv` `:250-268`）。
  - **扫码页**（`shared/qr_scan.dart:141` 的 `QrScanPage`，同步电视和设备同步共用）：顶栏手电筒（关 / 开 / 不可用三种图标，颜色跟顶栏前景色）、切换相机；画面上四角取景框，下面提示和“手动输入地址”；扫到后由调用方给状态 `QrScanStatus`（`:361`）：正在发送 → 成功（“完成”回去、“再扫一次”）或失败（写原因，“重试”“输入地址”）；相机不可用写原因和“重试”“输入地址”。
  - **日志页**（设置 → 数据 → 日志管理，`settings_model.dart:115`，路由 `RoutePath.kLogs`）：写入文件、最低级别、本次的日志（按级别筛、复制一条、复制全部）、分享、打开目录、清空（先确认，`log_page.dart:109-120`）。
  - **WebDAV**（`web_dav_page.dart:40`）：标题“WebDAV”下面一行当前服务器名（没有时“还没有服务器”，`:382-385`）；顶栏服务器（打开右侧抽屉）、刷新、⋮（仅上传关注列表——不能上传时变灰、使用帮助教程，`:386-423`）；路径从左开始，长了自动滚到最后一级（`_breadcrumbs` `:547-595`）；文件行图标 28、名字两行、“时间 · 大小”（文件夹只写时间），备份文件（名字以 `purelive` 开头）用专门的图标（`_EntryRow` `:662-737`）；点文件夹打开，点备份文件预览后恢复（`purelive_favorites` 开头的只恢复关注，`_open` `:324`），⋮ / 右键 / 长按同一个小菜单（文件夹只有删除，`_fileMenu` `:331`）；右下“备份到当前目录”带文字，上传中转圈（`:426-435`）；下拉刷新（`AppRefreshView`）。状态：没有配置（说明 +“创建新配置”+“使用帮助教程”）、没选服务器或保存的选择失效、加载失败（原因 +“重试”+“编辑配置”）、空目录（“这个目录是空的”）（`_content` `:462-521`）。恢复、删除时路径下一行字和进度条，列表变灰；上传、删除失败的提示条带“重试”（`_failed` `:150`）。抽屉：标题“WebDAV 服务器”、每台服务器名字和地址、同一行的编辑和红色删除、“添加新配置”（`_drawer` `:597-657`）。配置对话框可测试连接、显示密码，编辑时名称不能改（`web_dav_config_dialog.dart:22`）。子目录里按返回直接离开（R4 照 3.x）。帮助页内容照 3.x，卡片样式，截图点开看大图（`web_dav_help.dart:12`、`:156`）。
  - **设备同步**（备份与恢复 → 设备同步，`remote_receiver_page.dart:38`）：顶栏扫码（只在有相机的设备）、开始 / 停止；“我的设备”（地址可复制、二维码、六位配对码 28 号等宽字距 6、“同步账号 Cookie”开关、运行状态，停止时错误色；拿不到地址时写“未获取到本机地址”和“请连接 Wi-Fi 或有线网络；Android 需要允许……权限”，`_localDevice` `:438-528`）→“发现的设备”（按平台图标，“地址 · v版本”或“3.x 版本的设备”，设备之间一条分隔线，标题右边“正在搜索”转圈，`:530-593`）→“手动输入”（地址框可扫码、可粘贴同步链接，`:595`）。所有按钮“接收（描边）· 发送（实心）”（`_buttons` `:638`）。发送：写对方名字的确认 → 配对码（六个格子，`_PairingCodeDialog` `:667`）→ 发送；接收：配对码 → 拉取 → 预览会变什么（同备份页）→ 确认才写入（`_receive` `:140-158`）。对方请求时写对方名字（认得的话），“拒绝 / 允许”，点外面不能关（`_confirmIncoming` `:72-106`）。同步中顶栏下 2 像素进度条（`:330`）。宽 ≥840 且窗口不矮时两列（左我的设备，右另两块），最宽 1120；其余一列最宽 720（`:338`、`:357`）。离开页面服务停止（照 3.x）。
  - 布局：备份、WebDAV、设备同步、日志、帮助、扫码页用 `live_ui` 的 `settingsPageAppBar`（标题靠左 20 号 600，窗口高 <480 时顶栏 48，`packages/live_ui/lib/src/widgets/settings_page_frame.dart:13`）和最宽 720 的阅读列（`readableContentMaxWidth`，`settings_tiles.dart:12`）；账号列表、Cookie 页、扫码登录、网页登录、停用说明页用普通 `AppBar`（横屏手机也是 56 高，见“已知问题”），内容同样最宽 720。
- 内部怎么工作：
  - 账号：`accountPlatforms`（`account_platforms.dart:87`）列出九个平台、页面路由、核验方式 `AccountCheckKind`（`:7`：在线、斗鱼会话、Twitch 聊天身份、虎牙 yyuid、不核验）、输入提示和说明、网址、`usedByRequests`（网易CC 为假）；`accountStatus`（`account_state.dart:115`）把 `AccountSnapshot`（Cookie、读不出、斗鱼会话）和这次核验结果 `AccountCheck`（`:52`）变成一句 `AccountStatus`（文字、颜色 `AccountTone` `:8`、算不算已登录），列表和状态卡共用；核验、扫码、续期、时钟、退出等动作从 `account_services.dart` 的 provider 来（`:29-53`，测试可替换）。路由 `kSettingsAccount` 不带参数是列表、带平台 id 是该平台的页面（`account_page.dart:26`）。
  - 备份：`previewRestore`（`shared/backup/backup_data.dart:248`）算出恢复前后的差别（设置几项不同、关注、分区、历史、标签、屏蔽词、屏蔽用户、WebDAV、搜索记录、网络电视、多画面，`RestorePartKind` `:120`），`restoreWithPreview`（`backup_preview_dialog.dart:140`）给备份页、WebDAV 共用，设备同步用 `previewRestore` 自己画对话框；文件名（照 3.x `purelive_<时间>.txt`，同一秒加 `_2`）、默认目录（Android 先试 `Download/PureLive`，不可写时用应用自己的外部目录）、大小和时间文字在 `backup_files.dart`；网络电视播放列表单独一段 `backup_iptv.dart`。
  - 扫码：`QrScanPage` 只管相机和取景，相机是接口 `QrCamera`（`qr_scan.dart:24`，应用里是 `MobileQrCamera` `:55`，`platform/plugins.dart:42` 只在 Android、iOS 接上；测试用 `test/shared/fake_qr_camera.dart`）；`QrScan.available`（`:51`）决定“同步TV数据”和设备同步顶栏扫码出不出现。
  - 设备同步：`RemoteSyncService`（`remote_sync_service.dart:76`）进页面 `start`（Android 17 先要本地网络权限，拒绝时只弹提示，`:175-213`），离开 `dispose`；接收拆成 `fetch`（`:395`）和 `apply`（`:407`），页面在两步之间弹预览；对方来的请求经 `confirm` 回调问页面（`:342-350`），允许后直接写入；发现设备用 UDP 广播和 mDNS（`mdns_peers.dart:12`，能发现 3.x 设备）。
- 完成度（和 3.x 对照）：
  - 一致的：账号页的平台图标、名字、退出按钮和退出确认文字；Cookie 页的说明横幅、“Cookie”分组、多行输入、保存按钮、舍弃确认；斗鱼续期两个框和“立即续期”；扫码 3 秒轮询；网页登录的盖层和红条；备份四个操作、文件名、一次只做一件事；WebDAV 路径、文件菜单三项、上传按钮、抽屉、配置四个字段、删除确认、帮助内容、返回直接离开；设备同步三块、对方请求不能点外面关、扫码后选方向、离开页面停止服务、Cookie 存储键（D-018）。
  - 确认过的改动：A12.1 c1～c8 和 K1～K3、A12.2 c1～c15 和 L1～L3、A12.3 c1～c5 和 X1、X2、A12.4 c1～c11 和 Q1～Q3、A12.5 c1～c13 和 R1～R4、A12.6 c1～c11 和 S1、S2，都是建议 A（D-003）。去掉的只有 Firebase 云端账号（A12.3 c1、c2，用户决定）和 v4 自己加的“退出全部账号”（A12.1 K3）。
  - 还缺：全部没有 K90 结果；网易CC 的 Cookie 只存不用（C-22 未排）；设备同步不能选同步哪些内容（V01.6 提议）；哔哩哔哩多账号（V01.2）由 K01.2 做了，哔哩哔哩账号页多了“已记住的账号”一组（设计按 D-003 定在 V01.2 README 的 S6～S10，没出效果图，待真机）。

## 代码地图

账号和云端账号说明（`apps/pure_live/lib/features/account/`、`features/auth/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `account/account_page.dart`（50 行） | 路由入口 `AccountPage`（`:26`）：`kSettingsAccount` 不带参数是列表，带平台 id 或平台自己的路由时进那个平台的页面；斗鱼走 `DouyuCookieView`；`kBiliBiliQRLogin` 走扫码；`kBiliBiliWebLogin` 有内置浏览器时走网页登录，否则哔哩哔哩 Cookie 页加提醒（`:39`、`:48`） | A12.1、A12.2 |
| `account/account_list_view.dart`（224） | 平台账号列表 `AccountListView`（`:24`）：在线核验一次（`_check` `:62`，哔哩哔哩失效时提示并退出 `:86-91`）、点行进页面（`_open` `:97`）、退出（`_signOut` `:116`）、两组和提醒卡（`build` `:132`）、一行（`_tile` `:184`） | A12.1 c1～c8 |
| `account/account_platforms.dart`（160） | `AccountCheckKind`（`:7`）、`AccountPlatform`（`:25`，路由、核验方式、海外、提示和说明键、账号页名字、网址、`usedByRequests`）、九个平台的顺序 `accountPlatforms`（`:87`）、`accountPlatformOf`（`:144`）、`accountPlatformForRoute`（`:154`，`kDouyuCookie` 是 3.x 抖音页的旧名） | A12.1 c4、c6；A12.2 c3 |
| `account/account_state.dart`（261） | `AccountTone`（`:8`）、`AccountStatus`（`:27`）、核验结果 `AccountCheck` 及子类（`:52-85`）、`AccountSnapshot`（`:92`）、`accountStatus`（`:115`，各平台的状态文字）、`accountPageStatus`（`:180`）、`accountStored`（`:187`）、斗鱼会话 `douyuSessionState`（`:211`）和 `douyuSummary`（`:224`）、粘贴内容清理 `cleanPastedCookie`（`:255`）、`looksLikeCookie`（`:258`）、`pastedCookieField`（`:261`） | A12.1 c2、c7；A12.2 c5、c9 |
| `account/account_services.dart`（159） | 核验 `accountVerifierProvider`（`:29`）、扫码接口 `bilibiliQrApiProvider`（`:39`）、斗鱼续期 `douyuRenewerProvider`（`:44`）、时钟（`:50`）、动作 `AccountActions`（`:71`：读写 Cookie、退出、记住哔哩哔哩 uid、存斗鱼续期凭据） | K01.1（逻辑），A12 只调用 |
| `account/account_widgets.dart`（205） | `accountToneColor`（`:10`）、状态卡 `AccountStatusCard`（`:20`）、红色提醒 `AccountNotice`（`:70`）、说明横幅 `AccountTipBanner`（`:99`）、打开网页 `openAccountWebsite`（`:166`）、确认框 `confirmAccountAction`（`:176`）和退出确认 `confirmSignOut`（`:200`，列表和页面同一个） | A12.1 c8；A12.2 c2、c4、c7 |
| `account/cookie_editor.dart`（427） | `CookieInput`（`:13`）、`accountFieldDecoration`（`:36`）、输入框 `AccountField`（`:58`）、Cookie 页框架 `CookieEditorScaffold`（`:110`：改动检测 `:200`、保存 `:220`、页内退出 `:242`、舍弃确认 `:274`、粘贴清空 `:334-338`、Ctrl+S `:400`） | A12.2 c1、c5～c8 |
| `account/platform_cookie_view.dart`（167） | 通用 Cookie 页 `PlatformCookieView`（`:24`）：先核验再存（`_save` `:95`）、重新核验（`:149`）、没有内置浏览器时的提醒（`:140`） | A12.2 c2、c6、c15 |
| `account/douyu_cookie_view.dart`（305） | 斗鱼页 `DouyuCookieView`（`:29`）：吸收 passport Cookie（`:72`）、保存（`:93-115`）、立即续期（`_renewNow` `:121`）、续期组（`:201`）、强制续期卡（`:257`）、说明 `_DouyuTip`（`:279`） | A12.2 c9、c10 |
| `account/bilibili_qr_login.dart`（395） | `BilibiliQrPhase`（`:17`）、轮询状态机 `BilibiliQrLogin`（`:43`，3 秒一次、失败退避）、扫码页 `BilibiliQrLoginView`（`:183`，核验后才存 `:214`、“扫不了？”`:274-300`）、`_QrCard`（`:309`）、`_QrMessage`（`:349`） | A12.2 c11～c13 |
| `account/bilibili_web_login.dart`（230） | `isBilibiliHome`（`:25`）、`cookieHeader`（`:32`）、网页登录页 `BilibiliWebLoginView`（`:46`：清浏览器 Cookie `:67`、完成 `:105`、窄时只有图标 `:140`、盖层 `:185`、红条 `:193`） | A12.2 c14 |
| `auth/auth_page.dart`（119） | 云端账号说明 `AuthPage`（`:22`）：停用卡（`:34`）、“同步与备份”三行（`:62-90`）、“平台账号”一行（`:92-104`） | A12.3 |

备份、扫码和日志（`apps/pure_live/lib/features/backup/`、`shared/backup/`、`shared/qr_scan.dart`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `features/backup/backup_page.dart`（569） | 时钟、默认目录、选择器、能否打开目录四个 provider（`:22-41`）；正在做的事 `_Action`（`:45`）；`BackupPage`（`:57`）：读目录和文件（`:85`、`:96`）、一次只做一件 `_run`（`:116`）、创建 `_create`（`:126`）、恢复（`:150`、`:163`）、删除确认（`:181`）、选目录和改回默认（`:202`、`:228`）、同步电视（`_syncTv` `:250`）、四组（`build` `:274`）；文件行 `_BackupFileRow`（`:470`，小菜单 `:500`，右键和长按 `:545-546`） | A12.4 c1～c7、c10、c11 |
| `features/backup/tv_sync.dart`（244） | 电视地址规范化 `normalizeTvAddress`（`:13`）、发给电视的内容 `tvSyncDocument`（`:31`）、发送 `sendToTv`（`:49`）、输入地址对话框 `askTvAddress`（`:64`，框里有扫码按钮）、扫码后发送的页面 `TvSyncScanPage`（`:151`，发送中、完成、失败 `:213-233`） | A12.4 c2、c8 |
| `features/backup/log_page.dart`（290） | 分享接口 `logSharerProvider`（`:21`）、日志页 `LogPage`（`:28`：复制全部 `:78`、分享 `:83`、打开目录 `:95`、清空 `:109`）、一条日志 `_EntryRow`（`:249`） | A12.4 Q1（从设置搬来） |
| `features/backup/file_browser.dart`（175） | 没有系统选择器时的应用内文件浏览对话框 `showFileBrowser`（`:15`，选目录或选备份文件） | A12.4 c5 |
| `shared/backup/backup_data.dart`（355） | `backupServiceProvider`（`:14`）、`BackupScope`（`:19`）、导出和恢复（`:40`、`:59`，加搜索记录、多画面、网络电视段）、`RestorePartKind`（`:120`）、`RestorePart`（`:158`）、`RestorePreview`（`:196`）、`previewRestore`（`:248`） | A12.4 c4；J03.1 |
| `shared/backup/backup_preview_dialog.dart`（183） | 来源文字 `backupSourceText`（`:11`）、每项文字 `restorePartText`（`:21`）、预览对话框 `confirmRestore`（`:31`）、`restoreWithPreview`（`:140`） | A12.4 c4、A12.5 c5、A12.6 c2 |
| `shared/backup/backup_files.dart`（127） | 文件名 `backupFileName`（`:9`）、不重名 `freeBackupFile`（`:18`）、`LocalBackupFile`（`:29`）、`listBackupFiles`（`:51`）、默认目录 `defaultBackupFolder`（`:73`）、`isWritableFolder`（`:103`）、大小和时间文字（`:116`、`:123`） | A12.4 c3、c5、c6 |
| `shared/backup/backup_iptv.dart`（226） | 网络电视播放列表、频道、节目单对应的备份段（导出 `:21`、读出 `:37`、恢复 `:57`） | J03（数据）；A12.4 预览里的“网络电视”一项 |
| `shared/qr_scan.dart`（475） | `QrTorch`（`:10`）、相机接口 `QrCamera`（`:24`）、`QrScan`（`:46`，`available` `:51`）、`MobileQrCamera`（`:55`）、`scanQrCode`（`:107`）、扫码页 `QrScanPage`（`:141`，顶栏 `:224`、手电筒 `:234`）、取景角 `_Corners`（`:321`）、状态面板 `QrScanStatus`（`:361`）、给输入框用的扫码按钮 `qrScanButton`（`:464`） | A12.4 c8、A12.6 c9 |

WebDAV 和设备同步（`apps/pure_live/lib/features/web_dav/`、`features/remote_receiver/`）：

| 文件 | 职责 | 设计 |
|---|---|---|
| `web_dav/web_dav_page.dart`（738） | `webDavHttpProvider`、时钟（`:23`、`:26`）；`WebDavPage`（`:40`）：读配置和目录（`:82`、`:107`、下拉 `:135`）、失败带“重试”的提示条（`:150`）、选择 / 编辑 / 删除服务器（`:167`、`:179`、`:212`）、上传（`:254`）、恢复（`:284`）、删除（`:301`）、点文件（`_open` `:324`）、文件菜单（`:331`）、顶栏和上传按钮（`build` `:376`）、各状态（`_content` `:462`）、路径（`:547`）、抽屉（`:597`）；文件行 `_EntryRow`（`:662`） | A12.5 c1～c12、R1～R4 |
| `web_dav/web_dav_config_dialog.dart`（209） | 失败原因文字 `webDavFailureText`（`:11`）、配置对话框 `showWebDavConfigDialog`（`:22`，测试连接 `_CheckState` `:43`、成功用语义色 `:104`、显示密码 `:156`） | A12.5 c9 |
| `web_dav/web_dav_help.dart`（241） | 帮助页 `WebDavHelpPage`（`:12`，组标题 13 号主色、卡片圆角 16）、截图 `WebDavScreenshot`（`:156`，点开全屏看大图 `:193`） | A12.5 c13 |
| `web_dav/web_dav_client.dart`（310）、`web_dav_auth.dart`（237） | WebDAV 请求和 PROPFIND 解析（`WebDavClient` `:76`、`parseMultistatus` `:240`）、失败分类 `WebDavProblem`（`:30`）；Basic / Digest 认证（`parseAuthChallenges` `:18`、`DigestChallenge` `:69`、`digestAuthorization` `:127`） | J03.1、J04.1（逻辑） |
| `remote_receiver/remote_receiver_page.dart`（772） | `remoteSyncServiceProvider`（`:18`）、两列分界 `remoteSyncTwoColumns` 840（`:24`）；`RemoteReceiverPage`（`:38`）：对方请求（`:72`）、配对码（`:110`）、发送（`:125`）、接收和预览（`:140`、`:160`）、扫码后选方向（`:267`）、顶栏和两列（`build` `:306`）、组标题（`:388`）、我的设备（`:438`）、发现的设备（`:530`、`:555`）、手动输入（`:595`）、按钮对（`:638`）；配对码对话框 `_PairingCodeDialog`（`:667`，六个格子） | A12.6 c1～c11 |
| `remote_receiver/remote_sync_service.dart`（590）、`remote_sync_protocol.dart`（111）、`mdns_peers.dart`（122） | 设备 `RemoteSyncDevice`（`:17`）、服务 `RemoteSyncService`（`:76`：`start` `:175`、`stop` `:216`、选本机地址 `:243`、收请求 `:285`、`send` `:379`、`fetch` `:395`、`apply` `:407`、`nameOf` `:420`）；协议常量和二维码解析 `RemoteSyncProtocol`（`:7`）；mDNS `MdnsPeers`（`:12`）、`BonsoirPeers`（`:29`） | J05（逻辑）；A12.6 c2 拆了 `fetch` / `apply` |

入口和路由：`routes/app_router.dart:43-45`（三个旧路由 → `AuthPage`）、`:52`（`kBackup`）、`:58-60`（账号）、`:75`（`kWebDavPage`）、`:82`（`kRemoteSync`）、`:84`（`kLogs`）；`routes/app_navigator.dart:165`（`toBiliBiliLogin` 直接进扫码页）；共用的 `packages/live_ui/lib/src/widgets/settings_page_frame.dart`（`settingsPageAppBar` `:13`、`SettingsPageList` `:49`）、`settings_row.dart`（`SettingsGroup` `:118`、`SettingsRow` `:261`、`SettingsLinkRow` `:500`）、`qr_code_widget.dart`（`QrColors` `:6`、`QrCodeWidget` `:21`、`QrCodeCard` `:99`）、`apps/pure_live/lib/shared/in_app_web.dart`（`InAppWeb.available` `:15`）。

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/account/account_page_test.dart`（22） | A12.1 6 个：两组九个平台和各状态文字颜色、点行进页面和哔哩哔哩直接扫码、列表退出、启动核验失效、读不出的提醒、1280 宽 ≤720；A12.2 13 个：Cookie 页顺序和各状态、页内退出、剪贴板和 Ctrl+S、先核验再存、网易CC、斗鱼各部分、扫码覆盖层和刷新、平台拒绝不存、“扫不了？”、手机网页登录在前、宽屏、没有内置浏览器的提醒、斗鱼会话说明；A12.3 2 个：三个旧路由、宽屏和横屏；平台名统一 1 个（A07.9） |
| `apps/pure_live/test/features/backup/backup_page_test.dart`（18） | 数据 4 个（3.x 备份的预览、仅关注文件、搜索记录、文件名和电视地址）；页面 10 个（四组九行和图标、创建后列出、恢复时其他变灰、小菜单三种打开、删除确认、读不了目录、选目录和改回默认、不是备份的文件、手机扫码 / 电脑输入地址、横屏 48 顶栏、宽屏 720 和打开目录）；扫码页 4 个（顶栏、发送中到完成、失败、相机不可用） |
| `apps/pure_live/test/features/web_dav/web_dav_page_test.dart`（10）、`web_dav_auth_test.dart`（5） | PROPFIND 解析；加服务器、上传、预览后恢复；下拉刷新（A03.1）；顶栏和 ⋮、文件行；三种方式打开同一菜单；出错和“编辑配置”；抽屉；上传失败重试；返回直接离开；宽屏 720。Digest：RFC 示例、只认 Digest 的服务器、nonce 过期、Basic 照旧、真实 HTTP 栈 |
| `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart`（12） | 服务 3 个（3.x 二维码和地址、收发、配对码）、本机设备 1 个；页面 8 个（说明和三组、拿不到地址和停止、发送、接收先预览、对方请求、扫码选方向、宽屏两列、横屏一列） |
| `apps/pure_live/test/shared/backup_extras_test.dart`（4）、`test/plugins_test.dart`（8，其中 1 个） | 备份的网络电视和多画面段；电视地址对话框的扫码按钮（假相机） |
| `apps/pure_live/test/features/settings/settings_data_test.dart`（7，其中 1 个）、`features/home/home_test.dart` | 设置“数据”最后一行“日志管理”打开 `kLogs`；路由表 |
| `apps/pure_live/test/shared/fake_qr_camera.dart` | 假相机（备份、设备同步、插件测试共用），不是测试用例 |

## 3.x 基线

文件都在 `git show v3.2.11:lib/modules/` 下（另注的除外）：

- 账号：`account/account_page.dart`（288 行）：标题“三方认证”，一张卡片 8 行（哔哩哔哩、虎牙、YY、抖音、快手、Twitch、Soop、斗鱼，`:23-180`），点已登录的行直接弹退出确认 `_showLogoutDialog`（`:38` 起、`:244-287`），一行 `:188-242`。哔哩哔哩没登录时 `routes/app_navigation.dart:96-108` 的 `toBiliBiliLogin` 在手机上弹 `plugins/utils.dart:224` 的 `showOptionDialog`“请选择登陆方式”（短信登陆 / 二维码登陆），电脑直接扫码。
- Cookie 页：`account/widgets/account_cookie_editor.dart`（261）：标题都是“设置cookie”（`:156`），说明横幅（`:228-254`），多行输入（`:176-190`），保存后“Cookie 已保存在本机”（`:95-110`），舍弃确认（`:112-145`）；各平台 `huya/`、`douyin/`、`kuaishou/`、`yy/`、`twitch/`、`soop/` 的 `*_cookie_page.dart` 只差提示和说明。斗鱼 `account/douyu/douyu_cookie_page.dart`（126）、`douyu_cookie_controller.dart`（210）。
- 哔哩哔哩：扫码 `account/bilibili/qr_login_page.dart`（216）、`qr_login_controller.dart`（323，3 秒轮询、3 次失败后停 `:240-260`）、`bilibili_login_qr_code.dart`（55）；网页登录 `web_login_page.dart`（146）、`web_login_controller.dart`（196）。
- 云端账号：`auth/`（`sign_in_page.dart` 62、`components/firebase_email_auth.dart` 489、`mine_page.dart` 201、`user_manage_page.dart` 564、`components/user_detail_main_page.dart` 368、`utils/firebase_manager.dart` 372 等）；路由 `routes/app_pages.dart:78-80`。v4 全部去掉，三个路由落到说明页。
- 备份：`backup/backup_page.dart`（320）：“云端备份”（Firebase 账号行 `:88-148`、WebDav、设备同步、同步TV数据只在手机 `:163-170`）、“本地备份”（`:173-237`）、“备份设置”（`:239-255`）、“日志管理”（`:257-313`）；`plugins/backup_recovery_service.dart`（每次弹目录选择器 `:14-73`，恢复选完直接覆盖 `:75-108`）；扫码 `backup/scan_page.dart`（317）。
- WebDAV：`web_dav/web_dav_page.dart`（779，顶栏 ⋮ 菜单 `:248-296`、路径 `:310-386`、列表 `:472-550`、抽屉 `:116-176`、配置对话框 `:579-759`）、`web_dav_controller.dart`（432）、`web_dav_help.dart`（356）。
- 设备同步：`remote_receiver/remote_sync_page.dart`（447，对方请求 `barrierDismissible: false` `:37-57`、顶栏 `:184-200`、三块 `:217-396`、扫码页 `:399-447`）、`remote_sync_service.dart`（1138）、`remote_sync_protocol.dart`（96）。
- 必须保留：Cookie 的存储键和 `bilibiliUid`、`douyuCookieSavedAt`（D-018）；对方请求同步时不能点外面关；WebDAV 子目录里按返回直接离开（A12.5 R4）；备份文件名 `purelive_<时间>.txt` / `purelive_favorites_…`（3.x 的选择器还能认出）；设备同步离开页面就停止服务、二维码带配对码；[specs/UI.md](../../specs/UI.md) 附录 A 没有专门针对这几页的条目。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| A12.1～A12.6 登记为“完成”，记录里都没有 K90 结果：S02.3 记录写明“账号页没在真机上看”；备份、WebDAV、设备同步、扫码在 S02.4（未开始）；哔哩哔哩网页登录、登录后画质在 S02.6（未开始） | 各任务 `record.md`；[S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | 不符合 PROCESS 3.2“完成必须有真机结果”；相机、局域网发现、Keystore 解密、`Download/PureLive` 免权限写入只在测试里模拟 | 写进本单元报告；真机步骤在 [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)、[S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)、[K02.1](../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)；建议这些任务改回“待真机”或在 S02.4 结束后补记 |
| 账号列表、Cookie 页、扫码登录、网页登录、云端账号说明用普通 `AppBar`，横屏手机顶栏 56 高；同一组的备份、WebDAV、设备同步用 `settingsPageAppBar`，窗口高 <480 时 48 | `account_list_view.dart:167`、`cookie_editor.dart:404`、`bilibili_qr_login.dart:250`、`bilibili_web_login.dart:136`、`auth/auth_page.dart:107` | 同一组页面横屏顶栏高度不一样，矮窗口少 8 像素内容 | 没有任务管；建议并入 [A04.1](../A04-尺寸和适配/A04.1-尺寸和字号适配/README.md)（高度分档）时一起换成 `settingsPageAppBar` |
| 这几页在电脑上按 Esc 不返回（没有 `EscapeBack`） | `features/account/`、`auth/`、`backup/`、`web_dav/`、`remote_receiver/` 都没有 | 规范 5.4 的 Esc 返回链不全（WebDAV 抽屉、对话框有系统自带的 Esc） | A05.1 |
| 网易CC 的 Cookie 只存不用：状态写“已保存，暂未用于请求（登录后加入弹幕待验证）” | `account_platforms.dart:117-122`（`usedByRequests: false`）、`account_state.dart:171-173` | 用户填了也没有效果 | UPGRADES C-22“未排”（要用户的登录 Cookie，见 V03.3 的“需要维护者决定”）；接上后把状态改成“已保存” |
| 设备同步分不清“没连网络”和“没给权限”：权限被拒只弹提示（`remote_sync_service.dart:180-182`），选不到地址返回空串（`:243-264`），页面说明两种都提 | `remote_sync_service.dart:175-264`；`remote_receiver_page.dart:438` | 用户要自己判断 | 服务给出原因时再改文字（J05）；Android 17 本地网络权限见 [O04.1](../../O-Android系统集成/O04-权限/README.md) |
| 对方发来配置时（对方点“发送”），本机只问“拒绝 / 允许”，允许后直接写入，没有预览；预览只在本机主动“接收”时有 | `remote_sync_service.dart:342-358`、`remote_receiver_page.dart:72` | 被覆盖的一方看不到会变什么（3.x 也是这样，设计 S1 只要求主动接收预览） | 不在 A12.6 范围；有需要走 V01 提议（可并入 V01.6 选内容） |
| macOS 正式版没有 `com.apple.security.network.server` 权限（v4 没有 macOS 工程） | 以后的 `macos/Runner/Release.entitlements`（3.x 在 `~/ref/v3ref/macos/Runner/Release.entitlements`） | 以后在 Mac 上设备同步收不到连接 | 建 macOS 工程时加（[X04.1](../../X-多端客户端/X04-iOS和iPadOS/X04.1-苹果平台的构建和签名/README.md)、A18.2） |
| 设备同步不能选同步哪些内容 | `remote_receiver_page.dart:125-158` | 只能全部发送或接收 | [V01.6](../../V-需求和反馈/V01-新功能提议/V01.6-设备同步选择同步内容/README.md) 提议 |
| ~~哔哩哔哩只能存一个账号~~ | — | — | [K01.2](../../K-账号和登录/K01-账号和登录方式/K01.2-哔哩哔哩多账号/README.md)（V01.2）：哔哩哔哩账号页“已记住的账号”，待真机 |
| 日志页没有自己的组件测试（只测了设置里的入口和路由） | `features/backup/log_page.dart`；`test/features/settings/settings_data_test.dart:152` | 筛选、复制、清空确认改坏了测试发现不了 | 没有任务管；补测试时并入 S01 |
| 代码注释和测试分组名还用旧编号（`U.10a`、`U.11a`、`M12`、`U.1c` 等），本子分类的代码约 15 处 | 例如 `backup_page.dart:293`、`bilibili_qr_login.dart:181`、`auth/auth_page.dart:16-17`、`account_page_test.dart:208` 的分组名 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003：A12.1 K1～K3、A12.2 L1～L3、A12.3 X1、X2、A12.4 Q1～Q3、A12.5 R1～R4、A12.6 S1、S2 都按建议 A。
- D-011：标题位置照 3.x 实际运行的样子，这几页靠左（`settingsPageAppBar` 默认 `centerTitle: false`）。
- D-013：哔哩哔哩打码昵称做登录引导，引导入口用 `RoutePath.kSettingsAccount` 加平台 id（哔哩哔哩没登录时进扫码页）。
- D-018：Cookie 存储键、`bilibiliUid`、`douyuCookieSavedAt`、`douyuForceRenew` 不变。
- D-026：多账号（V01.2）、同步时选内容（V01.6）是新功能，先在 V01 提议。
- [specs/UI.md](../../specs/UI.md)：第 5.3 节（阅读型内容最宽 720，设备同步宽屏两列 1120 是 A12.6 S2 确认的例外）；第 7 节（文件行的更多操作用贴着按钮的小菜单，删除、退出、舍弃用对话框；WebDAV 上传、删除失败的提示条带“重试”，4 秒）；第 8.1 节（测试连接成功用语义色 `LiveSemanticColors.success`）。
- [AGENTS.md](../../../AGENTS.md)：不把真实 Cookie、账号、地址写进仓库，这几页的测试和效果图只用 `SESSDATA=ok`、`yyuid=1234`、`dav.test`、`192.168.1.100` 这类假值。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account test/features/backup test/features/web_dav test/features/remote_receiver test/shared/backup_extras_test.dart test/plugins_test.dart test/features/settings/settings_data_test.dart`（上表）。相机用假相机，网络用假服务和本机回环，没有访问真实平台和服务器。覆盖了每个确认的改动；缺的：日志页本身、深色主题下二维码和状态卡的截图对照、`defaultBackupFolder` 在 Android 11 以上的真实路径。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条（哔哩哔哩扫码登录、重开后仍登录，F-ACC-02、F-ACC-06）、第 7 条（网页登录，F-ACC-03）、第 8 条（登录后原画，F-ACC-07），第 5 节第 1 条（备份恢复，F-BAK-01～03）、第 2 条（坚果云 WebDAV，F-BAK-04）、第 3 条（设备同步和扫码，F-BAK-05、F-BAK-06）、第 8 条（本地网络权限）。都还没有结果（S02.4、S02.6 未开始）；S02.2、S02.3 都没有看这几页。

## 路线

1. [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（第二档）：K90 上走 CHECKLIST 第 5 节第 1～3、8 条，结果写回 A12.4～A12.6 的“实现和验证”；设备同步要第二台设备，缺设备时写“未验证（缺设备）”。
2. [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 和 [K02.1](../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)：哔哩哔哩扫码、网页登录、重启后仍登录、登录后原画，结果写回 A12.1、A12.2。
3. [J06.1](../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md)、[S04.1](../../S-质量和验证/S04-覆盖安装验证/S04.1-覆盖安装3.x验证/README.md)（第一档）：覆盖安装 3.x 后账号和备份数据都在。
4. 小改动（没有登记任务，建议并入已有任务）：账号几页的顶栏换成 `settingsPageAppBar`（A04.1）；Esc 返回（A05.1）；日志页补测试（S01）。
5. 新需求（多账号 V01.2 → K01.2、同步时选内容 V01.6 → J05.1，都待真机；被覆盖一方的预览）走 V01 提议，确认后再开这里的界面任务；网易CC 的 Cookie 接上请求等 C-22 排期。

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
