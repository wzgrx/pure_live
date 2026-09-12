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
4. 独立定位仍存在的 `AIBinder_linkToDeath` 告警；本轮日志中它出现 11 次，但没有 FATAL/ANR，
   现有证据只支持把它与 OpenSL ES 告警拆开跟踪。

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
