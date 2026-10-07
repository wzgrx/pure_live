# X04.1 苹果平台的构建和签名：任务书

## 背景

- 来源：D-004 的客户端顺序最后一步；A18.1、A18.2 的差异设计已确认但没有工程可以落地。登记时的旧编号 T19c.1。
- 现象：`apps/pure_live/` 下只有 `android/`、`windows/`，没有 `ios/`；iOS 上没有加密存储（`apps/pure_live/lib/platform/secret_cipher.dart:12-14` 抛异常）；14 个平台通道只有 Android 实现；本机没有 Mac。
- 为什么现在做：第三档，**以后**（版本路线“以后：iOS、iPadOS、macOS”，`docs/PLAN.md` 第 5 节）。
- **前置条件**：
  1. 维护者同意开始苹果平台（Windows、电视、Linux 之后，D-004）。
  2. 有一台能用的 Mac 和 Xcode（实体机或云 Mac；4.x 不用 GitHub Actions，要用 Actions 的 macOS 机器需要维护者决定例外）。
  3. 签名方式定了（见第 1 阶段），需要时有 Apple 开发者账号。
  条件不满足时只做第 1 阶段（方案文档）。
- 已经做过的：A18.1（iOS 和 iPadOS 差异设计，已确认）；Dart 代码里零散的 iOS 分支（见“现状”）；libmpv 的 iOS 原生包在 media_kit 分支里。
- 范围说明：本任务做 iOS 和 iPadOS；macOS 的工程和构建要在 X05 另外登记任务（签名账号、证书、Keychain 加密器的 Dart 侧可以共用）。

## 目标和验收

1. `record.md` 有方案并经维护者确认：包名、签名和分发方式、iOS 上录制要不要、14 个通道每个怎么处理、3.x iOS 用户怎么升级。
2. （有 Mac 后）`apps/pure_live/ios/` 进 master；`flutter build ios --simulator` 成功，模拟器启动到首页；Android、Windows 的构建和测试不受影响。
3. iPhone 真机：看哔哩哔哩直播（画面、声音、弹幕）、关注、设置；账号（粘 Cookie）重启后还在（Keychain）；后台播放、系统画中画按 A18.1 的设计（如果在本任务范围）。
4. 按方案做出能分发的包（TestFlight 构建、或未签名 IPA），写清安装步骤。
5. 门禁 `--all` 通过（iOS 工程不进门禁的构建，只要不影响其他成员）。

## 现状（读代码得出，写文件:行）

- 没有 `apps/pure_live/ios/`。
- 加密：`apps/pure_live/lib/platform/secret_cipher.dart:9-14`（Android `AndroidKeystoreCipher` `:20`、Windows `WindowsDpapiCipher` `:45`，其余抛 `UnsupportedError`）；接口在 `packages/live_store/lib/src/secrets.dart`。
- 平台通道（Dart 侧在 `apps/pure_live/lib/platform/` 和各功能里）：`pure_live/app`、`background_playback`、`device_controls`、`display_mode`、`multicast_lock`、`native_http`、`permissions`、`pip`、`predictive_back`、`recorder`、`secret_cipher`、`share_intake`、`system_access`、`text_codec`；原生实现只在 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/`（7 个 `.kt`），Windows 运行器有 `display_mode`。
- 已有的 iOS 分支：`lib/app/network.dart`、`lib/platform/plugins.dart`、`lib/shared/in_app_web.dart`、`lib/shared/rooms/room_cards.dart`、`room_menu.dart`、`lib/features/backup/backup_page.dart`、`lib/features/settings/settings_editors.dart`（mpv 的 iOS 选项）、`lib/main.dart`、`local_interaction_scope.dart:58`（系统 emoji）；`update_feed.dart:309`。
- 播放：`third_party/media_kit/hook/native_bundles.json:56-69`（`ios_arm64`、`ios_x64`）；`packages/live_player/lib/src/mpv_options.dart:4`。
- 录制：根 `pubspec.yaml:66-72` 的 `ffmpeg_kit_extended_config` 没有 iOS。
- 插件（`apps/pure_live/pubspec.yaml`）：`audio_service`、`file_picker`、`flutter_inappwebview`、`mobile_scanner`、`share_plus`、`url_launcher`、`connectivity_plus`、`bonsoir`、`path_provider` 都支持 iOS；`window_manager`、`tray_manager`、`screen_retriever` 是桌面的（iOS 上不能调用）；`android_intent_plus` 只在 Android。

## 3.x 基线

- `git show v3.2.11:ios/Runner.xcodeproj/project.pbxproj:610`（`com.mystyle.purelive.liu`）、`:627-629`（测试目标、iphoneos 和 macosx 的包名）；`ios/Runner/Info.plist`（显示名 `Pure Live`、相册权限说明）；`ios/Runner/AppDelegate.swift`、`SceneDelegate.swift`；`ios/ShareExtension/`（分享扩展：`ShareViewController.swift`、`Info.plist`、`ShareExtension.entitlements`）；`ios/Podfile`。
- `git show v3.2.11:.github/workflows/build-ios-unsigned.yml`：`macos-15`、Xcode 26、Flutter 3.47.5，未签名 IPA。
- 要保留：3.x 的设置键（D-018）；用户看得到的文字中文（权限说明也是，D-005）。不要带上 Firebase（`GoogleService-Info.plist`）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 11 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 3 节、第 4 节）；`docs/specs/UI.md` 第 5.4 节。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X04-iOS和iPadOS/README.md`；`docs/A-界面设计/A18-苹果平台界面/README.md`、`A18.1-iOS和iPadOS差异设计/README.md`（c1～c13）。

