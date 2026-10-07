# S04.1 覆盖安装 3.x 验证（和 J06.1 一起做）：任务书

## 背景

- 来源：4.0.0 发布说明对用户写“可以直接覆盖安装 3.x”；功能清点 F-APP-01（升级时导入 3.x 数据）、F-APP-02（网络电视库）是“没验证”，归 [J06.1](../../../J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md) 和本任务。
- 现象：没有已知的坏现象；但 3.x 数据导入至今只用造的 Hive 文件测过（`packages/live_store/test/migration_test.dart`），从没在一台装着 3.x 的设备上真的覆盖过。4.0.0 已经发给用户，用户的升级方式就是覆盖安装。
- 为什么现在做：第一档。一旦覆盖安装有问题（签名对不上装不上、首次启动崩溃、数据没过来），影响每一个从 3.x 升级的用户。
- **不能用 K90**：K90 上的 3.x 是用户每天用的（D-019：不碰 3.x 和正式包）；在 K90 上开第二个系统用户也不行（同一个包名的代码所有用户共用，覆盖会把主空间的 3.x 一起升级）。所以用 **Android 模拟器**（首选）或用户提供的另一台手机。
- 已经做过的：迁移代码（J02.1 设置盒子、L01.2 网络电视库）和它们的单元测试；Y01.1、Y01.2 做 4.0.0 发布时用 `aapt2` 检查过资源；`~/ref/release/v4.0.0-5001/` 里有用户拿到的三个正式包（arm64 versionCode 7001、x86_64 9001，已用 `aapt2 dump badging` 核对）。

## 目标和验收

1. 设备上装着 **3.2.11**（发布页的包，SHA-256 对得上），并按下面“造数据”清单造了一份数据；清单的每一项和它在 3.x 里的值记在 `verify.md`（给 J06.1 对照）。
2. 用 **4.0.0 构建号 5001 的正式包**覆盖安装成功：`adb install -r` 返回 `Success`（或系统安装器显示“更新”而不是“安装”）；`dumpsys package` 里 versionName 4.0.0、versionCode 9001（x86_64）或 7001（arm64），`firstInstallTime` 没变、`lastUpdateTime` 是这次。
3. 两个包的签名证书 SHA-256 一样（`apksigner verify --print-certs`）。
4. 第一次启动：不崩溃、不卡在启动页；`adb logcat` 有 `3.x import: LegacyImportReport(imported: 1, before: 0, failed: 0, …)` 和 `3.x IPTV import: …`，`skippedSecrets: 0`；没有“部分平台需要重新登录”的提示（模拟器的 Keystore 正常时）。
5. 第二次启动：日志是 `imported: 0, before: 1`（不再导入）；第一次启动后在 4.x 里改的东西（例如删掉一个关注）没被 3.x 的数据盖回来。
6. （模拟器能 `adb root` 时）3.x 的 `app_settings.hive` 和 `pure_live_tv.db` 覆盖前后 SHA-256 一样；4.x 的 `files/pure_live.db` 出现。
7. 3.x 时授予的权限（通知、所有文件访问、画中画）和通知类别（`com.mystyle.purelive.audio`）还在。
8. 装完冒烟：首页关注能看到造的关注、进一个直播间能播、录制中心有造的任务、网络电视有造的播放列表、版本页显示 4.0.0 且“已是最新”。
9. 回退：试着用 `adb install -r` 装回 3.2.11，记下系统的报错（预期 `INSTALL_FAILED_VERSION_DOWNGRADE`）；不要用 `-d` 强行降级。
10. 结果写进本文件夹的 `verify.md`（照 `docs/templates/verify.md`），截图在 `verify/`；CHECKLIST 第 4 节第 10 条、第 5 节第 9 条填结果；J06.1 拿到造数据清单和导入后的截图。

## 现状（读代码得出，写文件:行）

