# Picarto Android 覆盖安装与首轮原生录制（2026-09-07）

后续：[录像尾部诊断与源段保留](PICARTO_INPUT_INTEGRITY_AUDIT_2026_09_07.md)已定位末尾解码错误并修订损坏证据传递；126项定向测试通过，损坏来源与新源码原生验收继续。

## 结论与范围

- **覆盖安装通过、短录文件已产生，完整原生录制验收未通过。**
- 当前手机已是 `2006c044` Android arm64 Debug，3.1.8+4121 / Manifest 6121；
  不是 3.2.0 正式包。[构建分层证据](PICARTO_ANDROID_CANDIDATE_AUDIT_2026_09_07.md)
  仍按原记录，不将首次 1581/1 加定向 2/2 描述为一次完整全绿。
- 第三次录制完成文件增长、停止、封装与监控取消；代理自动恢复失败。
  后续完整解码又发现 H.264 损坏，因此不把文件非空、ffprobe 成功或退出码 0 当作全部通过。
- 本批应用源码未变化，复用现有 APK；只修订设备测试脚本与文档。
  没有升级版本、上游合并、推送或发布。

## 目标与保留数据安装

所有设备轮次使用 `run_android_device_test_turn.ps1 -NoRotation -Serial 192.168.1.2:5555`。
先核对 `25102RKBEC / myron`，每条设备命令绑定 `-s`。
用户提供的 MT 管理器当时在前台；明确启动本项目进入安装/恢复流程，没有向 MT 输入、停止 MT 或修改其配置。
未调用 Root、LSP 或 MT MCP；未重启手机/adbd、改 Wi-Fi/端口/授权、更新模块或清数据。

安装证据：`local-artifacts/android-2006c044-native-20260907/`。

| 项目 | 实际结果 |
| --- | --- |
| 时间（UTC） | 08:16:55–08:17:18 |
| 安装方式 | 停止本项目后 `install -r -t`，Success |
| 安装前主 Hive | 348,274 B；SHA-256 `AF3E3CCB602FFE298F7B049FCF31524263A7B9DE27A36AC5BDDA6C230869D915` |
| 安装后、首次启动前 Hive | 字节与上述 SHA 完全一致 |
| 设备 base.apk | SHA-256 `41223C88A81A62F54AC790EF5878D9C136EB725B3807D9E4A55B273C15BB8B4D`，与候选一致 |
| 首次启动 | COLD，TotalTime 1995 ms / WaitTime 2100 ms |
| 首页 | 1200×2608 PNG/XML；原关注列表可见，平台 TabBar 共 13 项 |

首次启动后 Hive SHA 改为 `215BFF35D127D6E5B941D66E99143A27DDFD571AC99E2E1BB2FE1A16944337F8`。
这不是启动后全配置字节不变的证据；配置迁移与运行时写入的语义对账未完成。
Hive 备份仅保存在本机忽略目录，不进入 Git。旧 `af88a032` 回滚 APK 保留。

## 代理独立往返与两次入口失败

独立代理往返先通过：设置完成 08:19:52 UTC，恢复完成 08:20:08 UTC；
两个原开关均为 false，临时 reverse 由本轮创建并移除，session 为 `restored`。
证据为安装目录下 `proxy-setup/`、`proxy-restore/`、`proxy-roundtrip-session.json`。

后续原生录制没有跳过失败记录：

1. `android-recording-smoke-20260907T162224839`：旧入口先 force-stop 本项目，
   底层 MT 随即成为前台，守卫阻止继续启动。未进入 Picarto、未创建录像。
   后续明确启动本项目并恢复代理，08:24:53 UTC session restored。
   中途 summary 的 noFatal=false 来自提前退出缺少日志，不据此推断应用崩溃。
2. `android-recording-smoke-20260907T162614043`：试验提交 `18c3822e` 用 Activity flags
   取代 stop/start；实机返回 WARM 94 ms，但 Flutter 路由仍在代理页，找不到“热门”。
   未进入 Picarto、未创建录像。明确恢复于 08:29:33 UTC 完成。
3. `5f41a19e` 不再假定 Activity flags 重置页面，按新 XML 中真实“返回”逐页回首页，
   并将代理恢复移到录制器 force-stop 之前。73 个守卫场景、6 个包装器测试通过。
   第三次原生运行实际用两个返回动作进入首页，成功打开 Picarto。

明确恢复的入口只用于本轮用户提供的 MT 工具与本项目之间切换；一般自动化守卫仍不接管其他应用。

## 第三次原生短录：成功部分与失败部分

