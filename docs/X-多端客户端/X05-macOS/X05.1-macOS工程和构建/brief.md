# X05.1 macOS 工程和构建：任务书

## 背景

- 来源：D-004 的客户端顺序（Android → Windows → 电视 → Linux → 苹果平台）最后一步；A18.2（macOS 差异设计）已确认，没有工程；docs v2 时在 X05 登记。
- 现象：`apps/pure_live/` 下没有 `macos/`；`secret_cipher.dart:12-14` 在 macOS 抛异常；桌面外壳只在 Windows 启用（`app/desktop/desktop_window.dart:257`）；本机没有 Mac。
- 为什么现在做：第三档，**以后**（`docs/PLAN.md` 第 5 节版本路线“以后：iOS、iPadOS、macOS”）。
- **前置条件**：
  1. 维护者同意开始苹果平台（Windows、电视、Linux 之后）。
  2. 有一台能用的 Mac 和 Xcode（4.x 不用 GitHub Actions；要用 Actions 的 macOS 机器需要维护者决定例外）。
  3. 最好在 X04.1 之后（共用 Keychain 加密器的 Dart 侧和开发者账号）。
  条件不满足时只做第 1 阶段（方案）。
- 已经做过的：A18.2 设计（c1～c10）；更新通道里已有 `macosDmg`、`macosZip`（`apps/pure_live/lib/features/version/update_feed.dart:223-227`）；media_kit 有 macOS 原生包。

## 目标和验收

1. `record.md` 有方案并经维护者确认：包名和 3.x 升级、沙盒和权限、录制做不做、14 个通道各怎么处理。
2. （有 Mac 后）`apps/pure_live/macos/` 进 master；`flutter build macos` 成功，启动到首页；Android、Windows 的构建和测试不受影响。
3. Mac 上：看哔哩哔哩直播（画面、声音、弹幕）；关注、设置；账号（粘 Cookie）重启后还在（Keychain）。
4. 桌面外壳：系统三个窗口按钮在顶栏左侧、中文菜单栏、⌘W 只关窗口应用留在程序坞、⌘Q 退出（有录制时先问）、系统全屏和直播间全屏是同一件事（A18.2 c2、c4～c8 的工程部分）。
5. 门禁 `--all` 通过（macOS 工程不进门禁的构建）。

## 现状（读代码得出，写文件:行）

- 没有 `apps/pure_live/macos/`。
- 加密：`apps/pure_live/lib/platform/secret_cipher.dart:9-14`（Android `AndroidKeystoreCipher`、Windows `WindowsDpapiCipher`，其余 `UnsupportedError`）；接口 `packages/live_store/lib/src/secrets.dart`。
- 平台通道：Dart 侧在 `apps/pure_live/lib/platform/`，14 个（清单见 X04.1 任务书“现状”）；原生实现只有 Android（`android/app/src/main/kotlin/com/mystyle/purelive/`）和 Windows 运行器的 `display_mode`。
- 桌面外壳：`apps/pure_live/lib/app/desktop/desktop_window.dart:257`（只在 Windows 启用）、`mini_window.dart:166-199`（macOS 隐藏标题栏）；插件 `window_manager`、`tray_manager`、`screen_retriever` 支持 macOS。
- 更新：`update_feed.dart:223-227`、`:308`。
- 录制：根 `pubspec.yaml:66-72` 没有 macOS 的 FFmpeg 包。

## 3.x 基线

- `git show v3.2.11:macos/Runner/Configs/AppInfo.xcconfig:11`（`PRODUCT_BUNDLE_IDENTIFIER = com.mystyle.pureLive`）；`macos/Runner/MainFlutterWindow.swift`、`MainMenu.xib`（菜单栏）、`DebugProfile.entitlements`、`Release.entitlements`（缺 `com.apple.security.network.server`）、`macos/Podfile`。
- `git show v3.2.11:.github/workflows/build_pure_live_release.yml:512-565`（3.x 怎么构建 macOS 通用包）。
- 要保留：3.x 的设置键（D-018）；用户看得到的文字中文（D-005）；v3 的单键快捷键（A18.2 c1）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 3 节、第 4 节）；`docs/specs/UI.md` 第 4 节、第 5.4 节。
3. 本文件夹的 `README.md`；`docs/X-多端客户端/X05-macOS/README.md`；`docs/A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计/README.md`；`docs/X-多端客户端/X04-iOS和iPadOS/X04.1-苹果平台的构建和签名/brief.md`（通道表、加密器）；`docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口/README.md`。

