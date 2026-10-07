# X04.1 苹果平台的构建和签名

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：客户端顺序的最后一步（D-004：Android → Windows → 电视 → Linux → 苹果平台）；A18.1、A18.2 的差异设计已确认，但 4.x 没有 `ios/`、`macos/` 工程（A18 子分类说明“现状”）。
- 旧编号：T19c.1
- 相关：决定 D-004；A18.1（iOS 和 iPadOS 差异设计）、A18.2（macOS 差异设计）；X05（macOS 的工程和构建要另外登记任务，本任务只做 iOS 和 iPadOS，和 macOS 共用的部分——Apple 开发者账号、证书、Keychain 加密器的 Dart 侧——在这里先做）；G01（libmpv 的苹果原生包）；Y01、Y02（发布、更新通道）

## 目标

1. 有一条能重复的路径把 4.x 构建成 iPhone 和 iPad 能装的包：`ios/` 工程、CocoaPods、构建命令、签名方式、分发方式都定下来并写清楚。
2. 4.x 在 iPhone 上能启动、看直播、弹幕、关注、设置，账号能加密保存（Keychain）。
3. 定下包名和分发方式（App Store / TestFlight / 自签名安装包），写清 3.x 的 iOS 用户怎么升级。

**前置条件**：维护者提供一台能用的 Mac（实体机或云 Mac）和 Xcode；签名方式需要的 Apple 开发者账号（如果走 App Store / TestFlight）。**本机没有 Mac，这些不满足时本任务不能开工**；只有“方案”阶段可以在没有 Mac 时写。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 工程 | `ios/`：`Runner.xcodeproj`（包名 `com.mystyle.purelive.liu`，`project.pbxproj:610`）、`AppDelegate.swift`、`SceneDelegate.swift`、`Info.plist`、`Runner.entitlements`、`ShareExtension/`、`Podfile`、`GoogleService-Info.plist`（Firebase） | 没有 `apps/pure_live/ios/` | `flutter create --platforms=ios` 生成后照 3.x 改（不要 Firebase） |
| 构建和分发 | `.github/workflows/build-ios-unsigned.yml`：`macos-15`、Xcode 26、Flutter 3.47.5，出未签名 IPA（TrollStore、自签名工具），可选建发布页 | 无；4.x 不用 GitHub Actions（Z01.1） | 在维护者的 Mac 上构建；签名方式维护者定 |
| 加密存储 | Cookie 明文 | `apps/pure_live/lib/platform/secret_cipher.dart:12-14` 没有 iOS | Keychain 实现 `SecretCipher` |
| 平台通道 | 3.x 的 iOS 插件 | 14 个 `pure_live/*` 通道只有 Android 实现 | 逐个：实现、用系统插件代替、或在 iOS 上不调用 |
| 播放 | libmpv（media_kit） | `third_party/media_kit/hook/native_bundles.json` 有 `ios_arm64`、`ios_x64`；`MpvPlatform.ios` | 实机上能播 |
| 录制 | 3.x 的 FFmpeg | 根 `pubspec.yaml:66-72` 的 FFmpeg 配置没有 iOS | 维护者定 iOS 上要不要录制 |
| 应用内更新 | — | `update_feed.dart:309` 认 `ios`；没有 iOS 的包类型 | 照 A18.1 c13：打开下载页或商店 |

## 方案

- c1（第 1 阶段，可以没有 Mac）方案：包名（沿用 `com.mystyle.purelive.liu` 还是新的）、签名和分发（A：App Store / TestFlight，要付费开发者账号；B：未签名 IPA 照 3.x，由用户自签或 TrollStore；C：免费账号 7 天证书，只适合自用）、录制要不要、14 个通道各自怎么处理；写进 `record.md`，维护者定。
- c2（第 2 阶段，要 Mac）工程：`flutter create --platforms=ios .`（在 `apps/pure_live`），按 3.x 改 `Info.plist`（中文显示名“纯粹直播”、相册、本地网络、后台音频的说明）、`Runner.entitlements`；`pod install`；模拟器启动到首页。
- c3（第 3 阶段）原生：Keychain 的 `SecretCipher`（Dart 侧在 `secret_cipher.dart`，原生用 `Security` 框架或 `flutter_secure_storage` 之类的插件——加依赖要维护者同意）；平台通道按 c1 的结论处理；真机看直播、弹幕。
- c4（第 4 阶段）签名和分发：按 c1 的结论做出包；`version.json` 加 `platforms.ios` 块（维护者，发布时）。

## 验证

- 自动测试：`TargetPlatform.iOS` 的 widget 测试（A18.1 的任务加）；`secret_cipher` 的 Dart 侧测试（假通道）。
- 真机：iPhone（和 iPad）上按 brief 的真机步骤。

## 留下的问题

- 还没开始。没有 Mac 时只能做第 1 阶段（方案）。macOS 的工程和构建不在本任务（X05 要先登记任务），但签名账号、证书和 Keychain 的 Dart 侧可以共用。