- 正式包：`apps/pure_live/android/app/build.gradle.kts:44`（`applicationId = "com.mystyle.purelive"`）、`:42-50`（`minSdk 26`、`targetSdk 37`、版本号取 `apps/pure_live/pubspec.yaml:5` 的 `4.0.0+5001`）；签名 `:9-24`（读 `android/key.properties`，没有就 `:63-75` 用调试密钥 `~/.android-purelive/debug.keystore`）；release 开 R8 和资源压缩。
- 启动时的导入：`apps/pure_live/lib/app/bootstrap.dart:114-135`（只在主窗口）：
  - `legacyHiveFiles()`（`app/data_root.dart:51-58`）在 Android 上找 `<应用文档目录>/PURE_LIVE/HIVE_DB/app_settings.hive`（`packages/live_store/lib/src/legacy/legacy_import.dart:29-31`），即 `/data/data/com.mystyle.purelive/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive`。
  - `LegacyMigration.importHiveFiles`（`legacy_import.dart` 的 `LegacyMigration`）：每个源按 `绝对路径|大小|修改时间毫秒` 记账（meta 键 `legacy.importedSources`；3.x 自己的 `settingsUpgradeImportedSources` 也算），只读字节（`HiveBoxReader`），读失败不记账、下次再试；合并时 4.x 已有的数据优先，关注、历史、分区、屏蔽按身份合并；Cookie 和 WebDAV 密码最后一起加密写入，Keystore 失败只跳过这一步（`skippedSecrets`）。
  - `LegacyReloginNotice.record`（`app/startup.dart:35-37`）：有跳过的凭据时记一笔，启动 1 秒后 `showOnce` 提示“部分平台需要重新登录：从 3.x 导入的登录信息和 WebDAV 密码无法在本机加密保存。”（`legacy_import_relogin`）。
  - `LegacyIptvMigration.importDatabases`（`app/iptv_legacy.dart:104`）：3.x 网络电视库 `<PURE_LIVE>/IPTV_CACHE/pure_live_tv/pure_live_tv.db`（`:16-25`）先复制到临时目录再用 sqlite 打开（`:152-164`），本地播放列表文件复制到 4.x 的播放列表目录（`:414`）。
  - 两次导入的结果都 `log('3.x import: $report', name: 'AppBootstrap')`，在 `adb logcat` 里能看到。
- 录制设置里 3.x 的值：导入时停在 `legacy_values`，录制服务启动时 `LegacyMigration.adoptLegacyValues`（`app/recording.dart:254`）接管。
- 丢掉的 3.x 键：`audioOnly`、`taobaoCookie` 等（`legacy_snapshot.dart:419`，3.x 自己启动时也删）。
- 4.x 的数据库：`/data/data/com.mystyle.purelive/files/pure_live.db`（`data_root.dart:21-27` 取应用支持目录；文件名 `packages/live_store/lib/src/live_store.dart:165`）。
- 旧关注换成主播身份（F-FAV-08，niconico、YouTube、抖音按场次存的关注）：`migration_test.dart:261` 的用例；启动后 `AppServices.followsReady` 在后台做。

## 3.x 基线

- 包：GitHub `wzgrx/pure_live` 发布页 `v3.2.11`（2026-09-27），`PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk`（模拟器用）、`…-arm64-v8a-release.apk`（备用机用），`SHA256SUMS.txt` 核对；包名 `v3.2.11:android/app/build.gradle.kts:49`，`minSdk 26`（`:53`），签名写法 `:74-78`。
- 数据位置：`v3.2.11:lib/common/global/initialized.dart:65`（`AppPathManager().getDir(AppPathManager.dirHiveDB)`）；3.x 自己的升级导入 `:69` 调 `SettingsUpgradeMigration.migrate`（`lib/common/services/utils/settings_upgrade_migration.dart:29`，账本键 `:32`）。
- 要保留的：3.x 的设置键名和含义（D-018），所以导入后设置的效果应该和 3.x 一样（例如弹幕速度、首选清晰度）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机验证、第 11 节发布、第 14 节规则）。
2. 本文件夹的 `README.md`、本子分类的 `README.md`（“覆盖安装时发生什么”）。
3. `docs/J-设置和数据/J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md`（同一次做，它要的数据清单）；`docs/Y-发布和运营/Y01-版本签名和发布/Y01.1-4.0.0发布前修复/record.md` 的 release 构建一节（`aapt2` 的用法）。
4. 代码：`apps/pure_live/lib/app/bootstrap.dart:80-137`、`packages/live_store/lib/src/legacy/legacy_import.dart`、`apps/pure_live/lib/app/iptv_legacy.dart:1-170`。

## 范围

