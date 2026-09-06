# Soop HLS 录制恢复审计（2026-09-06）

## 失败定位

`17a192f1` 接入应用代理后，新 Android Debug 候选仍录制零增长，故代理缺口不是本次零增长的完整解释。
读取活动 Dart VM 对象取得 FFmpeg 会话：`mediaStarted=false`、时长 0，连续分片 `HTTP error 404 Not Found`；HLS 中转 `_nextResourceId=0`。

最终取得同一 Soop CDN 清单的对照响应：

| 请求 | 响应 | 内容 |
| --- | --- | --- |
| 无 Range | 200 | HLS，`application/vnd.apple.mpegURL` |
| `Range: bytes=0-` | 206 | 同类 HLS 清单 |

原中转只在 200 时重写清单。206 直接转发，清单内相对分片路径被 FFmpeg 解析到回环服务器，却没有对应资源登记，持续 404。
对照证据：`local-artifacts/diagnostics/android-soop-29caea0b-20260906/active-recorder-vm.json` 的 `upstreamProbes`。

调试工具限制也单独保留：独立安装 Debug APK 的 VM 没有表达式编译服务，改用 `getObject` 读取字段；早期辅助脚本遇到 Map 包装及字符串截断问题，相关失败不计为完整诊断成功。最终所需会话、资源计数和 HTTP 对照已保存；可选字段采集尾部仍有 `'id'` 错误，不覆盖已取得的证据。

## 修复与代码验证

- `29caea0b`：已知 HLS 清单完整获取，不转发 FFmpeg 的 Range 探测；媒体分片及密钥保持原 Range 行为。TLS、代理和停止排空策略不变。
- 本地服务器复现相同 206 场景，修复前媒体请求 404：9 项通过、1 项失败，记录 `20260906T020849618Z-quality-focused.json`。
- 修复后 HLS、FLV、代理三个测试文件 **24 项通过**，analyze **No issues found!**（101.0 秒）。记录 `20260906T021148727Z-quality-focused.json`。
- Android Debug 构建记录 `20260906T021413807Z-build-androidarm64-debug.json`：128.965 秒，资源/ABI/16 KB 对齐门禁通过，结束活跃重型进程 0。应用源码为上述提交；构建时外部 AGENTS 修改使元数据 dirty 为 true，并非未提交应用代码。

## 实机结果

首次新候选已接收媒体（会话时长 50 秒、登记 35 个资源），但测试因前台切换及 UIAutomator idle 失败而强停；该轮不是正常停止证据。

测试脚本此前在文件增长检查前仍等待“录制中”的 UI dump；每秒更新时长/大小会使 UIAutomator 没有一秒静止窗口。移除此处不可靠的前置等待，使用原有实际文件两次增长作为运行判据，保留截图、停止状态、文件及进程清理检查。PowerShell 语法和 11 项平台/标签检查通过。

重测证据：`local-artifacts/diagnostics/android-soop-growth-29caea0b-20260906/`。

- Soop 房间 두치와뿌꾸，`room-recording.png` 可见实际游戏视频、10 条实际弹幕；原画/单线路。较早的 `room-before-record.png` 视频区仍黑屏而弹幕已显示，因此不计作首帧延迟达标。此轮不重复画质切换，也不计作多线路测试。
- 实际 TS 从 **1,572,864** 增至 **3,670,016** 字节；触发到增长确认 18.216 秒。
- 正常停止收尾 13.915 秒；录制中心本轮卡片显示“已停止”、20 秒、17.29 MB，无失败标签。
- MP4 **18,133,418 字节 / 20.002646 秒**，H.264 1920×1080、AAC。
- SHA256：`92c97067bce209f6a2d10ecb918ab2e17f073774dfd768707934118c93b874e1`。
- 全部 1072 个视频包 DTS 严格递增，0 倒退、0 重复。初次完整解码退出 0，但 null 输出时间基有 2 条重复 DTS 警告；保留源时间基后，完整严格解码退出 0、错误日志空。证据 `recording-timebase-decode.json`、`video-packets.json`。未修改录制文件以获得通过。
- 名义帧率 60，实际平均 `3216000/59999`，不宣称恒定 60 fps。先前活动会话有源包丢弃/过期分片警告；本次证明短录及最终文件可解码，不替代长时网络稳定性验收。
- 本轮监控已取消，进程及唤醒锁已清理；应用/播放器代理已关闭，ADB reverse 已移除。历史 YY 卡片和已有文件保持原状。没有进行本轮锁屏测试。

## 剩余范围

Windows 新候选、完整质量门禁、其他未完成矩阵项及正式全平台 3.2.0 发布仍未完成。本次不提升版本、不上传发布，也不把新 Android 证据套用到其他平台。
