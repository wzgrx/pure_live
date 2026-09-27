# Android MPV 音频输出后端与原生告警审计（2026-09-13）

## 结论

当前 Android 默认 MPV 音频输出已从依赖侧固定的 OpenSL ES 改为
`audiotrack,aaudio,opensles,` 有序回退。精确产品提交为
`fec7eae9f0da576b5b7e9df560e1dbb6265946dc`；同提交 arm64 Debug 已在
`25102RKBEC / myron / Android 17` 保留数据覆盖安装，并完成 5/5 次真实 Bilibili
视频→纯音频→返回循环。新包 PID 日志的 5,591 行尾窗中有 152 行 AudioTrack 相关记录，
OpenSL ES、`Configuration error: unknown key` 和
`PlayerBase::setVolume() error -19` 均为 0，业务与清理门禁 14/14 通过。

这是一台设备、一个 Debug 包、一个直播房间的增量证据。原生 Binder death-recipient 告警仍出现
11 次，未随音频后端切换消失，故不把它归因于 OpenSL ES，也不把本轮结果外推为所有 Android
设备或场景已闭环。A7-04 保持 `RUN`，宏观计数保持 **20 PASS / 40 RUN / 2 NR**。

## 源码与依赖定位

- `pubspec.yaml` 与 `pubspec.lock` 固定 media-kit 提交
  `994465d9bfca3f39d0b41199d16e7fd93fe97881`。该版本的
  `media_kit/lib/src/player/native/player/real.dart` 在 Android 实机上把 `ao` 固定为
  `opensles`。
- Pure Live 的 `MediaKitAdapter.applyNativeLiveProperties` 原来只在用户开启专家输出时覆盖
  `ao`，Linux 另设 `alsa`；Android 普通配置会继承上述 OpenSL ES 默认值。
- 本批构建合并后的 arm64 `libmpv.so` 二进制同时含 `audiotrack`、`aaudio` 和
  `opensles` 字符串。mpv 的 Android 构建也分别定义这三个输出模块；其 `--ao` 文档允许按
  逗号给出驱动优先级，末尾逗号允许继续尝试其他输出。
- Android NDK 当前将 OpenSL ES 标为继续支持但属于 legacy API，将 AAudio 列为当前原生音频
  API。media-kit #701 另有相同 `libOpenSLES: Configuration error: unknown key` 日志，可作
  现象对照，但不是本项目根因证明。

参考：

- Android NDK 稳定 API：<https://developer.android.com/ndk/guides/stable_apis>
- mpv 音频输出文档：<https://github.com/mpv-player/mpv/blob/master/DOCS/man/ao.rst>
- mpv Android 构建项：<https://github.com/mpv-player/mpv/blob/master/meson.build>
- mpv 音频选项：<https://github.com/mpv-player/mpv/blob/master/meson.options>
- media-kit #701：<https://github.com/media-kit/media-kit/issues/701>

## 产品修订

`fec7eae9` 同步修改四个文件：

1. `lib/player/utils/mpv_platform_profile.dart`
   - Android 设置页只显示 `auto / audiotrack / aaudio / opensles / null`；
   - Android 导入或残留的 `wasapi` 等异平台值归一化为 `auto`；
   - 普通配置默认写入 `audiotrack,aaudio,opensles,`，Linux 保留 `alsa`，其余平台继续使用
     media-kit 默认值。
2. `lib/player/adapters/media_kit_adapter.dart`
   - 播放源打开前应用平台默认音频输出；
   - 用户已启用专家输出时仍优先尊重其显式选择。
3. `lib/player/utils/player_consts.dart`
   - `auto` 标签改为准确的 `Automatic fallback`，去除“不可用”误导。
4. `test/player_settings_controller_test.dart`
   - 固定 Android 可见驱动、异平台值归一化和三平台默认行为。

第一轮新增断言因生产侧尚无平台默认帮助函数而得到有效红灯 0/1。修订后相邻三个文件
**28/28 PASS**；focused CI 再次 **28/28 PASS**，全库 analyze 为 `No issues found`。
质量记录：
`local-artifacts/build-records/20260912T163017109Z-quality-focused.json`。