- 可以改：本文件夹（`verify.md`、`verify/`、README 的结果）；CHECKLIST 第 4 节第 10 条、第 5 节第 9 条的“结果”；`docs/inventory/FEATURES.md` 的 F-APP-01、F-APP-02（和 J06.1 一起改）。
- 不能改：任何代码；签名文件和密钥（不进 git、不出现在记录里）；版本号、`assets/version.json`、`assets/releases.json`；K90 和它上面的 3.x、正式包；Windows 上 `D:\Soft\PureLive`、`D:\Soft\pure_live`。
- 不能做：在 K90 上装正式包；把模拟器里取出的 `app_settings.hive`、`pure_live_tv.db` 放进仓库（里面有造的 Cookie 和地址；要做测试样本先交给 J06.1 脱敏）；用 `adb install -d` 强行降级。

## 方案和阶段

登记表没有阶段（规模“小”）；按下面三步做，每步结束存模拟器快照。建议登记表改成三个阶段、规模“中”（维护者做）。

| 阶段 | 做什么 | 怎么算做完 |
|---|---|---|
| 1 准备 | 建模拟器；装 3.2.11；按清单造数据；导出一个 3.x 备份；（`adb root`）取出 3.x 两个文件的 SHA-256；存快照“v3-data” | 清单每项在 `verify.md` 有记录；快照存好 |
| 2 覆盖 | 核对证书和版本号；`adb install -r` 4.0.0+5001 正式包；第一次启动看日志、看首页；第二次启动看日志；文件 SHA-256；权限和通知类别；冒烟 | 验收 2～8 有结果；J06.1 能开始逐项对照 |
| 3 回退和收尾 | 装回 3.2.11 看报错；（master 代码有变化时）回到快照“v3-data”，用 master 的 release 构建再覆盖一次，重复阶段 2 的检查；写 `verify.md`、填 CHECKLIST | 验收 9、10 有结果 |

### 阶段 1：准备

模拟器（Windows 上，`C:\Users\123\AppData\Local\Android\Sdk` 已有 `emulator`，还没有系统镜像和虚拟机；也可以在 WSL 里用 `~/Android/Sdk`，本机有 `/dev/kvm`）：

```bash
# 镜像：Google APIs（不是 Google Play，才能 adb root），x86_64，Android 15（API 35）
sdkmanager "system-images;android-35;google_apis;x86_64" "emulator" "platform-tools"
avdmanager create avd -n pl_v3 -k "system-images;android-35;google_apis;x86_64" -d pixel_7
emulator -avd pl_v3 -no-snapshot-load        # 第一次冷启动
adb devices                                   # 记下 emulator-5554 这类序列号，下面都用 -s 指定，别连到 K90
```

3.2.11（在仓库外的临时目录，例如会话的 scratchpad）：

```bash
gh --repo wzgrx/pure_live release download v3.2.11 -p '*x86_64-release.apk' -p 'SHA256SUMS.txt'
sha256sum -c --ignore-missing SHA256SUMS.txt
~/Android/Sdk/build-tools/37.0.0/aapt2 dump badging PureLive-3.2.11-4134-*-x86_64-release.apk | head -1   # versionCode 应是 8134
adb -s emulator-5554 install PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk
```

造数据（在 3.x 里手动做，每项记下名字和值）：