证据：`local-artifacts/diagnostics/android-recording-smoke-20260907T163502928/`。
测试工具来源 `5f41a19e`，运行 16:35:03–16:38:36（UTC+8）。

| 项目 | 实际结果 |
| --- | --- |
| 平台/房间 | Picarto / HuckleberryBleu，实际热门目录进入 |
| 播放画面 | 初始截图黑色；`room-recording.png` 后续出现实际视频画面；不外推持续流畅/声音实听 |
| 画质/线路 | `720p 30fps` / `线路1`，各只有一个选项；切换结果均为 **SKIP** |
| 弹幕 | 系统提示远端尚未接入；无真实聊天连接验证 |
| 运行中文件增长 | TS 524,288 → 1,048,576 B，间隔 15.984 秒 |
| 墙钟/媒体时长 | 录制墙钟 26.088 秒；MP4 22.081666 秒 |
| 启动/停止测量 | recordStartMs 17,110；stopFinalizeMs 24,675，含测试观察开销，非纯引擎性能 |
| 文件 | `20260907_163655_889.mp4`，7,283,715 B |
| SHA-256 | `DC532468BBD5BD6FCEBB7778F624C35BD5BC8A5B40F62DD404A6BFFB7BE2CA24` |
| ffprobe | H.264 1280×720 30 fps，AAC 48 kHz 双声道 |
| 状态/资源 | 当前录制停止、监控取消，进程消失、活动唤醒锁释放，未发现目标 FATAL/ANR |
| 整轮结果 | **FAIL**：proxyRestoredBeforeStop=false，嵌套滚动容器被判歧义 |

录制中心截图包含一张 **09-06 的历史斗鱼失败卡片**，其后台时限文案不是本次 Picarto 失败。
本次 Picarto 卡片仅部分可见，详细卡片/大小/全部动作的视觉验收继续；不把测试布尔值当作完整截图证据。
实机还观察到房间头部显示 `site_picarto` 原始键和默认头像，语言标签缺口待修订。
本次未执行息屏、独立后台、长录、第二次签名续接、多画质、多线路或物理投屏。

### 完整解码失败，独立于代理恢复失败

本机对提取的 MP4 执行全视频/音频解码：

- 普通 `-v error -xerror -threads 2 ... -map 0:v -map 0:a -f null -` 返回 0，
  **错误日志 73 B**，含 `error while decoding MB 59 40, bytestream -25`。
- 加 `-err_detect explode` 后返回 **-1094995529**，错误日志 648 B，
  `strict-decode.json` 明确 `passed=false`。
- 因此普通命令的退出码 0 不代表无解码错误。保留原文件与两份日志，不覆盖为成功结果。
- 当前只有最终 MP4，记录清单不再包含原 TS；损坏来自直播源、接收、停止边界还是封装尚未定位。
  下一步先审查日志/录制边界代码并设计源与输出对照，再决定最小实机复验。

## 嵌套滚动修订与最终设备收尾

第三次在返回首页后，悬浮播放器外层暴露 scrollable View；设置页内部另有 ScrollView。
实际 XML 中前者 `[0,0][1200,2608]`，后者 `[0,312][1200,2608]`，不是两个独立设置列表。

- 使用该实际 XML 新建离线夹具，旧函数稳定复现“scroll container is missing or ambiguous”。
- 修订为只接受唯一、边界包含一致的嵌套链，选择内层视口；兄弟容器、缺失容器、
  边界冲突和非目标前台仍停止，不以固定坐标或重试代替观察。
- **25 个代理事务场景通过**，实际 ADB 命令 0；新修订尚未经历完整原生录制回归。
  红/绿日志在安装证据目录 `nested-scroll-red.log` / `nested-scroll-green.log`。

先完成实际恢复，再修订脚本：第三次 session
`foreign-proxy-session-6657075f28304b7abdad64a0b1c39728/session.json`
于 **08:42:01 UTC** 恢复为 `restored`，ownedReverse=false、reverseUncertain=false、
uiMayHaveChanged=false，两个开关恢复原来的 false。证据 `explicit-proxy-recovery-3/`。

最后 08:46:21 UTC 再次按型号、代号、当前前台核对后，只停止本项目，
`final-device-cleanup.json` 确认进程消失、tcp:7897 reverse 不存在、活动唤醒锁中无本项目。
包装器最后输出 StayAwake=false。没有遗留本轮录像监控或测试代理。

历史矩阵仍是 42 个未闭环大项，另有 16 组参考平台未注册；本批没有把它们改成 PASS。
