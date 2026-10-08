# O01.1 开播提醒（应用开着时；接 V01.1）：记录

- 日期：2026-10-09
- 执行者：Claude（本机工作区，没有推送、没有合并、没有构建安装包、没有上机）
- 分支和提交：工作区分支 `worktree-agent-a6da60e776be3e98a`，提交 `[O01.1] …`
- 任务书：[brief.md](brief.md)；说明：[README.md](README.md)；评估和设计：[V01.1 README](../../../V-需求和反馈/V01-新功能提议/V01.1-开播提醒/README.md)“评估结论和设计（定稿）”L1～L16

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 1 两个新设置，默认关、空 | 做了 | `Settings.liveAlertEnabled`、`Settings.liveAlertTagIds`（`refresh` 一节）；关着时 `LiveAlerts.observe` 第一行就忘掉记录返回，没有定时器、不发 |
| 2 开播发通知，点了进直播间 | 做了 | Dart `platform/live_alert_channel.dart` → `pure_live/live_alerts` `post` → `LiveAlerts.kt`；点按意图和桌面长按快捷方式同一条路（`ShareIntakePlugin.ACTION_OPEN`） |
| 3 同一场只一次 | 做了 | `LiveAlertTracker`：`unknown` 跳过、第一次看到只记、15 分钟内重连和开播时间相差 2 分钟以内算同一场、开播时间往后挪 15 分钟以上算新的一场；录制检查和关注刷新共用一个记录 |
| 4 不加常驻服务 | 做了 | 每一轮关注刷新的结果交给它；`Recorder.changes` 里成功的检查交给它；没开“关注自动刷新”时 `_scheduleAutoRefresh` 每 15 分钟只刷要提醒的关注；启动核验、下拉、再点“关注”、直播间“看其他”的刷新按钮只记不发（`refreshAll` 加了 `alert` 参数，`app/app.dart` 的按钮传 `alert: false`） |
| 5 按标签选 | 做了 | `liveAlertRooms`；设置里每个标签一个开关；已删除的标签不算 |
| 6 只问通知权限 | 做了 | `BackgroundPermissions.confirmNotifications`（文字讲开播提醒，不问电池）；`switchGateProvider` 对 `liveAlertEnabled` 走它；拒绝时 `GatedToggleTile` 照旧不开、说明变红 |
| 7 只在 Android、文字走翻译 | 做了 | 目录条目 `when: _android`；`liveAlertPosterProvider` 只在 Android 有值；13 个翻译键 |

偏差：没有。

## 根因

- 不是 bug，是新功能。要点：关注刷新把结果合并进存储，不保留上一轮的状态（`favorite_controller.dart` 的 `_pass`），所以“刚开播”只能在内存里比较（`LiveAlertTracker`）；失败的房间是 `pendingAfterError()`（`unknown`），不能当成“刚才不在播”。

## 改了哪些文件

- 逻辑：`apps/pure_live/lib/features/favorite/live_alerts.dart`（新）、`apps/pure_live/lib/features/favorite/favorite_controller.dart`、`apps/pure_live/lib/app/app.dart`（“看其他”的刷新按钮只记不发）
- 通知：`apps/pure_live/lib/platform/live_alert_channel.dart`（新）、`apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/LiveAlerts.kt`（新）、`AppChannelsPlugin.kt`（注册通道，7 行）
- 设置和权限：`apps/pure_live/lib/features/settings/live_alert_tiles.dart`（新）、`settings_catalog.dart`、`playback_tiles.dart`（`switchGateProvider`）、`apps/pure_live/lib/shared/permission_prompts.dart`（`confirmNotifications`）
- `packages/live_store/lib/src/settings/settings.dart`、`packages/live_ui/lib/src/icons/app_icons.dart`（`settingsLiveAlert` = `notification_3_line`）
- 翻译：`apps/pure_live/assets/translations/zh.json`、`en.json`
- 登记：`docs/inventory/OWNERS.toml`（`live_alerts.dart`、`live_alert_channel.dart`、`LiveAlerts.kt`、通道 `pure_live/live_alerts`、两个设置 → O01）、`tools/docs/settings_audit_notes.py`；重新生成 `OWNERS.md`、J01.2 的 `settings.md`（223 个设置）
- 文档：本文件夹；V01.1、V01、O01、O、I04 的说明；`docs/tasks.toml`（V01.1 已确认，新登记 O01.1、O01.2、A09.13）
- 测试：见下

