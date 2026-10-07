# A18 苹果平台界面

iOS、iPadOS、macOS 的差异设计。

一句话：同一套界面放到 iPhone、iPad 和 Mac 上时要改的地方（安全区、滑动返回、系统画中画、分享面板、剪贴板、iPad 分屏和键盘指针；Mac 的窗口按钮、菜单栏、Cmd 快捷键、关窗和退出、菜单栏图标、全屏空间）。两份设计都已确认，按客户端顺序排在最后，还没开发——4.x 现在连 iOS、macOS 的工程都没有。

## 范围

- 包括：
  - [A18.1](A18.1-iOS和iPadOS差异设计/README.md) iOS 和 iPadOS：A07.1、A07.4、A07.5、A07.6、A07.8、A06.1、A06.2 这些已设计的界面在 iPhone、iPad 上的差异（c1～c13），以及 A06.3 交来的 iOS 更新方式。
  - [A18.2](A18.2-macOS差异设计/README.md) macOS：A06.2、A07.5、A07.4、A07.8 的宽屏界面放进 Mac 窗口的差异（c1～c10），以及 A06.3 交来的 macOS 更新方式。
  - 只管“长什么样、怎么操作”：平台分支的界面代码（`defaultTargetPlatform`、`Platform.isIOS` / `isMacOS` 的界面分支）、苹果平台上的快捷键和菜单定义。
- 不包括（归哪里）：
  - 苹果平台的工程（`ios/`、`macos/` Runner）、构建、签名、权限文件、发布包：[X04 iOS和iPadOS](../../X-多端客户端/X04-iOS和iPadOS/README.md)（X04.1 苹果平台的构建和签名，未开始）、[X05 macOS](../../X-多端客户端/X05-macOS/README.md)（还没有任务）。
  - 系统画中画、后台音频、共享扩展这些原生能力的实现（Swift、`Info.plist`）：X04；它们在界面上的样子在 A18.1。系统界面（锁屏“正在播放”、启动画面、程序坞和菜单栏图标的正式图形）：[A14](../A14-系统界面/README.md)。
  - Windows、Linux 的标题栏、托盘、关闭时的选择：[A16.1](../A16-桌面界面/A16.1-桌面窗口/README.md)（A18.2 的快捷键和托盘菜单和它用同一组命令）。
  - 宽度分档、分屏和折叠屏的通用规则：[A04](../A04-尺寸和适配/README.md)；键盘焦点和读屏：[A05](../A05-无障碍/README.md)。
  - 电视：苹果平台没有电视版（不做 Apple TV，A17.4“各客户端”）。

## 现状：做到哪、怎么工作的

- **用户看得到的**：没有。4.x 只发布了 Android（2026-10-02 4.0.0），Windows 有代码没发布；`apps/pure_live/` 下只有 `android/`、`windows/` 两个原生工程，**没有 `ios/` 和 `macos/`**（3.x 有，`git ls-tree -d v3.2.11` 里有 `ios`、`macos`）。所以 A18 的设计目前没法在任何设备上看到。
- **代码里已经为苹果平台留的分支**（都是跟着各界面任务顺手写的，没在苹果设备上跑过）：
  - 滚动：`packages/live_ui/lib/src/widgets/scrolling.dart:18`、`:26`，iOS、macOS 用 `BouncingScrollPhysics`（弹性滚动，A18.1 c1、A18.2 c1 的“保留”）。
  - 直播间平台能力：`apps/pure_live/lib/features/live_play/player/player_controls.dart:55` 的 `RoomPlatform`：`android`（投屏、方向、系统画中画）、`mobile`（`:70`，Android 和 iOS：方向、手势、竖屏全屏，即 A18.1 c6 已经包括 iOS）、`windows`；上栏的小窗按钮在 iOS 上是否显示随 A07.8 c5。
  - 设置：`apps/pure_live/lib/features/settings/settings_model.dart:191`（`isIOS`）、`:197`（`isMobile`）、`:200`（`isOtherDesktop`：Linux、macOS）；“后台播放”`settings_catalog.dart:780-790` 已经是 `when: _mobile`（注释“iOS too (U.17a)”，即 A18.1 c5 的设置那一半已做）；动态取色 iOS 不显示（`appearance_pages.dart:119`）；mpv 驱动的 iOS、macOS 选项（`settings_editors.dart:94-115`）。
  - 剪贴板口令：`apps/pure_live/lib/app/intake/clipboard_rooms.dart` 的 `ClipboardRoomWatcher`，只有 Android 传 `stamp`（剪贴板变了才读，`:41`、`:93`）；iOS 没有，回到前台会直接读（A18.1 c9 要改成先查 `hasStrings` 再提示）。
  - 分享：`apps/pure_live/lib/platform/plugins.dart:95` 的 `SharePlus.instance.share(ShareParams(text: …))`，没传 `sharePositionOrigin`（A18.1 c7：iPad 上必须给位置）；`shared/rooms/room_menu.dart:247` 只有 Android、iOS 弹分享面板。
  - 更新：`features/version/update_feed.dart:308-309` 认得 `macos`、`ios`；版本页和新版本对话框没有 iOS 的“去下载页”（A18.1 c13）、macOS 的“在访达中显示”（A18.2 c10）。
  - 桌面外壳：`apps/pure_live/lib/app/desktop/desktop_window.dart:257` 的 `DesktopShell.supported` 只有 Windows（注释写“macOS is U.17b”）；`app/desktop/mini_window.dart:166-199` 在 macOS 上隐藏标题栏（桌面小窗）；`features/settings/settings_editors.dart:779` 在 macOS 上 `exit(0)`。
  - 本地互动 emoji：`features/live_play/local_interaction/local_interaction_scope.dart:58` 的 `_bundledEmoji`，iOS、macOS 用系统 emoji。
  - 快捷键：直播间 `features/live_play/live_play_page.dart:737-750`（Esc、F、空格、↑↓、R、媒体键）没有 Cmd 组合；Cookie 编辑器 `features/account/cookie_editor.dart:400-401` 有 Ctrl+S 和 ⌘S 两份。
