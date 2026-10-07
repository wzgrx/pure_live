# H01.4 录制余项：任务书

> 任务书模板（v2）。这个任务以真机验证为主：在 K90 上把录制还没验证的功能逐项看完，写结果、改功能清点；发现的问题另开任务修，本任务不改代码。

## 背景

- 来源：清点。[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 11 节“录制（REC）”在登记时统计为“1 项缺失、5 项没验证”；之后 H01.3 做完了缺失的 F-REC-13（合并进度），S02.3 在 K90 上录过一场（5 分 39 秒、两段合成一个 MP4），所以现在实际剩下：F-REC-06、F-REC-07、F-REC-10、F-REC-11 四项没验证，F-REC-03 备注“没在真机录完一场”，以及 [H01.3 记录](../H01.3-合并进度/record.md)“要在 K90 上看的”两条（清晰度标签、合并进度）。
- 现象：这些功能的代码和单元测试都在，但关键部分靠 Android 前台服务、系统权限页、真实平台的弹幕连接、真实 CDN 的 HLS，单元测试覆盖不到；没在真机看过就不能算完成（[PROCESS.md](../../../PROCESS.md) 第 3.2 节）。
- 为什么现在做：第二档。录制是 3.x 用户在用的功能；H01.5（第一档）合并后再做，第 1、3 步顺便验证 H01.5 没有把正常的重连弄坏。相关决定：D-019（K90 随时可用，只点测试包）。
- 已经做过的：S02.2（录 75 秒、通知和录制中心）、S02.3（录 5 分 39 秒两段合成；划掉应用没成功）。

## 目标和验收

1. F-REC-03：录 30 分钟以上（默认切片 5 分钟，至少 6 段）后停止，合成一个 MP4，系统播放器能从头放到尾，时长和录制中心显示的一致；分段 `.ts` 和日志 `.clock-v1.csv` 被清掉。
2. F-REC-06：录制中从最近任务里真正划掉应用，5 分钟后再打开：录制没断（文件一直在变大），录制中心是当前状态；如果 HyperOS 杀了进程，记下现象，并确认下次打开时把被杀时的分段合成了 MP4（任务“已停止”）。
3. F-REC-07：录制设置里把目录换到 `Download/` 下：先出说明，再打开系统“所有文件访问”页；允许后能写入（目录下出现 `PureLiveRecords/`）；拒绝时有提示、目录不变。
4. F-REC-10：录制设置开“同时录制弹幕”，录哔哩哔哩一个弹幕多的直播间 5 分钟：MP4 旁有同名 `.xml`，用文本编辑器打开是完整的 XML（以 `</i>` 结尾），弹幕时间和画面大致对得上（误差在几秒内）。
5. F-REC-11：走代理录一个海外 HLS 平台（Twitch 或 YouTube）30 分钟：录制中心不出现“有缺口”，或者比关掉预取时少（关预取要改代码，做不到时只记录“有没有缺口”）。
6. H01.3 清晰度：游客（没登录哔哩哔哩）录一个录制面板只列出“原画”的哔哩哔哩直播间：面板、通知、录制中心写平台实际给的清晰度（720p 应是“超清”）；开始后提示一次“平台实际返回 超清，已按真实画质录制”；断网重连后不再提示。若仍写“原画”且没有提示，说明平台当时确认的就是 10000，标签是对的，照实记下。
7. H01.3 合并进度：第 1 条停止后，“正在整理文件”标题右边有百分比、下面有进度条，走到底变“已保存”；录制中心同一张卡也一样。
8. 每条结果写进本文件夹 `verify.md`（结果、截图），功能清点第 11 节对应行和统计行改好；不通过的开出新任务并在 `verify.md` 写清现象和根因线索。

## 现状（读代码得出，写文件:行）

- 前台服务：`apps/pure_live/android/app/src/main/AndroidManifest.xml:141-145`（`dataSync`、`stopWithTask="false"`）；`RecorderForegroundService.kt:86` 起：唤醒锁、Wi-Fi 锁、录制期间绑定 audio_service 的媒体服务（防止后台播放结束时缓存的 Flutter 引擎被销毁），`onTimeout` 报给 Dart；`MainActivity.kt:88` 是 `AudioServiceActivity`（引擎缓存，划掉 Activity 不销毁引擎）。被杀后的恢复：`packages/live_record/lib/src/recorder.dart:1203-1302`（`restore` 把录制中被杀的任务的分段合并，标“已停止”）。
- 存储权限：`lib/platform/recording_platform.dart:321-345`（`androidStorageAccess`：可写就通过；只在用户操作时先说明 `explain` 再申请；API 30+ 打开“所有文件访问”页，返回后再查）；`RecorderPlugin.kt:173-200`（`requestStorage`，先试本应用的设置页 `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`，不行再开总页）。
- 弹幕 XML：`packages/live_record/lib/src/chat.dart`（`RecordChatRecorder` 看 `Recorder.changes`，录制中的任务保持一个连接；`RecordChatWriter` 每 2 秒写入并重写 `</i>`；时间以这次尝试进入“录制中”为 0）；连接器 `lib/app/recording.dart:43`（`recordChatConnector`：`DanmakuRegistry.connectionFor`、屏蔽词和屏蔽用户过滤、断开 30 秒后重连）。
- HLS 预取：`packages/live_media/lib/src/relay/hls_window.dart`（每个媒体列表最多 4 个并行、窗口 48 段、96 MiB 上限）；录制的中继默认打开（`packages/live_record/lib/src/input.dart:22-25`）；漏段由 FFmpeg 日志判定（`capture.dart:109-113`）。
- 清晰度和合并进度：`packages/live_record/lib/src/resolver.dart`（`servedQuality`）、`recorder.dart:480-483`（受限提示一次）、`merge.dart:137-151`（进度）、`apps/pure_live/lib/shared/record/record_status_card.dart`（“正在整理文件”的百分比和进度条）。
- 功能清点：第 11 节表格（F-REC-01～13）和开头“统计”一节的表（录制那一行仍是完成 7、部分 0、缺失 1、有问题 0、没验证 5；按表格实际是 9、0、0、0、4）。

## 3.x 基线

- 3.x 的同样功能：`git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt`（前台服务，`:229-248` 通知只写“直播录制进行中”）、`lib/recorder/pages/recorder/recorder_controller.dart:665`（存储权限）、`lib/recorder/services/recording_danmaku_service.dart`（弹幕 XML，结束时才写 `</i>`）、`lib/recorder/services/hls_relay_prefetch.dart`（预取）。
- 要保留的行为：划掉应用不停录制（3.x 同样 `stopWithTask="false"`）；只有用户操作时才弹权限页，自动恢复时不弹（3.x `requestIfMissing: false`）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.2 节状态、第 10 节真机验证、第 14 节规则）。
2. 本文件夹的 [README.md](README.md)；[S02 真机清单](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 3 节；[S02.3 记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)；[H01.2 记录](../H01.2-录制补全/record.md)“没验证的部分”；[H01.3 记录](../H01.3-合并进度/record.md)“要在 K90 上看的”。
3. 用户的设备约定：只操作测试包 `com.mystyle.purelive.v4dev`，每次输入前确认它在前台；不碰 3.x 和正式包（D-019）。

## 范围

- 可以改：本文件夹的 `verify.md`、`verify/` 截图、`record.md`；`docs/inventory/FEATURES.md` 第 11 节和统计表的录制那一行；登记表里本任务的状态，以及新开的修复任务。
- 不能改：任何代码；其他组的文档；版本号、`assets/version.json`、`assets/releases.json`；签名配置；手机上的 3.x 和正式包、它们的数据。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 不要代理的几项 | 验收 1、2、3、4、6、7 | `verify.md`、`verify/*.jpg`、`FEATURES.md` 第 11 节 | 六条都有结果和截图；通过的在功能清点改“完成”，不通过的开了任务 |
| 2 要代理的一项 | 验收 5（F-REC-11） | 同上 | 有结果（或写明“代理不可用，推迟”并留在“没验证”） |

## 测试

- 本任务不改代码，不加自动测试。验证前在合并后的 master 上跑一遍 `apps/pure_live` 的 `flutter test test/features/recorder` 和 `packages/live_record` 的 `dart test`，确认构建的代码本身是绿的。
- 构建：`flutter build apk --profile`（测试包），装到 K90：`adb -s 192.168.1.2:5555 install -r <apk>`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 录制设置：切片时长 5 分钟、开“同时录制弹幕”；在哔哩哔哩一个弹幕多的直播间点录制 → 立即录（游客状态） | 面板、通知、录制中心写平台实际给的清晰度，开始后提示一次“平台实际返回 …，已按真实画质录制”（验收 6） |
| 2. 录满 5 分钟后，在最近任务里把纯粹直播 v4dev 的卡片真正划掉（向上甩出屏幕，确认卡片消失） | 通知栏的“正在录制 · 主播”还在；`adb shell ls -l` 看分段文件，大小一直在涨（验收 2） |
| 3. 5 分钟后从桌面图标重新打开应用，进录制中心 | 任务是“录制中”，时长接着涨；若进程被杀：任务是“已停止”，目录里有被杀时那几段合成的 MP4，记下现象 |
| 4. 一共录满 30 分钟后在录制中心点“停止” | “正在整理文件”有百分比和进度条，走到底变“已保存”（验收 7） |
| 5. `adb shell ls -lR /sdcard/Android/data/com.mystyle.purelive.v4dev/files/Records/bilibili/` | 时间文件夹里一个 MP4 和同名 XML，没有 `.ts` 和 `.clock-v1.csv`；把 MP4 拉到电脑上用播放器从头放到尾，时长和录制中心一致（验收 1） |
| 6. `adb pull` 那个 XML，用文本编辑器打开 | 以 `<?xml` 开头、`</i>` 结尾，`<d p="秒数,…">` 条目的秒数和画面里弹幕出现的时间大致对得上（验收 4） |
| 7. 录制设置 → 录制文件目录 → 选择 `Download` | 先出说明对话框，再打开系统“所有文件访问”页；允许后回到应用，目录变成 `Download/PureLiveRecords`；录一小段能写进去（验收 3） |
| 8. 在系统设置里撤销“所有文件访问”，再录一次 | 提示没有权限，不会写到别处 |
| 9. （有代理时）应用代理开，录 Twitch 或 YouTube 的一个直播 30 分钟 | 录制中心卡片没有“有缺口”标记；停止后合成 MP4（验收 5） |

## 风险和注意

- HyperOS 的最近任务：上滑可能只是滚动列表（S02.3 就是这样），要确认卡片消失；“锁定”了应用的话划不掉。
- HyperOS 可能划掉即杀进程，这是系统行为，代码挡不住（H01.2 记录第 6 节）：这种情况验收 2 记“不通过（系统杀进程）”，并验证恢复路径；要不要引导用户打开“自启动 / 无限制后台”，开 O 组任务。
- 第 7、8 步会改测试包的权限状态，做完恢复成默认目录，免得影响别的验证。
- 每次点击前确认测试包在前台（手机上有别的自动化应用会抢前台）；只点测试包。

## 环境和提交

- 构建：`source ~/tools/purelive-env.sh`；根目录 `bash tools/ffmpeg_kit/fetch.sh`、`flutter pub get`；`cd apps/pure_live && flutter build apk --profile`。
- 文档改动在分支 `ai/H01.4` 或本机工作区；提交信息以 `[H01.4]` 开头（英文），例如 `[H01.4] K90 results for the recording items`；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已做的步骤写进 `verify.md`，没做的留空并在 `record.md` 写“停在第几步”；登记表写 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收的结果（通过 / 不通过 / 没做和原因）；不通过的现象、根因线索和新开的任务编号；功能清点第 11 节改了哪几行；截图放在哪；需要维护者决定的（例如 HyperOS 自启动引导）。
