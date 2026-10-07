# A14.1 系统界面：设计（第 1 版，已确认，Android 已开发，登记为完成）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02；原生部分多数确认改动没有 K90 结果，见“实现和验证”）
- 范围：系统画、应用决定内容的界面：Android 的播放通知（媒体控制）、录制前台服务通知、画中画窗口里的系统按钮、启动图标和系统启动画面、分享接收、桌面快捷方式、权限请求说明；Windows、Linux 的通知和任务栏按钮（v3 都没有）。iOS、macOS 的差异在 [A18.1](../../A18-苹果平台界面/A18.1-iOS和iPadOS差异设计/README.md)、[A18.2](../../A18-苹果平台界面/A18.2-macOS差异设计/README.md)
- 旧编号：U.14、T13a.1（见 [MAPPING.md](../../../MAPPING.md)）；相关决定 D-003（X1～X4 按建议 A）
- 一起做的功能任务：[O03.2](../../../O-Android系统集成/O03-分享接收和快捷方式/O03.2-接回半成品/README.md)（权限、分享接收、剪贴板口令）
- 对应：[TASKS.md](../../../TASKS.md)（A14.1 没有逐项界面条目，原生代码不在 Dart 里）；相关：[A07.8](../../A07-直播间界面/A07.8-小窗/README.md)（小窗和画中画里我们自己的按钮）、[A06.4](../../A06-首页和全局/A06.4-启动页/README.md)（应用的启动页）、[A06.3](../../A06-首页和全局/A06.3-全局弹窗/README.md)（口令导入对话框）、[A16.1](../../A16-桌面界面/A16.1-桌面窗口/README.md)（窗口、托盘）
- 评审页：claude.ai 私有页面（只有项目所有者能打开），每条改动可以点“满意 / 不满意 / 再想想”；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)；按章节导出在 [page/](page/01-说明.jpg)
- 记录：[record.md](record.md)
- 图片：通知栏、画中画菜单、桌面、分享面板、系统启动画面是**系统画的**，图里按 Android 15 原生样式示意（各厂商系统不同，K90 是 HyperOS）；其中应用决定的部分（文字、小图标、按钮、图标图案）照 v3 代码；封面和头像是示意图片

## 界面清点表

| 编号 | 界面 | 从哪出现 | 形态 | 状态 |
|---|---|---|---|---|
| A14.1-a | 播放通知（媒体控制） | 直播间开始播放时（Android；`LiveAudioService.start`） | 通知栏、锁屏（Android 13 起是媒体卡片，12 及以下是带两个按钮的通知） | 播放中、暂停（暂停后可以划掉）、定时关闭到点停止 |
| A14.1-b | 录制前台服务通知 | 开始录制、开播自动录开始录时（Android） | 通知栏 | 录制中（不管几个都一样）；被系统停掉时直接消失 |
| A14.1-c | 画中画窗口里的系统按钮 | 直播间小窗按钮进画中画后点一下画中画（A07.8） | 系统画中画 | 按钮显示、隐藏 |
| A14.1-d | 启动图标 | 桌面、应用列表、最近任务；Windows 的 exe、任务栏、标题栏、托盘；电视桌面横幅 | 各桌面的形状（圆、方圆、圆角方）、主题图标 | — |
| A14.1-e | 系统启动画面 | 冷启动，应用第一帧之前 | Android 12 起：底色加图标；11 及以下：底色；Windows、Linux 没有 | 浅色、深色（跟系统） |
| A14.1-f | 分享接收 | 别的应用里“分享”选“纯粹直播”；用纯粹直播打开 m3u 文件或 `purelive://` 链接 | 系统分享面板 → 应用里 | 直播间链接（直接进房间）、分享口令（A06.3 的对话框）、播放列表 / 节目单文件（导入）、认不出（提示条）、平台已下线（提示条）、解析失败（提示条） |
| A14.1-g | 桌面快捷方式 | Android 长按图标；Windows 安装时“创建桌面快捷方式” | 桌面 | v3：Android 长按只有系统项；Windows 安装程序默认勾选一次 |
| A14.1-h | 权限请求说明 | 打开“后台播放”“新直播间自动助眠”；录制、下载、代理等 | 对话框 → 系统权限框 | 说明、系统框、拒绝、永久拒绝 |
| A14.1-i | Windows、Linux 的系统通知、任务栏缩略图按钮、系统媒体控制 | — | — | v3 都没有 |

## v3 的样子（`v3.2.11`）

**播放通知**（`lib/player/core/live_audio_service.dart`、`live_audio_handler.dart`，用 audio_service）

