# U.2g 直播间的状态

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.2g/README.md](../compare/U.2g/README.md)（第 1 版，用户 2026-10-01 确认全部设计；待选 Z1～Z4 按建议 A 做）
- 范围：画面区域没在正常播放时的样子（加载、未开播、封禁、轮播、状态未知、获取失败、不存在、受限、没给地址、播放中断、重连、纯音频、恢复画面、回放播完），以及网络电视的节目单和回看
- 分工：竖屏、横屏全屏、宽屏的排法（U.2b–U.2d）由另一个代理同时改；这里只做**画面状态组件、状态逻辑和接入点**，没有改三种排法本身。网络电视的节目单和回看照 U.2g 做（包括它在竖屏、宽屏、全屏的位置）
- 改动的目录：`apps/pure_live/lib/features/live_play/`、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档
- 没有改原生部分，没有构建 APK，没有往手机安装

## 结构

| 部分 | 文件 | 说明 |
|---|---|---|
| 画面状态组件 | `packages/live_ui/lib/src/widgets/video_state_view.dart` | `VideoStateView`：转圈（用户选的“加载样式”）/ 图标 / 主播头像 → 一句话 → 一句原因 → 最多两个按钮（第一个白底、第二个描边）；可选 45% / 60% 暗化；`compact`（画面矮）省掉图标；按钮执行中转圈、不接第二次点击 |
| 状态逻辑（纯 Dart） | `features/live_play/logic/room_status.dart` | `pictureStateOf(...)`：由房间阶段、失败原因、房间状态和受限类型、播放状态、重连、纯音频、恢复中、加载较慢算出 18 种状态之一（`PictureStateKind`）、文字、按钮顺序（`PictureAction`）、底下垫什么（`PictureDim`）；`pictureHasControls`（只有打开了直播流才显示上下栏） |
| 接入点 | `features/live_play/player/player_status.dart`（`RoomStatusLayer`、`PictureStateView`、`CatchupBadge`、`AudioOnlyCover`） | 加载较慢的 8 秒计时、恢复画面的计时放在这一层；按钮动作：切换直播间、刷新、重试、换线路、去登录（账号页，回来自动重试）、在平台打开、从头播放 |
| 接入点 | `player/player_view.dart` | 状态层在控制层下面（播放中断时控制栏照常可用）；没在播放时不显示上下栏，全屏时保留精简上栏；回看角标 |
| 接入点 | `player/player_controls.dart` | `PlayerTopBar.reduced`：没在播放时去掉纯音频、投屏、小窗；回看时副标题“正在回看: 节目名” |
| 信息行 | `layout/room_info_bar.dart` | 未开播、封禁、轮播的标签；没在播时只留标题一行，受限时不显示清晰度和线路 |
| 控制器 | `logic/room_controller.dart` | 受限（在播但取不到流）时照常连弹幕、读醒目留言；受限房间不再每 60 秒整个重新加载（弹幕会被打断，用“重试”） |
| 节目单 | `dialogs/iptv_guide.dart`（`IptvGuideView`、`IptvGuideScope`）、`logic/iptv_guide_rows.dart` | 同一个组件放三处；按日期分组、行高 52、正在看的在第三行；读取中、失败重试、没配置来源、频道没有节目四种状态 |
| 页面 | `live_play_page.dart` 的 `_buildChannel` 和面板 | 只改了网络电视频道的分支（竖屏画面 16:9 + 下面节目单；宽屏右栏可收起；全屏右侧面板 `RoomPanelKind.guide`）。普通直播间的三种排法没动 |

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留：时机和判断、“加载样式”、播放中断时控制栏可用、自动恢复逻辑、耳机变黄、节目单的点法和三种状态 | ✅ | 转圈用 `LoadingStyles` 和用户的加载样式和颜色（没设颜色时白色） |
| c2 | 一个画面状态组件，各形态同一个；画面矮时省图标 | ✅ | 画面高 <260 省图标（U.2g 拿不准第 10 条），未开播的头像和受限的锁保留 |
| c3 | “正在进入直播间…”→“正在连接直播流…” | ✅ | |
| c4 | 8 秒还没画面：“比平时慢，可以换一条线路试试”+ 换线路、重试（Z4 A） | ✅ | 只有一条线路时只有“重试” |
| c5 | E2 占位；标签照常可用；没在播放时画面上不显示上下栏 | ✅ | 占位和标签是 U.2a 已有的；上下栏按 `pictureHasControls` |
| c6 | 全屏非播放状态保留精简上栏 | ✅（部分） | 返回、标题、切换直播间保留，纯音频、投屏、小窗去掉；时间电量、录制、菜单是 U.2c 给全屏上栏加的，由那边接上 |
| c7 | 未开播：封面 + 头像 + 一句话 + 切换直播间、刷新；不弹提示条；“未开播”标签；弹幕区显示公告 | ✅ | 弹幕区：公告卡片（三行，可展开）+“开播后这里显示弹幕”（`RoomNoticeState`，在 U.2e 的列表里） |
| c8 | 未开播时每 60 秒查一次，开播自动播放（Z2 A） | ✅ | v4 原有（`refreshDetail`），有测试；“进后台时停止”没有另做（原来的定时器在后台照跑，见“没做的”） |
| c9 | 全屏中下播留在全屏（Z3 A） | ✅ | v4 本来就不退出；有测试（全屏未开播时上栏有返回键） |
| c10 | 封禁、轮播、状态未知、不存在、获取失败各写各的 | ✅ | 不存在只给“切换直播间”；状态未知“刷新”在前 |
| c11 | 受限写原因和下一步；红框标签；弹幕照常 | ✅ | 需要登录：去登录、重试；付费、订阅、私密、仅 App、密码、年龄：在{平台}打开、切换直播间（网络电视没有平台页面，改为重试、切换直播间）；地区：重试、切换直播间；没给地址：重试、切换直播间。失败原因是 `NeedsLogin`、`RegionBlocked`、`StreamUnavailable` 但房间没有受限标记时按同样的类型处理 |
| c12 | 播放中断：原因写在画面上，重试、换线路；不弹提示条；暗化 60% 不盖控制栏 | ✅ | v4 原来就没有弹播放错误的提示条 |
| c13 | 重连照 E3，加 45% 暗化 | ✅ | |
| c14 | 纯音频照 E5；保留“正在恢复实时画面”；去掉透明度、滤镜、模糊、缩放 | ✅（有偏差） | 播放会话不报告“第一帧”，“正在恢复实时画面”显示到画面尺寸重新报告或最多 3 秒 |
| c15 | 回放已播完：从头播放、切换直播间 | ✅ | |
| c16 | 节目单：竖屏画面下方、横屏右侧面板、宽屏右栏可收起；同一个组件（Z1 A） | ✅ | 上栏节目单按钮：竖屏滚回正在看的节目，宽屏展开收起的栏，全屏打开右侧面板（宽 360）；返回键和 Esc 先关面板 |
| c17 | 按日期分组、正在播的在第三行、“回看”、超范围变灰、直播红标签、“可回看 N 天”、标题“节目单” | ✅ | 每 30 秒刷新一次标记（只重建看得到的行）；频道没写天数时不显示天数，不支持回看时写“不支持回看” |
| c18 | 回看中：画面角标、上栏副标题、节目单顶上的条和“返回直播”；不弹提示条 | ✅ | 角标“回看 19:30 · 返回直播”，点时间部分打开或显示节目单；回看打开失败显示为画面上的播放中断，不弹提示条 |
| c19 | 没配置节目单来源：“还没有节目单”+ 去导入节目单 | ✅ | 跳网络电视管理（路由 `/iptv`）；和“这个频道在节目单里没有节目”分开 |

