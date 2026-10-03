# A08.5 设置里的弹幕页和直播间同一个组件；“录制已停止”通知定位到任务：任务书

> 本任务的开发已经合并（代码 `10bbcabe1`、`6a599edee`，合并 `8fe678164`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 F02），按任务书模板 v2 重排；“现状”一节是合并后读代码写的。原任务单里“先读”那一行在 docs v1 改编号时被换坏了（变成了“A15.1 的 record.md～T06b.1.md”），这里按原意改回。

## 背景

- 来源：界面任务合并后留下的跨任务约定（当时的界面任务清单第 7 节）：A11.1 → A08.1、A11.3（设置总览新加的“弹幕”行要和直播间同一个组件，需要给它加路由）；A14.1 → A10.1（录制通知点开要定位到任务）；A15.1、A15.2、A09.10、A08.3 的记录里列出的不再使用的翻译键。
- 现象：
  1. 设置 → 弹幕打开的是 J01.1 留下的一组目录行：分组、范围和直播间的“弹幕设置”不一样（显示区域 10%～100%、速度 30～400、字号 10～40，图标是 Remix）。
  2. 录制失败后通知栏出现“录制已停止 · 主播名”，点开只到录制中心顶部，任务多时找不到是哪一条。
- 规模：小；分组：功能；能否和别的任务同时做：可以和任何组外任务同时（会碰 `features/settings/` 和 `features/recorder/`）。
- 出设计：不用（照已确认的 A08.1、A07.6、A11.1 c6、A14.1、A10.1 和本任务书）。
- 决定：c3 按维护者决定不做（D-016、D-024：上次清理误删了运行时拼出来的键）。

## 目标和验收

1. c1：设置里的“弹幕”行打开的页面和直播间的弹幕设置用同一个组件（`shared/danmaku/danmaku_settings_content.dart` 的 `DanmakuSettingsContent`），并给它加路由；原来那页有的全局设置不能少；设置搜索能找到这一页的项。
2. c2：“录制已停止”通知点开后定位到录制中心里对应的任务（录制中心加按任务 id 定位的接口），滚到那一条并短暂高亮；多条提醒各自定位到自己的任务。
3. c3：清理不再使用的翻译键——**不做**（D-024）。如果以后要做：运行时拼出来的键（如 `portrait_orientation_${name}`、`audience_${id}_detail`、`site_${id}`）不能删；删之前全仓库搜一遍，删完跑全部测试。
4. 翻译测试和全部测试通过；门禁通过。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- c1：`apps/pure_live/lib/features/settings/danmaku_page.dart`（184 行）：`DanmakuSettingsPage`（`:32`），正文 `DanmakuSettingsContent(hint: 改动立即生效, extra: [更多])`（`:60-63`），`_More`（`:72`，显示弹幕、在画面上显示飞行弹幕、YouTube 显示全部聊天、更换弹幕字体、弹幕屏蔽）；`settings_section_view.dart:129` 对 `SettingsSection.danmaku` 返回这一页；路由 `RoutePath.kDanmakuSettings`（`lib/routes/route_path.dart:72`）、`app_router.dart:62`。直播间那份是 `features/live_play/danmaku/danmaku_settings_panel.dart` 的 `RoomDanmakuSettings`（`:76`），多出“弹幕列表”“小窗弹幕”两组（`:97-133`），设置页没有（A08.6）。
- c2：`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`：`alert`（`:130`）、`openRecordings(context, request, task)`（`:171-179`，`putExtra(EXTRA_TASK, task)` `:176`）、按任务 id 的请求码（`:180` 起，避开常驻通知的 0～4）；`ShareIntakePlugin.kt`：`EXTRA_TASK = "task"`（`:66`），只对录制中心转发、最长 200 字（`:268-270`）；Dart：`lib/platform/share_channel.dart` 的 `SharedPayload.task`（`:58`）；`lib/app/intake/share_intake.dart:123-124`（只有录制中心带任务）；`lib/app/intake/system_intake.dart:77` 的 `openOutsidePage`（页面已在最上面时替换）；`features/recorder/recorder_page.dart`：`recorderTaskOf`（`:110`）、目标和高亮计数（`:131-134`）、`RecorderTaskHighlight`（`:605`）。
- c3：没动。不再使用的键清单在 [record.md](record.md)“留给以后”。

## 3.x 基线