- 只在 Android（和 macOS）建；通知类别“纯粹直播播放”（`audio_channel_name`），常驻，暂停后可以划掉，点通知回到应用，颜色固定蓝色（`live_audio_service.dart:51-63`）。没有指定小图标，用 audio_service 默认的 `mipmap/ic_launcher`（`audio_service.dart` 的 `androidNotificationIcon` 默认值）。
- 内容：标题是直播间标题，副标题是主播名，专辑名“纯粹直播”，封面是直播间封面（`:157-170`）。
- 按钮：暂停 / 播放、停止，紧凑通知两个都显示（`live_audio_handler.dart:193-196`）；按钮名称用 audio_service 的默认英文“Play / Pause / Stop”。Android 13 起由系统画成媒体卡片，audio_service 把“停止”放进自定义按钮位。
- 定时关闭、新直播间自动助眠到点时停止（`live_audio_handler.dart:203-214`）。

**录制通知**（`android/.../RecorderForegroundService.kt`）

- 录制开始时起一个 `dataSync` 前台服务（`:130-184`）；通知类别 id `pure_live_recording`，名称“Recording”、说明“Active live-stream recording”（英文，`:33-35`、`:216-227`），重要性低、不显示角标。
- 通知：小图标 `ic_launcher_foreground`（`:240`）；标题“直播录制进行中”，内容“录制与封装由独立后台服务保护，点按返回应用”（`recorder_background_service.dart:117-121`）；常驻、只响一次；点了回到应用（`:229-238`）；没有按钮。几个直播间同时录也只有这一条，文字不变。
- Android 15 起后台 `dataSync` 服务每天累计 6 小时，到时系统回调 `onTimeout`，服务马上停（`:188-198`）；应用把正在录的任务标成失败，原因“Android 后台数据同步时限已到，录制正在收尾……”（`recorder_controller.dart:1036-1054`），没有通知。

**画中画**（`plugins/built_in_kotlin/floating/.../FloatingPlugin.kt:88-110`）

- 进画中画时只给了画面比例、源区域和无缝缩放，没有给按钮（`RemoteAction`）。点一下画中画，系统画出它自己的按钮：设置、关闭、回到全屏（原生 Android；各厂商不同）。应用自己画的播放 / 关闭按钮只在鼠标悬停时出现，手机上看不到（A07.8）。

**启动图标和系统启动画面**（`android/app/src/main/res/`）

- 应用名“纯粹直播”（英文“PureLive”，`values*/strings.xml`）。
- 自适应图标：白色底层 + 前景图 `ic_launcher_foreground`，前景再往里缩 16%（`mipmap-anydpi-v26/ic_launcher.xml:4-8`）。前景图里的电视只占画布宽的 42%，再缩 16% 后约占可见圆直径的 43%。旧版图标 `mipmap-*/ic_launcher.png`。没有单色层。电视桌面用 `banner.png`。
- 系统启动画面：`LaunchTheme` 的底是 `launch_background`（浅色白、深色黑，没有图），`NormalTheme` 用系统背景色（`values/styles.xml:4-18`、`values-night/styles.xml`、`drawable-v21/launch_background.xml`）。Android 12 起系统自动在这个底上画应用图标（带白色底层的圆）。接着进应用自己的启动页（A06.4，青色渐变）。
- Windows：exe 和任务栏是 `app_icon.ico`，标题栏和托盘是 `assets/icons/icon.png`（A16.1）；窗口在第一帧准备好才显示，没有启动画面。

**分享接收**（`AndroidManifest.xml` 的 `SEND`、`SEND_MULTIPLE`、`VIEW`；`main.dart:105-131`）

- 分享面板里出现“纯粹直播”（文字和播放列表类文件：m3u、xml、json、gz 等）。
- 收到后依次判断（`shared_media_intake.dart:70-130`）：分享口令 → 弹“分享”对话框（A06.3）；m3u / txt / 节目单文件 → 导入（提示条在 A13.1）；含直播间链接 → 解析后直接进直播间（短链接要联网，`shared_live_link_opener.dart:30-63`）；平台已下线 → “该平台已下线，无法再打开，可在关注列表中取消关注”；解析失败 → “无法解析此链接”；都不是 → “不支持的文件格式，仅限 M3U 或 TXT”（`:146-148`）。
- 分享面板的“直接分享”目标声明了（`res/xml/share_targets.xml`），但从来没发布过，不出现。Windows、Linux 没有系统分享接收。

**桌面快捷方式**

- Android：没有静态或动态快捷方式，长按图标只有系统自己的项。
- Windows：安装程序有“创建桌面快捷方式”，默认勾选一次（`windows/packaging/exe/make_config.yaml` 的 `create_desktop_icon: true`，`inno_setup.iss:49-50`）；开始菜单照常。Linux：没有。

**权限请求说明**

