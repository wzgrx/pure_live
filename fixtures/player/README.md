# 播放器事件轨迹

用真实 libmpv（关掉视频输出）播放本地回环服务器提供的合成 FLV，记录 media_kit 的全部事件。v4 只保留一个回放这些轨迹的测试替身（诊断 06 ⑥-4；`spec/modules/playback.md` §4 EVT-13～EVT-19）。

- 录制器：`tool/probes/player_event_trace_probe_test.dart`；环境、mpv 版本、实际生效的 mpv 选项见 `meta.json`。
- 媒体：ffmpeg `testsrc2` + `sine` 合成，H.264/AAC，320×180，每秒一个关键帧，8 秒，没有时长元数据（和直播流一样）。
- 每行一个事件：`ms` 是从场景开始算起的毫秒数；`command` 是录制器的操作，`server` 是回环服务器的动作，其余是 media_kit 的事件流。position 和 duration 按 500 ms 节流。

| 场景 | 服务端行为 |
|---|---|
| `eof` | 按媒体时间实时发送，发完正常结束 |
| `stall` | 发 3 秒后停止发送，连接保持 15 秒再关闭 |
| `reset` | 发 3 秒后直接断开（不发 chunked 结束块） |
| `http403` | 返回 403 |
| `garbage` | 返回 200 和一段不是媒体的数据 |
| `pause_resume` | 实时发送；第 3 秒暂停 3 秒后恢复 |
| `reopen_after_403` | 第一次打开 403，同一个播放器再打开正常地址 |
| `stop_while_buffering` | 断供期间调用 stop() |

重录：

```bash
PURELIVE_TRACE_LIB=<libmpv.so> PURELIVE_TRACE_MEDIA=<合成.flv> \
  flutter test tool/probes/player_event_trace_probe_test.dart
```

还缺：Windows 和 K90 上带真实视频输出的轨迹（首帧、宽高、硬解回退）。