- **完成度**：A18.1、A18.2 设计 2026-10-01 确认（确认记录 `62391fdd2`“U.1c-d, U.13, U.14, U.15d-e, U.17a-b confirmed”；待选 Q1～Q3、K1～K4 按建议 A，D-003）；没有开发。“交给其他任务的”里，A11.3 的“后台播放 iOS 也显示”已经做了（见上）；其余（A06.3 改说明、A11.4 登录时打开、A14.1 苹果的系统界面、A12.6 的 macOS 权限文件、R02.1 iPhone Pro 的刷新率）要在苹果客户端阶段再核对。

## 代码地图

本子分类没有自己的目录（登记表的代码是“—”）；开发时改的是各界面的平台分支。现在和苹果平台有关的界面代码：

| 文件 | 职责 | 和 A18 的关系 |
|---|---|---|
| `packages/live_ui/lib/src/widgets/scrolling.dart` | 按平台选滚动物理：iOS、macOS 弹性（`:18`、`:26`） | A18.1 c1、A18.2 c1 保留 |
| `apps/pure_live/lib/features/live_play/player/player_controls.dart` | `RoomPlatform`（`:55`）：哪个平台有投屏、方向、小窗、音量条、窗口内全屏；上下栏 `PlayerTopBar`（`:260`）、`SafeArea`（`:334`、`:716`、`:785`） | A18.1 c2（横屏全屏让出安全区）、c4（iOS 小窗按钮）、c6；A18.2 c9（Mac 同 Windows：小窗、音量条、窗口内全屏） |
| `apps/pure_live/lib/features/live_play/live_play_page.dart` | 直播间返回链 `PopScope`（`:731`）、快捷键（`:737-750`） | A18.1 c3（全屏时左边缘滑动退出全屏）、c10；A18.2 c4、c5 |
| `apps/pure_live/lib/features/settings/settings_model.dart`、`settings_catalog.dart`、`settings_editors.dart`、`appearance_pages.dart` | 设置按平台显示（`isIOS` `:191` 等）；后台播放 `when: _mobile`（`settings_catalog.dart:790`）；mpv 驱动选项（`settings_editors.dart:94-115`） | A18.1 c5；A18.2（开机启动叫“登录时打开”、Mac 不显示“关闭窗口时”） |
| `apps/pure_live/lib/app/intake/clipboard_rooms.dart` | `ClipboardRoomWatcher`：回到前台识别分享口令；`stamp` 只在 Android（`:41`、`:61`、`:93`） | A18.1 c9 |
| `apps/pure_live/lib/platform/plugins.dart` | 平台插件接线：二维码相机和日志分享只在 Android、iOS（`:42`、`:54`），分享文字 `:95`、分享文件 `:59` | A18.1 c7（iPad 气泡位置）、c8（分享进来） |
| `apps/pure_live/lib/features/version/update_feed.dart`、`version_page.dart`、`update_prompt.dart`、`update_download.dart` | 平台包名（`update_feed.dart:308-309`）、版本页、新版本和下载对话框 | A18.1 c13（iOS 去下载页）；A18.2 c10（在访达中显示） |
| `apps/pure_live/lib/app/desktop/desktop_window.dart`、`title_bar.dart`、`tray.dart`、`close_dialog.dart`、`mini_window.dart` | 桌面外壳：只在 Windows 启用（`desktop_window.dart:257`）；自绘标题栏 `DesktopTitleBar`（`title_bar.dart:34`）、托盘 `DesktopTray`（`tray.dart:49`）、关闭对话框 `WindowCloser`（`close_dialog.dart:48`）、桌面小窗在 macOS 隐藏标题栏（`mini_window.dart:166-199`） | A18.2 c2（系统窗口按钮，不画自绘标题栏）、c6（关窗不退出）、c7（菜单栏图标）、c9 |
| `apps/pure_live/lib/features/live_play/local_interaction/local_interaction_scope.dart` | `_bundledEmoji`（`:58`）：iOS、macOS 用系统 emoji | 已经按平台区分 |
| `apps/pure_live/lib/shared/rooms/room_menu.dart`、`room_cards.dart` | 分享面板只在 Android、iOS（`room_menu.dart:247`）；`isPhoneDevice`（`room_cards.dart:123`） | A18.1 c7 |

