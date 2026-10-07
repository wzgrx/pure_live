# H05.1 录制通知按状态写标题，“录制已停止”提醒换新图标：任务书

> 本任务的代码已经合并（`79ecb5d2b`，2026-10-02），状态“待真机”。剩下的工作是在 K90 上验证，不通过时找根因并修。

## 背景

- 来源：[A10.3](../../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/README.md)待选 X4 的建议 A（“‘录制已停止’提醒另做‘!’小图标、准备中和合成中的通知按状态写字”），按 D-003 由维护者定；A10.3 的可改范围不包括通知代码，所以单独登记。
- 现象（改之前）：录制刚开始的几秒、断线重连时、停止后整理文件时，通知都写“正在录制 · 主播名”；录制失败的“录制已停止”提醒和正在录制的通知用同一个小图标，在状态栏里分不出来。
- 为什么现在做：待真机的任务要在下一轮真机验证里看完（[PROCESS.md](../../../PROCESS.md) 第 3.2 节：“完成”必须有真机结果）；它和 A10.3、A08.5 c3、S02.5 的清单 2B、4B 是同一批检查。
- 已经做过的：代码和测试（`79ecb5d2b`），见 [README.md](README.md)“结果”。

## 目标和验收

1. [verify.md](verify.md) 第 1～9 步都通过（第 1 步“准备录制”太快没看到不算失败；第 10 步可选）。
2. 通过后登记表 H05.1 改“完成”、写日期，`python3 tools/docs/docs.py` 刷新。
3. 不通过的每一条写清现象、截图和根因（文件:行），修好后（新提交，测试先失败再通过）再验一次。

## 现状（读代码得出，写文件:行）

- 标题：`apps/pure_live/lib/app/recording_notice.dart:22-55` 的 `recordNotificationContent`：只看 `status.isActive` 的任务（准备中、录制中、重连中、整理文件，`packages/live_record/lib/src/task.dart:50-53`）；一个时标题 `i18n(_oneTitleKey(task.status), …)`（`:43`），`_oneTitleKey`（`:59-64`）；几个时 `record_notify_many`（`:50`）。
- 送到通知：`RecordingNotices.changed`（`recording_notice.dart:147`）每次任务变化都调 `refresh`；`AndroidRecordKeepAlive.refresh`（`apps/pure_live/lib/platform/recording_platform.dart:216-228`）在服务开着、文字和上次不同时 `invokeMethod('update', …)`；原生 `RecorderPlugin.kt:82-85` → `RecorderForegroundService.update`（`RecorderForegroundService.kt:113-124`，服务不在前台时不更新）。
- 提醒：`recording_notice.dart:149-160` 在任务新变成 `failed` 且（`lastErrorStage == 'background'` 或应用不在前台）时 `alert`；`recordStoppedContent`（`:76-86`）写原因和已保存时长；原生 `RecorderForegroundService.alert`（`:130-149`）用 `R.drawable.ic_stat_record_stopped`（`:135`），标签 `record_alert:<id>`、通知 id `20260906 + 1`，点开 `openRecordings(context, taskRequest(id), id)`（`:133`）。
- 图标文件：`apps/pure_live/android/app/src/main/res/drawable/ic_stat_record_stopped.xml`（提醒）、`ic_stat_recording.xml`（前台通知，A10.3 c10 的形状）。
- 测试：`apps/pure_live/test/platform/system_surfaces_test.dart:52-58`（四种标题）、`:105-162`（提醒的文字和发不发）。

## 3.x 基线

- `git show v3.2.11:lib/recorder/services/recorder_background_service.dart:110-121`：通知文字固定“直播录制进行中”“录制与封装由独立后台服务保护，点按返回应用”，开了服务就不再更新。
- `git show v3.2.11:android/app/src/main/kotlin/com/mystyle/pure_live/RecorderForegroundService.kt:229-248`：小图标 `ic_launcher_foreground`、没有按钮；3.x 没有“录制已停止”提醒。
- 本任务是 4.x 的改动（A14.1 c3～c5 之上），没有要保留的 3.x 行为；3.x 的两个文字键仍是没有活动任务时的兜底。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 3.2 节状态、第 10 节真机验证、第 14 节规则）。
2. 本文件夹的 [README.md](README.md)、[verify.md](verify.md)；[H05 子分类说明](../README.md)。
3. A10.3 的 [verify.md](../../../A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标/verify.md)（第 7、8、12、13 条和本任务重叠）；S02.5 的 [brief.md](../../../S-质量和验证/S02-真机验证/S02.5-4.0.0构建号5001/brief.md) 清单 2B、4B。
4. 设备规则：[S02 真机验证](../../../S-质量和验证/S02-真机验证/README.md)（D-019：只点测试包，点之前确认前台）。