## 构建、覆盖安装与数据保护

`tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality` 在干净
`fec7eae9` 上完成：

| 项目 | 结果 |
| --- | --- |
| 包名 / 版本 | `com.mystyle.purelive` / `3.1.8` / manifest code `6121` |
| APK | `288822657` B |
| SHA-256 | `DE7DE185B3E44700CB0D7BE4D2907B17CEB6EFC48BF7BAD53FA5FF95ADFFAE0E` |
| ABI / 原生库 | `arm64-v8a`；16 个库；最小 ELF LOAD `0x4000` |
| 构建记录 | `local-artifacts/build-records/20260912T163154806Z-build-androidarm64-debug.json` |

设备轮次先核对 `25102RKBEC / myron` 和 `uid=0(root)`，再停止 Pure Live 并执行显式目标的
`install -r -t`。安装返回 `Success`，`firstInstallTime` 保持
`2026-07-21 18:07:53`；设备 `base.apk` 与候选 SHA-256 完全相同。规范 Hive 在安装前、本机
备份和首次启动前的 SHA-256 均为
`48E5982BACF3EBFAF025FC2C90FFC09AB283B68885FAE01506411BABC98E7D5B`。
安装证据：
`local-artifacts/diagnostics/android-audio-output-candidate-install-fec7eae9/install-summary.json`。

## K90 原生对照

旧 `039f8ff3` 候选的 50 次循环日志只保留最后 5,000 行。在这个有限尾窗中，三次播放打开
各出现一组 OpenSL ES 旧声道掩码、`setVolume() error -19`、unknown-key 和参数无效记录：

| PID 日志尾窗 | OpenSL ES 行 | unknown-key | setVolume -19 | AudioTrack 行 | FATAL/ANR |
| --- | ---: | ---: | ---: | ---: | ---: |
| 旧 50 次循环尾窗，5,473 行 | 9 | 3 | 3 | 146 | 0 |
| 新 5 次循环尾窗，5,591 行 | 0 | 0 | 0 | 152 | 0 |

这里比较的是两个有限 PID 日志尾窗，不按总循环数换算发生率。新候选运行结果：

- 5/5 次视频→纯音频→返回均完成，音频动作均一次输入生效，5 次应用内悬浮会话均关闭；
- 同一 PID `13254` 保持，14/14 资源、页面和致命日志门禁通过；
- 预热首页 PSS/RSS 为 `699593 / 872104` KB，循环后空闲 52 秒为
  `684946 / 857644` KB，分别为 `-14647 / -14460` KB；
- FD 从预热 `274`、循环首轮 `312`、循环末轮 `300` 回落到 `262`；DMA-BUF 从预热
  `25`、循环首末 `53/53` 回落到 `25`；Socket `20→20`；
- 原生堆从预热 `69580` KB 到最终 `70876` KB（`+1296` KB），线程 `67→69`，Codec
  线程最终为 3，BLAST layer 最终为 1；
- 最终应用停止、系统桌面前台，stay-awake 从测试值 `7` 恢复原值 `0`。

完整结果：
`local-artifacts/diagnostics/android-audio-output-room-probe-fec7eae9-rerun/summary.json`。

## 测试器失败链

新候选首轮在第 1 次循环后的资源采样中遇到线程刚好退出：`/proc/PID/task/*` 已枚举该 TID，
读取 `comm` 时文件已消失，旧命令因此把整轮判为失败。失败摘要和设备清理结果保留在
`local-artifacts/diagnostics/android-audio-output-room-probe-fec7eae9/summary.json`。

`da8c15b1717701d7e22d9d4de3b22abe7727d47f` 新增只接受数字 PID 的线程快照命令，单个瞬态
TID 消失时跳过该样本，同时保留 adb、su 和循环级错误；PowerShell 解析回归通过，随后同一 APK
完整重跑 5/5 成功。该修订只影响测试工具，不改变已安装产品字节。

## 后续

1. 用正式签名 Release 在至少一台不同厂商/Android 版本设备复验 AudioTrack→AAudio→OpenSL ES
   回退链。
2. 分别实测专家设置中的 `auto`、`audiotrack`、`aaudio`、`opensles` 与 `null`，并验证备份导入
   和升级迁移。