## 新设置、翻译键、原生代码

- 新设置：`liveAlertEnabled`（默认 `false`）、`liveAlertTagIds`（默认 `[]`），都在 `refresh` 一节，跟备份和设备同步；3.x 没有这两个键（3.x 的 `RefreshConfigController.parseConfig` 只读自己的 6 个键）。
- 翻译键（13 个）：`live_alert`、`live_alert_apply_failed`、`live_alert_channel_desc`、`live_alert_channel_name`、`live_alert_desc`、`live_alert_tags`、`live_alert_tags_desc`、`live_alert_tags_none`、`live_alert_text_empty`、`live_alert_title`、`permission_live_alert_blocked_content`、`permission_live_alert_content`、`settings_group_live_alert`。
- 原生（**没有编译过**）：`LiveAlerts.kt` 只用了 `RecorderForegroundService.kt` 已经用过的 API（`NotificationChannel`、`Notification.Builder`、`BigTextStyle`、`PendingIntent.getActivity` 带 `FLAG_IMMUTABLE`）加 `areNotificationsEnabled()`、`CATEGORY_SOCIAL`；新通道注册在 `AppChannelsPlugin`（引擎没有 Activity 时也能发）。清单不用改（`POST_NOTIFICATIONS` 已有）。没有新资源（小图标用 `ic_stat_playback`）。
- 门禁基线不变。

## 测试

新增 26 个用例：

- `apps/pure_live/test/features/favorite/live_alerts_test.dart`（新，12 个）：第一次看到只记、离线 → 在播发一次；`unknown` 不算证据；录播、轮播、封禁不算在播，受限的直播算；15 分钟内重连不发、之后发；同一个开播时间不发；开播时间挪后 15 分钟以上发；“安静”的一轮只记；`forget`；按标签选（含已删除的标签）；开关关着不发不记、打开时在播的不发；只发要提醒的、发失败只记日志；录制检查（第一次只记、同一次不重复、失败的不算、更早的失败不影响）。
- `apps/pure_live/test/features/favorite/favorite_test.dart`（3 个）：启动核验和下拉只记，回到前台发一次、再回来不重复，“看其他”按钮（`alert: false`）不发，关掉后不发；录制检查先发、之后关注刷新同一场不再发，不在关注里的录制任务不发；没开“关注自动刷新”时定时器只查带所选标签的关注（测试里间隔 1 秒），开了“关注自动刷新”后换成它的 30 分钟。
- `apps/pure_live/test/platform/system_surfaces_test.dart`（3 个）：通知文字（主播名、没有主播名用平台名、没有标题）和全部通道参数；`post` 走 `pure_live/live_alerts`、没有原生端时不出错；`LiveAlerts.kt` 和 `AppChannelsPlugin.kt` 的关键处（打开直播间的意图和四个参数、一个房间一个标签、默认重要性、请求码范围、通道注册）。
- `apps/pure_live/test/shared/permission_prompts_test.dart`（2 个）：只问通知、用开播提醒的文字、不问电池；永久拒绝时“去设置”的文字；`switchGateProvider` 对开播提醒只问通知。
- `apps/pure_live/test/features/settings/settings_general_test.dart`（4 个）：刷新设置里“关注列表”下面一组“开播提醒”、默认关、标签行变灰写“打开“开播提醒”后生效”，打开后没标签时的说明，加两个标签后按标签顺序存、再关掉一个；权限被拒时不开、说明变红；搜索“开播”找到两行；只在 Android 有。
- `packages/live_store/test/live_alert_settings_test.dart`（新，2 个）：默认值、分节、跟备份往返、3.x 备份没有它们时保持默认；`settings_defaults_test.dart` 的 `newInV4` 加两行。
- 默认值下行为不变的证据：原来的关注刷新、设置页、权限、系统界面测试一行没改照样通过（`favorite_test.dart` 原来的 21 个、`settings_general_test.dart` 原来的 10 个等）。