| 权限 | 什么时候要 | v3 怎么问 | 位置 |
|---|---|---|---|
| 通知 | 打开“后台播放”“新直播间自动助眠” | 先弹说明框“需要通知权限 / 为了在后台播放时显示控制条并防止直播中断，我们需要开启通知权限。”（取消 / 去开启），再弹系统框；没给就不打开开关 | `live_audio_service.dart:207-217`；`video_settings_page.dart:356-371` |
| 忽略电池优化 | 同上，通知之后 | 说明框“需要忽略电池优化 / 开启此选项能确保直播在手机锁屏或后台时不会被强制关闭。”，再弹系统框；不给也能打开开关 | `live_audio_service.dart:219-225` |
| 通知（录制） | 开始录制 | 不问 | — |
| 所有文件访问 / 存储 | 录制目录不能写时、备份 | 直接跳系统页面，不说明；失败提示条“没有获得存储权限，无法保存录制文件” | `recorder_controller.dart:664-688` |
| 安装未知应用 | 下载新版本 | 提示条（A06.3） | `plugins/update.dart` |
| 本地网络（Android 17） | 用局域网代理、投屏 | 系统框；拒绝后提示条 | `common/services/local_network_access.dart:33-35` |
| 画中画 | 小窗按钮 | 系统关掉时没反应（A07.8 的 c9 已处理） | — |

说明框是 SmartDialog 自己画的：宽 300、内边距 20、圆角 15、卡片色；标题 18 号粗体居中、内容 14 号居中；底下“取消”（文字按钮）和“去开启”（浮起按钮）分散排开（`live_audio_service.dart:229-261`）。

**Windows、Linux**：没有系统通知（开播、录制都不发）、没有任务栏缩略图按钮和任务栏进度、没有接系统媒体控制（音量浮窗里看不到、媒体键只在窗口有焦点时有用）。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| S1 | 通知小图标：播放通知没指定，audio_service 用 `mipmap/ic_launcher`，Android 8 起它是自适应图标（白色底层不透明），状态栏和媒体卡片左上角只剩一个白色圆块（按代码推算）；录制通知用 `ic_launcher_foreground`，电视只占这张图的四成，状态栏里是一个很小的电视 | `live_audio_service.dart:51-63`；`RecorderForegroundService.kt:240`；`mipmap-anydpi-v26/ic_launcher.xml` |
| S2 | 录制通知：类别名英文“Recording”、说明英文（系统通知设置里看得到）；内容永远是“直播录制进行中 / 录制与封装由独立后台服务保护，点按返回应用”，看不出录的是谁、几个、录了多久；没有“停止” | `RecorderForegroundService.kt:33-35`、`:216-248`；`recorder_background_service.dart:117-121` |
| S3 | 后台录制被系统停掉（Android 15 起每天 6 小时、服务被杀）时通知直接消失，只在应用里标失败，人不在应用里就不知道 | `RecorderForegroundService.kt:188-198`；`recorder_controller.dart:1036-1054` |
| S4 | 媒体按钮名称是英文“Play / Pause / Stop”，读屏读出来是英文 | `live_audio_handler.dart:193` |
| S5 | 画中画里没有我们自己的按钮，手机上在画中画里不能暂停（应用画的按钮只在鼠标悬停时出现） | `FloatingPlugin.kt:88-110`；`player_manager.dart:3215-3287` |
| S6 | 启动图标显得小：前景图四周本来就留了大片透明，自适应图标又往里缩 16%，电视只占可见圆的四成；没有单色层，Android 13 起打开“主题图标”时只有它不变色 | `mipmap-anydpi-v26/ic_launcher.xml:4-8`；`drawable-*/ic_launcher_foreground.png` |
| S7 | 系统启动画面：Android 12 起白底（深色黑底）加带白圈的小图标，接着换成青色渐变的启动页，底色和图标大小各跳一次；Android 11 及以下一片白（A06.4 的 S7） | `values/styles.xml:4-7`、`values-night/styles.xml:4-7`、`drawable-v21/launch_background.xml` |
| S8 | 分享来的文字里没有认得出的直播间链接时，提示“不支持的文件格式，仅限 M3U 或 TXT”，说的是文件 | `shared_media_intake.dart:112-121`、`:146-148` |
| S9 | 分享短链接（b23.tv 等）要先联网解析，这段时间没有任何反馈；冷启动时先看到首页，几秒后突然跳进直播间 | `shared_live_link_opener.dart:30-63` |
| S10 | 权限说明框和别的对话框不一样：宽 300、圆角 15、文字居中、两个按钮分散排开 | `live_audio_service.dart:229-261` |
| S11 | 通知权限被永久拒绝后，点“去开启”什么都不发生（系统不再弹框），“后台播放”开关弹回关，没有任何说明 | `live_audio_service.dart:210-217`；`video_settings_page.dart:371` |
| S12 | 录制不申请通知权限：Android 13 起通知关着时录制照常但通知看不见、停不了；录制目录要“所有文件访问权限”时直接跳到系统页面，没有说明 | `RecorderForegroundService.kt`；`recorder_controller.dart:671-686` |

