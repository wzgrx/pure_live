# 第 0 阶段诊断：原生代码、构建与工程

范围：android/、windows/、linux/、macos/、ios/、tool/、.github/、三份策略文件、AGENTS.md、docs/。全程只读，没有改动仓库里的任何文件。GitHub 远端只做了查询：`gh run list`、`gh secret list`。

## ① Android 原生

| 文件 | 行数 | 作用 | v4 处置 |
|---|---:|---|---|
| `android/app/src/main/kotlin/com/mystyle/pure_live/MainActivity.kt` | 378 | 继承 AudioServiceActivity，有三个通道：<br>• `pure_live/display_mode`：设置 preferredRefreshRate，显示器变化时回推<br>• `pure_live/background_playback`：后台播放时持有 WakeLock 和 WifiLock<br>• `pure_live/predictive_back`：以 PRIORITY_OVERLAY 优先级抢在 Flutter 之前处理全屏返回，另有 onBackPressed 兜底<br>onResume 时把音量键绑定到媒体音量 | 重写。高刷和保活移入新的原生插件包；预测性返回改用 Flutter 自带机制 [待确认：全屏返回场景是否够用] |
| `RecorderBackgroundPlugin.kt` + `RecorderForegroundService.kt` | 557+249 | `pure_live/recorder_background`：dataSync 类型的前台服务<br>• 按代次隔离<br>• 启动和停止各有 15 s 超时<br>• 系统触发 onTimeout 后留 45 s 排空<br>• 通过绑定 AudioService 保住 Flutter 引擎，并持有 Wake/Wifi 锁 | 重写进 live_record 的 Android 部分，状态机写进规格。Android 15 起 dataSync 每天限 6 小时 [待确认：长时间录制怎么办] |
| `NativeHttpChannel.kt` + `NativeHttpPlugin.kt` | 129+17 | `pure_live/native_http`：只放行 gql.twitch.tv 的 POST，用 HttpURLConnection 绕开 dart:io 走 CONNECT 代理时的 TLS 问题 | 删除，由 live_net 的 cronet_http 统一解决 |
| `src/debug/…/ShareIntentProbe{Receiver,Provider}.kt`、`RecorderLifecycleProbeReceiver.kt` | 281 | 只在 debug 包里，供 adb 脚本模拟多附件分享和录制生命周期 | 删除，改用 integration_test 或 patrol |
| `GeneratedPluginRegistrant.java` | — | 生成文件，未入库，共 41 个插件 | — |

以下功能都靠插件实现，没有自写的原生代码（见 `pubspec.yaml:185,215-218`）：
- 画中画：floating（本地补丁版）
- 通知栏、锁屏控制、耳机线控：audio_service
- 分享接收：share_handler
- 链接打开：app_links

**Manifest**（`android/app/src/main/AndroidManifest.xml`）

| 类别 | 内容 | 处置 |
|---|---|---|
| 保留 | INTERNET、ACCESS/CHANGE_NETWORK_STATE、ACCESS_WIFI_STATE、WAKE_LOCK、FOREGROUND_SERVICE（含 MEDIA_PLAYBACK、DATA_SYNC）、POST_NOTIFICATIONS、ACCESS_LOCAL_NETWORK（Android 17 局域网代理，3.2.7 回归的教训）、REQUEST_INSTALL_PACKAGES（应用内更新）、READ_MEDIA_VIDEO/AUDIO | 保留 |
| 需复核 | MANAGE_EXTERNAL_STORAGE + requestLegacyExternalStorage（录制目录，`lib/plugins/file_utils.dart`）；REQUEST_IGNORE_BATTERY_OPTIMIZATIONS；全局允许明文流量（`res/xml/network_security_config.xml`） | 改用 SAF 或应用私有目录 [待确认] |
| 疑似无用 | SYSTEM_ALERT_WINDOW、FOREGROUND_SERVICE_REMOTE_MESSAGING、VIBRATE；speech RecognitionService、PROCESS_TEXT、unilink 三个 queries（lib/ 里搜不到引用） | 删除 [待确认] |
| 组件 | MainActivity（singleTask、画中画、LEANBACK_LAUNCHER + banner、VIEW 协议 mystyle/purelive/file/content、SEND/SEND_MULTIPLE 共 8 种 MIME、share_targets）；AudioService + MediaButtonReceiver；RecorderForegroundService；FileProvider | 语义保留，代码重写 |

