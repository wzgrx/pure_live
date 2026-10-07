# X04 iOS和iPadOS

iPhone 和 iPad 客户端的工程层：`ios/` 运行器、Xcode 工程和权限文件、原生插件在 iOS 上的对应实现、构建和签名、分发方式。按 D-004 排在最后；本机没有 Mac，现在不能构建。

## 范围

- 包括：`apps/pure_live/ios/`（现在不存在）、`Info.plist` 和权限说明、`Runner.entitlements`、分享扩展、Podfile；应用里 14 个 `pure_live/*` 平台通道在 iOS 上的实现或降级；加密存储（Keychain）；后台音频、画中画、局域网权限这些 iOS 的系统能力；构建（Xcode、CocoaPods）、签名（Apple 开发者账号、描述文件）、分发（TestFlight / App Store / 自签安装包）。
- 不包括（归哪里）：
  - iPhone、iPad 上界面的差异（安全区、滑动返回、系统画中画的样子、分享面板、剪贴板提示、iPad 分屏和键盘指针）→ [A18.1](../../A-界面设计/A18-苹果平台界面/A18.1-iOS和iPadOS差异设计/README.md)（设计已确认）。
  - macOS → X05。
  - 播放内核的 iOS 原生包（`third_party/media_kit/hook/native_bundles.json` 的 `ios_arm64`、`ios_x64`）→ G01。

## 现状：做到哪、怎么工作的

- **没有 `apps/pure_live/ios/`**：4.x 的应用只有 `android/`、`windows/` 两个原生工程；3.x 有（`git ls-tree -r v3.2.11 ios`：`Runner.xcodeproj`、`AppDelegate.swift`、`SceneDelegate.swift`、`Info.plist`、`Runner.entitlements`、`GoogleService-Info.plist`、`ShareExtension/`、`Podfile`）。
- Dart 里已经为 iOS 留的分支（都没在 iOS 上跑过）：`apps/pure_live/lib/app/network.dart`（网络类型在 iOS 上照 Android 读）、`lib/platform/plugins.dart`、`lib/shared/in_app_web.dart`、`lib/shared/rooms/room_cards.dart`、`room_menu.dart`、`lib/features/backup/backup_page.dart`、`lib/features/settings/settings_editors.dart`（mpv 驱动的 iOS 选项）、`lib/main.dart`；本地互动的 emoji 在 iOS、macOS 上用系统字体（`lib/features/live_play/local_interaction/local_interaction_scope.dart:58`）；`packages/live_player/lib/src/mpv_options.dart:4` 有 `MpvPlatform.ios`；`update_feed.dart:309` 认得 `ios` 平台。A18 的子分类说明列了界面上已经做了的（弹性滚动、后台播放设置 `when: _mobile`）。
- **缺的原生部分**：
  - 加密存储：`apps/pure_live/lib/platform/secret_cipher.dart:12-14` 只有 Android、Windows，iOS 上抛异常——不补的话账号无处可存。
  - 14 个平台通道（`pure_live/app`、`background_playback`、`device_controls`、`display_mode`、`multicast_lock`、`native_http`、`permissions`、`pip`、`predictive_back`、`recorder`、`secret_cipher`、`share_intake`、`system_access`、`text_codec`）都只有 Android（Kotlin）实现，Windows 有 `display_mode`。
  - 录制的 FFmpeg：根 `pubspec.yaml:66-72` 的 `ffmpeg_kit_extended_config` 只配了 android、windows、linux。
  - 分发：版本页的包类型（`update_feed.dart:204-226`）没有 iOS（A18.1 c13 设计成“去下载页”）。
- **环境**：本机（WSL + Windows）没有 Mac，不能运行 Xcode、不能构建和签名；也没有记录是否有 Apple 开发者账号。
- 完成度：X04.1 未开始；A18.1 设计已确认。

## 代码地图