## v4 现在的偏差（`apps/pure_live/`）

- 播放通知照 v3（`lib/features/live_play/logic/background_playback.dart:152-230`），连颜色都没设；录制通知照 v3（`android/.../RecorderForegroundService.kt:98`、`:201-220`），类别名仍是英文“Recording”。
- 画中画照 v3，没有按钮（`MainActivity.kt:319-327`）。
- 启动图标、系统启动画面照 v3（同一套资源）。
- 分享接收还没有接上（M12.5 暂停中）。
- 打开“后台播放”时没有权限说明（没找到 `permission_notification_title` 的用处）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 通知栏（播放、录制）、录制通知各状态、画中画、图标、长按快捷方式、启动画面、分享、权限说明 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [通知栏 播放和录制](page/02-通知栏-播放和录制.jpg)
- [录制通知的各种样子](page/03-录制通知的各种样子.jpg)
- [画中画里的系统按钮](page/04-画中画里的系统按钮.jpg)
- [启动图标](page/05-启动图标.jpg)
- [长按图标](page/06-长按图标.jpg)
- [系统启动画面](page/07-系统启动画面.jpg)
- [分享接收](page/08-分享接收.jpg)
- [权限请求说明](page/09-权限请求说明.jpg)
- [Windows 和 Linux](page/10-Windows-和-Linux.jpg)
- [v3 的问题](page/11-v3-的问题.jpg)
- [改了什么](page/12-改了什么.jpg)
- [每个按钮是干什么的 怎么用](page/13-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/14-各客户端.jpg)
- [需要你选的](page/15-需要你选的.jpg)
- [性能要点](page/16-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-shade.jpg](v3-shade.jpg)、[v4-shade.jpg](v4-shade.jpg)、[v4-shade-n.jpg](v4-shade-n.jpg) | 通知栏：播放（媒体卡片）和录制，状态栏的小图标 |
| [v3-notify-states.jpg](v3-notify-states.jpg)、[v4-notify-states.jpg](v4-notify-states.jpg) | 录制通知的各种样子、暂停时的媒体卡片、通知类别 |
| [v3-pip.jpg](v3-pip.jpg)、[v4-pip.jpg](v4-pip.jpg)、[v4-pip-n.jpg](v4-pip-n.jpg) | 画中画点开后的系统按钮 |
| [v3-icons.jpg](v3-icons.jpg)、[v4-icons.jpg](v4-icons.jpg) | 启动图标在各种桌面形状、主题图标、Windows、通知小图标 |
| [v3-launcher.jpg](v3-launcher.jpg)、[v4-launcher.jpg](v4-launcher.jpg)、[v4-launcher-n.jpg](v4-launcher-n.jpg) | 长按启动图标 |
| [v3-splash-seq.jpg](v3-splash-seq.jpg)、[v4-splash-seq.jpg](v4-splash-seq.jpg) | 冷启动：系统启动画面 → 启动页 → 首页 |
| [v3-share-sheet.jpg](v3-share-sheet.jpg)、[v4-share-sheet-n.jpg](v4-share-sheet-n.jpg) | 系统分享面板（v3 和新设计一样） |
| [v3-share-result.jpg](v3-share-result.jpg)、[v4-share-result.jpg](v4-share-result.jpg)、[v4-share-opening.jpg](v4-share-opening.jpg) | 分享来的内容认不出 / 正在打开 |
| [v3-perm.jpg](v3-perm.jpg)、[v4-perm.jpg](v4-perm.jpg)、[v4-perm-n.jpg](v4-perm-n.jpg)、[v4-perm-denied.jpg](v4-perm-denied.jpg) | 打开“后台播放”时的通知权限说明；永久拒绝后 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 播放通知的内容（直播间标题、主播名、封面）、类别“纯粹直播播放”、暂停 / 播放和停止两个按钮、点通知回到直播间；录制用前台服务；画中画用系统的；分享接收的几条路（口令、播放列表文件、直播间链接）和已有的提示；权限先说明再请求，说明文字照 v3；Windows 安装时的桌面快捷方式 | — |
| c2 | 修改 | 通知小图标换成单色图：播放是电视图形，录制是录制圆点 | S1 |
| c3 | 修改 | 录制通知写清楚：一个直播间时“正在录制 · 晚风”，下面是标题和清晰度；几个时“正在录制 N 个直播间”，下面是主播名；顶上的计时由系统走（不每秒刷新）；类别名“录制”；点通知打开录制中心 | S2 |
| c4 | 增强 | 录制通知加两个按钮：“停止录制”（几个时“全部停止”）和“录制中心”（选择 X1） | S2 |
| c5 | 增强 | 后台录制被系统停掉、录制失败时发一条“录制已停止”提醒，写清原因和已保存的时长，点开到录制中心；新通知类别“录制提醒”（选择 X2） | S3 |
| c6 | 修改 | 媒体按钮名称中文：播放、暂停、停止 | S4 |
| c7 | 增强 | 画中画加“暂停 / 播放”按钮（系统画中画的动作按钮），和 A07.8 三种小窗同一套 | S5 |
| c8 | 修改 | 启动图标里的电视放大到和别的应用差不多（约占可见圆的六成），加单色层，打开主题图标时跟着变色（选择 X4） | S6 |
| c9 | 修改 | 系统启动画面：底色和 A06.4 的启动页一样（浅色、深色各一），中间是应用图标、不带白圈，大小和启动页的 Logo 一样；Android 13 起按应用自己选的深浅色（下次冷启动生效）；Android 11 及以下同底色 | S7 |
| c10 | 修改 | 分享来的内容里没有能打开的直播间链接时提示“分享的内容里没有能打开的直播间链接”；只有文件格式不对时才说“仅限 M3U 或 TXT” | S8 |
| c11 | 增强 | 收到分享的链接马上提示“正在打开分享的直播间…”，打开后消失；解析失败、平台下线的提示照 v3 | S9 |
| c12 | 修改 | 权限说明用通用对话框（A02.2：标题左对齐、按钮在右下），文字照 v3 | S10 |
| c13 | 修改 | 权限被永久拒绝时，说明框换成“通知权限已关闭”和“去设置”（打开本应用的系统通知设置）；回到应用后再检查一次，开了就把开关打开 | S11 |
| c14 | 增强 | 第一次开始录制而通知关着时，用同一个对话框说明一次（可以不开，录制照常）；录制目录要“所有文件访问权限”时先说明为什么，再跳系统页面 | S12 |
| c15 | 增强 | 长按启动图标：搜索直播、录制中心、最近看过的两个直播间（选择 X3） | — |
| c16 | 保留 | Windows、Linux 不加系统通知、任务栏缩略图按钮和系统媒体控制（v3 没有） | — |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 媒体卡片 | 点一下回到直播间（同 v3）。 |
| 2 | 暂停 / 播放 | 暂停或继续；耳机、蓝牙按键同。 |
| 3 | 停止 | 停止播放，通知消失。 |
| 4 | 录制通知 | 点一下打开录制中心。 |
| 5 | 停止录制 / 全部停止（新） | 停止录制，已录的保存。 |
| 6 | 录制中心（新） | 打开录制中心。 |
| 7 | 暂停 / 播放（画中画，新） | 在画中画里暂停或继续。 |
| 8 | 全屏（系统） | 回到应用的直播间。 |
| 9 | 关闭（系统） | 关掉画中画，停止播放。 |
| 10 | 设置（系统） | 打开系统里本应用的画中画设置。 |
| 11 | 启动图标 | 点开应用；长按出快捷方式。 |
| 12 | 搜索直播（新） | 直接打开搜索页。 |
| 13 | 录制中心（新） | 直接打开录制中心。 |
| 14 | 最近看过的直播间（新） | 直接进这个直播间；最多两个，跟历史记录走。 |
| 15 | 纯粹直播（分享面板） | 把链接、口令或播放列表文件交给应用：链接直接进直播间，口令弹“打开分享的直播间”（A06.3），播放列表进导入。 |
| 16 | 取消 | 不开权限，开关保持关。 |
| 17 | 去开启 / 去设置 | 弹系统的权限框；永久拒绝后打开系统设置。 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 上面的图（通知栏、画中画、桌面、分享面板都是系统画的，HyperOS 等样子不同，内容一样）。 |
| Android 平板、折叠屏 | 同手机。 |
| Windows | 不加系统通知、任务栏缩略图按钮、系统媒体控制（v3 没有）；图标：exe、任务栏、标题栏、托盘同一张图（A16.1）；安装时可选桌面快捷方式（照 v3）；没有启动画面，窗口在第一帧准备好后才显示（照 v3），窗口底色用表面色（A16.1 的 c5）；没有分享接收（剪贴板口令在 A06.4）。 |
| Linux | 同 Windows；v3 没有桌面文件（.desktop）和图标，打包时补上（名称“纯粹直播”，同一张图）。 |
| 电视 | 启动图标是横幅（`banner.png`），系统启动画面同手机的做法；通知、画中画、长按快捷方式不适用（pure_live_TV 没有画中画）；细节在 A17.2。 |
| 苹果平台 | iOS 的媒体控制在锁屏和控制中心（系统画，内容同 Android）；iOS 不能在后台长时间录制；画中画、分享接收（分享扩展）在 A18.1；启动画面（LaunchScreen）用同样的底色和图标；macOS 同 Windows（菜单栏图标在 A18.2）。 |

