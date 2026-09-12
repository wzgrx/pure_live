# 当前累计 Android 候选覆盖安装与冒烟（2026-09-12）

## 范围与设备保护

- 本报告先以基础播放候选 `3e41e848e2dc913baa36a9ac207bc54a0efd77b8` 完成全局运行冒烟，随后以小窗设置增量候选 `63597cf112e38dd77c8157b7cbb5e67dfb70ba52` 完成新修订专项；两个构建均保持 `3.1.8+4121`，按源码 SHA 区分。
- 网络 ADB 全程显式使用 `-s 192.168.1.2:5555`，每个设备阶段先核对 `25102RKBEC / myron`，Root 只读取 `su -c id` 身份。开始时手机位于系统桌面，Pure Live 没有进程或服务。
- 全程没有重启手机/adbd、切换 Wi-Fi、改 ADB 端口、撤销调试、更新 Root/LSP/模块或清除应用数据。设备轮次只临时取得 stay-awake，结束均从 `7` 恢复原值 `0`。

## 构建与独立归档

使用 `tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality` 串行构建，记录 `local-artifacts/build-records/20260912T095409510Z-build-androidarm64-debug.json`：

| 项目 | 结果 |
| --- | --- |
| 包名 / 版本 | `com.mystyle.purelive` / `3.1.8` / manifest code `6121` |
| APK | `288800843` B |
| SHA-256 | `43ECD8769A06464AC9452480B5080F31A6C61510CD863878C4C5C241FB158D57` |
| ABI / 原生库 | 仅 `arm64-v8a`；16 个库，最小 ELF LOAD `0x4000`；APK 16 KB 对齐通过 |
| Flutter 资源 | 1262 项，`206804499` B，完整性检查通过 |
| 签名证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

独立归档位于 `local-artifacts/candidates/android-3e41e848/`，复制后 APK 哈希、apksigner、构建元数据再次核对一致。该构建使用 `-SkipQuality`；本轮最近的播放器设置源码已有全库 analyze 无问题及六文件 147/147，精确源码提交再跑 147/147，未将这些定向证据表述为当前提交的完整全库发布门禁。

## 覆盖安装与数据一致性

安装前先拉取设备旧 `base.apk` 并分别执行 apksigner：旧包 `287054981` B、SHA-256 `D965095AC696FC98D000E89542835F98C8A0C30DA0DF54EF4089D19571762E8D`，与新候选证书摘要完全一致。随后在 Pure Live 已停止且系统桌面前台时执行 `adb -s 192.168.1.2:5555 install -r -t APK`，返回 `Success`；安装后的设备 `base.apk` SHA-256 与候选逐字节一致，`firstInstallTime` 保持 `2026-07-21 18:07:53`，`lastUpdateTime` 更新为 `2026-09-12 17:57:48`。

状态快照只纳入设置、shared preferences、数据库、datastore、WebView 小状态和 no_backup；录制目录 `app_flutter/PURE_LIVE`、可重建 Flutter assets、缓存更新 APK、cache/code_cache 原位保留且不进入本机副本。安装前 tar 为 `4618240` B、80 个成员、58 个普通文件，SHA-256 `DA3E4FA6962929B1EDFF5975A3A25C5FED1841F4DBB83C426C2CA5B26D6D6039`。覆盖安装后、首次启动前再次取得相同范围，两份 tar SHA 和逐文件路径/大小/SHA 均完全一致。证据根：`local-artifacts/android-current-candidate-20260912T175620667/`。

## 当前候选运行冒烟

`tool/android_runtime_smoke.ps1` 在独占设备轮次真实执行并 **16/16 PASS**：

- 冷启动进入当前 Activity，未出现 Android 16 KB 兼容提示；刷新热门页并进入真实 Bilibili 房间。
- 房间控制与弹幕 UI 存活，可见实时弹幕 10 条，清晰度与线路入口存在。
- 视频→纯音频在 3573 ms 内到达，纯音频→视频在 8904 ms 内恢复；随后进入系统 PiP、回到原直播间，弹幕 UI 仍存活。
- 应用日志无 FATAL/ANR；退出后进程消失。单点 PSS `769291` KiB、RSS `922688` KiB、线程 80、CPU 68% 只作为播放瞬时快照，不据此推导长时资源趋势。