| # | 数据 | 怎么造 | 4.x 里对应看哪里（J06.1 对照） |
|---|---|---|---|
| 1 | 关注 12 个以上 | 哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易 CC 各 1～2 个；niconico、YouTube 各 1 个（按场次存的旧关注，F-FAV-08）；至少 1 个没开播的 | 关注页；niconico、YouTube、抖音的换成主播身份后能刷新 |
| 2 | 观看记录 5 条以上 | 进 5 个不同的直播间各看 10 秒 | 观看记录（顺序） |
| 3 | 自定义标签 2 个 | 3.x 的“自定义标签”加两个，给几个关注设上 | 标签管理、关注页按标签筛选 |
| 4 | 屏蔽 | 弹幕屏蔽加 2 个关键词、1 个用户 | 设置 → 视频 → 弹幕屏蔽 |
| 5 | 设置改 8 项以上 | 主题颜色、深色模式、弹幕速度和透明度和字号、首选清晰度、移动网络清晰度、后台播放开、关注自动刷新开和间隔、平台显示顺序（拖一下）、录制目录 | 对应的设置页显示同样的值 |
| 6 | 账号（假的） | 虎牙 Cookie 填 `pl_s041=1`（不要用真实账号）；哔哩哔哩不登录 | 平台账号：虎牙“已设置”；没有“需要重新登录”的提示 |
| 7 | WebDAV 配置 | 添加一个 `http://192.0.2.10/dav/`、用户 `s041`、密码 `s041` 的配置（假地址，不测连接） | WebDAV 页有这个配置，密码已存 |
| 8 | 录制任务 | 给没开播的关注加“开播自动录”；（可选）录一个直播间 30 秒 | 录制中心有这两个任务，状态对 |
| 9 | 网络电视 | 导入一个本地 m3u（推一个小文件到 `/sdcard/Download/`）和一个远程订阅地址；收藏一个频道 | 网络电视两个播放列表、收藏 |
| 10 | 关注的分区 | 分区页关注 2 个分区 | 关注的分区页 |
| 11 | 3.x 备份 | 3.x 的备份页导出一个完整备份，`adb pull` 到会话的 scratchpad | 给 S02.4 第 1 阶段“恢复 3.x 备份”用 |
| 12 | 权限 | 允许通知；打开后台播放（会要电池优化）；（可选）录制目录选公共目录时允许所有文件访问 | 覆盖后 `dumpsys package` 里还是 granted |

```bash
adb -s emulator-5554 root
adb -s emulator-5554 shell sha256sum /data/data/com.mystyle.purelive/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive \
  /data/data/com.mystyle.purelive/app_flutter/PURE_LIVE/IPTV_CACHE/pure_live_tv/pure_live_tv.db
adb -s emulator-5554 shell dumpsys package com.mystyle.purelive | grep -E "versionCode|versionName|firstInstallTime|lastUpdateTime|granted=true"
adb -s emulator-5554 shell cmd notification list_channels com.mystyle.purelive 0   # 记下通知类别
# 把两个文件复制到 scratchpad 留底（不进仓库）：adb pull …
# 模拟器窗口里“快照”存一个 v3-data
```

### 阶段 2：覆盖

```bash
APK4=~/ref/release/v4.0.0-5001/PureLive-4.0.0-5001-debug-signed-android-x86_64-release.apk
APK3=<scratchpad>/PureLive-3.2.11-4134-debug-signed-android-x86_64-release.apk
~/Android/Sdk/build-tools/37.0.0/apksigner verify --print-certs "$APK3" | grep SHA-256
~/Android/Sdk/build-tools/37.0.0/apksigner verify --print-certs "$APK4" | grep SHA-256    # 两行一样
~/Android/Sdk/build-tools/37.0.0/aapt2 dump badging "$APK4" | head -1                      # versionCode='9001'
adb -s emulator-5554 logcat -c
adb -s emulator-5554 install -r "$APK4"                                                    # Success
adb -s emulator-5554 shell monkey -p com.mystyle.purelive -c android.intent.category.LAUNCHER 1
adb -s emulator-5554 logcat -d | grep -E "AppBootstrap|3.x import|3.x IPTV import|FATAL|Exception"
```

