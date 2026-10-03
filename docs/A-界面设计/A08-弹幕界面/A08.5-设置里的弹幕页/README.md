# A08.5 设置里的弹幕页和直播间同一个组件；“录制已停止”通知定位到任务

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（待真机：代码 2026-10-02 合并，K90 还没逐项看，见 [verify.md](verify.md)）；当时的任务单写的规模小
- 类型：功能
- 来源：界面任务合并后留下的跨任务约定：A11.1 c6（设置总览“播放”组新加“弹幕”一行）→ A08.1、A11.3（“这一行要和直播间同一个组件，需要给它加路由”）；A14.1（录制通知）→ A10.1（录制中心按任务定位）；A15.1、A15.2、A09.10、A08.3 的记录里列出的不再使用的翻译键
- 旧编号：F02、T06e.2（见 [MAPPING.md](../../../MAPPING.md)）
- 相关：决定 D-016、D-024（翻译键这次不清理，c3 不做）；设计沿用已确认的 [A08.1](../A08.1-弹幕列表和弹幕设置页/README.md) 和 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md)（弹幕设置组件）、[A11.1](../../A11-设置界面/A11.1-设置总览/README.md) c6（总览的“弹幕”行）、[A14.1](../../A14-系统界面/A14.1-系统界面/README.md)（录制通知）、[A10.1](../../A10-录制界面/A10.1-录制中心/README.md)（录制中心）；后续 [A08.6](../README.md)（把“弹幕列表”“小窗弹幕”两组也放进设置的弹幕页）
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)；真机：[verify.md](verify.md)

## 目标

- 设置 → 弹幕打开的页面就是直播间的“弹幕设置”（同一个组件、同样的分组和范围），改一项马上对所有直播间生效；有自己的路由，能从别处直接打开。之前打开的是 J01.1 留下的一组目录行（另一套分组和范围），两处对不上。
- “录制已停止”通知点开后，录制中心滚到那个任务并短暂高亮，用户一眼找到出问题的那条；之前只能打开录制中心顶部。
- （c3）清理不再使用的翻译键：按维护者决定不做（D-024），键名清单留在记录里。

## 3.x 和现状

| 方面 | 3.x（文件:行） | 开工前的 4.x | 现在（文件:行） | 要做到 |
|---|---|---|---|---|
| 弹幕设置在哪里改 | 只能在直播间：画面上的面板和“弹幕设置”标签（`git show v3.2.11:lib/modules/live_play/pages/danmaku_settings_page.dart`，648 行；`widgets/video_player/video_controller_panel.dart:2206`），设置里只有视频页的几行和“弹幕关键词过滤”入口（`lib/modules/settings/pages/video_settings_page.dart:266-293`） | 总览“弹幕”打开 `settings_catalog.dart` 弹幕一节的目录行（Remix 图标、自己的分组和范围：显示区域 10%～100%、速度 30～400、字号 10～40） | `apps/pure_live/lib/features/settings/danmaku_page.dart` 的 `DanmakuSettingsPage`（`:32`）：正文是 `shared/danmaku/danmaku_settings_content.dart` 的 `DanmakuSettingsContent`，第一组标题右边“改动立即生效”，末尾“更多”（`_More` `:72`）；总览入口 `settings_section_view.dart:129`；路由 `/danmaku_settings`（`routes/route_path.dart:72`、`app_router.dart:62`） | 和直播间同一个组件（做到）；“弹幕列表”“小窗弹幕”两组还没有（A08.6） |
| 录制停止的提醒 | 3.x 没有“录制已停止”提醒 | 提醒和按钮都是 `openRecordings(context, 1/2)`，意图里只有 `route`，所有提醒共用请求码 1、2 | Kotlin：提醒带任务 id，每个任务自己的请求码（`android/app/src/main/kotlin/com/mystyle/purelive/RecorderForegroundService.kt:171-179` 的 `openRecordings`、`:180` 起的请求码说明）；`ShareIntakePlugin.EXTRA_TASK = "task"`（`ShareIntakePlugin.kt:66`，只对录制中心转发、最长 200 字 `:268-270`）；Dart：`SharedPayload.task`（`lib/platform/share_channel.dart:58`）→ `share_intake.dart:123-124` → `RecorderPage`（`features/recorder/recorder_page.dart:94`，`recorderTaskOf` `:110`，高亮 `RecorderTaskHighlight` `:605`） | 点提醒定位到那条并高亮（做到）；录制中心开着时不叠第二个（`openOutsidePage`，`lib/app/intake/system_intake.dart:77`） |
| 不再使用的翻译键 | — | 旧弹幕目录行、A15/A09.10/A08.3 换掉的页面留下的键 | 没清（D-024） | 不做 |

## 结果