完整结果：`local-artifacts/android-current-candidate-20260912T175620667/runtime-smoke/summary.json`。

## 当前候选标准流与竖屏流呈现

同一候选随后串行运行 `tool/android_presentation_smoke.ps1` 两种模式，均由设备轮次恢复 stay-awake，脚本结束后 Pure Live 停止、系统回到桌面，自动旋转保持 1、用户旋转保持 0：

- **Standard 7/7**：当前 Bilibili 第一候选房间在普通 `1200×2608` 页面不暴露竖屏手势，进入 `2608×1200` 横屏全屏；系统返回恢复原直播间，再进入 PiP 并回房，画面/弹幕宿主保持，致命日志为 0。证据 `presentation-standard/summary.json`。
- **Portrait 9/9**：抖音第三候选房间同时出现竖屏手势和横屏动作；下滑进入 `1200×2608` 竖屏沉浸并显示恢复提示，上滑恢复弹幕栏，再进入 `2608×1200` 横屏全屏；系统返回、PiP 和回房后仍为同一类竖屏房间，致命日志为 0。证据 `presentation-portrait/summary.json`。

这两轮将 A3-01/A3-02 的既有 PASS 刷新到当前累计候选，不重复增加宏观 PASS；旋转锁、连续 20 次切换、内嵌黑边/迟到几何和长时资源仍按 A3 相邻矩阵执行。

## #858 软件注入媒体流补证

在播放器尚未创建的 Pure Live 首页，记录系统音乐流与铃声流均为 0；通过当前前台 Activity 注入一次 `KEYCODE_VOLUME_UP` 后，`STREAM_MUSIC` 从 0 变为 10，铃声流仍为 0。随后仍在该 Activity 中注入一次降低，音乐流恢复 0 和 muted 状态；结束时 Pure Live 进程消失、系统桌面恢复、stay-awake 恢复 0。该结果证明当前候选首页的 framework 按键路径解析到媒体流，而不是铃声流。

测试器保留三次夹具修订：首次错误选取任务列表中的第一条 `ACTIVITY`，尽管 `am start -W` 已报告目标 Activity 启动成功；第二次业务断言通过，但 OEM 对 `cmd media_session --set 0` 保持最小非静音档 10，清理门禁正确失败；改为在目标 Activity 中按步恢复后，第三次全部业务/清理断言已通过，但包装器读到无进程 `pidof` 的退出码 1；最终显式清理命令状态后整轮退出 0。失败记录均保存在同一 `volume-home/` 目录，没有用放宽产品断言换取通过。

该证据属于 **软件注入、首页、扬声器路由**；报告者的实体按键、播放中、弹窗、全屏、PiP、外部 Activity、前后台与其他输出设备仍按 `AND-PLAY-16` 逐项执行。因此 #858 保持 `not-reproduced`，A3-04 保持 RUN、A7-02 保持 NR。

## 小窗弹幕设置原生补证

当前候选在 K90 上完成“设置 → 小窗弹幕”的实时语义路由；旧缓存点 `(600,2175)` 已证实落在卡片空隙，测试器现按“菜单 → 设置 → 小窗弹幕”逐步解析语义，并以目标页专属“样式预览”作终态断言。最终页面截图/XML同时显示固定预览、总开关和恢复默认入口。

`tool/android_pip_danmaku_settings_smoke.ps1` 随后执行开启→关闭→重启→开启→重启。开启状态有 4 个当前可见 Switch、禁用遮罩消失；关闭状态只保留总开关且预览显示“小窗弹幕已关闭”，两种状态均跨进程保持。最终规范 Hive `443377` B 的恢复前后 SHA-256 均为 `701C666A664A784F5E466D5274F5A13C015DEAAF893BFBA51801ED989D8EA60C`，应用停止、桌面与 stay-awake 原值恢复。完整失败修订和证据路径见 `docs/ANDROID_PIP_DANMAKU_SETTINGS_NATIVE_AUDIT_2026_09_12.md`。