## 待选（建议 A）

- X1 录制通知上的按钮：A 加“停止录制”和“录制中心”；B 照 v3 没有按钮，点通知回到应用。
- X2 后台录制被系统停掉时：A 发一条“录制已停止”提醒；B 照 v3 只在应用里标失败。
- X3 长按启动图标：A 加搜索直播、录制中心、最近看过的两个直播间；B 照 v3 不加。
- X4 启动图标：A 电视放大到和别的应用一样、加单色层；B 照 v3。

## 拿不准的地方

1. v3 播放通知的小图标在 K90 上的样子：白色圆块是按代码推算的（audio_service 默认用 `mipmap/ic_launcher`，Android 8 起它是自适应图标）。
2. v3 画中画点开后，系统有没有从媒体会话取“播放 / 暂停”按钮（原生 Android 的部分版本会）；HyperOS 的画中画菜单和原生不同。要在 K90 上看。
3. Android 13 起媒体卡片里“停止”的位置：audio_service 把它转成自定义按钮，图里放在左下。
4. 通知顶上的计时（`setUsesChronometer`）在 HyperOS 上的样子。
5. HyperOS 用自己的图标主题，不一定读单色层；原生 Android 13 起的主题图标会用。
6. 系统启动画面按应用自己选的深浅色（Android 13 的 `SplashScreen.setSplashScreenTheme`）要在原生层做；用户选了别的主题色时，启动画面仍是默认蓝的底色（系统启动画面拿不到应用的主题色）。
7. 图里的通知栏、画中画菜单、分享面板、桌面都是示意，字号和间距按 Android 15 原生估的。