**Gradle 与杂项**

| 位置 | 现状 | v4 |
|---|---|---|
| `app/build.gradle.kts` | compileSdk/targetSdk 37；minSdk 26（注释里的理由是 FFmpegKit）；编译目标 Java 17；开启 R8；仍在应用 google-services 插件；proguard 里还有 IJK 和 Exo 的规则 | 删掉 Firebase、IJK、Exo 相关配置；minSdk 的理由改为引用宪法决定 |
| `gradle.properties` | enableJetifier、skipDependencyChecks、dependency.verification=off、warning.mode=none、newDsl=false | 这些都是用来压警告的开关，全部清理 |
| `android/build.gradle.kts` | 从 `../plugins/flv_lzc/android/libs` 取 16 KB 对齐的 fplayer-core；强制所有插件 compileSdk 37、minSdk 26 | 搬到 apps/legacy 时要同步改相对路径；第 5 阶段去掉 IJK 后删除 |
| Manifest 与目录 | Manifest 里的 `package=` 与 namespace 重复；Kotlin 目录名是 `pure_live`，包名是 `purelive`；没有单色主题图标（`mipmap-anydpi-v26/ic_launcher.xml`） | 新应用修正 |

**签名**

没有 `android/key.properties` 时，release 构建只打一条警告，就悄悄改用 debug 证书，不会失败（`build.gradle.kts:73-78`）。

| 证书 SHA-256 | 签过哪些版本 | 私钥在哪 |
|---|---|---|
| `1e832295…`（本机 debug keystore） | v3.1.1–v3.2.11 的全部正式版（`assets/releases.json` 里的文件名带 debug-signed；另见 `README.md:407`） | Codex 那台 Windows 机器用户目录下的 `.android`；WSL 有一份副本 |
| `c0bb9574…`（仓库 Secrets `PURELIVE_*`） | v2.7–v3.0.23；`sign-staged-android.yml:41` 仍然固定这个指纹 | GitHub Secrets，但 Secret 无法导出原文件 |
| `14a346b1…` | 上游 liuchuancong 的安装包 | 拿不到 |

| 签名结论 | 说明 |
|---|---|
| 正式密钥可以沿用 c0bb | 做一条 1e83→c0bb 的轮换谱系，3.0.x 和 3.1+ 两批用户都能覆盖安装 [待确认：用户手里还有 c0bb 的原始 keystore] |
| Android 8 的限制 | minSdk 是 26，Android 8 只校验 v2 签名，所以以后每次发布都要用旧 debug 密钥签 v1/v2、新密钥签 v3 [待确认：需实测]。因此 debug keystore 已经成了必需资产，要先备份进 Secrets |
| 现有工作流的签名风险 | `feature-build.yml` 用 c0bb 签名，拿它发的包无法覆盖安装在现有用户手机上；`build_pure_live_release.yml` 引用的 `KEYSTORE_BASE64`、`CERTIFICATE` 两个 Secret 根本不存在 |

## ② Windows 与其它平台