| 步骤 | 期望 |
|---|---|
| 1. 覆盖前看两个包的证书和版本号 | 证书 SHA-256 一样；4.x versionCode 9001 > 3.x 8134 |
| 2. `adb install -r` 4.x | `Success`；不是 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`（证书不同）或 `INSTALL_FAILED_VERSION_DOWNGRADE` |
| 3. `dumpsys package com.mystyle.purelive` | versionName 4.0.0、versionCode 9001；`firstInstallTime` 和阶段 1 记的一样，`lastUpdateTime` 是刚才；阶段 1 记的 `granted=true` 权限还在 |
| 4. 第一次打开 | 启动画面 → 启动页 → 首页，不崩溃、不卡住（10 秒内到首页）；日志 `3.x import: LegacyImportReport(imported: 1, before: 0, failed: 0, follows: N, history: M, skipped: k, skippedSecrets: 0)`，N、M 和造的数对得上；`3.x IPTV import:` 一行导入了 2 个播放列表；没有 FATAL |
| 5. 等 2 秒 | 没有“部分平台需要重新登录……”提示（Keystore 正常）；出现了就记下 `skippedSecrets` 的数，再重启确认只出一次 |
| 6. 首页关注、观看记录、标签、录制中心、网络电视、设置的几项、平台账号、WebDAV、关注的分区 | 造的数据都在（逐项对照交给 J06.1，这里只看“有”）；niconico、YouTube、抖音的关注刷新后状态正常（CHECKLIST 4.10） |
| 7. 删掉一个关注；`adb shell am force-stop com.mystyle.purelive` 后再打开 | 日志 `imported: 0, before: 1`；删掉的关注没有回来 |
| 8. `adb root` 后再算两个 3.x 文件的 SHA-256；`ls -l /data/data/com.mystyle.purelive/files/` | 和阶段 1 一样；`pure_live.db` 在 |
| 9. `cmd notification list_channels com.mystyle.purelive 0` | 3.x 的 `com.mystyle.purelive.audio` 还在，用户在 3.x 里对它的设置没变；多了 4.x 的“录制”“录制提醒” |
| 10. 冒烟：进一个国内直播间看 30 秒；开后台播放按 Home；录制中心点那个任务；版本页 | 能播；后台播放通知的小图标和“暂停”“停止”正常（release 包的资源压缩没删掉图标）；任务状态对；版本页 4.0.0、检查更新说已是最新 |

### 阶段 3：回退和收尾

| 步骤 | 期望 |
|---|---|
| 11. `adb -s emulator-5554 install -r "$APK3"` | 失败，记下原文（预期 `INSTALL_FAILED_VERSION_DOWNGRADE`）；应用和数据不受影响 |
| 12. （master 在 `v4.0.0` 之后改过 `apps/`、`packages/` 时）模拟器回到快照“v3-data”；在 WSL 里 `cd apps/pure_live && flutter build apk --release --split-per-abi --target-platform android-x64`（门禁不在跑的时候；没有 `key.properties` 时用调试密钥，看构建日志里的警告）；用 `build/app/outputs/flutter-apk/app-x86_64-release.apk` 重复第 1～10 步 | 结果同上；记下提交号 |
| 13. 写 `verify.md`、填 CHECKLIST、把造数据清单和截图交给 J06.1 | — |

备用机（用户提供的 arm64 手机）代替模拟器时：用 arm64 包（3.x 6134 → 4.x 7001）；没有 root 时第 8 步跳过；其余一样。

## 测试

- 本任务不写自动测试。发现的问题（例如某类数据没过来）交给 J06 先写改之前会失败的测试（用阶段 1 取出的文件脱敏后做样本）再修。

## 真机验证（维护者在模拟器或备用机上做）

见上面阶段 1～3 的表（第 1～13 步）。全程不连 K90：每条 `adb` 都带 `-s emulator-5554`（或备用机的序列号）。

## 风险和注意

- **别连错设备**：电脑上同时连着 K90（`192.168.1.2:5555`）时，`adb install` 不带 `-s` 会报“more than one device”，带错了会把正式包装到 K90 上覆盖用户的 3.x。每条命令都写 `-s`，开始前 `adb devices` 看清楚。
- 模拟器要 Google APIs 镜像才能 `adb root`；Google Play 镜像没有 root，第 8 步只能跳过。
- 造数据用假的 Cookie 和 WebDAV 账号；取出的文件放仓库外，用完删掉。
- 远程订阅地址、直播间要联网；模拟器的网络是 NAT，能上网但和局域网设备互相看不见（设备同步不在本任务）。
- release 构建会和门禁、测试包构建抢生成的文件：门禁运行时不要构建（PROCESS 第 8 节第 5 条）。
- 模拟器的 Keystore 是软件实现，和真机不同；“需要重新登录”的路径在真机（K02.1）上才有意义。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）；需要构建时根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 本机工作区；只提交文档：提交信息以 `[S04.1]` 开头（英文），例如 `[S04.1] install over 3.2.11 on an emulator: results`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：模拟器存快照（写清快照名和它停在哪一步）；已做的步骤写进 `verify.md` 提交；在末尾写“停在哪”；登记表 `next` 写下一步。

## 报告（中文，简洁）

每一步的结果（第 1～13 步）；日志里两次导入的原文；证书和版本号；没过来的数据（交给 J06.1 的清单）；回退的报错原文；发现的问题（现象、根因线索、建议去向）；需要维护者决定的（发布说明要不要写“回退前先备份”、要不要把脱敏的 3.x 文件做成样本、登记表规模和阶段）。
