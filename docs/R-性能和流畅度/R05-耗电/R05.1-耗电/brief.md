# R05.1 耗电：任务书

## 背景

- 来源：[specs/UI.md](../../../specs/UI.md) 第 9.1 节；[V03.2 调研](../../../V-需求和反馈/V03-审查和调研/V03.2-流畅度、刷新率、分辨率调研/README.md) 1.5 节、4.3 节第 6 条（“新做法的省电档不能比 v3 的省电档更耗电”）；R02.1 设计“以后在 K90 上怎么测”的耗电一行；2026-10-02 登记（旧编号 T14f.1）。
- 现象：没有用户报告；4.x 加了按帧率选刷新率（均衡档 24/25/50 帧空闲也 120 Hz），去掉了一些持续出帧的动画，但从来没测过耗电，不知道比 3.x 好还是差。
- 为什么现在做：第三档（PLAN 第三档“耗电（R05）”）；最好在 R02.2 的真机验证通过之后做（刷新率策略定了再测）。
- 已经做过的：R02.1、R02.2（刷新率）、R01.1（去掉离屏绘制和多余转圈）、D03.1（没有弹幕时弹幕层停）、O05.1（只在播放时常亮）。

## 目标和验收

1. `record.md` 有一张表：每组（见“方案和阶段”）两次的电量差（%）、`batterystats` 里应用的估算耗电（mAh）、30 分钟后的皮肤温度，和测试时间、房间、清晰度、帧率。
2. 判定：4.x 省电档相对 3.x 省电档（v3bench 包）的差；差 >5% 时写出原因的排查（刷新率投票、弹幕帧率、渲染）和建议开的任务。没有 v3bench 包时写明原因，只给 4.x 各组的相对值。
3. 均衡档、最高档、帧率匹配开关、纯音频、后台锁屏的相对代价写进记录，并给出建议（例如设置说明要不要提、纯音频要不要改成不解码视频），交给对应组的维护者决定。
4. 不改代码；发现的问题开到对应组（在报告里列出）。

## 现状（读代码得出，写文件:行）

- 刷新率：`apps/pure_live/lib/platform/display_mode.dart:142-148`（`playbackRefreshRate`：省电 0 → 只声明视频帧率；均衡空闲取 ≤60 的整数倍、没有就最低的整数倍；操作中和最高取整数倍里最高；没有整数倍取设备最高）；`packages/live_ui/lib/src/widgets/refresh_rate.dart`（三档、1.5 秒回落）；默认 `refreshRateMode = powerSaving`（`packages/live_store/lib/src/settings/settings.dart:64-69`）、`matchVideoFrameRate = true`（`:73`）。
- 解码：`packages/live_player/lib/src/mpv_options.dart:88-96`（硬解 `auto-safe`）；`enableCodec` 默认开（`settings.dart:289`）。
- 纯音频：`packages/live_player/lib/src/mpv_engine.dart:230-258`（Android 只关视频输出）。
- 后台：`apps/pure_live/lib/features/live_play/logic/background_playback.dart` 的 `BackgroundKeepAlive`（唤醒锁和 Wi-Fi 锁）、`RoomBackgroundPolicy`（不开后台播放时离开 1.5 秒后暂停）；`enableBackgroundPlay` 默认关（`settings.dart:21`）。
- 屏幕常亮：`packages/live_player/lib/src/screen_wake.dart`（只在播放或缓冲时），`enableScreenKeepOn` 默认开（`settings.dart:33`）。
- 弹幕：`apps/pure_live/lib/shared/danmaku/danmaku_templates.dart` 的 `resolvedDanmakuFps`（取刷新率的整数分之一）；没有弹幕时弹幕层停（D03.1）。

## 3.x 基线

- 3.x 默认省电档，播放时不按帧率选刷新率（`git show v3.2.11:lib/common/widgets/adaptive_refresh_rate_scope.dart`）；弹幕帧率省电档上限 60（`lib/common/services/settings/danmaku_settings_controller.dart:135-158`）。
- 3.x 在 K90 上是用户的正式包，**不能拿来测**（D-019）。对比包：在独立工作区 `git worktree add <路径> v3.2.11`，`android/app/build.gradle` 的 `applicationId` 改成 `com.mystyle.purelive.v3bench`、应用名改“纯粹直播 v3bench”，本机构建 profile 包；测完卸载（和 G03.1、R04.1 共用这个包；3.x 的设置在 v3bench 里是全新的，要手动设成和 4.x 测试时一样：省电档、同一清晰度、弹幕开）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 10 节真机、第 14 节规则）。
2. `docs/specs/UI.md` 第 9.1 节；V03.2 调研第 1.5、4.3 节。
3. 本文件夹的 `README.md`；`docs/R-性能和流畅度/R05-耗电/README.md`；`docs/R-性能和流畅度/R02-刷新率/R02.2-刷新率策略修正/record.md`（“手感和耗电的变化”）；`docs/R-性能和流畅度/R02-刷新率/R02.1-刷新率和帧率匹配/README.md`（“以后在 K90 上怎么测”）。