## 交给其他任务的

- A06.4：Logo 放到屏幕正中（文字和进度条在它下面），和系统启动画面的图标对齐，切换时不跳；跨任务待同步里“A06.4 → A14.1 系统启动画面和应用启动页同底色”由本任务 c9 处理。
- A02.2：权限说明用通用对话框；“去设置”一类跳系统设置的按钮。
- A11.3：“后台播放”“新直播间自动助眠”在权限被拒时的说明（c13）。
- A10.1：录制中心接住通知上的“停止录制”和“录制已停止”提醒（点开定位到那条任务）；第一次录制时的通知说明（c14）。
- A07.8：画中画的暂停按钮和三种小窗同一套（c7）。
- A16.1：Windows 窗口在第一帧前的底色（c5 已写）。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-02，和 O03.2 一起做，合并提交 `dad6c96fc`“Merge U.14 (Android) and F.0a: permissions, share intake, clipboard codes, playback proxy, system surfaces”；登记表记的是记录提交 `8cf3c21b7`）

定稿：用户确认第 1 版，X1～X4 由维护者按建议 A 定（D-003）。这一轮只做 Android；c16（Windows、Linux 照 3.x 不加系统通知）本来不用改。

| 编号 | 做到 | 现在的代码（Dart 在 `apps/pure_live/lib/`，原生在 `apps/pure_live/android/app/src/main/`） |
|---|---|---|
| c1 | ✅ | 保留的照旧：播放通知类别 id `com.mystyle.purelive.audio`（`features/live_play/logic/background_playback.dart:311`）、点通知回到直播间、录制前台服务（`AndroidManifest.xml:142`）、系统画中画、`res/xml/share_targets.xml`；分享接收和权限说明是 O03.2 新接的 |
| c2 | ✅ | 播放 `res/drawable/ic_stat_playback.xml`（`background_playback.dart:316` 的 `androidNotificationIcon`，`res/raw/keep.xml` 留住）；录制 `res/drawable/ic_stat_recording.xml`（`kotlin/com/mystyle/purelive/RecorderForegroundService.kt:331`），后来随 A10.3 改成实心圆挖方块 |
| c3 | ✅ | 文字 `app/recording_notice.dart:22` 的 `recordNotificationContent`（一个：“正在录制 · 主播名”+“标题 · 清晰度”；几个：“正在录制 N 个直播间”+ 主播名；计时起点取最早开始的）；有变化才发 `platform/recording_platform.dart:216` 的 `AndroidRecordKeepAlive.refresh`；原生 `buildNotification`（`RecorderForegroundService.kt:323`），系统计时 `setUsesChronometer`（`:341`）；类别 `pure_live_recording`（`:97`）名字改成“录制”（`record_channel_name`）；点通知打开录制中心（`:334`） |
| c4 | ✅ | 两个按钮 `RecorderForegroundService.kt:335-336`（“停止录制 / 全部停止”、“录制中心”）；“停止录制”→ `RecorderPlugin.kt:159` 的 `onStopRequested` → `recording_platform.dart:300` → `RecordingNotices.stopAll`（`recording_notice.dart:165`，已录的保存） |
| c5 | ✅（偏差 1，后来补上） | `RecordingNotices.changed`（`recording_notice.dart:147`）：后台被停掉（`lastErrorStage == 'background'`）一定发，其他失败只在应用不在前台时发，每次失败只发一次；文字 `recordStoppedContent`（`:76`，原因 + 已保存时长）；原生 `alert`（`RecorderForegroundService.kt:130`），新类别“录制提醒”（`pure_live_recording_alerts` `:98`），按钮“打开录制中心” |
| c6 | ✅ | `background_playback.dart:276` 的 `mediaControls`：播放、暂停、停止（`media_play`、`media_pause`、`media_stop`；图标仍用 audio_service 的） |
| c7 | ✅ | `PictureInPicture.bindPlayback`（`background_playback.dart:72`，`RoomBackgroundPolicy._syncNotification` `:434` 调，变化才发）；原生 `MainActivity.kt:545` 的 `setPictureInPicturePlaying` 和 `:532` 的 `pictureInPictureActions`（一个 `RemoteAction`，图标 `ic_pip_play.xml` / `ic_pip_pause.xml`）；进画中画、自动画中画、更新参数都带上；离开房间 `unbindPlayback`（`:515`） |
| c8 | ✅ | `res/mipmap-anydpi-v26/ic_launcher.xml`：前景内缩 16% → 2%（电视约占可见圆的六成），`<monochrome>` 用 `res/drawable/ic_launcher_monochrome.xml` |
| c9 | ✅（偏差 2） | `res/values-v31/styles.xml`（`LaunchTheme`、`SplashTheme.Light`、`SplashTheme.Dark`）、`res/values-night-v31/styles.xml`；底色 `res/values/colors.xml` 的 `splash_light` `#FAF8FF`、`splash_dark` `#121318`；图标 `res/drawable/splash_icon.xml`（`splash_logo.png` 内缩 24%，288 dp 的框里约 150 dp，不设图标底色所以没有白圈）；13 起 `app/intake/system_intake.dart:58` 跟着“主题模式”调 `setSplashTheme`（`:96`）→ `MainActivity.kt:570`；11 及以下 `res/drawable/launch_background.xml`、`drawable-v21/launch_background.xml` 同底色 |
| c10 | ✅ | `app/intake/share_intake.dart:155`、`:159`（没有链接：“分享的内容里没有能打开的直播间链接”，`share_intake_no_room`）、`:202`（只有文件格式不对：`unsupported_file_format`） |
| c11 | ✅（偏差 3） | `share_intake.dart:183`（“正在打开分享的直播间…”，`share_intake_opening`）；平台下线、解析失败照 3.x（`:191`） |
| c12 | ✅ | `shared/permission_prompts.dart:30` 的 `showPermissionDialog`：A02.2 的对话框（标题左对齐，“取消”和主按钮在右下），文字照 3.x 的 `permission_*` 键 |
| c13 | ✅ | `BackgroundPermissions._notifications`（`permission_prompts.dart:105`）：永久拒绝时换成“通知权限已关闭”+“去设置”（`:120-124`），打开本应用的通知设置（`PermissionsPlugin.kt:72`），`nextResume`（`:49`）回到应用再查，开了就把开关打开；还是关的照 A11.3 红字 |
| c14 | ✅ | `RecordingPermissionPrompts.notificationsOnce`（`permission_prompts.dart:168`，“以后再说”，录制照常）、`explainStorage`（`:207`，所有文件访问权限先说明）；见 O03.2 的 c6 |
| c15 | ✅（偏差 4） | 动态快捷方式 `ShareIntakePlugin.kt:139` 的 `setShortcuts`（搜索直播、录制中心、最多两个直播间 `:156`，名字最长 24 字）；Dart `system_intake.dart:57`、`:83` 的 `recentRoomShortcuts`（跟观看记录，变了才发）；文字 `res/values/strings.xml`、`values-en/strings.xml` |
| c16 | 不用改 | Windows、Linux 没有系统通知、任务栏缩略图按钮、系统媒体控制（同 3.x）；X01 开工时确认 |