| 文件 | 作用 | v4 处置 |
|---|---|---|
| `windows/runner/main.cpp` | 无参数启动时，在创建引擎之前用互斥体 `Local\PureLive_Primary_Instance_v1` 拦下重复启动，并把已有窗口置前；设置 AUMID；退出时直接调用 TerminateProcess，避免插件 DLL 卸载时卡住 | 保留思路，代码重写 |
| `flutter_window.cpp` | `pure_live/display_mode` 通道：枚举当前显示器支持的刷新率，在 WM_MOVE、WM_DISPLAYCHANGE、WM_DPICHANGED 时回推；析构时加了保护，防止子窗口回调导致崩溃 | 保留，接口改用 Pigeon 生成 |
| `win32_window.cpp`、`utils.cpp` | 前者按 STARTUPINFO 决定窗口的显示方式（深色标题栏是模板自带的）；后者落后于 Flutter 3.47.5 的模板，缺少 CWE-126 越界修复 | 用最新模板重新生成，再把改动补上 |
| 多实例 | `lib/common/utils/windows_multi_instance_launcher.dart`：每个窗口是一个独立进程、用一份独立的 Hive，靠 `--instance`、`--open-room`、`--config-file` 参数启动；pub 包 windows_single_instance 负责转发参数 | 建议改成在 C++ 里用命名管道转发，去掉这个插件 |
| `plugins/windows_single_instance/` | 目录里只剩一个孤立的 pubspec.lock | 删除 |
| `windows/CMakeLists.txt` | 随包带 msvcp140、vcruntime140、vcruntime140_1 三个运行库，缺一个就构建失败 | 保留 |
| 打包 | 现在有两套 Inno Setup 脚本：<br>• 本地用 `packaging/exe/local_release.iss`：普通用户权限安装、沿用旧安装目录、写搬迁账本 `AppData\previous_install_locations.txt`<br>• CI 用 fastforge 的模板 `inno_setup.iss`，没有搬迁逻辑<br>MSIX 方面：发布者是占位符，证书 Secret 缺失，`windows_msix_available=false` | 只保留 local_release.iss，在 CI 里直接调用 ISCC；删除 MSIX、fastforge 以及 msix/dmg 开发依赖。AppId `C76CD88E…` 永远不改 |
| 缺口 | 系统媒体控制（SMTC）、跟随系统代理、DPAPI 加密、代码签名，目前都没有 | 按 PLAN 第 11 节新写 |
| `linux/CMakeLists.txt`、`my_application.cc` | APPLICATION_ID 还是 `com.example.pure_live`，窗口标题是 “pure_live”；libmpv 兜底库的安装逻辑是对的 | 修正 ID，但 ID 一改数据目录也会变，需要做数据迁移 [待确认] |
| macOS / iOS | bundle id 是 `com.mystyle.purelive.liu`（上游遗留）；`ios/ShareExtension` 只是 Xcode 模板空壳；含 GoogleService-Info.plist | 删除 ShareExtension；随 Firebase 一起移除配置文件 |

## ③ tool/ 脚本（174 个文件，约 2.56 万行）