## 范围

- 可以改：本文件夹的 `record.md`；可以新建 `tools/perf/battery_summary.py`（把 `batterystats` 的输出里本应用的估算耗电摘出来）。
- 不能改：任何应用代码和默认值（测出问题开到对应组）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

登记表没有写阶段，开工时补上 `stages = ["4.x 各档测量", "3.x 对比和结论"]`。

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 4.x 各档测量 | c1 统一条件；c2、c3 的 4.x 各组（省电、均衡、最高、省电 + 帧率匹配关、纯音频、后台锁屏；可选弹幕多的房间） | `record.md` | 验收第 1 条的 4.x 部分 |
| 2 3.x 对比和结论 | c3 v3bench 省电档两次；c4 判定和建议 | `record.md` | 验收第 1～4 条 |

## 测试

- 没有自动测试（只读测量，不改代码）。
- 每组测两次，两次差 >3 个百分点（电量）时加测第三次。

## 真机验证（维护者在 K90 上做）

准备：K90 无线 adb（`adb connect 192.168.1.2:5555`，不插 USB、不充电，电量 80% 以上开始）；亮度 50%（关自动亮度）、音量 30%、Wi-Fi，其他应用全部关掉；打开勿扰模式；手机在室温。房间：一个长时间直播、码率稳定的哔哩哔哩房间（记下房间号、清晰度、帧率——帧率按 R02.2 verify 的办法在省电档下用 `dumpsys SurfaceFlinger` 看）。

每一组的做法：

```bash
adb -s 192.168.1.2:5555 shell dumpsys batterystats --reset
adb -s 192.168.1.2:5555 shell dumpsys battery | grep level      # 记开始电量
# 进房间，播 30 分钟，不碰屏幕
adb -s 192.168.1.2:5555 shell dumpsys battery | grep level      # 记结束电量
adb -s 192.168.1.2:5555 shell dumpsys batterystats --charged com.mystyle.purelive.v4dev > battery-<组>-<次>.txt
adb -s 192.168.1.2:5555 shell dumpsys thermalservice | grep -i skin
```

| 步骤 | 期望 |
|---|---|
| 1. 4.x 省电档（帧率匹配开），竖屏普通布局播 30 分钟，两次 | 记录；右上角“显示刷新率”（开发者选项）多半是 60 |
| 2. 4.x 均衡档，同上 | 记录（不碰屏幕时 60；24/25/50 帧的房间是 120） |
| 3. 4.x 最高档，同上 | 记录（一直 120） |
| 4. 4.x 省电档，关掉“播放时匹配视频帧率”，同上 | 记录 |
| 5. 4.x 省电档，开纯音频（屏幕亮着），同上 | 记录 |
| 6. 4.x 开后台播放，进房间后锁屏 30 分钟 | 记录；结束时声音还在 |
| 7. （可选）4.x 省电档，弹幕每秒几十条的热门房间 | 记录 |
| 8. v3bench 包（3.x）省电档，步骤 1 的同一房间、同一清晰度，两次 | 记录；和步骤 1 对比 |

## 风险和注意

- 电量百分比的分辨率是 1%，30 分钟的差可能只有 2%～4%：以 `batterystats` 的估算 mAh 为主、电量差为辅；每组两次。
- 同一房间的码率和帧率会变（主播换场景）：记下测试时间；对比组尽量连着测。
- 温度会累积：每组之间等手机回到室温（`thermalservice` 的皮肤温度回到开始值附近）。
- 只点测试包和 v3bench 包（D-019）；不碰正式包和 3.x；v3bench 测完卸载。

## 环境和提交

- 只需要 adb；v3bench 包的构建见“3.x 基线”（`source ~/tools/purelive-env.sh`，本机构建，构建完 `./gradlew --stop`）。
- 分支 `ai/R05.1` 或本机工作区；提交信息以 `[R05.1]` 开头（英文）；不推 master。原始的 `batterystats` 输出不进仓库，汇总表写进 `record.md`。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：在 `record.md` 写“停在哪”（测完哪几组）、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

各组的耗电和温度表；省电档和 3.x 的对比结论；各档的相对代价；发现的问题和建议开的任务（组、内容）；需要维护者决定的（例如设置说明、纯音频不解码视频）。