- 偏差（记录“和设计不同的地方”）：①c5 点开当时只到录制中心——后来 A08.5（`6a599edee`“Recording reminder opens the recording centre at its task”，A08.5 c3）做到定位到那条任务（`RecorderForegroundService.kt:171` 的 `openRecordings` 带任务 id、`:187` 每个任务一个请求码）；只录一个直播间时点**前台**录制通知仍不定位 → H05.2。②c9 自选主题色、纯黑深色时系统启动画面仍是默认底色（系统启动画面拿不到应用的主题色，设计“拿不准”第 6 条）。③c11 提示条没有转圈、3 秒后自己消失（提示条没有关闭接口，在 `routes/` 里，不在可改范围）。④c15 直播间快捷方式用统一的电视图标、没有主播头像（要下载头像）；是动态快捷方式（开发包包名不同，静态的写不了），先打开过一次应用才出现。
- 后来的变化：H05.1（`79ecb5d2b`）单个直播间的通知标题按状态写（`_oneTitleKey`，`recording_notice.dart:59`：准备录制、正在录制、正在重连、正在整理录像），“录制已停止”换成自己的小图标 `ic_stat_record_stopped.xml`（`RecorderForegroundService.kt:135`）；A10.3 改了 `ic_stat_recording.xml` 的形状；`c5bc87666` 把 audio_service 的三个按钮图标加进 `res/raw/keep.xml`（发布版资源压缩删掉后 Android 13 起播放通知和前台服务起不来）；`132a5672b` 让本地网络请求用自己的请求码。
- 提交：`02085e8dd`（应用：分享、口令、权限、播放代理、系统界面）、`def02145b`（测试）、`1d98ecc04`（Android：插件、服务、资源，29 个文件）；合并 `dad6c96fc`；记录 `8cf3c21b7`。`flutter build apk --debug` 通过（只构建、没有安装）。
- 新翻译键 31 个（O03.2 和本任务合计）：本任务的是 `media_play/pause/stop`、`record_channel_*`、`record_alert_channel_*`、`record_notify_*`、`record_stopped_*`、`permission_notification_blocked_*`、`permission_open_settings`、`permission_later`、`permission_record_notification_content`、`permission_storage_*`、`share_intake_no_room`、`share_intake_opening`；原生 `strings.xml` 加 `shortcut_search`、`shortcut_recordings`。没有新设置（`detectClipboardRooms` 是 O03.2 的）。
- 和合并有关的：改了 `features/live_play/logic/background_playback.dart`（c2、c6、c7 只能在这里接，只加不改原逻辑）、`packages/live_ui`（一个图标）。

