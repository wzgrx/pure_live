# V01.1 开播提醒：任务书

## 背景

- 来源：旧任务清单 T07e.3（“v3 没有的新功能，先出方案再定做不做”）；功能清点写明 3.x 没有开播提醒。用户和 issue 都没提过，是维护者登记的提议。
- 现象：想知道关注的主播什么时候开播，只能打开应用看关注页；“关注自动刷新”默认关，开了也只更新卡片，不通知。
- 为什么是第三档：新功能（D-026 要用户确认），涉及后台和耗电；不影响现有功能。
- 已经做过的：本文件夹 `README.md` 的评估初稿（三种做法 A、B、C，建议 A，改动清单 c1～c6）。

## 目标和验收

本任务是**提议**：做到“用户能拍板”为止，实现在目标组的任务里。

1. 评估补完：README 的“3.x 和现状”“方案”核对到当时的代码（文件:行）；做法 A 的同一场直播去重规则写清（用哪个字段：开播时间、场次 id，哪些平台没有）。
2. 出图：c3 通知（单个、合并）、c4 设置里的开关和说明、c5 卡片长按菜单和直播间关注小菜单里的开关、关注卡片的小铃铛；竖屏为主，横屏一张；`src/` 写源文件，生成 `v4-*.jpg`。
3. 评审页：`page.json`（说明、三种做法对比、改了什么、每个按钮怎么用、需要你选的：做不做 / A 还是 A+B / 默认开关 / 按房间还是全部），生成并发布成 claude.ai 私有页面给用户；登记表改“待确认”（维护者）。
4. 用户回复后：确认的——在 [DECISIONS.md](../../../DECISIONS.md) 记一条（维护者），在目标组登记实现任务并写进本任务的 `to`；否决的——状态改“不做”、原因进 DECISIONS、写进 V04 的说明。
5. （阶段 3）目标组的实现任务都完成后，本任务改“完成”。

## 现状（读代码得出，写文件:行）

- 关注刷新：`apps/pure_live/lib/features/favorite/follow_refresher.dart`（`FollowRefresher.refresh`，返回 `FollowRefreshResult.rooms` 写回存储）；`favorite_controller.dart:298-307` 的 `_scheduleAutoRefresh`（`Timer.periodic(Duration(minutes: autoRefreshInterval))`，`autoRefreshFavorite` 默认关）；回前台刷新 `refreshFavoriteOnResume` 默认开（`packages/live_store/lib/src/settings/settings.dart:741`）。刷新结果合并进存储（`FollowStore.update`），**没有保留上一轮的状态**——c2 要在合并前比较。
- 状态：`packages/live_core/lib/src/live_room.dart:9` 的 `LiveStatus`，`:383` `effectiveLiveStatus`、`:386` `isLiveNow`、`:393` `isExplicitlyOfflineNow`（offline、banned、carousel）；失败的房间标 `pendingAfterError`（状态待确认，不能当成“刚开播”的前一状态）。
- 等开播：`packages/live_record/lib/src/recorder.dart:1071` 的 `_schedulePoll`（普通 `Timer`）。
- 通知：没有通用的本地通知插件（`apps/pure_live/pubspec.yaml` 只有 `audio_service`）；录制提醒是原生发的：`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:98`（类别 `pure_live_recording_alerts`）、`:130` 起的 `alert`、`:154-161` 建类别；Dart 侧 `apps/pure_live/lib/app/recording_notice.dart`、`platform/recording_platform.dart`。
- 权限：`apps/pure_live/lib/shared/permission_prompts.dart`（通知权限、永久拒绝时的“去设置”）。
- 后台：没有 WorkManager 一类的插件；进程活着时定时器才跑。

## 3.x 基线

- 3.x 没有开播提醒；关注刷新在 `git show v3.2.11:lib/modules/favorite/favorite_controller.dart`（冷却 5 分钟 `:43`、回前台 15 秒 `:48`、10 秒超时 `:49`）。
- 要保留：3.x 的关注格式和设置键不变（D-018）；新开关只加不改，默认关。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面设计、第 6 节新功能）。
2. `docs/specs/UI.md` 第 3 节；`docs/DECISIONS.md` D-026、D-018、D-003（注意：D-003 只管“需要你选的”细节，不管做不做）。
3. 本文件夹 `README.md`；`docs/I-浏览和发现/I04-关注/README.md`（刷新的时机和规则）；`docs/O-Android系统集成/O01-通知和前台服务/README.md`；`docs/A-界面设计/A14-系统界面/A14.1-系统界面/README.md`（通知的样子）；`tools/ui/mock/README.md`（出图）。

## 范围

- 可以改：本文件夹（README、`src/`、`v4-*.jpg`、`page.json`、`page/`）。
- 不能改：任何代码（实现在目标组的任务）；`docs/tasks.toml`、`docs/DECISIONS.md`（维护者改，报告里写建议）；其他组的文档；版本号、`assets/version.json`、`assets/releases.json`。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 方案和对比页 | 补完评估；出图（通知、设置、菜单、卡片铃铛）；写 `page.json`，`python3 tools/ui/mock/page.py docs/V-需求和反馈/V01-新功能提议/V01.1-开播提醒/page.json` 生成并发布评审页 | 本文件夹 | 评审页地址写进 README 的“经过”；报告给维护者改“待确认” |
| 2 用户确认 | 读用户的表态；按 PROCESS 第 6 节第 3 步：确认 → 建议的 DECISIONS 条目和目标组任务（标题、规模、档位、阶段）；否决 → 建议的 V04 说明 | README | 维护者登记完、`to` 写好 |
| 3 开发 | 不在本任务做：等目标组任务（I04、O01、A 组等）都完成 | — | 目标组任务都“完成”后改本任务“完成” |

## 测试

- 本任务不写测试。README 的“验证”一节写清实现任务要加的测试（刷新前后状态比较、去重、通知文字）和真机步骤，实现任务照着写。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 无（提议阶段不上机；实现任务各自写 verify.md） | — |

## 风险和注意

- 不要承诺“应用被清理后也能提醒”：做法 A 做不到，HyperOS 上做法 B 也不可靠；评审页和设置说明要写清。
- 平台差异：有的平台失败时状态是“待确认”，不能把“待确认 → 直播”当成刚开播（会误报）；轮播（carousel）不是开播。
- 去重：同一场直播在刷新失败又恢复后不能再提醒一次。
- 和录制“等开播”同一个房间时不要重复请求（c6）。

## 环境和提交

- 出图：`tools/ui/mock/README.md`（每台机器准备一次）；`python3 tools/ui/mock/render.py docs/V-需求和反馈/V01-新功能提议/V01.1-开播提醒/src/`。
- 本机工作区或分支 `ai/V01.1`；提交信息以 `[V01.1]` 开头（英文）；不推 master。
- 提交前：`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：已写的评估和图先提交；README 末尾写“停在哪”（哪些图没出、评审页发了没有）；报告里写下一步。

## 报告（中文，简洁）

评估的结论（建议哪种做法、规模、涉及的组）；评审页地址；需要用户选的问题；建议的 DECISIONS 条目和目标组任务；风险。
