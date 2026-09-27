# 0007 仓库布局：旧应用留在根目录作为 workspace 根

- 状态：被 0013 取代（旧应用已移到 `legacy/`）；原先取代 0001 中“旧应用移到 `apps/legacy`”的做法
- 日期：2026-09-27

## 背景

原方案要把旧应用整体移到 `apps/legacy`。工程诊断（[diagnosis/08-native-tooling.md](../rewrite/diagnosis/08-native-tooling.md)）指出，这需要在同一个提交里修改 Gradle 相对路径、pubspec 的 path 依赖、构建输出目录、tool 脚本的仓库根、analysis_options 排除项和所有工作流路径，而且 Windows 的构建脚本（SUBST、目录联接）、Linux 的容器构建都依赖当前布局。

Dart 文档没有明确说 workspace 根能否同时是一个应用包，所以做了实验（Flutter 3.47.5 / Dart 3.13.4）：根目录是一个 Flutter 应用，`workspace:` 列出一个纯 Dart 包、一个 Flutter 包和一个成员 Flutter 应用。

- `flutter pub get` 只在根目录生成一份 `pubspec.lock`；
- 根目录 `flutter analyze` 无问题，根应用 `flutter test` 通过；
- 纯 Dart 成员 `dart test` 通过；
- 成员 Flutter 应用 `flutter build apk --debug` 成功（使用与正式项目相同的 AGP 9.4.1、Gradle 9.8.0）。

## 决定

1. 旧应用保持在仓库根目录，根 `pubspec.yaml` 同时是 workspace 根，增加 `workspace:` 列表。
2. v4 的包放在 `packages/*`，新应用放在 `apps/pure_live`，工具放在 `tools/*`，都声明 `resolution: workspace`。
3. 旧应用只做接线改动（通过开关接入新包），新代码不写进根目录的 `lib/`。
4. 第 8 阶段切换时：新应用改用正式包名和签名，删除根目录的旧应用代码（`lib/`、`android/`、`windows/` 等），根 `pubspec.yaml` 只保留 workspace 声明。

## 备选方案与放弃理由

- 移到 `apps/legacy`：一次性改动面大，构建和发布链路都要重新验证，收益只是目录更整齐。
- 新包不进 workspace、各自一份锁文件：依赖版本容易漂移，也无法一次 analyze 全部代码。

## 影响

- 旧应用和新代码共用一份依赖解析。旧应用的 `dependency_overrides` 会影响新包，第 3 阶段先清理多余的覆盖（依赖诊断列出 9 个“越过 SDK 锁定”的覆盖）。
- 根目录的 CI、构建脚本和 Linux 容器构建保持不变；新应用单独增加构建步骤。
- 方案、宪法和 0001 中所有 `apps/legacy` 的写法改为“根目录的旧应用”。
