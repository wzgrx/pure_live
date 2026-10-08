# H05.3 录制通知在合并时显示进度：真机验证

- 设备：Redmi K90 Pro Max（Android 17，120 Hz，`192.168.1.2:5555`）
- 构建：`com.mystyle.purelive.v4dev`，含 `[H05.3]` 提交的 master（debug 或 profile 都行；可以和 H05.2 的 verify 用同一个构建）
- 日期：（验证时填）；验证人：（验证时填）
- 准备：关注里有两个正在直播的国内直播间（下面叫 A、B）；录制设置的分段时长设 5 分钟。每次点按前确认前台是测试包，不碰 3.x 和正式包。截图放本文件夹的 `verify/`。

| 步骤 | 期望 | 结果 | 截图 |
|---|---|---|---|
| 1. 在 A 开始录制，录 10 分钟以上，点“停止录制”，马上下拉通知栏 | 标题“正在整理录像 · A 的主播名”，正文“直播间标题 · 清晰度 · 42%”这样末尾的百分比在涨，下面有进度条；右上角没有计时 | | `verify/01.jpg` |
| 2. 同时打开录制中心对照 | 通知的百分比和录制中心卡片上的一致（最多差 1 秒的更新） | | `verify/02.jpg` |
| 3. 等整理完 | 通知消失（或变成没有任务时的样子），没有残留的进度条；录制中心显示“已保存” | | `verify/03.jpg` |
| 4. 同时录 A 和 B，停止其中一个，下拉 | 标题“正在录制 2 个直播间”，没有进度条 | | `verify/04.jpg` |
| 5. 再录 A 10 分钟后停止，整理时把应用划到后台、锁屏 1 分钟再看 | 进度继续走，没有卡在某个数 | | `verify/05.jpg` |

## 结论

- 通过：登记表 `docs/tasks.toml` 的 H05.3 改成“完成”，写日期；运行 `python3 tools/docs/docs.py`。
- 不通过：
  - 没有百分比：看 `apps/pure_live/lib/app/recording_notice.dart:57`（只在一个任务、`processing`、FFmpeg 报了进度时有）。
  - 百分比不动或跳得慢：看 `apps/pure_live/lib/platform/recording_platform.dart:229-280`（节流，每秒最多一次，到点补发最新的）。
  - 没有进度条或进度条不消失：看 `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:352-353`。
  - 整理时还有计时：看 `recording_notice.dart:52`（`since` 只算录制中、重连中）。