| 类别 | 主要文件 | 行数 | v4 处置 |
|---|---|---:|---|
| 构建、打包、发布（Windows） | flutterw.ps1（用 SUBST 和目录联接绕开长路径，并注入 JDK）、build_local_release.ps1（只支持 AndroidArm64 和 WindowsX64）、publish_local_release.ps1、install_android_local.ps1、prefetch_android_native.ps1、prefetch_windows_native.ps1（用于下载 Firebase C++ SDK）、normalize_flutter_generated_paths.ps1、resolve_subst_path.ps1、verify_android_apk.ps1、verify_android_elf_alignment.ps1 | ≈2300 | 交给 CI。APK 完整性和 16 KB 对齐检查改写后保留，其余删除 |
| 原生库构建配方 | native/libmpv-android、native/libmpv-linux | 小 | 保留 |
| FFmpegKit 专用 | verify_ffmpeg_native.py、assemble_ffmpeg_android_aar.py | 274 | 第 5 阶段去掉 FFmpegKit 后删除 |
| 质量门禁与策略检查 | local_ci.ps1、build_resource_guard.ps1、validate_build_policy.ps1（716 行，检查“源码里必须包含某个字符串”）、audit_repository.py、audit_built_in_kotlin.py、validate_agent_workflow.py、update_actions_sha.py、verify_actions_sha.py、review_upstream_update.ps1 | ≈2600 | 换成 tool/gate.sh 加 CI；字符串标记类的检查全部删除 |
| Android 设备 UI 自动化 | android_*.ps1 共 27 个、device_ui_map.json（4451 行）、run_android_device_test_turn.ps1、wake_android_device.ps1、recording_*.ps1 | ≈15000 | 只保留设备租约相关脚本。新界面上线后其余脚本都会失效，改用 patrol |
| 脚本的自测 | test_*.ps1 共 15 个，tests/*.py 共 10 个 | ≈2700 | 随被测脚本一起删除 |
| 探针 | interface_probe.py（1558 行，用 Python 把 9 个平台的请求重写了一遍）、huya_danmaku_probe.py、run_danmaku_connection_probe.ps1、probes/*.dart 共 68 个、probes/*.py 共 5 个 | ≈14400 | 全部由 `live_cli probe` 取代；all_sites_playback_probe_test.dart 的流程作为参考 |

脚本之间的调用关系：

```text
build_local_release.ps1 → local_ci.ps1 → validate_build_policy.ps1 / audit_repository.py / audit_built_in_kotlin.py / interface_probe.py / 10 个 test_*.ps1 / tests/*.py
build_local_release.ps1 → flutterw.ps1 → resolve_subst_path.ps1
build_local_release.ps1 → prefetch_*.ps1、verify_android_apk.ps1 → verify_android_elf_alignment.ps1
所有重型入口 → build_resource_guard.ps1（Windows 进程级互斥）
android_*_smoke.ps1 → android_ui.ps1 / android_activity_state.ps1 / recording_turn_ownership.ps1
run_android_device_test_turn.ps1 → 仓库外的 shared-device-test-rotation\Invoke-DeviceTestTurn.ps1 + wake_android_device.ps1
```

| 重复实现（做同一件事） | 各处实现 |
|---|---|
| 平台接口探测 | interface_probe.py / probes/all_sites_playback_probe_test.dart / 各站的 *_public_contract_probe_test.dart |
| 虎牙弹幕探测 | huya_danmaku_probe.py / danmaku_connection_matrix_probe_test.dart + run_danmaku_connection_probe.ps1 |
| APK 原生库与对齐检查 | verify_android_apk.ps1 + verify_android_elf_alignment.ps1 / verify_ffmpeg_native.py / sign-staged-android.yml 里内联的 zipalign |
| Action 固定版本检查 | update_actions_sha.py（只处理一个工作流）/ verify_actions_sha.py / validate_build_policy.ps1:643 / Dependabot |
| 工作流静态检查 | validate_agent_workflow.py / validate_build_policy.ps1 |
| 发布索引更新 | update_releases.py / update_releases.yml / publish_local_release.ps1 / 两个构建工作流里的 update-json 作业 |
| 录制时钟矩阵 | generate_recording_clock_matrix.py / recorder_clock_matrix_probe_test.dart |
| 脚本自测 | test_android_*.ps1 和 tests/test_android_*.py 测的是同一批脚本 |
| 构建与安装包 | Android 有 4 套构建（build_local_release、feature-build、build_pure_live_release、local-signed-android）；Windows 安装包有 2 套 iss 脚本 |

近两个月的提交数：tool/ 349 次，workflows 192 次，docs 913 次，全仓共 2095 次。工程维护本身占用了大量精力。

## ④ CI

| 工作流 | 触发 | 作业与平台 | 现状 |
|---|---|---|---|
| build_pure_live_release.yml（987 行） | 仅手动，所有输入默认为 false | 串行执行：quality → android（3 个 ABI）→ windows（fastforge 打 exe 和 msix）→ linux（Ubuntu 24.04）→ apple（dmg 和 TrollStore IPA）→ publish → update-json | Android 和 Windows 作业引用的 Secret 不存在，必定失败；9 月 27 日的两次成功运行，据记录只勾选了 Apple |
| feature-build.yml（1715 行） | 手动，或推送 stage-linux/macos/ios-* 标签 | 与上一个基本相同，但 Android 只打 arm64，并用 c0bb 签名 | 大部分步骤与上一个重复 |
| local-signed-android.yml | 手动 | 需要自托管的 Windows runner | 用 API 查询 runner，返回空列表 [待确认] |
| sign-staged / publish-signed / stage-hosted / publish-staged-release | 手动 | 给本机构建的产物做短时签名、校验，再挂到草稿 Release；publish-staged 需要自托管 runner | 签名流程最后一次运行在 2026-08-31 |
| build-ios-unsigned、build-native-ffmpeg-apple | 手动 | macos-15 | 构建 Apple 平台的 FFmpeg 资产 |
| audit-upstream、update_releases | 手动 | ubuntu | — |

固定的 Action 版本：

| Action | 固定的提交（版本） | 使用次数 |
|---|---|---:|
| actions/checkout | 3d3c42e5…（v7.0.1） | 22 |
| actions/upload-artifact | 043fb46d…（v7.0.1） | 16 |
| actions/download-artifact | fa0a91b8…（v7.0.1）与 3e5f45b2…（v8.0.1）混用 | 8+1 |
| subosito/flutter-action | 1a449444…（v2.23.0）；另有几处直接下载官方压缩包并校验 SHA256，两种方式并存 | 7 |
| actions/setup-java | b6effb05…（v5.7.0，zulu 26） | 4 |
| softprops/action-gh-release | 3bb12739…（v2） | 3 |
| actions/setup-python | 5fda3b95…（v7.0.0） | 3 |
| juliangruber/read-file-action | 271ff311…（v1） | 2 |

主要问题：
- 没有配置 push 和 PR 触发，master 上的每次推送都没有经过任何自动门禁。
- 发布流程里的 run_quality 默认关闭，可以跳过测试。
- analyze 带着 `--no-fatal-infos --no-fatal-warnings`，警告不会让检查失败。
- 没有 SBOM、构建来源证明，也没有定时任务。

v4 的 CI 建议拆成以下几个工作流：

| v4 工作流 | 触发 | 内容 |
|---|---|---|
| ci.yml | push 到 master、PR | 格式检查；analyze（新包加 `--fatal-infos`）；依赖方向检查；许可证检查；只对改动的包跑测试；legacy 跑全量测试；android/ 有改动时构建 debug 包做冒烟 |
| nightly.yml | 每天 | `live_cli probe` 跑全部平台，生成 site-status.json 作为发布资产；在宿主机上测桌面性能。真机的 patrol 和性能测试需要本机定时任务加设备租约 [待确认] |
| weekly.yml | 每周 | 运行 check_latest；Dependabot 改为每周 |
| release.yml | 推送 `v*` 标签 | 构建全部 ABI（包括给 TV 盒子用的 armeabi-v7a），用正式密钥签名并带轮换谱系；用 ISCC 打安装包和便携包；Linux 版在容器里构建；Apple 平台可选。生成 SHA256SUMS、SBOM 和构建来源证明（attest-build-provenance）；上传后重新下载核对哈希；自动更新 releases.json 和 version.json |
| native-libs.yml | 手动 | 构建 libmpv 和 FFmpeg 原生资产 |

其余工作流全部删除。

## ⑤ 文档分类

docs/ 共 570 份：旧文档 565 份，加上 v4 新增的 5 份。下表按文件名关键词自动归类，边界处有少量误差。

| 类别 | 份数 | 体积 | 处置 |
|---|---:|---:|---|
| 播放、录制、弹幕专项审计 | 130 | 757 KB | 提炼根因和不变量，写入 spec/modules 和 spec/regressions.md |
| 界面、功能、数据审计 | 118 | 549 KB | 布局类直接归档；迁移和事务类（标签映射、备份导入、EPG）写入 live_store 的规格 |
| 在役平台的接口和契约审计 | 105 | 630 KB | 作为第 1 阶段编写 spec/sites 的主要输入 |
| 已下线平台的审计 | 30 | 137 KB | 归档 |
| 平台工程、构建、网络审计 | 47 | 316 KB | 代理、TLS、窗口相关的结论写入规格；Firebase 相关归档 |
| STAGE_UPDATE_* 阶段发布记录 | 45 | 185 KB | 归档 |
| 候选包、门禁、回归记录 | 34 | 199 KB | 归档 |
| Issue 分流记录 | 27 | 180 KB | `ISSUE_TRIAGE_LEDGER_3_2_0.md` 并入 regressions |
| 验收计划和矩阵 | 8 | 115 KB | `TEST_CHECKLIST.md`、`FULL_CLIENT_TEST_PLAN_2026_08_28.md` 改成第 8 阶段的对齐清单 |
| 冻结的历史记录 | 5 | 559 KB | 归档 |
| 上游同步审计 | 7 | 68 KB | 归档；`UPSTREAM_PORT_2026_09_27.md` 里的移植项写入规格 |
| 操作手册 | 9 | 121 KB | 改写后放进 docs/runbooks |

值得提炼的具体文档：

| 文档 | 去向 |
|---|---|
| PLATFORM_COMPATIBILITY（画质与线路契约）、PLATFORM_PROBE_2026_09_25、在役平台的 *_CONTRACT_CHECKPOINT、YY_DANMAKU_PROTOCOL、HUYA_PLAYBACK_SESSION | spec/sites |
| VIDEO_GEOMETRY_ENGINE、RECORDING_CLOCK_*、RECORDER_GRACEFUL_FLV_STOP、HUYA_NATIVE_LEASE_FIX、ANDROID_PIP_RETURN_FAILURE | spec/modules 和 regressions |
| WINDOWS_DATA_AND_UPGRADE、WEBDAV、BACKUP_IMPORT_AUDIT、TAG_ROOM_MAPPING_MIGRATION 等 | 存储规格（数据迁移、备份格式） |
| DEPENDENCY_AUDIT | 依赖许可证登记 |
| BUILD_AND_RELEASE、ANDROID_DEVICE_TEST_ROTATION、PERFORMANCE、tool/native/*/README | docs/runbooks |
| MSIX_INSTALL | 删除 |