A2-04 因此由 NR 进入 RUN；Windows 双栏、其余样式控件、默认/模板组合、实际系统 PiP/Windows 小窗与长时资源继续，不记为全项 PASS。

## 小窗设置无障碍与默认恢复增量候选

`63597cf1` 将开关改为具名、整行可点击且状态一致的 `SwitchListTile`，为七类滑块补充“设置名 + 格式化数值”语义，并使恢复默认文案与实际 14 项赋值一致。六文件聚焦回归 **43/43**、全库 analyze 通过；arm64 Debug 为 `288802226` B，SHA-256 `D52040A348B28638A593F9AC905D8368FFA0A2CB9D584C236BF14F7288DF8977`。

该包已通过 `install -r -t` 覆盖当前安装，首次安装时间保持、首次启动前规范 Hive SHA 不变，设备 `base.apk` 与候选逐字节一致。K90 原生页面的四个可见 Switch 均有独立中文名称，字号/字重滑块分别显示“字体大小, 12.0”“字体粗细, 稍粗”；取消恢复保留关闭状态，确认恢复后回到默认开启并跨进程保持。最终规范 Hive 精确恢复、应用停止、桌面与 stay-awake 原值恢复。详见[无障碍与默认恢复审计](ANDROID_PIP_DANMAKU_ACCESSIBILITY_RESET_AUDIT_2026_09_12.md)。

## 09-13 AudioTrack 优先增量候选

`fec7eae9` 将 Android 普通 MPV 音频输出从依赖侧固定 OpenSL ES 改为
`audiotrack,aaudio,opensles,` 有序回退，并把 Android 设置页限制为当前包实际包含的驱动；
用户启用专家输出时仍优先尊重显式选择。相邻与 focused CI 均 **28/28 PASS**、全库 analyze
无问题。干净提交构建的 arm64 Debug 为 `288822657` B，SHA-256
`DE7DE185B3E44700CB0D7BE4D2907B17CEB6EFC48BF7BAD53FA5FF95ADFFAE0E`。

该包已保留数据覆盖当前设备：`firstInstallTime` 保持，规范 Hive 安装前、本机备份和首次启动前
哈希完全相同，设备 `base.apk` 与候选逐字节一致。K90 上 5/5 次真实 Bilibili
视频→纯音频→退出、14/14 门禁通过；新 PID 日志尾窗含 152 行 AudioTrack 相关记录，
OpenSL ES、unknown-key 和 `setVolume -19` 均为 0。Binder death-recipient 告警仍存在并拆分
跟踪；瞬态线程退出造成的测试器误失败由 `da8c15b1` 修订后完整重跑通过。后续
`09315462` 补齐 Android 五项音频菜单 Widget，`3bfda37b` 将设置导航改为双语实时语义与目标页
断言；同一已安装 APK 的 K90 音频菜单 6/6 通过，当前选中 auto、桌面驱动未混入，规范 Hive
用测试前副本精确恢复。详见
[Android 音频输出后端审计](ANDROID_AUDIO_OUTPUT_BACKEND_AUDIT_2026_09_13.md)。

## 当前结论

当前设备安装的是 `fec7eae9` 同签名 Android 增量候选，最新包哈希为
`DE7DE185B3E44700CB0D7BE4D2907B17CEB6EFC48BF7BAD53FA5FF95ADFFAE0E`；其 Android
音频输出与 5 次进退房专项已经通过。50 次资源循环仍绑定前一 `039f8ff3` 候选，基础播放、弹幕、
PiP、标准/竖屏呈现及其他增量证据各自继续按原精确包记录，不自动外推到新字节。当前仍是 Debug
验收输入；宏观状态为 **20 PASS / 40 RUN / 2 NR，共 42 组未闭环**。
