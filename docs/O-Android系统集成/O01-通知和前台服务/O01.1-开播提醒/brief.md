# O01.1 开播提醒（应用开着时；接 V01.1）：任务书

## 背景

- 来源：新功能提议 V01.1（D-036 同意做，默认关）；旧任务清单 T07e.3。3.x 和上游都没有开播提醒。
- 现象：想知道关注的主播什么时候开播，只能打开应用看关注页；“关注自动刷新”开了也只更新卡片，不通知。
- 为什么是第三档：新功能；涉及后台和耗电；不影响现有功能。
- 已经做过的：V01.1 的评估和设计（`docs/V-需求和反馈/V01-新功能提议/V01.1-开播提醒/README.md`“评估结论和设计（定稿）”，维护者按 D-003 选了 L1～L16，拆成 O01.1、O01.2、A09.13）。

## 目标和验收

1. 新开关 `liveAlertEnabled`（默认关）和 `liveAlertTagIds`（默认空 = 全部关注）；关着时什么都不发、不记，和以前一样。
2. 开着时：关注的主播从不在播变成在播，发一条“主播名 开播了”的系统通知，正文是直播标题；点通知进这个直播间。
3. 同一场只发一次（V01.1 L4～L6）：请求失败不算证据；第一次看到只记下；15 分钟内重连、同一个开播时间不算新的一场；录制检查和关注刷新共用记录。
4. 不加常驻服务：用关注刷新的每一轮和录制等开播任务的检查；没开“关注自动刷新”时每 15 分钟只查要提醒的关注；用户自己发起的刷新只记不发（L10）。
5. 选择提醒哪些关注：按标签，都不选 = 全部（L3）。
6. 打开开关时只问通知权限（L8），拒绝时开关不开、说明变红。
7. 只在 Android 显示和生效；文字走翻译。

## 现状（读代码得出）

- 关注刷新：`apps/pure_live/lib/features/favorite/favorite_controller.dart`（`_verifyAll`、`refreshVisible`、`refreshAll`、`_resumed`、`_scheduleAutoRefresh`、`_pass`）；结果 `FollowRefreshResult.rooms`，失败的是 `pendingAfterError()`。
- 录制等开播：`packages/live_record/lib/src/recorder.dart` 的 `_doPoll`（成功 `lastLiveCheckAt = now`，失败同时 `markFailure`）；`Recorder.changes` 是广播流。
- 通知：`RecorderForegroundService.kt` 的两个类别；打开直播间的意图：`ShareIntakePlugin.ACTION_OPEN` + `platform`、`roomId`、`title`、`nick`（桌面快捷方式）。
- 权限：`shared/permission_prompts.dart` 的 `BackgroundPermissions`；设置的 `GatedToggleTile`、`switchGateProvider`（`features/settings/playback_tiles.dart`）。

## 3.x 基线

- 3.x 没有开播提醒；关注刷新的时机和规则照 3.x（I04），本任务不改。
- 要保留：3.x 的设置键和关注格式不变（D-018），新设置只加。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`。
2. `docs/specs/ENGINEERING.md`、`docs/specs/UI.md` 第 3 节。
3. V01.1 的 README（L1～L16）；I04、O01、H04 的 README。

## 范围

- 可以改：`features/favorite/`（控制器和新的 `live_alerts.dart`）、`app/app.dart`（直播间“看其他”的刷新按钮只记不发）、`platform/live_alert_channel.dart`、`features/settings/`（目录里的开播提醒和权限门）、`shared/permission_prompts.dart`、`packages/live_store` 的设置、`packages/live_ui` 的图标、翻译文件、`android/.../LiveAlerts.kt` 和 `AppChannelsPlugin.kt`（尽量少）、对应测试、`docs/inventory/OWNERS.toml`、`tools/docs/settings_audit_notes.py`、本文件夹和 V01.1、O01、I04 的说明、登记表。
- 不能改：关注刷新的时机、并发、冷却（I04）；录制的轮询（H04）；3.x 的设置键；不加插件、不加前台服务、不用系统闹钟。

## 方案和阶段

规模中，一次做完（一个阶段）：c1 判断 → c2 接关注刷新和录制 → c3 原生通知 → c4 设置和权限 → c5 存储 → 测试 → 文档。

## 测试

- `apps/pure_live/test/features/favorite/live_alerts_test.dart`：判断规则、要提醒的关注、开关、录制检查。
- `apps/pure_live/test/features/favorite/favorite_test.dart`：控制器里哪几轮发、哪几轮只记；录制检查先发后关注刷新不重复；只查要提醒的关注的定时器。
- `apps/pure_live/test/platform/system_surfaces_test.dart`：通知文字、通道参数、原生代码的关键处。
- `apps/pure_live/test/shared/permission_prompts_test.dart`、`apps/pure_live/test/features/settings/settings_general_test.dart`：权限问答、设置界面。
- `packages/live_store/test/live_alert_settings_test.dart`、`settings_defaults_test.dart`：默认值、备份。

## 真机验证（维护者在 K90 上做）

见 [record.md](record.md)“真机上要看的”。

## 风险和注意

- Kotlin 没有在本机编译：`LiveAlerts.kt` 只用了 `RecorderForegroundService.kt` 已经用过的 API，但必须先 `flutter build apk --debug` 通过再上机。
- HyperOS 会冻结或清理后台：不开后台播放、不在录制时，退到后台后基本收不到；回到前台时“回到前台刷新”会补发这期间开播的（开关说明已写）。
- 关注很多、没选标签时，每 15 分钟会查全部关注（和开“关注自动刷新”选 15 分钟一样的流量）。

## 环境和提交

- 本机工作区；提交信息以 `[O01.1]` 开头（英文）；不推 master；`bash tools/gate/gate.sh --all` 通过。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条做到没有；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的。
