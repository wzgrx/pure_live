# Android 应用内小窗、国外平台与 AcFun（2026-09-06）

## 范围与候选

复用已验证并安装的 `c252e522` Android Debug（应用源码同 `7ba627fd`），没有重复构建。所有设备步骤均经 `run_android_device_test_turn.ps1 -NoRotation`，网络ADB在线优先；结束恢复常亮与临时代理。本批次只扩展验收脚本的 AcFun 平台入口及平台能力检查，不改应用代码。

## 应用内小窗与长暂停

证据 `local-artifacts/diagnostics/android-overlay-c252e522-20260906/`，08:54–08:59。

- 先在设置确认“退出小窗播放”本来已开启，未改用户配置。
- 斗鱼 pigff 24422：设置超清/线路2后返回列表，应用内 Overlay 有实际画面。这与系统 PiP 是不同路径。
- 点按小窗显示控件，再暂停。截图播放图标及 Android MediaSession `PAUSED(2)` 双重确认；约 **94.163秒**后恢复，MediaSession `PLAYING(3)`，后续游戏画面变化。时长由同一 MediaSession 的 updated 单调时钟差计算，不使用工具等待时长估计。
- 再次暂停并通过小窗重入直播间：MediaSession 仍为 `PAUSED(2)`，updated 未变，页面保留超清/线路2，未擅自恢复播放。
- 返回列表后关闭小窗：Overlay 节点消失，MediaSession `NONE(0)`。本轮普通关闭的是播放器，不以应用进程存活判为失败。
- 未观察到黑屏终态或被迫新源恢复，不宣称已验证失效地址 resolver；Android 成功也不替代旧 Windows 黑屏场景复验。

非阻塞后续项：小窗暂停/关闭按钮及普通播放暂停按钮在原生无障碍树中缺少文字标签；本轮由可见控件和 MediaSession 校验操作，不借此扩大为新的 APK 批次。

## Twitch：通过

证据 `android-recording-smoke-20260906T090026437/`，09:00:26–09:03:32。

- 本地Clash 7897通过ADB reverse使用；应用层与播放器代理均启用。1080P60（原画）切到160P，3196ms，实际画面与标签一致；观察到6条实际弹幕。只有线路1，**未发生线路切换**，不把条件通过算成多线路验收。
- 独立录制仍为1080P60 H.264/AAC，32.016秒，19,133,626字节；SHA256 `4764f03c236b5218911db57839839e86421db6d4adaf5ab002625b51395d3ec5`。
- 严格完整解码退出0、错误日志空，2.999秒。对应文件 `recording-full-decode.json`。
- 清理证据 `android-proxy-disabled-20260906T090332558/summary.json`：两个代理开关false，reverse已移除。无前台干扰，测试监控移除。

## AcFun：Android实际观看与短录通过

证据 `android-acfun-c252e522-20260906/`，09:05:03–09:07:42，林梦仙 / 主机单机。

- 原脚本参数枚举缺少 AcFun，现增加标签与入口，远端弹幕能力沿用应用真实状态为未接入；没有伪造“弹幕已连接”。10个平台标签/能力合同和实际AcFun中文标签检查通过，加入本地质量入口。
- 蓝光4M切超清，3095ms，截图呈现实际画面、在线人数和超清标签。只有线路1，未发生多线路切换；远端弹幕未接入说明清晰可见，视频里主播嵌入的聊天画面不计为本应用收到弹幕。
- 录制33.560333秒，5,381,187字节，1080P H.264/AAC；视频平均30fps，时间戳为可变间隔，不能用r_frame_rate=60000/1001单独宣称60fps。SHA256 `910bf5bfec499545f812d405f4634a0590434f818b9c76b22cc328d35779c183`。
- 首次完整解码退出0，但默认null输出器记录7条非递增DTS消息。定向检查1003个源视频包：DTS严格递增，倒退0/重复0。保留源1/90000时间基、`-fps_mode:v passthrough -enc_time_base:v 1:90000`再次完整解码退出0且日志空。这一对照定位到验证输出时间基问题，不改应用时间戳、不隐藏第一次日志。证据 `video-packet-summary.json`、`recording-timebase-decode.json`。

## Soop：新增未闭合失败

证据 `android-recording-smoke-20260906T090836392/`，09:08:36–09:11:03，두치와뿌꾸。

- 本地Clash下观看可见、4条实际弹幕，原画→标清提交8305ms。只有线路1。
- 启动录制后页面显示录制中，但30秒增长观察未找到正向文件增长，原错误 `The active recording file did not show positive byte growth.`。现有脚本finally随后force-stop，所以它不是应用自行给出的终态错误。
- 停止后查看该平台私有录制目录，没有本轮9月6日的新媒体文件；既有9月2–5日文件保留。重启录制中心，本次卡片已停止、没有时长/大小或持久错误详情。常规logcat未保存原生FFmpeg会话诊断，尚未区分新源请求、HLS代理输入、原画线路或启动阶段阻塞；不把它归为已确认网络故障或已修复。
- 原自动清理没有移除失败后监控，已手动定位本轮Soop卡片执行“取消监控”并确认；`owned-monitor-removed.xml`与`manual-monitor-cleanup.json`证实本轮卡片消失，历史YY卡片保留。应用已force-stop。代理清理 `android-proxy-disabled-20260906T091103627/summary.json` 已完成。

## 下一步

优先补强失败时的首个无效状态证据：复用当前Debug候选，在有界Soop重现中读取活跃FFmpeg会话/输入relay状态与文件观察，再判断代码修复；不盲目拉长增长超时。随后继续终态重试、其他平台和Windows候选验收。完整清单与3.2.0正式发布仍未完成。
