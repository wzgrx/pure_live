# Z04 构建和装机

怎么在本机构建 Android 的测试包和正式包、录制用的 FFmpeg 原生包怎么准备，以及把测试包装到 K90、截图、带前台检查地点按的助手。

## 范围

- 包括：
  - `apps/pure_live/android/app/build.gradle.kts` 的三种构建类型（debug、profile、release）、包名后缀、资源压缩和保留表 `res/raw/keep.xml`、release 签名的读取逻辑（签名方案本身在 Y01）。
  - `tools/ffmpeg_kit/`（`fetch.sh`、`fetch.ps1`、`bundles.txt`）：录制用的 FFmpeg 9.0.2 原生包下载、校验、缓存和链接。
  - 本机环境脚本 `~/tools/purelive-env.sh`、装机和截图助手 `~/tools/pl-adb.sh`（都在仓库外，Z04.1 要把助手放进仓库）。
- 不包括（归哪里）：
  - 版本号、正式包的签名、发布页、`SHA256SUMS` → Y01。
  - Windows、Linux、苹果平台的构建 → X01.3、X02.1、X04.1。
  - 真机上看什么、结果写在哪 → S02（`CHECKLIST.md`）和各任务的 `verify.md`。
  - 基准测试的构建（`flutter drive --profile`）→ R01。
  - 工具链版本 → Z01。

## 现状：做到哪、怎么工作的

- 三种构建（`build.gradle.kts:64-92`）：

| 类型 | 包名 | 应用名 | 签名 | 压缩 | 用途 |
|---|---|---|---|---|---|
| debug | `com.mystyle.purelive.v4dev`（`applicationIdSuffix = ".v4dev"`） | 纯粹直播 v4dev | 调试密钥 | 关 | 开发 |
| profile | 同上 | 纯粹直播 v4dev | 调试密钥 | 照 release | 真机验证、基准测试 |
| release | `com.mystyle.purelive`（覆盖安装 3.x） | 纯粹直播 | 有完整的 `android/key.properties` 用它，否则用调试密钥并打警告；`-PpureLive.requireReleaseSigning=true` 时缺了直接失败（`:9-25`、`:66-71`） | `isMinifyEnabled`、`isShrinkResources`，ProGuard 规则 `proguard-rules.pro` | 发布 |

  测试包和正式包并存，不碰用户的 3.x（D-019）。`minSdk = 26`、`targetSdk = 37`、`compileSdk = 37`；versionCode 由 Flutter 按 ABI 算：`--split-per-abi` 时 armeabi-v7a、arm64-v8a、x86_64 分别是 `1000、2000、4000 + 构建号`（构建号 5001 → 6001、7001、9001，PROCESS 第 11 节）。
