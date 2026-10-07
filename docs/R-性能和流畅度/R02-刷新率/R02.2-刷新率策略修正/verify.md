# R02.2 刷新率策略修正：真机验证

- 设备：Redmi K90 Pro Max（Android 17，HyperOS，显示模式只有 60 / 90 / 120 Hz，`192.168.1.2:5555`）
- 构建：`com.mystyle.purelive.v4dev`，合并后的 master（包含提交 `584da6662` 的任一提交；debug 或 profile）
- 日期：YYYY-MM-DD；验证人：……
- 准备：
  - 开发者选项打开“显示刷新率”（右上角数字）；系统设置 → 显示 → 屏幕刷新率是“高”（120）。
  - 应用：设置 → 通用 → “界面刷新率”选“均衡”，“播放时匹配视频帧率”开着。
  - 电脑上 `adb -s 192.168.1.2:5555 shell` 可用；下面两条命令的输出贴进本文件夹的 `verify/`（文字即可）：
    - `adb shell dumpsys SurfaceFlinger | grep -iE "renderRate|activeMode=|frameRate"`
    - `adb shell dumpsys display | grep -iE "mVotes|PRIORITY_|appRequest" -A2`
  - 视频帧率怎么看：4.x 没有“统计信息”面板。把“界面刷新率”临时改成“省电”时，应用在 Flutter 画面上声明的就是视频本身的帧率，`dumpsys SurfaceFlinger` 里 `SurfaceView[com.mystyle.purelive.v4dev/...]` 那一层的帧率投票就是它；看完改回“均衡”。
  - 只点测试包，不碰正式包和 3.x。

| 步骤 | 期望 | 结果 | 截图 |
|---|---|---|---|
| 1. 进一个 60 帧的直播间（先按“准备”的办法确认帧率是 60；哔哩哔哩、斗鱼的游戏直播多数是 60），不碰屏幕 10 秒 | 右上角 60；`dumpsys SurfaceFlinger` 里 Flutter 那一层投 60（`ExplicitExact` 或 `ExplicitExactOrMultiple` 字样），窗口的 `preferredRefreshRate` 是 0 | | |
| 2. 拖聊天列表或竖屏面板 | 100 毫秒内到 120；那一层投 120；松手约 1.5 秒回到 60 | | |
| 3. 进出这个直播间各三次 | 不黑屏、不闪 | | |
| 4. 进一个 30 帧的直播间（同样先确认），不碰屏幕 | 60（30 的整数倍里不超过 60 的） | | |
| 5. 网络电视导入一个 25 帧或 50 帧的源（或照 V03.2 调研 1.7 节用 ffmpeg 生成带帧号的 HLS 放在电脑上），播放，不碰屏幕 | 右上角 120，不是 60（没有整数倍取最高） | | |
| 6. 回首页（不播放），均衡档在列表上滑动，再停 2 秒 | 滑动时 120，停下约 1.5 秒后回落；`dumpsys SurfaceFlinger` 里 Flutter 那一层是 `ExplicitGte`（或 AT_LEAST 字样）120（Android 17 走 `AT_LEAST`） | | |
| 7. “界面刷新率”改“最高”，在首页停 10 秒 | 一直 120（画面静止时 HyperOS 若自己降到 60，记下，属于系统行为） | | |
| 8. 系统设置 → 显示 → 屏幕刷新率改成“标准”（60）；回到应用，均衡档在设置页上下滑动 3 秒以上 | “界面刷新率”下面出现黄色的“系统把本应用限制在 60 Hz，可以在系统设置 → 显示 → 屏幕刷新率里调高”；改成“省电”时这行不显示 | | |
| 9. 系统刷新率改回“高”，回到应用再滑一下 | 提示消失 | | |
| 10. 点“界面刷新率” | 对话框三个选项下面是中文说明（3.x 原文），不是 `refresh_rate_..._desc` | | |
| 11. 均衡档，在第 1 步的直播间里拖面板，同时看首页列表页拖动（对比） | 如果播放中拖面板仍是 60、列表页能到 120，就是 HyperOS 按场景限制（V03.2 调研 1.3 节的推测）：记下，此时第 8 步的提示应在播放中出现 | | |
| 12. 第 1～2 步时各截一份 `dumpsys display` 的 mVotes | 贴进 `verify/`：看 `PRIORITY_MIUI_REFRESH_RATE` 的上限在 60 和 120 之间怎么变 | | |

## 结论

- 通过：登记表 `docs/tasks.toml` 的 R02.2 改成“完成”，写日期；在 [R02.1 的记录](../R02.1-刷新率和帧率匹配/record.md) 末尾补一句“K90 结果见 R02.2 verify.md”；运行 `python3 tools/docs/docs.py`。
- 不通过：写现象和根因线索。第 1、2 步不对：看 `dumpsys SurfaceFlinger` 里那一层的投票是不是我们声明的值（是 → 系统没采纳，属于厂商限制；不是 → `MainActivity.kt:784` 的 `applyRefreshRate` 或 `display_mode.dart:279` 的 `_applyRate`）；第 3 步闪屏：`CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS` 没生效，记录模式切换；第 8 步误报或不报：`display_mode.dart:301-356` 的计时。开新任务或退回。
- 顺便请维护者对记录“需要维护者决定的”三条表态（特别是 144/165 Hz 屏空闲时的上限）。