- c1 设置里的“弹幕”行打开的页面和直播间的弹幕设置用同一个组件，并有路由：做到。
  - `DanmakuSettingsPage` 正文 = `DanmakuSettingsContent`（观看模板、显示范围含 A07.10 的“暂停时的弹幕”、样式、重复弹幕、画面弹幕交互、流畅度），第一组标题右边“改动立即生效”，最多 720 宽，宽屏在右栏打开；路由 `RoutePath.kDanmakuSettings = '/danmaku_settings'`（3.x 没有这条路由）。
  - 原来那页有、组件里没有的全局设置放在末尾“更多”：显示弹幕、在画面上显示飞行弹幕（`hideDanmaku` 反着显示）、YouTube 显示全部聊天、更换弹幕字体（显示当前字体，打开字体页）、弹幕屏蔽（打开 `/shield`）。
  - 搜索：目录里弹幕一节改成只给搜索用的行，分组、标题、范围和这一页一致；屏蔽行加了“相似、刷屏、斗鱼、机器人”关键词。
- c2 “录制已停止”通知点开后定位到录制中心里对应的任务：做到。通知本身和“打开录制中心”按钮都带任务 id；录制中心滚到那张卡（没建出来时一屏一屏往下找；录制器还在恢复、任务后到时，等它出现再定位），主色描边 + 淡底高亮约 2.4 秒（前一半保持、后一半淡出）；任务已删除时停在顶部；系统“减少动态效果”时滚动不做动画。顺带：从外部打开的页面正好在最上面时替换它而不是再压一层（录制中心、搜索快捷方式都受益）。
- c3 清理翻译键：按维护者决定不做（D-024；上一次清理误删了运行时拼出来的键，4.0.0 里刷新率说明显示成了键名）。清单见记录“留给以后”。
- 偏差（记录“偏差和原因”）：
  1. “弹幕列表”“小窗弹幕”两组没有放进设置的弹幕页：它们在 `features/live_play` 的 `RoomDanmakuSettings` 里，设置不能引用，当时也不能改 `live_play`（A07.11 在改）。→ 登记为 A08.6。
  2. “更多”一组是新的（全局设置放末尾，建议 A）；“显示弹幕”“字体”“屏蔽”在视频页也各有一行（同一个设置）。
  3. 相似过滤、斗鱼过滤不在弹幕页上，在“弹幕屏蔽”页（A08.3）。
  4. 改了任务单“可以改”以外的文件：`lib/routes/`（c1 本身要求加路由）、`lib/platform/share_channel.dart`、两个 Kotlin 文件（c2 的意图 → Dart 通路）、测试 `home_test.dart`、`intake_test.dart`。
  5. 前台录制通知（“正在录制 · 主播名”）点开仍是录制中心顶部（任务单只要求“录制已停止”）。
- 改了哪些文件、新路由和原生意图字段：见记录。没有新设置、没有新翻译键（“更多”用已有的 `more`）。门禁：settings 的直接图标 25 → 0（`tools/gate/ui_baseline.json` 去掉这一项）。
- 提交：`10bbcabe1`（`Settings: the danmaku page is the live room's danmaku settings, with a route`）、`6a599edee`（`Recording reminder opens the recording centre at its task`）；合并 `8fe678164`（2026-10-02，`Merge F02: …`）；登记表写的是记录提交 `ec7a27261`。

## 性能任务：测量

不是性能任务。

## 验证

- 自动测试（新增 14 个，改了 2 个；合并 master 后 `apps/pure_live` 852 个通过）：
  - `apps/pure_live/test/features/settings/settings_danmaku_test.dart`（6）：总览“弹幕”打开的是 `DanmakuSettingsContent`（分组顺序、“改动立即生效”、暂停时的弹幕、不再画目录行、返回总览）；改描边就是直播间那个设置；“更多”的三个开关（含反向的“在画面上”）、字体名“系统默认”、屏蔽打开 `/shield`；1280×800 在右栏、不超过 720；搜索“弹幕 速度”“暂停”“相似”；路由表。
  - `apps/pure_live/test/features/recorder/recorder_centre_test.dart`（新增 6）：手机上 12 个任务定位到最后一个、描边 3 秒后消失；第一屏原地高亮；1280×800 三栏；任务后到；任务不存在；`recorderTaskOf`。
  - `apps/pure_live/test/intake_test.dart`（新增 2）：任务只随录制中心传给页面；录制中心在最上面时再打开是替换。
  - 原生：`flutter build apk --debug --target-platform android-arm64` 编译通过；Kotlin 的请求码和 extra 没有单元测试。
- 真机：**待真机**，步骤在 [verify.md](verify.md)（来自记录“要在真机上看的”6 条）。

## 留下的问题

- 设置的弹幕页缺“弹幕列表”“小窗弹幕”两组 → [A08.6](../README.md)（记录“需要维护者决定的”第 1 条，登记表已登记为任务）。
- 前台录制通知只有一个房间时点开要不要也定位到那条（记录“需要维护者决定的”第 2 条）：还没定，写在 [brief.md](brief.md)“风险和注意”；属于录制通知，定了以后在 H05（录制通知）开任务。
- c3 翻译键：D-024，以后由 Z05 按 D-016 先列清单。
- 设置的弹幕页在电脑上 Esc 不返回 → A05.1。
- 可能冲突的文件：`features/settings/settings_section_view.dart`、`settings_catalog.dart`（A04.1 也改设置的高度分档）；`tools/gate/ui_baseline.json`。