- 3.x 没有“设置里的弹幕页”：弹幕设置只能在直播间里改（`git show v3.2.11:lib/modules/live_play/pages/danmaku_settings_page.dart`，648 行；画面上的面板 `widgets/video_player/video_controller_panel.dart:2206`）；设置 → 视频里有“显示弹幕”等几行和“弹幕关键词过滤”入口（`lib/modules/settings/pages/video_settings_page.dart:266-293`）。设置键名和含义照 3.x（D-018），这个任务不加新设置。
- 3.x 没有“录制已停止”提醒（4.x 的 A14.1 加的），所以 c2 没有 3.x 行为要对照；录制中心的列表照 A10.1。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节第 6 条、第 7 节。
3. 本文件夹的 `README.md`、`record.md`；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`（E1）、`docs/A-界面设计/A11-设置界面/A11.1-设置总览/README.md`（c6、c7）、`docs/A-界面设计/A14-系统界面/A14.1-系统界面/README.md`（录制通知）、`docs/A-界面设计/A10-录制界面/A10.1-录制中心/README.md`。
4. 翻译键（只在要做 c3 时）：`docs/A-界面设计/A15-小页面/A15.1-工具箱/record.md`、`docs/A-界面设计/A15-小页面/A15.2-关于和版本/record.md`、`docs/A-界面设计/A09-浏览界面/A09.10-标签管理/record.md`、`docs/A-界面设计/A08-弹幕界面/A08.3-弹幕屏蔽页/record.md`；`docs/DECISIONS.md` 的 D-016、D-024。

## 范围

- 可以改：`apps/pure_live/lib/features/settings/`、`lib/shared/danmaku/`、`lib/features/recorder/`、`lib/app/`（通知点开）、`lib/routes/`（加路由）、`lib/platform/share_channel.dart`、`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt`、`ShareIntakePlugin.kt`、翻译文件、对应测试。
- 不能改：`features/live_play/`（当时 A07.11 在改；“弹幕列表”“小窗弹幕”两组归 A08.6）；其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；运行时拼出来的翻译键。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1：新页 `DanmakuSettingsPage` + 路由 + “更多” + 搜索行 | `features/settings/danmaku_page.dart`（新）、`settings_section_view.dart`、`settings_catalog.dart`、`routes/route_path.dart`、`app_router.dart`、`tools/gate/ui_baseline.json` | `settings_danmaku_test.dart` 6 个通过（已合并） |
| 2 | c2：提醒带任务 id、请求码按任务、Dart 通路、录制中心定位和高亮、不叠两个录制中心 | 两个 Kotlin 文件、`share_channel.dart`、`app/intake/share_intake.dart`、`system_intake.dart`、`features/recorder/recorder_page.dart` | `recorder_centre_test.dart` 新增 6 个、`intake_test.dart` 新增 2 个通过；debug APK 编译通过（已合并） |
| 3 | 真机验证 | `verify.md` | K90 上 6 步都通过，登记表改“完成” |

每个阶段都要能单独合并（门禁通过、不留半截功能）。c3 不做。

## 测试

- 已有（见 README“验证”）：`apps/pure_live/test/features/settings/settings_danmaku_test.dart`、`test/features/recorder/recorder_centre_test.dart`、`test/intake_test.dart`、`test/features/home/home_test.dart`（路由表）、`settings_page_test.dart`（搜“字体”）。
- 修补时：先写能复现的测试（例如两条提醒各自的任务 id 解析、任务后到时的定位）；Kotlin 的请求码没有单元测试，靠真机第 4 步。
- 测试里的定时器至少 1 秒；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 弹幕 | 和直播间“弹幕设置”标签一样，末尾“更多”；改一项后进直播间立即生效 |
| 2. 两条“录制已停止”提醒分别点 | 各自定位到自己的任务并高亮约 2 秒 |

完整步骤见 [verify.md](verify.md)（6 条）。

## 风险和注意

- 请求码：所有提醒共用一个请求码时，`FLAG_UPDATE_CURRENT` 下 Android 认为是同一个 `PendingIntent`（extras 不参与比较），多条提醒会都指向最后一条的任务；所以每条提醒按任务 id 用自己的请求码（`RecorderForegroundService.kt:180` 起）。
- 录制器启动时在恢复任务，提醒点开时任务可能还没出现：页面要等任务出现再定位（已做，测试“任务后到”）。
- 可能冲突的文件：`features/settings/settings_section_view.dart`、`settings_catalog.dart`（A04.1 改设置的高度分档；A08.6 会改 `danmaku_page.dart`）；`tools/gate/ui_baseline.json`。
- 还没定的（README“留下的问题”）：前台录制通知只有一个房间时点开要不要也定位到那条——维护者定了以后在 H05 开任务，不在本任务里做。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A08.5` 或本机工作区；提交信息以 `[A08.5]` 开头（英文）；不推 master。
- 提交前：`apps/pure_live` 跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`；改了 Kotlin 时 `flutter build apk --debug --target-platform android-arm64`（门禁不在跑的时候，之后 `./gradlew --stop`）；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件（含原生）；新路由和原生意图字段；要在真机上看的；需要维护者决定的；可能冲突的文件。
