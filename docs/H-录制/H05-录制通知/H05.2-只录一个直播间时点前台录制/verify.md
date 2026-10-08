# H05.2 只录一个直播间时，点前台录制通知也定位到那条任务：真机验证

- 设备：Redmi K90 Pro Max（Android 17，120 Hz，`192.168.1.2:5555`）
- 构建：`com.mystyle.purelive.v4dev`，含 `[H05.2]` 提交的 master（debug 或 profile 都行；H05.3 的 verify 可以用同一个构建一起做）
- 日期：（验证时填）；验证人：（验证时填）
- 准备：录制中心里先留十几条别的任务（已保存、等待开播），让正在录的那条不在第一屏；关注里有两个正在直播的国内直播间（下面叫 A、B）。每次点按前确认前台是测试包，不碰 3.x 和正式包。截图放本文件夹的 `verify/`。

| 步骤 | 期望 | 结果 | 截图 |
|---|---|---|---|
| 1. 在 A 开始录制，回到桌面 | 通知“正在录制 · A 的主播名” | | `verify/01.jpg` |
| 2. 下拉通知栏，点通知本身 | 录制中心打开（筛选“全部”），滚到 A 的任务，主色描边约 2 秒后淡掉 | | `verify/02.jpg` |
| 3. 回桌面，点通知上的“录制中心”按钮 | 同第 2 步 | | `verify/03.jpg` |
| 4. 再录 B，回桌面点通知 | 录制中心打开在顶上，没有高亮 | | `verify/04.jpg` |
| 5. 停掉 B，等它整理完；回桌面再点通知 | 又定位到 A 的任务 | | `verify/05.jpg` |
| 6. 停在录制中心时点通知，然后按一次返回 | 不叠出第二个录制中心；返回到进录制中心之前的页面 | | — |
| 7. 关“自动断线重连”，让 A 在后台断网失败（同 H05.1 verify 第 7 步），点“录制已停止”提醒；之后把开关改回 | 照旧定位到失败的那条 | | `verify/07.jpg` |

## 结论

- 通过：登记表 `docs/tasks.toml` 的 H05.2 改成“完成”，写日期；运行 `python3 tools/docs/docs.py`。
- 不通过：
  - 不定位：看 `apps/pure_live/lib/app/recording_notice.dart:49`（一个活动任务时的 `task`）、`apps/pure_live/lib/platform/recording_platform.dart:373`（`extra`）、`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:52`（读 `task`）、`:340`、`:342`（点按、按钮）。
  - 录两个时还定位到旧任务：`FLAG_UPDATE_CURRENT` 没替换附加数据，看 `openRecordings`（`RecorderForegroundService.kt:175`）。
  - 找不到卡片（只到顶上）：A10.1 的定位行为，记下现象交维护者。
