# A18.1 iOS 和 iPadOS 差异：任务书

## 背景

- 来源：界面重做的苹果平台部分（旧编号 U.17a、T19a.1）。设计第 1 版 2026-10-01 评审确认（确认记录 `62391fdd2`“U.1c-d, U.13, U.14, U.15d-e, U.17a-b confirmed”），待选按建议 A（D-003）：剪贴板口令回到前台只查有没有新文字、出提示条、点了才读（Q1）；全屏时左边缘滑动退出全屏（Q2）；加一组 Cmd 快捷键、和 macOS 同一套（Q3）。设计正文在本文件夹 [README.md](README.md)（界面清点表 A18.1-01～11、I1～I10、c1～c13、HIG 依据、按钮用法、快捷键、“拿不准的地方”“交给其他任务的”），评审页导出在 `page/`。
- 现象：4.x 还没有 iOS 客户端——`apps/pure_live/` 下没有 `ios/` 工程，所以 iPhone、iPad 上什么都看不到。3.x 在 iPhone、iPad 上的问题（设计 README 的 I1～I10，按代码推断）里，和 Dart 代码有关的几条 4.x 照样有：横屏全屏的上下栏是否让出灵动岛和指示条、全屏时左边缘滑动、iPad 分享不给弹出位置、iOS 回到前台直接读剪贴板、没有 Cmd 快捷键、iOS 没有更新入口。
- 为什么现在做：第三档，客户端顺序的最后一个（D-004：Android → Windows → 电视 → Linux → 苹果平台）。**本机没有 Mac**（[specs/UI.md](../../../specs/UI.md) 第 5.6 节“暂时只设计、不构建”），开工要等有 Mac 和 X04.1。
- 已经做过的：设计中“交给其他任务的”有一条已落实：“后台播放”开关 iOS 也显示（`apps/pure_live/lib/features/settings/settings_catalog.dart:790` `when: _mobile`，注释“iOS too (U.17a)”）。竖屏全屏 iPhone 也有（`features/live_play/player/player_controls.dart:70` 的 `RoomPlatform.mobile` 包括 iOS，A07.2）。
- 半成品：没有。

## 目标和验收