### 选择

Z1～Z4 都按 A，见上表 c16、c8、c9、c4。

### 提示条（设计“提示条”一节）

| v3 提示条 | 做到 |
|---|---|
| 当前主播未开播或已下播；服务器错误（封禁）；获取直播间信息失败 | v4 本来没有弹，画面上写 |
| 无法读取视频信息 / 读取失败 / 无法读取播放地址 | 画面写受限原因或“平台显示在播，但没有给出可播放的地址”（手动换清晰度失败的提示条保留，那是正在播放时） |
| 8 种播放错误 | 写在播放中断画面上 |
| 无效播放地址、该节目尚未开播、该节目不在可回看范围内 | 保留 |
| 正在为您加载回看节目 / 已返回直播 | 去掉 |
| 无法播放直播（回看失败） | 画面上的播放中断 |

## `AppIcons` 和颜色（`packages/live_ui`，只做添加）

- 图标（跨任务待同步 U.2g → U.1b 的三个也在内）：`switchLine`（Material `alt_route`）、`banned`（`block`）、`statusUnknown`（`help_outline`）、`login`、`guideTitle`、`catchup`、`liveNow`、`guideEmpty`、`guideFailed`、`add`、`unfoldLeft`；U.2e 用的 `chatEmpty`、`danmakuTimeout`、`danmakuUnavailable`、`superChatPrice`、`superChatMark`、`superChatTime`、`chipRemove`。对照表测试已更新。
- 颜色角色：`OnVideoColors.dimLight`（45%）、`buttonInk`、`buttonFill`、`buttonOutline`、`avatarRing`；`InkOnColor.contrastOn` / `contrastMutedOn`（按对比度选墨色）；`LiveSemanticColors.superChatGold`。

## v3 文件 → v4 文件