| 文件 | 职责 |
|---|---|
| （不存在）`apps/pure_live/ios/` | 运行器和 Xcode 工程 |
| `apps/pure_live/lib/platform/secret_cipher.dart:9-14` | 加密器的平台选择（iOS 缺） |
| `apps/pure_live/lib/platform/*.dart` | 各平台通道的 Dart 侧（iOS 都要对应） |
| `apps/pure_live/lib/app/platforms.dart` | 平台能力判断 |
| `third_party/media_kit/hook/native_bundles.json:56-69` | libmpv 的 iOS 原生包 |
| 根 `pubspec.yaml:66-72` | FFmpeg 原生包（没有 iOS） |
| `apps/pure_live/lib/features/version/update_feed.dart:305-313` | 更新的平台名 |

测试：没有 iOS 专门的测试（界面测试可以用 `TargetPlatform.iOS` 跑，A18 的任务会加）。

## 3.x 基线

- `git show v3.2.11:ios/Runner.xcodeproj/project.pbxproj:610`：包名 `com.mystyle.purelive.liu`（测试目标 `com.mystyle.pureLive.RunnerTests`）；`ios/Runner/Info.plist`（显示名 `Pure Live`、相册权限说明）；`ios/ShareExtension/`（分享扩展）；`ios/Runner/GoogleService-Info.plist`（Firebase，4.x 不要）。
- 3.x 的 iOS 分发：`.github/workflows/build-ios-unsigned.yml`（`macos-15`、Xcode 26、Flutter 3.47.5，出未签名的 IPA 给 TrollStore 或自签名工具用，可选建发布页）；没有上架。
- 要保留：3.x 的设置键（D-018）；如果要让 3.x 的 iOS 用户覆盖升级，包名必须是 `com.mystyle.purelive.liu`、签名团队相同（未签名 IPA 由用户自签，不存在“覆盖”）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有 Mac，不能构建 | 环境 | 整个子分类做不了 | X04.1 的前提：维护者提供 Mac（实体机、云 Mac 或 GitHub Actions 的 macOS，但 4.x 不用 Actions，要维护者决定例外） |
| 没有 `ios/` 工程 | `apps/pure_live/` | — | X04.1 第 1 阶段 |
| iOS 上没有加密器 | `secret_cipher.dart:12-14` | 账号存不了 | X04.1（Keychain） |
| 平台通道都只有 Android 实现 | `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/` | iOS 上调用会 `MissingPluginException` | X04.1 逐个实现或在 iOS 上不调用 |
| 包名 3.x 是 `com.mystyle.purelive.liu`，和 Android 的不一样 | 3.x 的 `project.pbxproj:610` | 选新包名还是沿用影响已装 3.x 的人 | X04.1 定 |

## 相关决定和规范

- D-004（苹果平台排在最后）、D-018（设置键）、D-005（文字中文，iOS 的权限说明也要中文）。
- A18.1 的确认改动（界面差异）；ENGINEERING 第 3 节（只在本机构建——苹果平台要 Mac）。

## 测试和验证

- 自动：界面差异用 `TargetPlatform.iOS` 的 widget 测试（A18.1）；原生部分没有 Mac 就没法测。
- 真机：iPhone 和 iPad 各一台（iPad 看分屏和键盘指针）；在那之前只能在模拟器（也要 Mac）。

## 路线

1. X04.1（第三档，中）：前提是有 Mac 和签名方式；第 1 阶段生成 `ios/` 工程能在模拟器上启动，之后补 Keychain、平台通道、权限文件，最后签名和分发。
2. A18.1 的界面差异在 X04.1 能运行之后开发。
3. 版本路线里苹果平台在“以后”（`docs/PLAN.md` 第 5 节），不定时间。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [X 多端客户端](../README.md)。

- 代码：—
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| X04.1 | 苹果平台的构建和签名 | 发布 | 未开始 | — | — | [设计或说明](X04.1-苹果平台的构建和签名/README.md)、[任务书](X04.1-苹果平台的构建和签名/brief.md) |

## 还没完成的

- **X04.1 苹果平台的构建和签名**（未开始，第三档，规模 中）

<!-- docs:生成结束 -->