**验证**

- 自动测试：`apps/pure_live/test/platform/system_surfaces_test.dart`（新，记录时 9 个，现在 12 个用例声明：后来加了 H05.1 的按状态标题、发布版留住的资源、插件请求码不重复）：录制通知文字、保活没变不发、“停止录制”停全部、“录制已停止”的文字和何时发、媒体按钮中文、画中画按钮、资源文件（小图标、图标内缩和单色层、启动画面颜色和图标、快捷方式两种语言）。分享提示、权限、快捷方式数据在 O03.2 的 `apps/pure_live/test/intake_test.dart`（15 个）、`apps/pure_live/test/shared/permission_prompts_test.dart`（7 个）。原生画出来的样子测试代替不了。
- 真机（K90，[S02.2 记录](../../../S-质量和验证/S02-真机验证/S02.2-K90冒烟/record.md)、[S02.3 记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)，2026-10-02，提交 `288fec0ec` 的 arm64 profile）：

  | 记录“要在 K90 上看的” | 结果 |
  |---|---|
  | 1. 状态栏小图标形状；媒体卡片按钮中文 | 按钮“暂停”“停止”中文、标题和正文对，**通过**（S02.2，c6）；小图标形状**没有记录**（c2） |
  | 2. 录制一个、两个直播间的通知、计时、两个按钮、通知类别名 | 一个直播间的标题、正文、“停止录制”“录制中心”**通过**（S02.2，c3、c4）；两个直播间、计时、按钮能停、类别名**没有记录** |
  | 3. 系统停掉后台录制时的“录制已停止” | **没有记录**（c5）；排在 [S02.5](../../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/README.md) 阶段 4 的 4B-01～06（A08.5、H05.1） |
  | 4. 画中画的暂停 / 播放按钮 | 进画中画**通过**（S02.3）；暂停按钮**没有记录**（c7） |
  | 5. 桌面图标、主题图标、长按快捷方式 | **没有记录**（c8、c15） |
  | 6. 冷启动的系统启动画面、跟主题模式 | **没有记录**（c9）；S02.2 只记了冷启动 198 毫秒 |
  | 7. 分享、权限（O03.2） | 分享链接直接进直播间**通过**（S02.3）；打开后台播放：说明 → 系统通知权限 → 电池说明 → 系统电量页**通过**（S02.2，c12）；“没有链接”“正在打开”提示（c10、c11）、永久拒绝（c13）、第一次录制的说明（c14）**没有记录** |

  登记表写“完成”，但原生部分的多数确认改动没有 K90 结果（不符合 PROCESS“完成要有真机结果”）；建议并入 [S03.1](../../../S-质量和验证/S03-统一验证/README.md) 或补一份 verify.md，由维护者定。
- 留下的问题和去向：前台录制通知不定位 → [H05.2](../../../H-录制/H05-录制通知/H05.2-只录一个直播间时点前台录制/README.md)；合并时不显示进度 → [H05.3](../../../H-录制/H05-录制通知/H05.3-录制通知显示合并进度/README.md)；从画中画回来控制条卡住 → [O02.1](../../../O-Android系统集成/O02-画中画/O02.1-画中画复验/README.md)；快捷方式头像、提示条转圈没有登记（以后走 V01 提议）；Windows、Linux（c16）→ X01、X02。
