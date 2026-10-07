# A18.1 iOS 和 iPadOS：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：已经设计好的界面（A07.1 竖屏直播间、A07.4 横屏全屏、A07.5 宽屏直播间、A07.6 弹窗、A07.8 小窗、A06.1 手机首页、A06.2 宽屏首页）在 iPhone 和 iPad 上要改的地方：安全区、灵动岛和主屏指示条、滑动返回、系统画中画和后台播放、分享面板（分享出去、分享进来）、剪贴板口令、iPad 分屏和台前调度、外接键盘 Cmd 快捷键、指针悬停；A06.3 交来的 iOS 更新方式
- 对应：[TASKS.md](../../../TASKS.md)（A18.1）；INVENTORY 和 TASK_FILES 里没有 X 的条目（v3 的 iOS 部分是原生工程和 `lib/` 里的平台分支，下面逐条列出）
- 评审页：claude.ai 私有页面（只有项目所有者能打开），每条改动可以点“满意 / 不满意 / 再想想”；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)
- 图片：项目历史上没有在苹果设备上跑过的 v3，v3 的图按 `v3.2.11` 代码推出在 iPhone、iPad 上的样子；新设计直接用 A07.7、A07.5、A06.1、A06.2 的生成脚本画出已确认（或待确认）的界面，只加平台需要的部分。画面、头像、主屏、其他应用是示意图片；系统画的部分（状态栏、灵动岛、分享面板、画中画按钮、粘贴提示、快捷键列表）是示意，以系统为准
- 尺寸：iPhone 393×852（灵动岛 126×37，距顶 11；安全区上 59、下 34；横屏左右各 59、下 21），iPad 1180×820（状态栏 24、主屏指示条区 20），分屏一半 585
- 旧编号：U.17a、T19a.1。设计确认：2026-10-01（确认记录 `62391fdd2`“U.1c-d, U.13, U.14, U.15d-e, U.17a-b confirmed”），待选 Q1～Q3 按建议 A（D-003）。下面正文里“改动（待确认）”“待评审”等是定稿前的字样，正文没有改。还没开发，任务书见 [brief.md](brief.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A18.1-01 | 安全区（灵动岛、状态栏、主屏指示条、屏幕圆角） | 所有页面 | iPhone 竖屏、横屏全屏；iPad | 竖屏、横屏（灵动岛在左或右）、全屏时状态栏隐藏 |
| A18.1-02 | 滑动返回 | 二级页面、直播间 | iPhone、iPad | 普通页面、直播间普通、直播间全屏、有面板或菜单时 |
| A18.1-03 | 系统画中画 | 画面上栏的小窗按钮；（可选）离开应用时自动 | iPhone、iPad | 播放、暂停、按钮显示、藏到边上、系统不允许 |
| A18.1-04 | 后台播放和锁屏“正在播放” | 播放中离开应用、锁屏 | 系统 | 开、关（设置“后台播放”） |
| A18.1-05 | 分享出去（系统分享面板） | 直播间菜单“分享”、卡片长按“分享” | iPhone 底部面板；iPad 贴着按钮的气泡 | 正常、失败 |
| A18.1-06 | 分享进来（共享扩展） | 其他应用的分享面板里选“纯粹直播” | 系统 | 直播间链接、分享口令、播放列表和节目单文件、不认识的内容 |
| A18.1-07 | 剪贴板口令 | 回到前台 | iPhone、iPad | 剪贴板有新文字、没有；识别成功、不是口令 |
| A18.1-08 | iPad 分屏和台前调度 | 系统 | 1/3、1/2、2/3、全屏、台前调度窗口 | 宽度跨过 600、840 时换排法 |
| A18.1-09 | 外接键盘快捷键 | 按住 ⌘ 显示列表 | iPad（iPhone 接键盘同） | — |
| A18.1-10 | 指针悬停 | 触控板、鼠标 | iPad | 悬停、按下、右键 |
| A18.1-11 | 更新（版本页、新版本对话框） | 自动检查、关于 → 版本更新 | iPhone、iPad | 有新版本（A06.3） |

## v3 在 iPhone、iPad 上的样子（按代码）

**原生工程**（`ios/Runner/Info.plist`）：iPhone 支持竖屏和左右横屏，iPad 四个方向都支持（:93-104）；没写 `UIRequiresFullScreen`，iPad 可以分屏和台前调度；`UIApplicationSupportsIndirectInputEvents`（:87）让触控板和鼠标的指针事件进到 Flutter；`CADisableMinimumFrameDurationOnPhone`（:5）放开 120 赫兹，`AppDelegate.swift:16-41` 有 `pure_live/display_mode` 通道；**没有 `UIBackgroundModes`**（后台音频）；有共享扩展 `ShareExtension`，但 `ShareViewController.swift:11-32` 是 Xcode 模板（`SLComposeServiceViewController`，点“发布”只是结束），应用里只在 Android 接收分享（`main.dart:105-106`）。

**安全区**：竖屏直播间是 `Scaffold` 的顶栏加 `SafeArea` 的正文（`live_play_content.dart:550-554`），内容从灵动岛下面开始、弹幕列表停在主屏指示条上面，和 Android 一样。横屏全屏时 `SystemUiMode.immersiveSticky` 隐藏状态栏（`player/utils/fullscreen.dart:291-297`），控制层**不避开安全区**：上栏、下栏只有 8 的边距（`video_controller_panel.dart:321`、`:1425`），锁定按钮在右边正中、离边 20（`:1009-1025`）——手机转到灵动岛在右边时，锁定按钮正好被灵动岛挡住；下栏贴着主屏指示条。

**上栏的按钮**（`video_controller_panel.dart:38-61`）：竖屏时只有纯音频（投屏只在 Android，小窗只在 Android 和 Windows）；全屏时是切换直播间（深色圆底）、时间、电量（不是 Android 就放右边）、纯音频。下栏同 Android（方向按钮 `isMobile` 也显示）。竖屏直播的竖屏全屏只在 Android 有（`live_play_content.dart:575-580`）。

**滑动返回**：`common/style/theme.dart:4-13` 只给 Android、Windows 指定了转场，iOS 用 Flutter 默认的 Cupertino 转场，带左边缘滑动返回；GetX 在 iOS 默认开启手势（`get/get_navigation/src/root/get_root.dart:92`）。直播间全屏时路由不让返回（`live_play_back_scope.dart:120-121`），左边缘滑动没有反应，只能点返回或退出全屏。

**小窗和后台**：iOS 没有小窗按钮，也没有画中画；“后台播放”开关只在 Android 显示（`modules/settings/pages/video_settings_page.dart:176`）；`audio_service` 在 iOS 上会建“正在播放”（`player/core/live_audio_service.dart:119`），但没有后台音频模式，离开应用后声音会停（按 Info.plist 推断）。

**分享**：分享出去调用 `SharePlus.instance.share(ShareParams(text: …))`（`common/utils/share_command_handler.dart:64-66`），没给弹出位置；iPhone 从底部弹系统面板，iPad 上系统面板必须贴着一个按钮弹出，share_plus 13 在没给位置时报错，v3 提示“分享失败，请重试”（`:217-220`，标题是英文 “Error”，`common/utils/snackbar_util.dart:15-23`）。

**剪贴板口令**：`DesktopWindowMixin` 用在所有平台的应用根上（`main.dart:53`），启动后和每次回到前台 1 秒后读剪贴板找分享口令（`common/global/platform/desktop_manager.dart:596-625`）。iOS 16 起，读别的应用拷贝的内容时系统每次都会问“是否允许粘贴”。

**键盘和指针**：快捷键是空格和媒体键暂停、R 刷新、↑↓ 音量、Esc（`widgets/keyboard/video_keyboard.dart:53-80`），宽屏列表 ← → 翻页（`common/base/base_page_view_extension.dart:10-15`），没有任何 Cmd 组合键，按住 ⌘ 时系统的快捷键列表是空的。悬停用的是 Flutter 的 `MouseRegion`（`video_controller_panel.dart:141-142` 等），iPad 接触控板时画面控制层、按钮提示会随指针出现。

**iPad 宽度**：首页按父组件宽度 680 分界（`home_page.dart:232`），直播间按整屏宽度 680 分栏；2/3 分屏（约 795）时直播间左右分栏、画面很小（A07.5 的 W1）。

**更新**：版本页只有 Android、Windows、macOS 的下载卡片（`modules/version/version_page.dart:43-99`），iOS 没有；新版本对话框点“更新”进版本页（`modules/about/widgets/version_dialog.dart:71-80`），iOS 上是一页只有更新日志的页面。发布里的 iOS 包是给 TrollStore 装的 IPA（`.github/workflows/build-ios-unsigned.yml`）。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| I1 | 横屏全屏的按钮不避开安全区：锁定按钮在灵动岛一侧时被挡住，返回键贴着屏幕圆角，下栏压在主屏指示条上，点下栏容易变成上滑回主屏幕 | `video_controller_panel.dart:321`、`:1425`、`:1009-1025` |
| I2 | iOS 没有小窗（画中画），也不能后台播放：没有后台音频模式，“后台播放”开关只在 Android 显示 | `video_controller_panel.dart:61`；`ios/Runner/Info.plist`；`video_settings_page.dart:176` |
| I3 | 竖屏直播的竖屏全屏只在 Android 有 | `live_play_content.dart:575-580` |
| I4 | 全屏时左边缘滑动没有反应（Android 的返回键却能退出全屏），同一条退出链两个平台不一样 | `live_play_back_scope.dart:120-121` |
| I5 | iPad 上分享直接失败：系统分享面板不知道从哪个按钮弹出，提示“分享失败，请重试”（标题还是英文 Error） | `share_command_handler.dart:64-66`、`:217-220` |
| I6 | 从别的应用分享到纯粹直播没用：弹出 Xcode 模板的发布框，点“发布”什么也不做；应用只在 Android 接收分享 | `ShareViewController.swift:11-32`；`main.dart:105-106` |
| I7 | 每次回到前台都读剪贴板，iOS 每次都弹“是否允许粘贴” | `desktop_manager.dart:596-625`；`main.dart:53` |
| I8 | 外接键盘没有 Cmd 组合键，⌘F、⌘, 这些 iPad 用户习惯的键都没用，按住 ⌘ 的快捷键列表是空的 | `video_keyboard.dart:53-80` |
| I9 | iPad 2/3 分屏、台前调度的中等宽度时直播间按 680 分栏，画面只剩一小块（A07.5 的 W1） | `live_play_content.dart` 的 680 分界 |
| I10 | iOS 没有更新入口：版本页没有 iOS 卡片，新版本对话框点“更新”进了一个没法下载的页面 | `version_page.dart:43-99`；`version_dialog.dart:71-80` |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 界面、按钮、手势和 Android 是同一套（计划书第 3 节第 7 条）；iOS 照 v3 已有的：普通页面左边缘滑动返回、弹性滚动、120 赫兹 | — |
| c2 | 修改 | 安全区：竖屏内容从灵动岛下面开始，弹幕列表可以滚到主屏指示条下面、最后一行留在它上面；横屏全屏画面照常铺满，上下栏、锁定键、录制角标放进安全区（左右各让 59，下边让 21），放不下时照 A07.4 的窄屏规则把本地弹幕输入框收成按钮；全屏时状态栏隐藏，主屏指示条几秒不碰自动变淡 | I1 |
| c3 | 修改 | 滑动返回走同一条退出链：有面板或菜单先关它，全屏时左边缘滑动退出全屏，普通时离开（选择 Q2） | I4 |
| c4 | 增强 | 画面上栏的小窗按钮在 iPhone、iPad 也显示（位置同 Android，依赖 A07.8 的 c5），进入系统画中画；画中画里只有画面，按钮是系统的（回到应用、关闭、暂停）；“离开应用时自动画中画”同 A07.8 的 J1；系统不允许时弹 A07.8 的“无法打开画中画”，“去设置”打开系统设置里本应用的页面 | I2 |
| c5 | 增强 | 后台播放：“后台播放”开关 iOS 也显示（同一个设置组件，A11.3）；打开时离开应用继续出声，锁屏和控制中心显示“正在播放” | I2 |
| c6 | 修改 | 竖屏全屏 iPhone 也有，做法同 Android（A07.2），上方两行从灵动岛下面开始 | I3 |
| c7 | 修改 | 分享出去：iPhone 从底部弹系统分享面板（同 v3）；iPad 从点的那个按钮旁边弹系统的分享气泡（菜单里点“分享”时从右上角的菜单按钮弹出） | I5 |
| c8 | 修改 | 分享进来：在别的应用的分享面板选“纯粹直播”直接打开应用，按 Android 收到分享的做法处理（直播间链接进直播间，口令弹 A06.3 的“口令导入”，播放列表和节目单文件导入，不认识的内容提示），不再弹空白的发布框 | I6 |
| c9 | 修改 | 剪贴板口令：回到前台时只查剪贴板“有没有新文字”（不读内容，系统不弹提示），有就在底部出一条提示“剪贴板里有新内容，要识别分享口令吗？[识别]”，6 秒后自动消失；点“识别”才读（系统问一次“允许粘贴”，用户在系统设置里选“允许”后不再问）（选择 Q1） | I7 |
| c10 | 增强 | 外接键盘：v3 的单键照旧；加一组 Cmd 组合键，和 macOS 菜单栏同一套（A18.2），按住 ⌘ 时系统列出（选择 Q3） | I8 |
| c11 | 修改 | iPad 分屏和台前调度只按窗口宽度换排法（计划书 5.1）：小于 600 用手机排法（底部导航、直播间上下排），600 以上侧边导航，直播间 840 以上才左右分栏；窗口变宽变窄时播放不中断；台前调度窗口左上角的系统窗口按钮（iPadOS 26 起）给它留出位置，和 macOS 同一个做法 | I9 |
| c12 | 修改 | 指针：iPad 接触控板或鼠标时悬停效果同电脑（按钮高亮、卡片变浅、显示按钮名称、控制层随指针出现），双指点按等于长按（A09.1）；指针外形是系统的 | — |
| c13 | 修改 | 更新（A06.3 交来的）：版本页加 iOS 卡片“去下载页”（打开发布页，IPA 自己用 TrollStore 等安装）；新版本对话框的主要按钮在 iOS 上是“去下载页”，不弹下载对话框 | I10 |

## 每处差异依据的苹果规范（Human Interface Guidelines）

| 差异 | 依据 |
|---|---|
| 安全区、灵动岛、屏幕圆角、主屏指示条 | 《Layout》：内容和控件放在安全区里，避开灵动岛、圆角和主屏指示条；背景和画面可以铺满 |
| 全屏隐藏状态栏、主屏指示条自动变淡 | 《Status bars》（看视频这类沉浸内容时可以临时隐藏）、《Layout》 |
| 左边缘滑动返回、全屏时滑动退出全屏 | 《Gestures》：左边缘向右滑是系统的返回手势，应用要支持并保持一致，不要另作他用 |
| 系统画中画、离开应用自动进入 | 《Playing video》：支持系统画中画，不要自己做悬浮窗口；按钮由系统提供 |
| 后台播放、锁屏和控制中心的“正在播放” | 《Playing audio》：离开应用继续播放的音频要接入“正在播放” |
| iPhone 底部分享面板、iPad 贴着按钮的分享气泡、共享扩展 | 《Activity views》：用系统的分享面板；iPad 上以气泡从触发它的控件弹出；共享扩展要快、少打扰 |
| 剪贴板只在用户点了才读 | 《Privacy》：只在用户需要时访问个人数据；UIKit `UIPasteboard` 文档：`hasStrings` 等查询不触发粘贴提示 |
| iPad 分屏、台前调度按宽度换排法 | 《Multitasking》《Layout》：任何窗口大小都要好用，尺寸变化时平滑过渡 |
| 台前调度窗口左上角留位置 | 《Windows》（iPadOS）：窗口按钮在窗口左上角，内容不要被它挡住 |
| Cmd 快捷键、按住 ⌘ 显示列表 | 《Keyboards》：支持标准快捷键（⌘, 设置、⌘F 查找等），给命令起名让系统能列出来 |
| 指针悬停 | 《Pointing devices》：可交互的元素在指针悬停时有反馈 |
| iOS 不能在应用里安装 | 系统限制（应用不能自己安装安装包），不是 HIG 条目 |

## 按钮的作用和用法

[v4-iphone-room-n.jpg](v4-iphone-room-n.jpg)（竖屏）：

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 左边缘 | 从屏幕左边缘往右滑 = 返回（照 v3 的系统手势）；有面板、菜单时先关掉它们 |
| 2 | 返回 | 同 v3 |
| 3 | 纯音频 | 同 v3 |
| 4 | 画中画（新） | 进入系统画中画，画面浮在其他应用上 |
| 5 | 四宫格菜单 | 同 A07.6；iOS 上没有“投屏”（投屏只有 Android）；“分享”弹系统分享面板 |
| 6 | 全屏 | 进入横屏全屏 |
| 7 | 方向 | 同 v3（自动、横屏、竖屏） |

[v4-iphone-full-n.jpg](v4-iphone-full-n.jpg)（横屏全屏，其他按钮同 A07.4）：

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回（挪进安全区） | 退出全屏 |
| 2 | 左边缘滑动（新） | 退出全屏，和 Android 返回键一样；左半边上下滑仍是调亮度 |
| 3 | 画中画（新） | 同竖屏 |
| 4 | 本地弹幕（收成按钮） | 安全区里放不下输入框，收成星形按钮，点开再输入（A07.4 窄屏规则） |
| 5 | 锁定（挪进安全区） | 同 v3，不再落在灵动岛下面 |
| 6 | 退出全屏 | 同 v3 |
| — | 主屏指示条 | 全屏时几秒不碰自动变淡（系统做） |

其他：剪贴板提示条的“识别”读剪贴板并识别口令，✕ 关掉；画中画里的按钮是系统的（左上回到应用、右上关闭即停止播放、中间暂停，直播没有快进快退）；iPad 键盘见 [v4-ipad-keys.jpg](v4-ipad-keys.jpg)。

快捷键（iPad 和 macOS 同一套，Windows、Linux 的 Ctrl 版本由 A16.1 定）：⌘, 设置、⌘F 搜索直播、⌘L 链接解析、⌘Y 历史记录、⌘1–⌘4 关注 / 热门 / 分区 / 录制中心、⌘[ 返回、⌘R 刷新、⌃⌘F 全屏；v3 的空格、R、↑↓、← →、Esc 照旧。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 对照基准：这一页的新设计都是 Android 的界面，只改苹果平台需要的地方 |
| 宽屏（iPad） | 同 Android 平板（A06.2、A07.5）：状态栏下开始，主屏指示条上面留空；分屏、台前调度按窗口宽度换排法；键盘、指针同电脑 |
| 电视 | 不适用 |
| macOS | 见 A18.2 |
| iPhone | 本页：安全区、滑动返回、画中画、分享、剪贴板 |

## 待选

- Q1 剪贴板口令：建议 A 回到前台只查有没有新文字，出提示条，点了才读；B 照 v3 每次回到前台自动读（每次系统都问）。
- Q2 全屏时左边缘滑动：建议 A 退出全屏（和 Android 返回键一致）；B 照 v3 不响应，只能点返回或退出全屏按钮。
- Q3 Cmd 快捷键：建议 A 加一组，iPad 和 macOS 同一套；B 只保留 v3 的单键。

## 拿不准的地方

1. 安全区数值按 iPhone 15 / 16（393×852）的公开数值画（竖屏上 59、下 34；横屏左右 59、下 21），没有真机核对；横屏时灵动岛在哪一边取决于转向，左右安全区都一样。
2. mpv 的画面能不能交给系统画中画（`AVSampleBufferDisplayLayer`），要有 Mac 才能验证（A07.8 已记）。
3. iPad 上 share_plus 不给位置时是报错还是不弹，按 share_plus 13 的说明推断为报错。
4. v3 在 iOS 上离开应用后是否立刻停播，按 Info.plist 没有后台音频推断。
5. iPadOS 26 台前调度和窗口模式下左上角的窗口按钮会不会盖住应用内容、Flutter 能不能拿到它的位置（UIKit 有按角落适配的布局区域，Flutter 还没有），要在真机上看；iPadOS 26 的分屏方式也变了，图里按两个应用各占一半画。
6. 按住 ⌘ 显示快捷键列表、iPadOS 26 的菜单栏都要原生的 `UIKeyCommand` / `UIMenuBuilder`，Flutter 不会自动生成，要在 Runner 里写一层。
7. `hasStrings`、`changeCount` 不触发粘贴提示是苹果文档的说法，没在真机核对；系统粘贴提示的中文措辞按示意画。
8. 共享扩展打开主应用用的是 share_handler 插件的做法（扩展里转到应用的 URL scheme，v3 的 Info.plist 已有 `ShareMedia-…`），苹果没有正式支持，以后的系统版本可能要换做法。

## 交给其他任务的

- A11.3：“后台播放”开关 iOS 也显示（c5）。
- R02.1、A11.4：“界面刷新率”v3 只在 Android、Windows 显示（`general_settings_page.dart:24`），iOS 原生已经有 `pure_live/display_mode`，iPhone Pro 上也应显示。
- A07.2：iPhone 也有竖屏全屏（c6，A07.2 已写“iPhone 同 Android 手机”）。
- A07.1、A07.4、A07.5：iOS 上栏显示小窗按钮、不显示投屏；菜单里没有“投屏”（随 A07.8 的 c5）。
- A06.3：iOS 的更新按钮是“去下载页”（c13，本页已定，A06.3 改说明即可）。
- A14.1：iOS 锁屏和控制中心的“正在播放”、启动画面（v3 是白底加 `LaunchImage`，`LaunchScreen.storyboard`）、画中画里系统画的按钮。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 安全区、滑动返回、画中画和后台播放、分享、剪贴板、iPad 分屏台前调度键盘指针、更新；三个选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比 iPhone 竖屏直播间](page/02-对比-iPhone-竖屏直播间.jpg)
- [对比 iPhone 横屏全屏](page/03-对比-iPhone-横屏全屏.jpg)
- [首页 画中画](page/04-首页-画中画.jpg)
- [对比 分享](page/05-对比-分享.jpg)
- [对比 剪贴板口令](page/06-对比-剪贴板口令.jpg)
- [iPad 宽屏 分屏 台前调度 键盘和指针](page/07-iPad-宽屏-分屏-台前调度-键盘和指针.jpg)
- [v3 的问题](page/08-v3-的问题.jpg)
- [改了什么](page/09-改了什么.jpg)
- [每处差异依据的苹果规范](page/10-每处差异依据的苹果规范.jpg)
- [每个按钮是干什么的 怎么用](page/11-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/12-各客户端.jpg)
- [需要你选的](page/13-需要你选的.jpg)
- [性能要点](page/14-性能要点.jpg)
- [拿不准的地方 交给其他任务的](page/15-拿不准的地方-交给其他任务的.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-iphone-room.jpg](v3-iphone-room.jpg)、[v4-iphone-room.jpg](v4-iphone-room.jpg)、[v4-iphone-room-n.jpg](v4-iphone-room-n.jpg) | iPhone 竖屏直播间：v3 / 新设计 / 按钮编号 |
| [v3-iphone-full.jpg](v3-iphone-full.jpg)、[v4-iphone-full.jpg](v4-iphone-full.jpg)、[v4-iphone-full-n.jpg](v4-iphone-full-n.jpg) | iPhone 横屏全屏（灵动岛在右）：v3 / 新设计 / 按钮编号 |
| [v4-iphone-safe.jpg](v4-iphone-safe.jpg) | 安全区示意 |
| [v4-iphone-home.jpg](v4-iphone-home.jpg) | iPhone 首页 |
| [v4-iphone-panel.jpg](v4-iphone-panel.jpg) | iPhone 横屏录制面板（右侧面板让出安全区） |
| [v4-iphone-pip.jpg](v4-iphone-pip.jpg) | 系统画中画 |
| [v4-iphone-share.jpg](v4-iphone-share.jpg) | 分享出去：系统分享面板 |
| [v3-iphone-share-in.jpg](v3-iphone-share-in.jpg)、[v4-iphone-share-in.jpg](v4-iphone-share-in.jpg) | 分享进来：v3 的模板发布框 / 新设计直接打开应用 |
| [v3-iphone-paste.jpg](v3-iphone-paste.jpg)、[v4-iphone-paste.jpg](v4-iphone-paste.jpg) | 剪贴板口令：v3 的系统粘贴提示 / 新设计的提示条 |
| [v4-ipad-home.jpg](v4-ipad-home.jpg) | iPad 首页，指针悬停在卡片上 |
| [v4-ipad-room.jpg](v4-ipad-room.jpg) | iPad 直播间（左右分栏） |
| [v4-ipad-split.jpg](v4-ipad-split.jpg) | iPad 分屏一半（585 宽，手机排法） |
| [v4-ipad-stage.jpg](v4-ipad-stage.jpg) | iPad 台前调度窗口（760×600，侧边导航，左上窗口按钮） |
| [v4-ipad-keys.jpg](v4-ipad-keys.jpg) | iPad 按住 ⌘ 的快捷键列表 |
| [v3-ipad-share.jpg](v3-ipad-share.jpg)、[v4-ipad-share.jpg](v4-ipad-share.jpg) | iPad 分享：v3 失败 / 新设计的分享气泡 |

## 实现和验证

- 实现：**还没开发**（登记表“已确认”，第三档，没有阶段记录）。按 D-004，苹果平台排在所有客户端最后，[specs/UI.md](../../../specs/UI.md) 第 5.6 节“暂时只设计、不构建”。开发的要求、阶段、测试和真机步骤都在 [brief.md](brief.md)；前提是苹果平台的工程（[X04](../../../X-多端客户端/X04-iOS和iPadOS/README.md)、[X05](../../../X-多端客户端/X05-macOS/README.md)）。
- 现在的代码：4.x 没有 `ios/` 工程（X04.1 未开始）。代码里已经有的 iOS 分支：“后台播放”iOS 也显示（`apps/pure_live/lib/features/settings/settings_catalog.dart:790`，即本页 c5 交给 A11.3 的那一半）、竖屏全屏 iOS 也有（`features/live_play/player/player_controls.dart:70` 的 `RoomPlatform.mobile`，c6）、弹性滚动（`packages/live_ui/lib/src/widgets/scrolling.dart:18`）。v3 的几个问题 4.x 照样有：iOS 回到前台直接读剪贴板（`app/intake/clipboard_rooms.dart:93`，只有 Android 有 `stamp`）、iPad 分享不给弹出位置（`platform/plugins.dart:95`）、直播间快捷键没有 Cmd 组合（`features/live_play/live_play_page.dart:737-750`）、全屏时不让返回（`:731` 的 `PopScope`）。
- 开发前要知道的：本机没有 Mac，原生部分（系统画中画、后台音频、共享扩展、`UIKeyCommand`）只能在 Mac 上做和验；mpv 画面能否交给系统画中画没核对；“交给其他任务的”里 R02.1 / A11.4 的 iPhone Pro 刷新率、A14.1 的苹果系统界面还没有任务。
- 验证：没有自动测试，也没有设备结果（项目里没有苹果设备）。
- 留下的问题和去向：见[子分类页](../README.md)“已知问题”。