## ⑥ 策略规则

v4 应继承的规则：

| 规则 | 出处 | v4 中的形式 |
|---|---|---|
| 同一时间只跑一个重型任务；一次只构建一个平台 | BUILD_POLICY §1、§5 | gate.sh 用 flock 加锁；CI 用 concurrency 组 |
| K90 设备租约：按 biliroaming→xhs→purelive 轮转，每次输入前核对前台应用；设备操作需要用户当次明确授权 | BUILD_POLICY §5.1、AGENTS.md、docs/ANDROID_DEVICE_TEST_ROTATION.md | 写成操作手册和技能 |
| 先找到第一个出错的状态再修，禁止用延时或重试掩盖问题；报告时分层列出各类证据 | MAINTENANCE §3、§7 | 精简后写进宪法 |
| 播放器不变量：没有用户意图就不 pause/stop；不能凭“没收到某个可选事件”判定播放失败 | MAINTENANCE §8 | 写入规格 |
| APK 门禁：只含目标 ABI、关键原生库齐全、通过 `zipalign -P 16`、ELF LOAD 段对齐 ≥0x4000；核对 split-per-abi 带来的 versionCode 偏移 | BUILD_POLICY §4、§1.1 | 放进 release.yml |
| Windows：随包带运行库；按 install_manifest 打包；安装目录可自选，数据跟着安装目录走，并保留搬迁账本 | BUILD_POLICY §3、local_release.iss | 保留 |
| Secret 不进仓库；Action 按 40 位 SHA 固定；禁止 pull_request_target；工作流输入走环境变量；Release 写明平台、ABI、签名和 SHA256 | AGENTS.md、UPSTREAM §1、MAINTENANCE §7 | CI 检查加发布模板 |

