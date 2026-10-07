# X05 macOS

Mac 客户端的工程层：`macos/` 运行器、Xcode 工程、沙盒和权限、桌面外壳在 macOS 上的做法（窗口按钮、菜单栏、Cmd 快捷键、关窗不退出、菜单栏图标）、构建、签名、公证和分发。**现在没有任务**；本机没有 Mac，不能构建。

## 范围

- 包括：`apps/pure_live/macos/`（现在不存在）、`Info.plist`、`entitlements`（沙盒、网络、文件访问）、Podfile；应用里的平台通道和加密存储（Keychain）在 macOS 上的实现；桌面外壳（`apps/pure_live/lib/app/desktop/`）在 macOS 上启用；构建、Developer ID 签名、公证、`.dmg` / `.zip` 分发；`version.json` 的 `platforms.macos` 块的内容。
- 不包括（归哪里）：
  - Mac 上界面的差异（红绿灯窗口按钮、菜单栏、Cmd 快捷键、关窗和退出、菜单栏图标、全屏空间、更新方式）→ [A18.2](../../A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计/README.md)（设计已确认，c1～c10）。
  - iOS 和 iPadOS → X04（X04.1 会先建 Apple 开发者账号和 Keychain 加密器的 Dart 侧，macOS 可以共用）。
  - libmpv 的 macOS 原生包（`third_party/media_kit/hook/native_bundles.json` 的 `macos_arm64`、`macos_x64`）→ G01。

## 现状：做到哪、怎么工作的

- **没有 `apps/pure_live/macos/`**；3.x 有（`git ls-tree -r v3.2.11 macos`：`Runner.xcodeproj`、`AppDelegate.swift`、`MainFlutterWindow.swift`、`MainMenu.xib`、`Configs/AppInfo.xcconfig`（包名 `com.mystyle.pureLive`，`:11`）、`DebugProfile.entitlements`、`Release.entitlements`、`Podfile`）。3.x 的发布工作流能构建 macOS 通用包（`git show v3.2.11:.github/workflows/build_pure_live_release.yml:21-22`、`:512-565`，`macos-15`、`flutter build macos`），但 3.x 的 `version.json` 没有 `macos` 块。
- Dart 里已有的 macOS 分支（都没在 Mac 上跑过）：
  - 桌面外壳：`DesktopShell.supported` 只有 Windows（`apps/pure_live/lib/app/desktop/desktop_window.dart:254-257`，注释“macOS is U.17b”，即 A18.2）；桌面小窗在 macOS 上隐藏标题栏（`lib/app/desktop/mini_window.dart:166`、`:181`、`:199`）。
  - 设置：清缓存后重启在桌面平台（含 macOS）直接 `exit(0)`（`lib/features/settings/settings_editors.dart:779`）；mpv 驱动的 macOS 选项（`settings_editors.dart:94-115`，A18 子分类说明）；滚动在 iOS、macOS 上用弹性滚动（`packages/live_ui/lib/src/widgets/scrolling.dart:18`、`:26`）。
  - 更新：`apps/pure_live/lib/features/version/update_feed.dart:223-227`（`macosDmg` `macos-universal.dmg`、`macosZip` `macos-universal.zip`）、`:308`（平台名 `macos`）。
  - 本地互动的 emoji 用系统字体（`local_interaction_scope.dart:58`）。
- 缺的：加密器（`apps/pure_live/lib/platform/secret_cipher.dart:12-14` 没有 macOS）；平台通道的 macOS 实现；录制的 FFmpeg（根 `pubspec.yaml:66-72` 没有 macOS）；运行器和工程本身。
- 完成度：没有登记任务；A18.2 设计已确认。

## 代码地图

| 文件 | 职责 |
|---|---|
| （不存在）`apps/pure_live/macos/` | 运行器和 Xcode 工程 |
| `apps/pure_live/lib/app/desktop/desktop_window.dart:254-257` | 桌面外壳的平台开关（macOS 要打开或另做） |
| `apps/pure_live/lib/app/desktop/mini_window.dart:166-199` | 桌面小窗的 macOS 分支 |
| `apps/pure_live/lib/platform/secret_cipher.dart:9-14` | 加密器（macOS 缺） |
| `apps/pure_live/lib/features/version/update_feed.dart:223-227`、`:308` | macOS 的包类型和平台名 |
| `third_party/media_kit/hook/native_bundles.json:70-83` | libmpv 的 macOS 原生包 |

测试：没有 macOS 专门的测试（界面可以用 `TargetPlatform.macOS` 跑，A18.2 的开发任务会加）。

## 3.x 基线

- `git show v3.2.11:macos/Runner/Configs/AppInfo.xcconfig:11`（`PRODUCT_BUNDLE_IDENTIFIER = com.mystyle.pureLive`）；`macos/Runner/MainFlutterWindow.swift`、`MainMenu.xib`（菜单栏）、`DebugProfile.entitlements`、`Release.entitlements`（沙盒、网络）。
- 构建：`.github/workflows/build_pure_live_release.yml:512-565`（通用包，找 `.app` 打包）。
- 要保留：3.x 的设置键（D-018）；A18.2 确认的 macOS 习惯。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没有任何登记的任务 | `docs/tasks.toml` | 路线里有 macOS，但没有可以开工的任务 | 见“路线”：先登记工程和构建任务 |
| 没有 Mac | 环境 | 不能构建、签名、公证 | 维护者提供 Mac 后再开工 |
| macOS 上没有加密器 | `secret_cipher.dart:12-14` | 账号存不了 | 和 X04.1 共用 Keychain 方案 |
| 公证需要付费 Apple 开发者账号（Developer ID） | — | 没有公证的 `.app` 会被 Gatekeeper 拦 | 维护者定分发方式 |

## 相关决定和规范

- D-004（苹果平台排在最后）、D-018（设置键）。
- A18.2 的确认改动；ENGINEERING 第 3 节（只在本机构建）。

## 测试和验证

- 自动：`TargetPlatform.macOS` 的 widget 测试（A18.2 的开发任务）。
- 真机：一台 Mac（Apple 芯片和 Intel 各一台更好，通用包）。

## 路线

1. **先登记任务**（维护者在 `tasks.toml` 加，建议两个）：
   - X05.1 macOS 工程和构建：生成 `macos/`、沙盒和权限、Keychain 加密器（和 X04.1 共用 Dart 侧）、平台通道的处理、桌面外壳在 macOS 上的做法（A18.2 c1～c10 的工程部分）、能在 Mac 上运行。
   - X05.2 macOS 签名、公证和分发：Developer ID 签名、公证、`.dmg`/`.zip`、应用内更新（`macosDmg`、`macosZip` 已有）、`platforms.macos` 块。
2. 前提：有 Mac；客户端顺序到了苹果平台（D-004，在 Windows、电视、Linux 之后）；最好在 X04.1 之后（共用开发者账号和 Keychain）。
3. A18.2 的界面差异在 X05.1 能运行之后开发。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [X 多端客户端](../README.md)。

- 代码：—
- 进度：还没有任务


还没有任务。

<!-- docs:生成结束 -->
