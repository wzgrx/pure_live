# X05.1 macOS 工程和构建

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：D-004 的客户端顺序最后一步；[X05 子分类说明](../README.md)的“路线”；A18.2 的差异设计已确认，没有工程可以落地
- 相关：D-004、D-006（签名材料不进 git）、D-018；[A18.2](../../../A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计/README.md)（界面差异）；[X04.1](../../X04-iOS和iPadOS/X04.1-苹果平台的构建和签名/README.md)（共用 Keychain 加密器的 Dart 侧、开发者账号）；[X05.2](../X05.2-macOS签名和分发/README.md)（签名和分发）；[A16.1](../../../A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md)（桌面外壳）

## 目标

在 Mac 上能构建、运行 4.x：首页、直播间（画面、声音、弹幕）、关注、设置、账号（Keychain）都能用；桌面外壳在 macOS 上按 A18.2 的工程部分工作。本任务不做签名、公证和分发（X05.2）。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 工程 | `git ls-tree -r v3.2.11 macos`：`Runner.xcodeproj`、`AppDelegate.swift`、`MainFlutterWindow.swift`、`MainMenu.xib`、`Configs/AppInfo.xcconfig:11`（`com.mystyle.pureLive`）、`DebugProfile.entitlements`、`Release.entitlements`、`Podfile` | 没有 `apps/pure_live/macos/` | 新建 `macos/`，包名按方案 |
| 构建 | 3.x 发布工作流能出 macOS 通用包（`git show v3.2.11:.github/workflows/build_pure_live_release.yml:21-22`、`:512-565`，`macos-15`） | 4.x 只在本机构建（ENGINEERING 第 3 节），本机没有 Mac | 在 Mac 上 `flutter build macos` 成功 |
| 加密存储 | 3.x 不加密 | `apps/pure_live/lib/platform/secret_cipher.dart:12-14` 除 Android、Windows 外抛异常 | Keychain 加密器（和 X04.1 共用 Dart 侧） |
| 播放 | media_kit | `third_party/media_kit/hook/native_bundles.json` 有 `macos_arm64`、`macos_x64` | 通用包里两种架构都能播 |
| 录制 | 3.x 有 | 根 `pubspec.yaml:66-72` 的 `ffmpeg_kit_extended_config` 没有 macOS | 方案里定：做（加 macOS 的 FFmpeg 包）还是先隐藏录制 |
| 桌面外壳 | — | 只在 Windows 启用（`apps/pure_live/lib/app/desktop/desktop_window.dart:257`，注释 “macOS is U.17b”）；桌面小窗在 macOS 隐藏标题栏（`app/desktop/mini_window.dart:166-199`）；没有 `PlatformMenuBar` | A18.2 c2～c8 的工程部分：系统窗口按钮、中文菜单栏、Cmd 快捷键、关窗不退出、菜单栏图标、系统全屏 |
| 权限 | `Release.entitlements` 缺 `com.apple.security.network.server`（A12.6 设备同步要监听） | — | 正式版权限文件补上；A11.4 的“登录时打开”一起处理 |

## 方案

- c1 方案（不需要 Mac）：包名（沿用 3.x 的 `com.mystyle.pureLive` 能不能覆盖 3.x，3.x 用户怎么升级）、沙盒和权限清单、录制做不做、14 个平台通道每个在 macOS 怎么处理（照 X04.1 的表）。写进 `record.md`，维护者确认。
- c2 工程：`flutter create --platforms=macos` 生成后只提交需要的文件；`Info.plist`（显示名“纯粹直播”，权限说明中文）、`entitlements`（网络客户端和服务端、用户选择的文件读写）、`Podfile`；`.gitignore` 加 `*.p12`、`*.mobileprovision`、`*.p8`（和 X04.1 共用）。
- c3 原生：Keychain 加密器；通道按方案降级；`desktop_window.dart` 在 macOS 启用外壳。
- c4 桌面外壳的 macOS 做法：A18.2 c2（标题栏和系统按钮）、c4（菜单栏）、c5（Cmd 快捷键）、c6（关闭和退出）、c7（菜单栏图标）、c8（全屏）的工程部分；界面细节按 A18.2 的设计。

## 验证

- 自动测试：加密器选择和读写往返（假通道）；`TargetPlatform.macOS` 下调用 Android 专有通道的地方不抛 `MissingPluginException`。
- 真机（Mac）：见任务书“真机验证”。现在：待开工。

## 留下的问题

- 签名、公证、`.dmg`/`.zip`、应用内更新 → X05.2。