3. 把视频、纯音频、全屏、PiP、后台、耳机/蓝牙和音频焦点场景纳入同一长时资源矩阵。
4. 在正式签名 Release 和其他厂商设备上继续记录 `AIBinder_linkToDeath` 告警，连同系统 build
   fingerprint、Codec2 组件名和发生阶段对照；不为消除日志而关闭硬件解码。

本批 Windows Computer Use 与 Astra Light 使用次数均为 **0**。

## 后续 UI 与验收工具补证

初版 focused CI 只纳入设置控制器与两个播放器相邻文件，未覆盖播放器内核设置 Widget。随后显式
执行 `test/player_kernel_settings_page_test.dart`，旧用例仍查找已经退役的
`auto (Not available)`，得到 **2 PASS / 1 FAIL** 的有效红灯。`09315462` 更新该断言，并新增
Android 目标平台 Widget：打开真实音频输出弹窗，逐项确认五个 Android 后端、排除 Windows、
Linux 与 macOS 项，再选择 AAudio 并验证持久值。与设置控制器合跑 **16/16 PASS**；focused CI
再次 16/16、全库 analyze 无问题。记录：
`local-artifacts/build-records/20260912T165929371Z-quality-focused.json`。

K90 原生首轮补证还暴露 `open_settings` 仍使用两处历史缓存坐标：脚本日志声称点击完成，但 UI
层级仍停留首页，目标“播放器内核”经过 7 次滚动也未出现。测试先对两种竖屏 profile 得到有效
红灯；`3bfda37b` 把“菜单 → 设置”改为双语实时语义，并以“主题设置 / Theme Settings”作
目标页断言。PowerShell 与四 profile JSON 校验通过，随后同一已安装 APK 的真实语义路由到达
播放器内核页和音频弹窗：

- 当前选中 `auto (Automatic fallback)`；
- 五个 RadioButton 完整可见，桌面驱动片段为 0；
- 原生 UI 检查 **6/6 PASS**，截图与 XML 位于
  `local-artifacts/diagnostics/android-player-audio-menu-fec7eae9-final/`；
- 应用启动期间规范 Hive 字节发生运行态写入，测试没有把它解释为弹窗修改；清理阶段用开始前副本
  恢复，最终 SHA-256 与基线
  `19F40EA9E29A6017317ACB14AEBA8CF4378A6EEAA96BA15E09C7CD2312D1F050` 完全相同；
- 最终 Pure Live 停止、系统桌面前台，stay-awake 恢复 `0`。

以上补证仍不扩大 5 次单设备 Debug 运行的外推范围，A7-04 与宏观计数保持不变。

为避免后续五种音频后端矩阵再次各自实现页面滚动，本轮又把该路径固化为
`open_player_kernel_settings`：菜单、设置与播放器内核三步全部使用实时双语语义，并以
“核心内核设置 / Core Kernel Settings”验证终点。测试先对缺失序列得到有效红灯；补齐两种
竖屏 profile 后，UI map 回归及四 profile schema 校验通过。K90 原生复跑 4/4 检查通过，实际
点击坐标来自当次 UI 层级，最终应用停止、桌面前台且 stay-awake 恢复为 `0`。该只读路由首版
遗漏了设置文件保护；应用启动自身把规范 Hive 从 `19F40EA9…D1F050` 写成
`DC887921…31E3C`。后续矩阵虽准确恢复了自身开始时的 `DC887921…31E3C`，但没有把它误报为
更早的用户基线；检测到跨轮漂移后，已用原始本机副本按 `10946:10946:600` 与 SELinux context
恢复，最终设备 SHA-256 精确回到 `19F40EA9…D1F050`。路由与修复证据：
`local-artifacts/diagnostics/android-player-kernel-semantic-route-9da14ceb/summary.json`、
`local-artifacts/diagnostics/android-player-kernel-semantic-route-9da14ceb/settings-repair-summary.json`。