1. （前提）有 iOS 工程（X04.1），在 iPhone 和 iPad 上能装、能起播一个直播间。
2. （c2）安全区：竖屏内容从灵动岛下面开始，弹幕列表可以滚到主屏指示条下面、最后一行停在它上面；横屏全屏画面铺满，上下栏、锁定键、录制角标都在安全区里（左右各让 59、下让 21），放不下时本地弹幕输入框收成按钮（A07.4 的窄屏规则）；全屏时状态栏隐藏。
3. （c3）滑动返回走同一条退出链：有面板或菜单先关它；全屏时左边缘滑动退出全屏；普通时离开直播间；普通页面左边缘滑动返回照旧。
4. （c4、c5）画面上栏的小窗按钮在 iPhone、iPad 也显示，进入系统画中画（按钮是系统的）；“离开应用时自动画中画”同 A07.8；系统不允许时弹 A07.8 的“无法打开画中画”，“去设置”打开系统设置里本应用的页面。“后台播放”打开时离开应用继续出声，锁屏和控制中心有“正在播放”。
5. （c6）竖屏全屏 iPhone 也有，上方两行从灵动岛下面开始。
6. （c7、c8）分享出去：iPhone 底部系统分享面板；iPad 从点的那个按钮旁边弹分享气泡（菜单里点“分享”时从菜单按钮弹）。分享进来：别的应用的分享面板选“纯粹直播”直接打开应用，按 Android 的处理（直播间链接进房、口令弹 A06.3 的“口令导入”、播放列表和节目单文件导入、不认识的提示），不再弹空白发布框。
7. （c9，Q1 A）回到前台只查剪贴板有没有新文字（`hasStrings` / `changeCount`，不读内容、系统不弹提示），有就底部提示“剪贴板里有新内容，要识别分享口令吗？[识别]”，6 秒后消失；点“识别”才读。
8. （c10，Q3 A）外接键盘：v3 的单键照旧；加 Cmd 组合键（⌘, 设置、⌘F 搜索直播、⌘L 链接解析、⌘Y 历史记录、⌘1～⌘4 关注 / 热门 / 分区 / 录制中心、⌘[ 返回、⌘R 刷新、⌃⌘F 全屏），按住 ⌘ 时系统列出；和 A18.2 同一组命令。
9. （c11）iPad 分屏和台前调度只按窗口宽度换排法（小于 600 手机排法、600 以上侧边导航、直播间 840 以上左右分栏）；窗口变宽变窄时播放不中断；台前调度窗口左上的系统窗口按钮让出位置。
10. （c12）iPad 接触控板或鼠标时悬停效果同电脑，双指点按等于长按。
11. （c13）版本页有 iOS 卡片“去下载页”；新版本对话框的主要按钮在 iOS 上是“去下载页”，不弹下载对话框。
12. Android 和 Windows 的界面一点不变；`flutter test` 全部通过。

## 现状（读代码得出，写文件:行）

- 工程：`apps/pure_live/` 只有 `android/`、`windows/`；3.x 的 `ios/`（`Runner/Info.plist`、`AppDelegate.swift`、`SceneDelegate.swift`、`ShareExtension/`、`LaunchScreen.storyboard`）在 4.x 没有。X04.1（[X04](../../../X-多端客户端/X04-iOS和iPadOS/README.md)）未开始。
- 直播间：`apps/pure_live/lib/features/live_play/player/player_controls.dart`：`RoomPlatform`（`:55`：`android` 投屏、方向、系统画中画；`mobile` `:70` 含 iOS）；上栏 `PlayerTopBar`（`:260`）、`SafeArea`（`:334` `bottom: false`、`:716`、`:785`）——横屏全屏时左右是否让出安全区要在 iPhone 横屏（灵动岛在左或右）的 `MediaQuery.padding` 下核对。返回链 `features/live_play/live_play_page.dart:731` 的 `PopScope(canPop: _poppable…)`，全屏时不让 pop（左边缘滑动没反应，即 I4）。快捷键 `:737-750`（Esc、F、空格、↑↓、R、媒体键），没有 Cmd 组合。小窗和画中画 `features/live_play/mini/`（`room_mini_window.dart:136`、`:165`、`:316` 的 `showPipDisabledToast`）。
- 剪贴板：`apps/pure_live/lib/app/intake/clipboard_rooms.dart` 的 `ClipboardRoomWatcher`：只有 Android 传 `stamp`（`:41`、`:61`），回到前台 `:93` 起读；iOS 没有 `stamp`，直接 `Clipboard.getData`（`:15`）。设置 `detectClipboardRooms`（`settings_catalog.dart:1457`）。
- 分享：`apps/pure_live/lib/platform/plugins.dart:95` 的 `SharePlus.instance.share(ShareParams(text: text))`（没有 `sharePositionOrigin`）、`:59` 分享文件；`shared/rooms/room_menu.dart:247` 只在 Android、iOS 弹分享面板。分享进来：Android 的 `app/intake/share_intake.dart`（`ShareIntake`，O03.2）。
- 更新：`features/version/update_feed.dart:309` 认 `ios`；`features/version/version_page.dart`、`update_prompt.dart`（`NewVersionDialog` `:108`）、`update_download.dart`（`showUpdateDownload` `:74`）没有 iOS 分支。
- 宽度分档：A04 定的 600、840（`packages/live_ui/lib/src/theme/grid_columns.dart` 和各页面）；iPad 分屏时窗口变宽变窄的行为没有测过。
- 已为 iOS 写的分支：`settings_model.dart:191`（`isIOS`）、`:197`（`isMobile`）；`appearance_pages.dart:119`（iOS 不显示动态取色）；`packages/live_ui/lib/src/widgets/scrolling.dart:18`（弹性滚动）。

## 3.x 基线

- 原生：`git show v3.2.11:ios/Runner/Info.plist`（`:5` 120 Hz；`:50` 共享扩展 URL scheme；没有 `UIBackgroundModes`、没有 `UIRequiresFullScreen`，`:87` 指针事件、`:93-104` 方向）、`ios/Runner/AppDelegate.swift:16-41`（`pure_live/display_mode`）、`ios/ShareExtension/ShareViewController.swift:11-32`（模板）。
- Dart：`lib/modules/live_play/widgets/video_player/video_controller_panel.dart:38-61`、`:321`、`:1009-1025`、`:1425`；`lib/modules/live_play/widgets/layout/live_play_back_scope.dart:120-121`；`lib/common/utils/share_command_handler.dart:64-66`、`:217-220`；`lib/common/global/platform/desktop_manager.dart:596-625`（剪贴板）；`lib/modules/live_play/widgets/keyboard/video_keyboard.dart:53-80`；`lib/modules/version/version_page.dart:43-99`；`lib/modules/about/widgets/version_dialog.dart:71-80`（设计 README 的“v3 在 iPhone、iPad 上的样子”逐条写了）。
- 要保留：同一套界面（c1）；普通页面左边缘滑动返回、弹性滚动、120 Hz；v3 的单键快捷键。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.1 节（宽度分档）、第 5.6 节（苹果平台）、第 3 节第 7 条。
3. 本文件夹 `README.md`（尤其“改动”“拿不准的地方”“交给其他任务的”）和 `page/`；`A18.2-macOS差异设计/README.md`（快捷键同一套）。
4. 相关界面：`docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏/README.md`（窄屏规则）、`A07.8-小窗/README.md`（c5、J1、“无法打开画中画”）、`A07.2-竖屏流和竖屏全屏/README.md`；`docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗/README.md`（口令导入、新版本）；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`（Ctrl 快捷键）；`docs/A-界面设计/A04-尺寸和适配/README.md`。
5. `docs/X-多端客户端/X04-iOS和iPadOS/README.md` 和 X04.1 的任务说明。

## 范围

- 可以改：上面“现状”列的 Dart 文件里的平台分支（`player_controls.dart`、`live_play_page.dart`、`clipboard_rooms.dart`、`plugins.dart`、`room_menu.dart`、`features/version/`、`features/live_play/mini/`）；新文件放快捷键定义（和 A18.2、A16.1 共用一份命令表，例如 `apps/pure_live/lib/app/shortcuts.dart`）；`apps/pure_live/ios/` 里的界面相关原生部分（画中画、后台音频的 `Info.plist` 项、共享扩展打开主应用、`UIKeyCommand`）——**前提是 X04.1 已经建好工程**；翻译文件（只加键）；测试；本文件夹。
- 不能改：Android、Windows 的界面和行为（平台分支以外的改动要证明对它们没影响）；设置键名和含义（D-018）；签名配置和证书（X04.1 的事）；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 前提检查：X04.1 的工程在 iPhone、iPad 上能装能播；找一台 Mac 和设备；核对设计 README“拿不准的地方”1～8 条（安全区数值、mpv 能否交给系统画中画、share_plus 在 iPad 不给位置的行为……），结论写 record.md | record.md | 每条有结论；画中画做不了时按 A07.8 的“无法打开画中画”处理并写明 |
| 2 | 纯 Dart 能做的（Linux 上就能写测试）：横屏全屏安全区（c2）、全屏左边缘滑动退出全屏（c3）、剪贴板先查再读（c9）、iPad 分享气泡位置（c7 出去部分）、iOS 更新“去下载页”（c13）、iPad 宽度分档和播放不中断（c11 Dart 部分）、悬停（c12） | 上表 Dart 文件 | 新测试（`debugDefaultTargetPlatformOverride = TargetPlatform.iOS`）全部通过；Android 的相关测试不改断言照样通过 |
| 3 | Cmd 快捷键（c10）：和 A18.2、A16.1 共用一份命令表；iOS 上按住 ⌘ 的列表要原生 `UIKeyCommand`（Runner 里写一层） | `app/shortcuts.dart`（新）、`ios/Runner/` | Dart 层：每个组合键触发对应命令的测试；原生层：Mac 上按住 ⌘ 看到列表 |
| 4 | 要原生的（在 Mac 上做）：系统画中画和自动画中画（c4）、后台音频和“正在播放”（c5）、共享扩展打开主应用（c8）、台前调度窗口按钮让位（c11 原生部分） | `ios/`、`features/live_play/mini/`、`app/intake/` | 真机步骤通过；不能做的写明原因和替代 |

每个阶段都要能单独合并。登记表没有写阶段，开工时按上表补。

## 测试

- 改之前会失败（Linux 上能跑）：`apps/pure_live/test/features/live_play/` 加“iOS 横屏全屏、`MediaQuery.padding` 左右 59 时上下栏在安全区里”，和“iOS 全屏时 `handlePopRoute` 退出全屏而不是离开”。
- 要加：剪贴板——iOS 上回到前台不调用 `Clipboard.getData`，只查有没有文字，点“识别”后才读（替身记录调用次数）；分享——iPad 宽度时传了 `sharePositionOrigin`（替身）；更新——iOS 的新版本对话框主要按钮是“去下载页”；宽度——585、795、1180 三种宽度的排法，切换宽度时播放会话没有重建（同一个会话对象）；快捷键——每个 ⌘ 组合触发对应命令。
- 测试里的定时器至少 1 秒（提示条 6 秒用可注入时长）；不访问真实平台。

## 真机验证（要 iPhone 和 iPad，在 Mac 上构建）

| 步骤 | 期望 |
|---|---|
| 1. iPhone 竖屏进直播间 | 内容从灵动岛下面开始；弹幕列表最后一行在指示条上面 |
| 2. 横屏全屏，转到灵动岛在右 | 锁定键、返回键、下栏都在安全区里，不被灵动岛挡、不压指示条 |
| 3. 全屏时从左边缘往右滑 | 退出全屏（不离开直播间）；再滑一次离开直播间 |
| 4. 点上栏小窗按钮；回桌面 | 系统画中画；打开“后台播放”时锁屏有“正在播放” |
| 5. iPad 上菜单“分享” | 分享气泡从菜单按钮旁弹出，不报错 |
| 6. 在 Safari 里分享一个哔哩哔哩直播间链接给“纯粹直播” | 直接打开应用进直播间 |
| 7. 在别的应用拷贝一个分享口令，切回来 | 底部提示“剪贴板里有新内容…[识别]”，系统没有弹“允许粘贴”；点“识别”后才弹一次 |
| 8. iPad 接键盘按住 ⌘；按 ⌘F | 快捷键列表；⌘F 打开搜索 |
| 9. iPad 分屏拖动分隔条（1/3 → 1/2 → 2/3） | 排法跟着变，播放不中断 |
| 10. 有新版本时 | 对话框主要按钮“去下载页”，打开发布页 |

## 风险和注意

- 没有 Mac 就做不了第 3 阶段的原生部分和第 4 阶段；第 2 阶段可以先在 Linux 上做（只改平台分支），但没有真机前不要改登记表的状态。
- mpv 画面交给系统画中画（`AVSampleBufferDisplayLayer`）可能做不到（设计“拿不准的地方”第 2 条）：做不到时 c4 降级，写进 record.md 由维护者定。
- 共享扩展打开主应用用的是非官方做法（URL scheme），以后的系统可能要换。
- 改返回链（c3）会影响 Android 的返回逻辑：只在 iOS 分支里改，Android 的直播间返回测试必须不改断言照样通过。
- 可能冲突的文件：`player_controls.dart`、`live_play_page.dart`（A07 的后续任务）、`clipboard_rooms.dart`（O03）、`features/version/`（Y02）、快捷键命令表（A18.2、A16.1、X01.1）。

## 环境和提交

- Linux / WSL：`source ~/tools/purelive-env.sh` 或按 `toolchain.env` 装 Flutter；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；只能跑 Dart 测试，**不能构建 iOS**。
- Mac：按 X04.1 的说明装 Xcode、CocoaPods，`flutter build ios`；签名和证书不进 git。
- 分支 `ai/A18.1`；提交信息以 `[A18.1]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；第 1 阶段“拿不准的地方”各条的结论；画中画能不能做；测试数量（改之前失败几个）；改了哪些文件（Dart 和原生分开列）；新翻译键；要在设备上看的；可能冲突的文件。