## 范围

- 可以改（只在验证不通过、需要修时）：`apps/pure_live/lib/app/recording_notice.dart`；`apps/pure_live/lib/platform/recording_platform.dart` 的 `AndroidRecordKeepAlive.refresh`、`alert`；`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt` 的 `update`、`alert`；`res/drawable/ic_stat_record_stopped.xml`；`test/platform/system_surfaces_test.dart`；翻译文件里的 `record_notify_one_*`、`record_stopped_*`；本文件夹的 `verify.md`、`record.md`。
- 不能改：前台通知的小图标形状（A10.3）；通知的按钮、点按去向（H05.2）、进度（H05.3）；前台服务的启停和保活（H02）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；通知类别 id `pure_live_recording`、`pure_live_recording_alerts`（改了用户的通知设置会丢）。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 用合并后的 master 装测试包，按 verify.md 第 1～11 步逐条看，截图 | `verify.md`、`verify/*.jpg` | 每一步有结果；全部通过时改登记表 |
| 2（只在不通过时） | 每个不通过的现象找根因，先写会失败的测试再修；修完重做相关步骤 | 上面“可以改”的文件、`record.md` | 测试先失败后通过；相关步骤通过 |

## 测试

- 只验证时没有新测试。
- 需要修时：标题、提醒的逻辑都在 Dart，用 `system_surfaces_test.dart` 的 `_task` 和假的 `MethodChannel` 写改之前会失败的用例（例如“重连中的任务恢复写文件后，`refresh` 发出的标题变回‘正在录制’”）；原生改动没有单元测试，本机 `flutter build apk --debug` 一次，真机再看。
- 测试里的定时器至少 1 秒；不访问真实平台（D-017）。

## 真机验证（维护者在 K90 上做）

见 [verify.md](verify.md)（11 步）。要点：

| 步骤 | 期望 |
|---|---|
| 1～4. 一个直播间：开始、写文件、断网重连、停止 | 标题依次“准备录制 / 正在录制 / 正在重连 / 正在整理录像 · 主播名” |
| 5～6. 两个直播间 | “正在录制 2 个直播间”、“全部停止”能停 |
| 7～9. 关“自动断线重连”后在后台断网 | “录制已停止 · 主播名”，开口圆环加“!”的小图标；点开定位到任务；在前台时不提醒 |

## 风险和注意

- 造“录制失败”不要靠“等重试用完”：H01.5 之前，断网时先出现的 EOF 让任务无限快速重连，永远等不到失败；verify.md 第 7 步先关“自动断线重连”。S02.5 清单 4B-01 写的“等重试用完”有同样的问题，做到那里时照这里的办法。
- 准备中通常只有一两秒，截图很难截到；重连中要断够久（FFmpeg 读写超时 15 秒）才会出现。
- HyperOS 的通知栏会合并同一应用的通知，展开后才看得到标题；截图时展开。
- 第 10 步的 `am stopservice` 在 Android 17 上可能被拒绝（服务没导出），不行就跳过，不要用 `force-stop`（会连 Dart 一起杀掉，根本发不出提醒）。
- 可能冲突的文件：`RecorderForegroundService.kt`（H05.2、H05.3 也改）、`recording_notice.dart`（H05.3）。

## 环境和提交

- `source ~/tools/purelive-env.sh`；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`；装测试包 `cd apps/pure_live && flutter build apk --debug`（或 profile），`adb -s 192.168.1.2:5555 install -r …`。
- 只验证时：结果写进 `verify.md`，提交信息 `[H05.1] Record the K90 check`（英文），改登记表后运行 `python3 tools/docs/docs.py`。
- 需要修时：分支 `ai/H05.1`，提交信息以 `[H05.1]` 开头；提交前 `apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。不推 master。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：`verify.md` 里已做的步骤先写上结果并提交；在登记表 `note` 写“verify.md 做到第 N 步”。

## 报告（中文，简洁）

每一步通过没有（附截图名）；不通过的现象和根因；改了哪些文件（如有）；登记表改了什么；顺带发现的问题（例如通知栏合并、权限）。
