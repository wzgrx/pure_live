# Z01.2 例行依赖升级检查：记录

## 2026-10-08

- `GITHUB_TOKEN=$(gh auth token) dart run tools/check_latest/bin/check_latest.dart`：59 项，8 项落后，查询全部成功。
- 升了 6 个 pub 包（都在原约束内，只改 `pubspec.lock`）：url_launcher 6.3.2 → 6.3.3、drift 2.35.1 → 2.35.2、connectivity_plus 7.3.1 → 7.3.2、hive_ce 2.20.1 → 2.20.2、share_plus 13.3.0 → 13.3.1、material_ui 1.5.0 → 1.6.0。`tools/gate/gate.sh --all` 通过（14 个成员）。
- 没升：Flutter 3.47.5 → 3.47.6、Gradle 9.8.0 → 9.8.1（工具链，要换本机 SDK；当时有多个代理在用同一个 SDK 跑测试，下次一并升，改 `toolchain.env` 后跑门禁和一次 APK 构建）。
- 工具链（同日第二轮）：Flutter 3.47.5 → 3.47.6（Dart 3.13.5）、Gradle 9.8.0 → 9.8.1（`gradle-wrapper.properties` 的 sha256 取自 `services.gradle.org`，和本机下载的包一致）；`toolchain.env` 新增 `ANDROID_PLATFORM_TOOLS=37.0.1`、`ANDROID_CMDLINE_TOOLS=23.0`、`ANDROID_CMAKE_VERSION=4.1.2`，`check_latest` 也查这三项（14 项、落后 0）。AGP 9.4.1、Kotlin 2.4.20、JDK 27（本机 27.0.0+35）、compileSdk 37.2、build-tools 37.0.0、NDK 30.0.16248370 本来就是最新。
- 查出的偏差（根因）：`toolchain.env` 写着 NDK 30.0、compileSdk 37.2，但 `app/build.gradle.kts` 是 `compileSdk = 37`、`ndkVersion = flutter.ndkVersion`（Flutter 3.47 默认 28.2.13676358），插件模块用 AGP 默认的 NDK 和 CMake 3.22.1——上次构建日志里 376 处 `ndk/28.2`、144 处 `cmake/3.22.1`。改成 `android/build.gradle.kts` 读 `toolchain.env`，给 app 和全部插件模块设 `compileSdk` 37 + `compileSdkMinor` 2、`buildToolsVersion`、`ndkVersion`，有 C/C++ 的插件（`jni`、`cnativeapi`、`ffmpeg_kit_extended_flutter`）设 CMake 4.1.2 并加 `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`（`ffmpeg_kit_extended_flutter` 要求 CMake 3.4.1，CMake 4 不接受低于 3.5）；顺带把已弃用的 `BaseExtension` 换成 `CommonExtension`。
- `test_api 0.7.14` 的覆盖仍然需要（3.47.6 的 flutter_test 还是锁 0.7.12），只改了注释里的版本。
- 验证：`flutter build apk --release --target-platform android-arm64` 通过（125.4 MB，lint 通过），日志里只有 Gradle 9.8.1、`platforms/android-37.2`、`build-tools/37.0.0`、`ndk/30.0.16248370`、`cmake/4.1.2`；`tools/gate/gate.sh --all` 通过。
- 下次：2026-11 上旬。