测试：没有专门的苹果平台测试。可以在 Linux 上用 `debugDefaultTargetPlatformOverride = TargetPlatform.iOS / macOS` 跑布局和分支测试（现有的 `apps/pure_live/test/` 里按平台切换的用例很少）；原生部分（画中画、共享扩展、菜单栏）只能在 Mac 上验证。

## 3.x 基线

- 3.x 有 `ios/` 和 `macos/` 工程（`git ls-tree -r --name-only v3.2.11 -- ios macos`）：
  - iOS：`ios/Runner/Info.plist`（`:5` `CADisableMinimumFrameDurationOnPhone` 放开 120 Hz；`:50` 共享扩展的 `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` URL scheme；**没有** `UIBackgroundModes`、没有 `UIRequiresFullScreen`）、`AppDelegate.swift`（`pure_live/display_mode` 通道）、`SceneDelegate.swift`、`ShareExtension/ShareViewController.swift`（Xcode 模板，点“发布”什么也不做）、`LaunchScreen.storyboard`。发布的是给 TrollStore 装的未签名 IPA（`.github/workflows/build-ios-unsigned.yml`）。
  - macOS：`macos/Runner/AppDelegate.swift`（最后一个窗口关了就退出）、`Base.lproj/MainMenu.xib`（Flutter 模板的英文菜单）、`Configs/AppInfo.xcconfig`、`Release.entitlements`（只有 `com.apple.security.network.client`，没有 `network.server`，设备同步在正式版收不到连接，A18.2 交给 A12.6 的问题）。
  - `lib/` 里的平台分支：A18.1、A18.2 的 README“v3 在 iPhone、iPad 上的样子”“v3 在 macOS 上的样子”逐条写了文件:行（`video_controller_panel.dart:38-61`、`live_play_back_scope.dart:120-121`、`share_command_handler.dart:64-66`、`desktop_manager.dart:57-137`、`:596-625`、`plugins/utils.dart:242-385` 等）。
- 3.x 在苹果设备上的问题：A18.1 的 I1～I10、A18.2 的 M1～M9（都是按代码推断，项目历史上没人在苹果设备上跑过 v3）。
- 要保留的：界面、按钮、手势和 Android / Windows 是同一套（[specs/UI.md](../../specs/UI.md) 第 3 节第 7 条）；iOS 的左边缘滑动返回、弹性滚动、120 Hz；v3 的单键快捷键；Mac 上分享照 v3 复制口令。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 4.x 没有 `ios/`、`macos/` 工程，苹果平台根本构建不了 | `apps/pure_live/`（只有 `android/`、`windows/`） | A18 的任何开发都没法验证 | X04.1（iOS）；macOS 在 X05 还没有任务，要先登记（写进报告） |
| 本机没有 Mac，WSL 和 Linux 上不能构建 iOS、macOS | — | 只能做 Dart 层的平台分支和测试，原生部分（画中画、共享扩展、`UIKeyCommand`、菜单栏、窗口按钮位置）要有 Mac 的人做 | 各任务书的第一阶段是前提检查；[specs/UI.md](../../specs/UI.md) 第 5.6 节“暂时只设计、不构建” |
| iOS 回到前台会直接读剪贴板（没有 `stamp`），iOS 16 起每次弹“是否允许粘贴” | `app/intake/clipboard_rooms.dart:93` | 苹果平台上打扰用户（v3 的 I7 在 4.x 还在） | A18.1 c9 |
| iPad 分享不给弹出位置 | `platform/plugins.dart:95` | iPad 上分享会失败（v3 的 I5 在 4.x 还在） | A18.1 c7 |
| 桌面外壳只在 Windows 启用，macOS 会走手机和 Windows 的混合分支（没有自绘标题栏，但窗口按钮压在内容上） | `app/desktop/desktop_window.dart:257` | Mac 上三个窗口按钮压内容（v3 的 M1） | A18.2 c2 |
| A18.1、A18.2 的设计正文里还有“改动（待确认）”“待评审”等定稿前的字样；A18.2 写“A16.1 还没有设计”（现在 A16.1 已完成） | 两个任务 README | 读起来像没确认 | 设计正文不改；确认和后来的变化写在各任务“实现和验证”和任务书里 |
| “交给其他任务的”只有一部分落实：A11.3 后台播放 iOS 已显示；A12.6 的 macOS `network.server`、A11.4 的“登录时打开”、R02.1 iPhone Pro 刷新率、A14.1 苹果系统界面都没有登记任务 | 两个任务 README 末尾 | 苹果客户端阶段容易漏 | 写进报告，建议苹果客户端开工时并入 X04.1 / X05 的任务或开新任务 |