| v3（`lib/modules/live_play/`） | v4（`features/live_play/` 和 `packages/live_ui`） |
|---|---|
| `widgets/layout/live_play_video.dart`、`widgets/video_player/video_loading.dart`、`widgets/placeholder/not_living_video_widget.dart`、`widgets/video_player/playback_failure_overlay.dart` | `player/player_status.dart`、`logic/room_status.dart`、`live_ui` 的 `VideoStateView` |
| `player/core/player_manager.dart` 的 `buildAudioOnlyUI` | `player/player_status.dart`（`AudioOnlyCover`、“正在恢复实时画面”状态） |
| `widgets/video_player/iptv_schedule_dialog.dart`、`video_controller.dart` 的节目单和回看部分 | `dialogs/iptv_guide.dart`、`logic/iptv_guide_rows.dart`、`live_play_page.dart`（`_buildChannel`） |
| `controllers/live_play_controller.dart`（`_handleNotLiveRoom`、`_handleUnknownStatus`）、`controllers/player_controller.dart` | `logic/room_controller.dart` |
| `resolution_selector/resolutions_row.dart` | `layout/room_info_bar.dart` |

## 新设置项

无。

## 新增的文字

中英各加：`live_play_connecting_stream`、`live_play_slow_hint`、`live_play_go_login`、`live_play_catchup_badge`、`live_play_guide_title`、`live_play_guide_catchup_days`、`live_play_guide_no_catchup`、`live_play_guide_replay_short`、`live_play_guide_replaying`、`live_play_guide_replaying_at`、`live_play_guide_replaying_now`、`live_play_guide_tomorrow`、`live_play_guide_date`、`live_play_weekday_1`～`7`、`live_play_guide_loading`、`live_play_guide_import`、`live_play_guide_channel_empty`、`live_play_guide_fold`、`live_play_guide_unfold`、`live_play_chat_after_live`。改了一条已有词条的中文：`live_play_guide_failed`“读取节目单失败”→“节目单读取失败”（照设计，只有节目单用）。

## 门禁

- `live_play` 直接写的颜色和图标 9 → 8（和 U.2e 合计），`ui_baseline.json` 已改。
- 没有新增跨功能引用；新的 `logic/room_status.dart`、`logic/iptv_guide_rows.dart` 不引 material（`room_status.dart` 只从 foundation 取 `immutable`）。

## 测试

- 新增 `test/features/live_play/live_play_states_test.dart` 19 个：
  - 逻辑：加载、连接、较慢（一条线路时只有重试）；未开播、封禁、轮播、状态未知的文字和按钮顺序；获取失败和不存在；受限各类型的按钮；播放中断、重连、纯音频、恢复、播完；只有打开了直播流才有上下栏；节目单的分组、各行状态、第三行位置、日期文字、“可回看 N 天 / 不支持回看”。
  - 直播间里：加载时的文字和转圈、没有上下栏、标签可用，加载完后出现下栏；未开播的头像、两个按钮的顺序、不弹提示条、信息行“未开播”标签、弹幕区公告和“开播后这里显示弹幕”；受限（需要登录、付费）的按钮和弹幕照常连接；较慢 8 秒后的提示和按钮；全屏未开播的精简上栏；宽屏状态在左边。
  - 网络电视：竖屏节目单在 16:9 画面下面；宽屏右栏用把手收起、上栏按钮展开；全屏上栏按钮打开右侧 360 宽的面板、Esc 先关面板；节目单的头部、日期、直播标签、回看文字、点没开始的节目提示；读取中、失败重试、没配置来源、频道没有节目。
- `live_ui` 新增 3 个（`VideoStateView` 的结构和按钮样式、省图标和转圈、按钮执行中转圈）。
- 和新设计冲突、照实改了的原有断言：

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `live_play_page_test` 获取失败 | “直播间不存在”时有“重试” | 有“切换直播间”，没有“重试” | c10：不存在的直播间重试没有用 |

- 全部测试：`apps/pure_live` 310 个通过；`flutter analyze` 无问题；`check_ui_structure.py` 通过。

## 没做的和原因

1. **全屏精简上栏里的时间电量、录制、菜单**：U.2c 正在给全屏上栏加这些按钮；这里只做了 `reduced`（去掉要有画面才有用的三个）。U.2c 合并时在 `reduced` 下保留它们即可。
2. **宽屏节目单栏的把手**：设计要求和 U.2d 收起聊天栏是同一个把手；U.2d 还在做，这里先做了一个同样位置和大小的把手（`_GuideFoldHandle`），U.2d 合并后换成同一个组件。
3. **未开播检查在应用进后台时停止**：原来的 60 秒定时器在后台照跑，这次没改（涉及 `RoomBackgroundPolicy`，属于 U.2j 的后台播放规则）。
4. **“去登录”跳到哪**：先跳账号页（`/settings_account`），回来自动重试；具体到平台的登录位置随 U.10b 定（跨任务待同步已记）。
5. **暂停时画面中间的大暂停图标**：v3 没有，留给 U.2a/U.2c 决定（设计拿不准第 9 条），保持原样。
6. **网络电视顶栏的录制按钮**：不在本任务范围（设计拿不准第 5 条）。
7. **电视**：U.15d、U.15e 出图。