## 范围

- 可以改：新建 `apps/pure_live/macos/`；`apps/pure_live/lib/platform/`（macOS 加密器、通道的平台判断）；`apps/pure_live/lib/app/desktop/`（macOS 分支）；`.gitignore`（苹果签名文件）；对应测试；本文件夹的文档。
- 不能改：Android、Windows 的原生代码和行为；A18.2 的设计；版本号、`assets/version.json`、`assets/releases.json`；签名配置（X05.2）。
- 绝对不能：把证书、`.p12`、描述文件、公证用的 App Store Connect 密钥放进 git 或文档（D-006）。

## 方案和阶段

| 阶段 | 做什么（README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案（不需要 Mac） | c1 | `record.md` | 维护者确认 |
| 2 工程（要 Mac） | c2 | `apps/pure_live/macos/`、`.gitignore` | `flutter build macos` 成功，启动到首页；其他平台不受影响 |
| 3 原生 | c3 | `lib/platform/`、`macos/Runner/` | 验收 3 |
| 4 桌面外壳 | c4 | `lib/app/desktop/`、`macos/Runner/` | 验收 4 |

登记表现在没有写阶段，开工时按上表补上。

## 测试

- 加密器：`TargetPlatform.macOS` 选到 Keychain 加密器；读写往返（假通道）。
- 通道降级：macOS 上不抛 `MissingPluginException`（widget 测试）。
- 桌面外壳：关闭窗口不退出的逻辑、退出确认（有录制时）可以用现有的桌面外壳测试照着加 macOS 分支。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 Mac 上做）

| 步骤 | 期望 |
|---|---|
| 1. 运行构建出来的应用 | 显示名“纯粹直播”，首页；三个系统窗口按钮在顶栏左边 |
| 2. 进一个哔哩哔哩直播间 | 画面、声音、弹幕正常 |
| 3. 设置 → 账号，粘 Cookie，⌘Q 退出再打开 | 账号还在 |
| 4. ⌘W | 窗口关闭，应用留在程序坞；点程序坞图标窗口回来 |
| 5. 直播间里点全屏 | 进入系统全屏空间；按 Esc 或绿色按钮离开时直播间同时退出全屏 |
| 6. 开一个录制（如果做了录制），⌘Q | 先问要不要退出 |

## 风险和注意

- 沙盒会限制录制目录和下载目录的访问，要用“用户选择的文件”权限和安全书签。
- 3.x 的包名是 `com.mystyle.pureLive`（大写 L），和 Android 不同；沿用才能让 3.x 用户覆盖，但要确认签名能一致（X05.2）。
- 可能冲突的文件：`apps/pure_live/lib/platform/`（X02.1 Linux、X04.1 iOS 也会加加密器）；`apps/pure_live/lib/app/desktop/`（A16 的后续任务）。

## 环境和提交

- Mac：Xcode（和 `toolchain.env` 的 Flutter 兼容的版本）、CocoaPods、Flutter（版本见 `toolchain.env`）。WSL 上只能做第 1 阶段和 Dart 部分。
- 分支 `ai/X05.1` 或本机工作区；提交信息以 `[X05.1]` 开头（英文）；不推 master。
- 提交前（WSL）：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；`tools/gate/gate.sh --all`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

方案的结论；在哪台 Mac 上做的；工程、加密器、通道、桌面外壳各做到哪；Mac 上的结果；需要维护者决定的（包名、录制、沙盒）；可能冲突的文件。