## 门禁

- 2026-10-09 本机 `bash tools/gate/gate.sh --all`（日志在会话 scratchpad 的 `v011-1791478200/gate.log`）：`gate: passed (all, 14 members)`。第一次跑时有两处没过，改了以后重跑通过：设置说明超过 40 个字（A01.4 c2 的测试；`live_alert_desc` 缩短，“每 15 分钟查一次”“被清理后收不到”改写在本任务和 V01.1 的说明里）；`live_alert_settings_test.dart` 的 `omit_local_variable_types`。

## 真机上要看的

K90（`com.mystyle.purelive.v4dev`，每次点按前确认前台是测试包）。先 `flutter build apk --debug` 确认 `LiveAlerts.kt` 能编译。

1. 覆盖安装后先不改设置：设置 → 刷新设置，“关注列表”一组下面是“开播提醒”一组：开关关着，说明是“关注的主播开播时发通知，点了进直播间；只在应用开着时（前台、后台播放或录制）提醒”；下面“只提醒这些标签的关注”是灰的，写“打开“开播提醒”后生效”。用一会儿，不会来任何开播通知（和以前一样）。
2. 系统设置里先关掉测试包的通知，再打开“开播提醒”：弹“通知权限已关闭”，文字讲开播提醒（不是后台播放），“去设置”；不开通知回来，开关不开、说明变红。打开通知后再开：开关打开，**不问**电池优化。
3. 关注一个马上要开播的主播（或者用另一台设备自己开播一个测试直播间），“关注自动刷新”保持关；应用留在前台的热门页：最多 15 分钟内来一条“主播名 开播了”，正文是直播标题，通知时间是开播时间（平台给了的话）。系统设置 → 通知里出现类别“开播提醒”。
4. 点这条通知：直接进这个直播间，通知消失。从后台（应用在别的页面）点也一样。
5. 同一场不再提醒：继续开着 30 分钟以上，不来第二条；下拉刷新关注、再点“关注”也不来。
6. 后台播放：打开“后台播放”，进另一个直播间播放，按 Home 回桌面，等关注的另一个主播开播：来通知（应用在后台也能收到）；点了进那个直播间。
7. 不开后台播放、退到桌面锁屏 30 分钟：大概率收不到（HyperOS 冻结后台，开关说明已写）；回到应用时（回到前台刷新），这期间开播的主播会补来通知（每人一条）。
8. 按标签：建标签“提醒”，只给一个关注加上；在“只提醒这些标签的关注”里只开“提醒”：别的关注开播不再来通知，带“提醒”的照来。把“提醒”标签删掉：回到提醒全部关注。
9. 自动录制：给一个关注建录制任务，录制设置里开“自动轮询”；它开播时录制开始，同时来一条开播提醒（只一条，之后关注刷新不会再来第二条）；录制的常驻通知照旧。
10. 打开“关注自动刷新”选 5 分钟：开播最多 5 分钟内来通知（这时查的是全部关注）。
11. 关掉“开播提醒”：不再来通知。
12. `adb shell dumpsys notification --noredact | grep -A5 live_alert` 能看到 `live_alert:<平台>:<房间号>` 的通知；`adb shell dumpsys activity services com.mystyle.purelive.v4dev` 里没有为开播提醒多出的服务。

## 留下的问题

- 正在看的就是这个直播间时照发（V01.1 L11）。
- O01.2（被冻结或清理后也查）、A09.13（卡片和菜单里单独开关）等用户定。
