# 当前累计 Android 候选覆盖安装与冒烟（2026-09-12）

## 范围与设备保护

- 候选绑定干净提交 `3e41e848e2dc913baa36a9ac207bc54a0efd77b8`，本地与 GitHub `master` 在构建前一致；版本保持 `3.1.8+4121`，本轮不升 3.2.0、不发布。
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

## 当前结论

当前累计源码已经落到同签名 Android 候选并覆盖安装，安装前数据范围逐文件一致，基础播放/弹幕/音频模式/PiP 冒烟、标准流与竖屏流的普通页/沉浸/横屏/PiP 往返，以及首页软件音量按键路由补证均通过。它仍是 Debug 验收输入，不替代完整全库质量、全部设置页、22 个平台、录制、故障注入、长测和正式发布门禁；宏观状态保持 **20 PASS / 33 RUN / 9 NR，共 42 组未闭环**。