- 调试密钥：环境脚本设 `ANDROID_USER_HOME=~/.android-purelive`，Gradle 用其中的 `debug.keystore`；这把密钥和 Windows 主机共用，也是 3.2.11 正式包的签名密钥，所以本机构建的正式包能覆盖安装 3.x（D-006，细节在 Y01）。
- 资源压缩的坑：只在 Dart 里按名字引用的资源会被压缩器删掉，`res/raw/keep.xml` 保留 `ic_stat_playback` 和 audio_service 的三个媒体按钮图标（Y01.1 第 1 条：删掉后 Android 13 起媒体通知和前台服务起不来），`test/platform/system_surfaces_test.dart` 守着。
- FFmpeg 包：`bundles.txt` 写 3 个包（Android `.aar`、Linux、Windows 的 zip）和 SHA-256；`fetch.sh [android|linux|windows]` 下载到 `~/.cache/pure_live/ffmpeg_kit/`（可用 `PURE_LIVE_FFMPEG_KIT_CACHE` 改），校验后链接进 `<仓库>/.ffmpeg_kit/`（`.gitignore` 排除）；根 `pubspec.yaml` 的 `ffmpeg_kit_extended_config` 指向这些本地路径，因为插件的构建钩子遇到远程地址每次都重新下载。克隆或新建工作区后先跑一次；门禁在改了应用时自动跑 `fetch.sh linux`（`flutter test` 要构建 Linux 那一份）。
- 常用命令：测试包 `flutter build apk --profile --split-per-abi`（在 `apps/pure_live`），装机 `adb -s 192.168.1.2:5555 install -r build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk`；正式包 `flutter build apk --release --split-per-abi`（门禁不在跑时）。构建产物在 `apps/pure_live/build/`（`.gitignore` 排除）；4.0.0 两次发布的正式包和 `SHA256SUMS.txt` 留在本机 `~/ref/release/v4.0.0/`、`v4.0.0-5001/`。
- 装机和截图助手（仓库外，`~/tools/pl-adb.sh`，16 行，`source` 后用）：`fg` 读前台应用；`need_pl` 前台不是 `$PL_APP` 就中止；`tap`、`key`、`text`、`swipe` 每次先 `need_pl`；`shot` 截屏到会话的 scratchpad；`ui`、`tapl` 用 `uiautomator dump` 按文字找控件。**默认 `PL_APP` 还是旧的 `com.mystyle.purelive.next`**，用之前要 `export PL_APP=com.mystyle.purelive.v4dev`；截图路径写死成某一次会话的 scratchpad。
- 完成度：构建和 FFmpeg 包都在用；Z04.1（助手进仓库）未开始。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/android/app/build.gradle.kts`（112 行） | 读 `key.properties`（`:9-25`）、`defaultConfig`（`:42-51`，包名、SDK、versionCode/Name、应用名占位）、签名（`:53-62`）、三种构建类型（`:64-92`）、Flutter 任务不进配置缓存（`:106-112`） |
| `apps/pure_live/android/app/proguard-rules.pro` | release 的代码压缩规则 |
| `apps/pure_live/android/app/src/main/res/raw/keep.xml` | 资源压缩时保留只在 Dart 里引用的 4 个图标 |
| `apps/pure_live/android/gradle.properties` | Gradle 内存、并行、配置缓存、AGP 内置 Kotlin |
| `tools/ffmpeg_kit/bundles.txt` | 3 个 FFmpeg 包的文件名、SHA-256、下载地址（`native-ffmpeg-9.0.2-b1`） |
| `tools/ffmpeg_kit/fetch.sh`（WSL/Linux）、`fetch.ps1`（37 行，Windows） | 下载、校验、缓存、链接；可按平台筛选 |
| 根 `pubspec.yaml:66-72` | `ffmpeg_kit_extended_config`：三个平台的本地包路径 |
| `~/tools/purelive-env.sh`（仓库外） | Flutter、JDK、Android SDK、`ANDROID_USER_HOME`、`GRADLE_USER_HOME`、代理、Flutter 镜像 |
| `~/tools/pl-adb.sh`（仓库外，16 行） | 装机后点按和截图的助手（见上） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 只在 Dart 里引用的图标都在 `keep.xml` 里；各插件的权限请求码不重复 |
| （没有） | `build.gradle.kts` 的签名分支、`fetch.sh` 都没有自动测试；靠构建和 `aapt2 dump`、`apksigner verify` 核对 |

## 3.x 基线

- 3.x 的构建在 GitHub Actions（`git show v3.2.11:.github/workflows/local-signed-android.yml`、`publish-signed-android.yml`、`build_pure_live_release.yml`），本地有 `tool/` 下的构建脚本；包名 `com.mystyle.purelive`，正式包文件名 `PureLive-<版本>-<构建号>-debug-signed-android-<ABI>-release.apk`（4.x 沿用这个命名）。
- 3.x 的 `android/app/src/main/res/raw/keep.xml` 保留的正是 audio_service 的三个图标（Y01.1 第 1 条的依据）。
- 3.x 没有独立的测试包：开发版和正式版同包名（4.x 改成 `.v4dev`，和用户的 3.x 并存）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 装机助手不在仓库里，其他执行者（其他 AI、换机器）用不了；默认 `PL_APP` 是旧包名 `.next`，截图路径写死成某次会话的 scratchpad | `~/tools/pl-adb.sh:4`、`:7` | 忘了改 `PL_APP` 时前台检查拦住所有输入；截图落到别的会话目录 | Z04.1 |
| `build.gradle.kts` 的注释写“Release signing (docs/specs/ENGINEERING.md §9)”，ENGINEERING 只有 7 节 | `apps/pure_live/android/app/build.gradle.kts:9` | 按注释找不到说明 | Z06 已知问题统一记；改时指向 Y01 |
| `docs/specs/ENGINEERING.md` 第 6 节和 AGENTS.md 说 `apps/pure_live` 有 Linux，但仓库里没有 `linux/` 运行器 | `AGENTS.md`“目录”一节 | 文档和代码不符 | X02.1 |
| 构建时 FFmpeg 构建钩子遇到远程地址会每次重新下载；现在靠本地路径绕开，换包时 `bundles.txt` 和根 `pubspec.yaml` 两处要一起改 | `tools/ffmpeg_kit/bundles.txt` 注释、根 `pubspec.yaml:56-65` 注释 | 只改一处会构建失败或用旧包 | 两处注释都写了；没有任务 |
| 门禁和正式包构建不能同时在一份代码里跑 | PROCESS 第 8 节第 5 条 | 互相改生成的文件 | 规则；没有技术上的锁 |

## 相关决定和规范

- D-006（正式包用维护者调试密钥签名，签名文件不进 git）、D-019（K90 随时可用，只点测试包，不碰 3.x 和正式包）、D-007（版本号只在发布时改）。
- ENGINEERING 第 3 节（只在本机构建、FFmpeg 包）、第 6 节（测试包和正式包）；PROCESS 第 10 节（真机验证的设备和规则）、第 11 节（发布的构建步骤）。

## 测试和验证

- 构建通过就是证据：`flutter build apk --profile --split-per-abi`、`--release --split-per-abi` 成功；正式包用 `aapt2 dump badging` 看包名和 versionCode，`apksigner verify --print-certs` 看证书（命令在 Y01 的说明里）。
- 装机后的检查按 S02 的 [CHECKLIST.md](../../S-质量和验证/S02-真机验证/CHECKLIST.md)。

## 路线

1. Z04.1（第三档，小）：把装机和截图助手放进仓库（`tools/device/`），包名默认 `.v4dev`、设备和截图目录可配置，带前台检查；S02、各任务的 `verify.md` 改用它。
2. 以后加 Windows、Linux 构建时（X01.3、X02.1），各平台的构建命令和产物位置写进这里或对应的 X 子分类。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`apps/pure_live/android/`、`tools/ffmpeg_kit/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z04.1 | 装机和截图助手进仓库：K90 截图、带前台检查的点按 | 工程 | 完成 | 2026-10-08 | — | [设计或说明](Z04.1-装机和截图助手进仓库/README.md)、[任务书](Z04.1-装机和截图助手进仓库/brief.md)、[记录](Z04.1-装机和截图助手进仓库/record.md) |

<!-- docs:生成结束 -->