新增 `tool/android_audio_output_settings_smoke.ps1` 后完成五项原生选择矩阵。工具要求显式 serial，
先核对型号/代号/root 和设备 APK 哈希，随后完整备份 Hive 的字节、uid/gid/mode；每项均通过
语义路径启用“自定义驱动与硬件加速”，选择目标、立即重新打开弹窗核对，再强制停止并重启应用
复核。结果如下：

| 专家 `--ao` | 立即选中 | 重启后选中 | 弹窗选项数 |
| --- | --- | --- | ---: |
| `auto` | PASS | PASS | 5 |
| `audiotrack` | PASS | PASS | 5 |
| `aaudio` | PASS | PASS | 5 |
| `opensles` | PASS | PASS | 5 |
| `null` | PASS | PASS | 5 |

五种值的即时显示和跨进程持久化全部通过，每次弹窗都只有五项 Android 后端；工具静态合同同时
固定显式目标、精确选项、语义路由、备份/恢复及清理约束。矩阵结束后其开始态字节恢复通过，
再完成上述跨轮基线校正；最终应用停止、桌面前台、stay-awake 为 `0`。完整证据：
`local-artifacts/diagnostics/android-audio-output-settings-fec7eae9/summary.json`。这组结果证明设置
UI 与持久化；下节继续记录五个后端的真实媒体输出矩阵。

## 五后端真实播放矩阵与回退修订

首次逐后端播放矩阵
`local-artifacts/diagnostics/android-audio-output-playback-matrix-fec7eae9/summary.json`
只有 `audiotrack`、`aaudio`、`opensles` 通过。`auto` 虽有实时视频，但没有命中可接受的
Android 音频后端；`null` 在 MediaKit 后续自动回退到 Fijk 时又由 Fijk 固定音量创建了
AudioTrack，破坏静音语义。这里同时暴露了两个相邻缺口：Android 专家值 `auto` 没有解析为
当前包已验证的有序链，自动换内核也没有继承“禁用音频输出”的意图。

产品提交 `b303fffd` 完成以下修订：

- Android 自定义 `auto` 在进入 MPV 前解析为 `audiotrack,aaudio,opensles,`，其他平台和专家
  显式值保持原语义；
- `null` 通过同步的播放器能力合同在初始化前传递到自动回退内核；Fijk 同时写入 IJK
  `an=1`、宿主 `request-audio-focus=0` 和音量 0，VideoPlayer 先静音再启动，避免创建阶段的
  短暂有声窗口；
- 只抑制自动回退路径，用户手动切换内核继续保持正常音频；
- 播放 smoke 增加显式 `-PlaybackProbe`，要求画面帧变化、目标应用 Surface、原生解码日志，
  并按选择核对 MediaKit/Fijk/Better、AudioTrack/AAudio/OpenSL ES、Fijk `an=1` 及
  AudioFlinger 活跃轨道。

有效红测先命中缺失的解析助手、同步能力合同和构造器参数；最终 focused CI **189/189 PASS**，
全库 analyze 为 `No issues found`。Fijk 原生通道夹具 **8/8 PASS**，明确记录 `an=1`、
`request-audio-focus=0` 和 volume 0。干净 `b303fffd` arm64 Debug 构建记录为
`local-artifacts/build-records/20260912T181911316Z-build-androidarm64-debug.json`：APK
`288826114` B，SHA-256
`539E8ACC0A52699B820B6F7330A382D962E526A44B1418392CCCC43C23840E23`，设备覆盖安装后
`base.apk` 逐字节一致且 `firstInstallTime` 保持 `2026-07-21 18:07:53`。

短矩阵先确认 `auto` 有 AudioTrack 活跃轨道、`null` 的三类后端信号和 AudioFlinger 活跃轨道
均为 0；结果见
`local-artifacts/diagnostics/android-audio-output-fallback-b303fffd/install-playback-summary.json`。
随后完整矩阵第一次运行在冷启动后 250 ms 仍停留 MIUI 桌面，安全前台断言按设计中止输入；
`6f40be2c` 将目标应用进入改为 `am start -W` 后轮询 top-resumed package，保留
`-NoBringToFront` 的即时保护语义。最终原生结果：