已经过时的规则：

| 规则 | 原因 |
|---|---|
| bugfix-android-release-default（每批修复都发一个 Android 版本） | 与“版本号只随正式发布修改”冲突 |
| local-build-first，签名走 staged 流程 | v4 改为 CI 全自动构建和签名 |
| 24 核/192 GB 的资源档位、Gradle workers 16/20、SUBST、PowerShell 5.1 的 BOM 规则 | 都是 Codex 那台 Windows 机器上的临时办法 |
| 上游合并的语义台账；新功能请求转交上游 | v4 是全量重写，不再合并上游 |
| validate_build_policy 的字符串标记检查 | 把文档文字和代码绑死，应换成真正的测试 |
| 3.2.0 验收文档的归属表、62 行验收矩阵 | 由 regressions 和自动测试取代 |
| Astra Light 模型策略；“只有明确要求时才用子代理” | 前者是 Codex 专用；后者与 PLAN 第 15 节冲突 |
| Firebase 预取、以 FFmpegKit 为由的 minSdk、fplayer 的 16 KB AAR、默认只发 arm64 | 相关依赖都会被移除；TV 盒子需要 armeabi-v7a 包 |

## ⑦ 对第 3 阶段（工程底座）的建议

| 项目 | 建议 |
|---|---|
| 迁移提交 | 用 `git mv` 把旧应用移到 apps/legacy，同一个提交里要一起改这些路径：<br>• `android/build.gradle.kts` 中的 `../plugins/flv_lzc`<br>• pubspec 里指向 plugins/* 和 third_party/* 的 path 依赖<br>• 构建输出目录 `../../build`<br>• tool 脚本里的 `$repoRoot`<br>• analysis_options 的 exclude 列表<br>• 各工作流里的路径<br>third_party 留在仓库根目录 |
| workspace 依赖风险 | media_kit 和 fvp 的 dependency_overrides 在 workspace 里只能写在根 pubspec [待确认]。legacy 和新包共用一份 lock，旧依赖可能卡住新包升级，要先试着解析一次 [待确认] |
| 工具链 | 用一个 toolchain 文件（Flutter、JDK、NDK、Gradle 版本）同时驱动 CI 的 composite action 和 `purelive-env.sh` |
| 原生代码 | 新建 `packages/live_platform` Flutter 插件（Kotlin + C++，接口用 Pigeon 生成），收纳显示模式、保活、录制前台服务、画中画、SMTC、系统代理、Keystore/DPAPI；legacy 在切换前保持原样 |
| 工具 | tools/live_cli 负责探针、样本录制、APK 校验和生成更新说明；tool/gate.sh 用 flock 加锁，只对改动的包跑 analyze 和测试。PowerShell 脚本等 release.yml 跑通后再删。Codex 用的 `.agents/`、`.codex/` 换成 `.claude/`（hooks，以及 `/probe-site`、`/release` 两个技能） |
| 签名 | 按顺序做：<br>1. 把 debug keystore 备份进 Secrets<br>2. 确认 c0bb 的原始文件还在<br>3. 生成轮换谱系<br>4. 在 Android 8、9–12、13+ 三档机型上实测覆盖安装<br>5. 构建脚本在缺少密钥时直接报错，不再退回 debug 证书 |
| 发布 | Windows 只保留 local_release.iss；应用内更新仍从 master 读取 version.json，由 release.yml 自动提交 |
| 文档 | 第 1 阶段提炼完之后，把旧文档移到 docs/archive（加 `.ignore`，让搜索默认跳过）并打 tag `v3-docs`；第 8 阶段删除。根目录的 shell/（抓表情图的脚本）和 server.py 移到 tools/ 或删除 [待确认] |
