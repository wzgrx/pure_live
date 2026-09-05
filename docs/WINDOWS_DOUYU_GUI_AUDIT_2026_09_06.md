# Windows 斗鱼 GUI 验收与长暂停恢复缺口（2026-09-06）

## 候选与前置质量

- 应用源码 `6babe449`，开发版本 **3.1.8+4121 Debug**，不是正式 3.2.0。
- 全 `test/` 目录 **1140/1140**：`20260905T223642019Z-quality-focused.json`，337.044 秒，结束活跃重型进程 0。这是 Focused 入口承载全测试目录，非完整发布门禁；新增返回手势测试不包含在其中。
- Windows 构建：`20260905T224414183Z-build-windowsx64-debug.json`，432.148 秒，结束活跃重型进程 0。应用源码已提交；外部 AGENTS.md 修改使元数据 `tracked_files_dirty=true`，不宣称整个工作树干净。
- ZIP 141,198,322 字节，SHA256 `8c75a8a8900b8b2055934b40511eb6adefb5b20c9b5974ed9063146436689c53`；CRC 与解压路径检查通过，解压到 `local-artifacts/candidates/windows-6babe449-debug/`。保留 MSB8028 / CMake DEPENDS 构建警告，尚未证明关联运行缺陷。
- 以独立实例 `acceptance_6babe449_20260906` 启动；预置空 shared_preferences 避免导入用户历史数据。本轮没有手机操作、上游合并或公开附件替换。

## 实际操作与证据边界

时间均为北京时间。原始日志及 JSON 位于上述候选目录。

| 操作 | 结果 |
| --- | --- |
| 空关注启动、热门 Bilibili / Douyu 列表 | 可见卡片正常载入 |
| 斗鱼 pigff，房间 24422 | 06:46:22 原画 1080P60、线路 1，实际游戏画面与弹幕 |
| 切蓝光 4M，再切线路 2 | 06:46:56 / 06:47:23 提交相应标签，线路从 hw1a 到 huos1a，画面继续变化 |
| 录制菜单立即启动、录制中心停止 | 独立录制默认最高档 / 线路 1；42 秒后完成文件，不与观看的 4M / 线路 2 混淆 |
| 录制中心返回观看 | 保留 4M / 线路 2，视频呈现 |
| 双击视频全屏、Esc | 返回普通窗口且未退出房间 |
| 全屏画质菜单 | 本轮点击未得到菜单证据，未计通过 |
| Windows 原生小窗进入 / 退出 | 356×200 小窗口有动态画面；退出保留暂停状态。此项不是 Android 应用内 Overlay 验收 |
| 暂停约 90 秒再恢复 | **失败**：短暂旧帧后反复 EOF / 恢复，随后黑屏，弹幕仍更新 |
| 返回列表重新进入同房间 | 重新取流后产生新帧；窗口随后曾显示未响应，故仅记媒体恢复，不记整个 UI 恢复通过 |

## 录制文件验证

- 文件 `AppData/acceptance_6babe449_20260906/RECORDS/douyu/pigff/2026-09-06/06-47-45/20260906_064745_586.mp4`。
- 58,798,735 字节；SHA256 `56646031956c44d32b8d7c29182a6700646af2fa31d13fc28293cae1da902b4d`。
- ffprobe：H.264 1920×1080、60 fps、AAC，时长 42.151667 秒。
- FFmpeg `-v error -xerror -err_detect explode -threads 2` 全文件解码 5.9335 秒、退出 0、错误日志为空、结束活跃重型进程 0。
- 证据：`recording-ffprobe.json`、`recording-full-decode.json`、`recording-decode.log`。文件解码通过不证明扬声器听感已验收。

## 长暂停恢复失败

1. 日志 session 3 于 06:53:31.461727 暂停，06:55:02.245246 恢复，frameAge 约 90,799 ms。
2. session 4–8 反复 `complete=true` / `live_source_completed`，先重试当前 huos1a，随后回退 hw1a。
3. session 9 于 06:55:57 出现 `source_runtime`；日志最后进入 recover，没有随后新帧。
4. 07:00:22 的房间接口仍为 `show_status=1`、`videoLoop=0`，见 `room-status-after-black.json`。不归因为主播下播。
5. 只读 VM 快照：session 9、`_playbackRequested=false`、`_nativeLoading=true`、`_sourceRefreshResolver=null`，连续性 / buffering / video-frame timers 为空。见 `manager-field-snapshot.json`、`manager-related-snapshot.json`；尚需源代码合同解释，快照本身不证明唯一根因。
6. 07:03:54 重新进入同房间后 session 14；07:03:55 frameRevision 从 874 增为 875，原生帧继续回调。此前窗口有未响应、stderr 有 AXTree 错误，两者因果待查。
7. 后续进程复核旧 PID 41176 已不存在；本轮未观察其退出原因，不记为主动正常退出或确认崩溃。

## 下一步与发布状态

优先从暂停恢复、旧地址重试、错误终态和 watchdog 所有权定位第一处错误状态，建立确定性回归；再用新候选核验相同步骤。Windows 长暂停恢复和 UI 响应仍是发布前缺口，继续保留完整平台与功能验收范围。上述局部成功不等同于全平台稳定版完成。