| 专家 `--ao` | 实时画面 | 实际后端信号 | 活跃 AudioFlinger | 结果 |
| --- | --- | --- | ---: | --- |
| `auto` | PASS | MediaKit + AudioTrack | 1 | PASS |
| `audiotrack` | PASS | MediaKit + AudioTrack | 1 | PASS |
| `aaudio` | PASS | MediaKit + AAudio | 1 | PASS |
| `opensles` | PASS | MediaKit + OpenSL ES | 0（以初始化日志门禁） | PASS |
| `null` | PASS | MediaKit；三类音频后端均无信号 | 0 | PASS |

最终汇总
`local-artifacts/diagnostics/android-audio-output-playback-matrix-b303fffd-rerun/summary.json`
为 **5/5 PASS**：五项均跨进程保持、到达真实 Bilibili 房间、画面帧变化且无 FATAL/ANR；
规范 Hive 最终恢复到
`19F40EA9E29A6017317ACB14AEBA8CF4378A6EEAA96BA15E09C7CD2312D1F050`，应用停止、桌面前台，
stay-awake 恢复 `0`。本轮只覆盖一台 K90、一份 Debug 包和一个 Bilibili 房间；最终五轮
MediaKit 均稳定，Fijk 自动回退抑制由单元/原生通道夹具证明而未在该直播源现场触发。
A7-04 保持 RUN，宏观保持 **20 PASS / 40 RUN / 2 NR**、42 组未闭环；Release、多平台、
视频恢复、全屏/PiP/后台和更长轮次继续。

## Binder death-recipient 告警归因边界

本轮 11 条 `AIBinder_linkToDeath` 告警均处在 Android 原生媒体链附近，而不是 AudioTrack 或
OpenSL ES 初始化附近。日志可复核的相邻关系包括：

- `CCodec allocate(c2.qti.avc.decoder)` 之后紧接告警，再出现
  `Created component [c2.qti.avc.decoder]`；
- `CCodecBufferChannel ... start` 与 `MediaCodec ... STARTED` 之后再次出现同文告警；
- 有限日志尾窗覆盖的连续四次 MediaCodec 会话重复出现这一结构，音频后端切换后告警仍存在，
  且本轮没有 FATAL/ANR。

Android Binder NDK 的 `AIBinder_DeathRecipient::linkToDeath` 源码明确：传入非空 cookie、但 death
recipient 没有设置 `onUnlinked` 回调时会打印该告警。与本机时序相符的 Codec2 AIDL 客户端实现
在 `AidlDeathManager` 中创建 death recipient，并把序号转成非空 cookie 传给
`AIBinder_linkToDeath`，该实现片段没有先设置 `onUnlinked`。作为版本差异对照，AOSP 当前
Codec2 AIDL `Component` 的另一条 death-recipient 路径已经在 link 前调用
`AIBinder_DeathRecipient_setOnUnlinked`，并由回调释放上下文。Flutter `video_player` 的公开日志也
记录了同类告警紧跟 `c2.qti.avc.decoder` 创建，说明该现象并非 Pure Live/media-kit 独有。

参考：

- Binder NDK 告警条件：
  <https://android.googlesource.com/platform/frameworks/native/+/master/libs/binder/ndk/ibinder.cpp#598>
- Codec2 客户端 `AidlDeathManager`：
  <https://android.googlesource.com/platform/frameworks/av/+/aa71b5c2c1/media/codec2/hal/client/client.cpp#1893>
- 当前 Codec2 AIDL `Component` 的 `onUnlinked` 生命周期：
  <https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/codec2/hal/aidl/Component.cpp#533>
- Flutter `video_player` 的同类 CCodec 日志：
  <https://github.com/flutter/flutter/issues/176575>

据此，本轮把它分类为 **Android 平台/厂商 Codec2 媒体栈告警的高可信归因线索**：本机日志与
AOSP 调用形态一致，但缺少该 Android 17 系统映像的带符号栈和精确 frameworks/av 构建提交，
所以不把源码对照写成设备二进制的最终根因证明。Pure Live 源码没有直接调用上述 Binder NDK
API；当前也没有崩溃、ANR 或资源门禁失败支持在应用层禁用 MediaCodec/硬件解码。后续只在
Release、其他系统版本或实际故障伴随出现时升级处理优先级。
