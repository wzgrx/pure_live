# M0 工程底座

- 日期：2026-09-28
- 上传内容：工具链文件、workspace 根配置、门禁、版本检查工具、代码规范、仓库说明、重构方案。

## 从归档 v4 沿用的部分

只沿用工程工具，不涉及界面：

| 内容 | 文件 | 说明 |
|---|---|---|
| 工具链版本 | `toolchain.env` | 唯一来源 |
| workspace 结构 | `pubspec.yaml` | 所有成员共用一个 `pubspec.lock`；依赖覆盖只能写在根目录 |
| 门禁 | `tools/gate/gate.sh` | 依次检查格式、依赖方向、`dart analyze --fatal-infos` 和测试；有全局锁，同时只跑一个 |
| 依赖方向检查 | `tools/gate/check_deps.py` | 按 docs/PLAN.md 第 4 节的分层写规则表；新成员不在表里就报错，逼着先定方向 |
| 版本检查 | `tools/check_latest` | 对照官方渠道检查工具链、media_kit 上游和 pub 依赖 |
| Claude Code 钩子 | `.claude/settings.json`、`tools/gate/hooks/format_dart.sh` | 改完 Dart 文件自动格式化，结束时跑门禁 |
| 忽略规则 | `.gitignore`、`.gitattributes` | 签名文件不进 Git |

## 和 v3 工程的对比

| v3 的问题 | 这次的做法 |
|---|---|
| 11 个 CI 工作流：没有 push 和 PR 触发；发布工作流引用了不存在的 Secret | 不用 GitHub Actions，只在本机构建和跑门禁 |
| `tool/` 下有 174 个脚本，共 2.56 万行，大部分是一次性的 | 只保留门禁和版本检查；其余按模块需要时再加 |
| 工具链版本散落在多个文件 | 集中在 `toolchain.env`，由 `check_latest` 核对 |
| 依赖方向靠约定（平台层、播放层、界面层互相引用） | 由门禁强制 |

## 环境版本（2026-09-28 核对，全部是最新稳定版）

| 项目 | 版本 |
|---|---|
| Flutter | 3.47.5（Dart 3.13.4） |
| Gradle | 9.8.0 |
| Android Gradle Plugin | 9.4.1 |
| Kotlin | 2.4.20 |
| JDK（Temurin） | 27 |
| Android NDK | 30.0.16248370 |
| compileSdk | 37.2 |
| build-tools | 37.0.0 |
| mpv | 0.41.0 |
| FFmpeg | 9.0.2 |
| media_kit 上游（Predidit/media-kit） | `803c4a2` |
| pub 依赖（args、pub_semver、test、very_good_analysis、yaml） | 全部最新 |

- 查询方式：`GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`，16 项，落后 0，失败 0。
- 不带令牌时，GitHub 接口会限流返回 403；带上令牌后可以正常查询。

## 其他

- 清空 master 时，已安装的 3.x 检查更新要读的 `assets/version.json` 和 `assets/releases.json` 也被删了，导致更新检查返回 404。已原样恢复（提交 `ac40984d8`），AGENTS.md 里注明不能删。

## Android 构建按 `toolchain.env` 取版本（2026-10-02）

- 问题：`toolchain.env` 写的 compileSdk 37.2、build-tools 37.0.0、NDK 30.0.16248370，`check_latest` 也一直按这三个核对，但构建一个都没用上：

| 项 | 原来实际用的 | 根因 |
|---|---|---|
| compileSdk | 37.0 | `app/build.gradle.kts` 写 `compileSdk = 37`，插件统一成 `compileSdkVersion(37)`，都没有小版本 |
| build-tools | 36.0.0 | 没写 `buildToolsVersion`，用 AGP 9.4.1 的默认值 |
| NDK | 28.2.13676358 | `ndkVersion = flutter.ndkVersion`，即 Flutter 3.47.5 的默认值；要编原生代码的三个插件（`ffmpeg_kit_extended_flutter`、`cnativeapi`、`jni`）也都用它 |

- 做法：`apps/pure_live/android/settings.gradle.kts` 读仓库根目录的 `toolchain.env`，`build.gradle.kts` 用 `ANDROID_COMPILE_SDK`（主版本加 `compileSdkMinor`）、`ANDROID_BUILD_TOOLS`、`ANDROID_NDK_VERSION` 设置应用和每个插件。以后升级只改 `toolchain.env`。
- 验证（云端容器，`flutter build apk --debug --target-platform android-arm64`）：先把 NDK 28.2、build-tools 36.0.0、platform 37.0 移出 SDK，并关掉 AGP 的自动下载，构建照样成功（约 7.7 分钟）；三个插件的 CMake 缓存都指向 `ndk/30.0.16248370`，`.so` 里是 NDK 30 的编译器（clang 21.0.0，r574158c）。同一次改动上 `apps/pure_live` 的 `flutter test` 779 个通过，1 个失败是容器以 root 运行造成的（`backup_page_test.dart` 用 `chmod 000` 造“读不了”，root 不受限制），与本改动无关。
- Kotlin：`KOTLIN_VERSION=2.4.20`，但应用实际用 2.2.10 编译。Flutter 的 `kgpVersion` 任务报 `KGP Version: 2.2.10`，`:app` 的 `kotlinCompilerClasspath` 是 `kotlin-compiler-embeddable:2.2.10`。根因：AGP 9 的内置 Kotlin 用和它同一 classpath 上的 Kotlin Gradle 插件，`settings.gradle.kts` 只放了 AGP，于是用的是 AGP 9.4.1 自己依赖的最低版本 2.2.10。改法：`settings.gradle.kts` 读 `toolchain.env`（`build.gradle.kts` 改为用它读出的结果），在插件声明里加上 `org.jetbrains.kotlin.android`（只放进 classpath，不应用），版本取 `KOTLIN_VERSION`。改后 `kgpVersion` 报 2.4.20，编译器是 `kotlin-compiler-embeddable:2.4.20`。APK 里的 Kotlin 标准库随之从 2.2.20 变为 2.4.20（`debugRuntimeClasspath` 的 `kotlin-stdlib` 全部解析到 2.4.20）；arm64 调试包构建通过。
- AGP 的版本仍然写在 `settings.gradle.kts` 里（和 `AGP_VERSION` 一致）：flutter_tools 用正则从这个文件读 AGP 版本，换成从 `toolchain.env` 读取后它会认不出来。升级 AGP 时两处一起改。
- 要在 K90 上看：三个插件的原生代码换了编译器，Kotlin 代码换了编译器和标准库，录制（FFmpegKit）、播放、`jni` 相关功能和原生部分（通知、画中画、分享接收、悬浮窗）各走一遍。