## 相关决定和规范

- D-003：Q1～Q3（剪贴板先查再读、全屏左边缘滑动退出全屏、加 Cmd 快捷键）、K1～K4（关窗不退出、菜单栏图标默认显示可关、完整菜单栏、统一标题栏）都按建议 A。
- D-004：客户端顺序 Android → Windows → 电视 → Linux → 苹果平台；当前只做 Android，A18 两个任务第三档、排在最后。
- D-005：菜单栏、提示都中文（v3 的 macOS 菜单全是英文，A18.2 c4 改）。
- D-018：设置键名和含义不变；苹果平台只是改设置的显示条件（例如“后台播放”iOS 也显示）。
- [specs/UI.md](../../specs/UI.md)：第 5.6 节（苹果平台：没有返回键靠左边缘滑动、避开灵动岛和指示条、系统画中画、iPad 按宽度分档、Mac 窗口按钮在左上、菜单栏、系统全屏；暂时只设计不构建）；第 5.1 节（宽度分档 600、840）；第 3 节第 7 条（同一套界面）；第 9.3 节（不用模糊，A18.2 c3 去掉毛玻璃）。
- 两个任务 README 的“每处差异依据的苹果规范”表：每条改动对应的 Human Interface Guidelines 章节。

## 测试和验证

- 自动测试：没有。开发时在 Linux 上用 `debugDefaultTargetPlatformOverride` 跑 Dart 层：iOS 横屏全屏的上下栏在 `MediaQuery.padding`（左右 59、下 21）里；全屏时返回先退出全屏；iPad 宽度 585 / 795 / 1180 的排法；Mac 的菜单定义（`PlatformMenuBar` 的项和快捷键）和 Windows 的命令同一组；剪贴板只在点“识别”后读。
- 真机：要 iPhone（带灵动岛）、iPad（台前调度、外接键盘和触控板）、Mac；本机都没有。S02 的真机清单目前只有 K90；苹果设备的检查项在各任务书的“真机验证”一节。

## 路线

按 D-004 排在所有客户端最后：

1. 先有工程：X04.1（iOS 的工程、构建、签名，照 3.x 的 `ios/` 重建）；macOS 先在 X05 登记一个“工程和构建”的任务（现在没有任务）。没有工程，A18 的开发停在 Dart 层。
2. A18.1 iOS 和 iPadOS：先做纯 Dart 能做、Android 也受益的部分（横屏全屏安全区、全屏时返回链、iPad 宽度分档、剪贴板先查再读、分享气泡位置），再做要原生的部分（系统画中画、后台音频、共享扩展、`UIKeyCommand`）。
3. A18.2 macOS：标题栏和窗口按钮、中文菜单栏（`PlatformMenuBar`）、Cmd 快捷键（和 A18.1 c10、A16.1 同一组命令）、关窗不退出、菜单栏图标、全屏空间、更新下载完“在访达中显示”。
4. 收尾时核对两个 README 的“交给其他任务的”逐条落实。

新想法写进 V01 提议，不直接加任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：—
- 进度：`███████░░░░░░░░░░░░░` 35%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A18.1 | iOS 和 iPadOS 差异设计 | 界面 | 已确认 | — | — | [设计或说明](A18.1-iOS和iPadOS差异设计/README.md)、[评审页](A18.1-iOS和iPadOS差异设计/page/01-说明.jpg) |
| A18.2 | macOS 差异设计 | 界面 | 已确认 | — | — | [设计或说明](A18.2-macOS差异设计/README.md)、[评审页](A18.2-macOS差异设计/page/01-说明.jpg) |

## 还没完成的

- **A18.1 iOS 和 iPadOS 差异设计**（已确认，第三档，规模 中）
- **A18.2 macOS 差异设计**（已确认，第三档，规模 中）

<!-- docs:生成结束 -->