## 范围

- 可以改：新建 `apps/pure_live/ios/`；`apps/pure_live/lib/platform/`（iOS 的加密器、通道的平台判断）；需要的 Dart 侧条件判断；`apps/pure_live/pubspec.yaml`（加 iOS 需要的依赖要维护者同意）；对应测试；本文件夹的文档。
- 不能改：Android、Windows 的原生代码和行为；A18.1 的界面设计（界面差异的实现是 A18.1 的开发任务，本任务只让工程能跑）；版本号、`assets/version.json`、`assets/releases.json`；Android 的签名配置。
- 绝对不能：把苹果的证书、描述文件、`.p12`、App Store Connect 的密钥放进 git 或文档（D-006 同理）。现在的 `.gitignore` 排除了 `*.jks`、`*.keystore`、`*.pfx`、`*.key`、`*.csr`、`key.properties`，**没有**苹果的 `*.p12`、`*.mobileprovision`、`*.p8`，开工时先加上。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案（不需要 Mac） | c1：包名、签名和分发、录制、14 个通道、3.x 用户升级 | `record.md` | 维护者确认 |
| 2 工程（要 Mac） | c2：生成 `ios/`、`Info.plist`、`entitlements`、`pod install`；`.gitignore` 加苹果签名文件 | `apps/pure_live/ios/`、`.gitignore` | 模拟器启动到首页；其他平台不受影响 |
| 3 原生 | c3：Keychain 加密器；通道按方案处理；真机看直播 | `lib/platform/`、`ios/Runner/` | 验收 3 |
| 4 签名和分发 | c4：按方案出包 | `record.md`（安装步骤） | 验收 4 |

## 测试

- `secret_cipher` 的 Dart 侧测试（假通道）：iOS 平台选到 Keychain 加密器；读写往返。
- 通道降级：iOS 上调用 Android 专有通道的地方不抛 `MissingPluginException`（widget 测试用 `TargetPlatform.iOS`）。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 iPhone、iPad 上做）

| 步骤 | 期望 |
|---|---|
| 1. 安装（按方案的方式），打开 | 显示名“纯粹直播”，首页 |
| 2. 进一个哔哩哔哩直播间 | 画面、声音、弹幕正常 |
| 3. 设置 → 账号，粘 Cookie，杀掉应用再打开 | 账号还在 |
| 4. 横过来全屏、滑动返回 | 按 A18.1 的设计（如果已经实现） |
| 5. iPad：分屏 1/2、接键盘 | 布局跟着窗口变；键盘快捷键可用（A18.1） |

## 风险和注意

- 苹果的签名材料和 Android 的一样不进 git；开工先补 `.gitignore`。
- App Store 审核对“聚合第三方直播”的应用可能不通过；分发方式要维护者先权衡。
- `flutter create` 会改 `pubspec.yaml` 以外的生成文件，只提交 `ios/` 下需要的。
- 可能冲突的文件：`apps/pure_live/lib/platform/`（X02.1 也加 Linux 的加密器）；`apps/pure_live/pubspec.yaml`。

## 环境和提交

- Mac：Xcode（和 Flutter 3.47.5 兼容的版本，3.x 用 Xcode 26）、CocoaPods、Flutter 3.47.5（`toolchain.env`）。WSL 上只能写第 1 阶段和 Dart 部分。
- 分支 `ai/X04.1` 或本机工作区；提交信息以 `[X04.1]` 开头（英文）；不推 master。
- 提交前（WSL）：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`bash tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`（登记表现在没有写阶段，开工时按上表补上）。

## 报告（中文，简洁）

方案的结论；在哪台 Mac 上做的；工程、加密器、通道各做到哪；真机结果；分发方式和安装步骤；需要维护者决定的（包名、开发者账号、App Store、录制）；可能冲突的文件。
