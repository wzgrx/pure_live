# A07.11 直播间小问题合集：单击立即响应、全屏状态保持、全屏不再有居中对话框等

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（一批直播间的小问题；没有新的设计稿，照已确认的设计和任务书做）
- 来源：审查报告 B-8、B-10、B-11、B-12、B-15～B-19（[V03.1 全面审查](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；任务书的两次补充：D04.1 之后（c6、c7）、A07.12 之后（c8、c9，维护者已定）
- 旧编号：B09、T05f.2
- 相关：附录 A 第 1、3 条（单击、双击）；D-012；A02.1（`TabLabel`、`AppChip`、可点的 `CommonAvatar`）；A02.2 c13（要用户选的提示条不自动消失）；D04.1（录制面板的异步文件检查）；排在 A07.10、A07.12、A07.13 之后（同一批文件，依次做）

## 目标

直播间里一批“不大但每天碰到”的问题：

- 单击画面立即响应（不再等 300 毫秒双击超时），双击照样切全屏。
- 横屏刘海不挡录制角标；竖屏全屏在分屏、系统“显示大小”调大时不溢出。
- 进出全屏、换布局后，聊天区的标签、滚动位置、三档面板的档位都还在。
- 文字和读屏：取消关注写“取消关注”并能撤销、开播时长写“2 小时 18 分”、把手读“最低 / 中间 / 最高”、电量数字至少 11 号、宽屏把手不再挡画面右缘。
- 录制中心任务卡不在构建时同步读文件；表情只解析一次。
- 全屏里不再弹居中对话框；直播间几个部件换成 A02.1 的统一组件。

## 3.x 和现状

| 方面 | 3.x（`git show v3.2.11:lib/...`） | 现在（文件:行，`apps/pure_live/lib/` 省略） | 要做到 |
|---|---|---|---|
| c1 单击和双击 | 画面的 `GestureDetector` 同时有 `onTap`、`onDoubleTap`（`modules/live_play/widgets/video_player/video_controller_panel.dart:196-249`），单击要等双击超时，慢半拍 | `features/live_play/player/player_view.dart:333-366`（`_onTap`：立即生效，`kDoubleTapTimeout`、`kDoubleTapSlop` 内第二下撤销第一下再切全屏）；`:207`（`_controlsSettling`：刚出现的控制层 300 毫秒内不接点击） | 立即响应，双击照旧 |
| c2 录制角标 | 3.x 画面上没有录制角标（A07.1 新加） | `player_view.dart:717-724`（控制层隐藏时 `left: 12 + padding.left`，全屏时） | 横屏左边刘海不挡 |
| c3 竖屏全屏第二行 | 普通 `Row`，7 个 48 的按钮放不下（`video_controller_panel.dart:1508-1558`） | `features/live_play/player/player_controls.dart:803` 的 `_InlineRow`（上栏 `:319`、下栏 `:748`，放不下时横向滚动，“退出全屏”固定在最右） | 300 宽不溢出 |
| c4 进出全屏保持 | 标签的 `TabController` 在控制器里（`modules/live_play/widgets/danmaku/danmaku_tab.dart:22-25`），标签保留；聊天列表的 `ScrollController` 在列表自己的 State 里（`danmaku_list_view.dart:62`），三档面板高度在 `_PortraitLiveRoomLayoutState`（`widgets/layout/live_play_content.dart:146`），全屏时整个弹幕区不构建，回来后位置和档位丢了 | `features/live_play/layout/room_view_memory.dart:10` 的 `RoomViewMemory`（标签、聊天位置 `ChatListMemory` `:28`、三档档位）；页面持有 `live_play_page.dart:191`，换房间时只留档位（`:373`） | 标签、位置、档位都保持 |
| c5 文字和读屏 | 开播时长、把手读屏、电量 9 号、宽屏没有收起把手（都是 4.x 新加的部件） | 开播时长 `layout/room_info_bar.dart:323`（`shared/rooms/room_texts.dart:66` 的 `elapsedText`）；把手读屏 `layout/portrait_panel.dart:9`、`:255`；电量 `player/bar_parts.dart:120`（最少 36×17，字 11）；宽屏把手进控制层 `RoomPlayer.edge`（`player_view.dart:770`） | 见目标 |
| c6 录制中心任务卡 | — | `shared/record/saved_file.dart:12` 的 `SavedFileCheck`，`features/recorder/recorder_task_card.dart:139` 用它 | 构建时不同步读文件 |
| c7 表情解析 | — | `shared/danmaku/emotes.dart:112`（`Expando` 缓存）、`:122`（`chatSegments`） | 一条消息一张表只解析一次 |
| c8 全屏的居中对话框 | — | 画中画被关掉：`features/live_play/mini/room_mini_window.dart:316` 的提示条；屏蔽关键词：`danmaku/message_panel.dart:81-95` 的第二页；录制失败原因：`record/record_panel.dart:84` 的 `_FailureReason` 在面板里展开 | 全屏里没有居中对话框（还剩一个，见“留下的问题”） |
| c9 统一组件 | — | 标签 `danmaku/chat_panel.dart:106-109` 的 `TabLabel`；清晰度芯片 `record/record_panel.dart:468` 的 `AppChip`；顶栏头像 `layout/room_header.dart:163` 的 `CommonAvatar` | 照 A02.1 |

## 结果

- 改动清单（逐条见 [record.md](record.md)）：
  - c1 B-8：去掉画面的 `onDoubleTap`，单击在手指抬起时立即生效（显示或隐藏控制层，点中飞行弹幕时立即打开面板）；300 毫秒、100 以内的第二下算双击：先撤销第一下（控制层回到原样，或关掉刚打开的弹幕面板），再切全屏。A07.10 的规则不变；锁定时没有双击。补了一处：单击刚让控制层出现时，300 毫秒内控制层不接受点击，免得双击的第二下按到刚出现的按钮。
  - c2 B-10：控制层隐藏时的录制角标 `left: 12 + padding.left`（全屏时）。
  - c3 B-11：竖屏全屏上下栏第二行用和普通页面底栏同一个 `_InlineRow`：放得下时左右分开，放不下时横向滚动；下栏“退出全屏”固定在最右。选了横向滚动，没有收进“更多”。顺带修了两处同类溢出：16:9 画面宽不到 285 时上下栏比画面高；信息条的人数、开播时长在大字体下横向溢出（改成省略）。
  - c4 B-12：`RoomViewMemory` 存标签序号、聊天列表停住时的那批行和滚动位置、三档面板的档位（按档位存，不按像素）；跟随最新时恢复后仍跟随；切到另一个直播间时清空，只保留档位。
  - c5 B-15 已由 A07.12 做（红色“取消关注”、提示条“已取消关注 X · 撤销”）；B-16 开播时长用卡片同一个 `elapsedText`（删掉 `formatOnAir`）；B-17 把手读屏“最低 / 中间 / 最高”；B-18 电量 9 号 → 11 号、框 35×15 → 最少 36×17；B-19 宽屏聊天栏、网络电视节目单的收起把手放进播放器控制层，随控制层显隐、隐藏时不接点击。
  - c6 D04.1 的做法提成共用的 `SavedFileCheck`（构建时用上次的结果，后台 `File.exists()`，同一时间一次，变了才重建），录制面板和录制中心任务卡都用。
  - c7 `chatSegments` 用 `Expando` 把“消息 + 表情表”的解析结果挂在消息上，聊天列表和飞行弹幕层拿到同一个不可改的列表；`EmoteTable.of` 预编译表里代码的正则。
  - c8 “无法打开画中画”改成提示条（“无法打开画中画：系统设置里关掉了“纯粹直播”的画中画”，带“去设置”和 ✕，不自动消失）；“屏蔽关键词…”改成长按弹幕面板的第二页（左上 ←、单行、预填并全选、字数 40、“屏蔽”）；多做一处：录制面板“查看原因”在状态卡下面展开（可选中、“收起”），录制中心页面里仍是对话框。
  - c9 聊天区四个标签用 `TabLabel`（角标、焦点框，窄栏时整个标签缩小）；录制面板清晰度芯片用 `AppChip`（圆角 8、选中带勾）；顶栏头像用可点的 `CommonAvatar`（悬停、按下变暗、焦点框，提示“直播间详情”）。
- 根因（核对过）：B-8 Flutter 的单击识别器要等双击识别器放弃（`kDoubleTapTimeout` 300 毫秒），3.x 也一样；B-10 角标 `Positioned(left: 12)` 没加 `padding.left`；B-11 两条第二行是 `Row` + `Spacer`，7 个按钮加边距 352，分屏或“显示大小”调大后只有 300 左右；B-12 `_page` 按 `_display` 换整棵树，`ChatPanel`、`ChatList`、`PortraitPanelLayout` 的 State 被销毁；B-16 `formatOnAir` 写 `H:MM`；B-17 `Semantics.value` 是像素；B-18 `fontSize: 9`；B-19 把手是页面里叠在画面右缘的 `Positioned`，一直在；c6 `onPlay` 在 `build` 里调 `existsSync`；c7 飞行层对同一条消息再解析一次、每次现编正则；c8 三个函数都是根导航器上的居中对话框。
- 提交：2026-10-02，合并提交 `df67f1147`“Merge B09: instant single tap, kept chat and panel state across layouts, no centred dialogs in full screen”；登记表记的是记录提交 `d3272b9b1`。改了任务书可改目录以外的 `features/recorder/recorder_task_card.dart`、`shared/record/`、`shared/danmaku/emotes.dart`（c6、c7 的补充条目要求）；`features/favorite/` 没动；没有改 `packages/live_ui`、没有原生改动。
- 新设置：无。新翻译键：`portrait_panel_stop_low`、`portrait_panel_stop_middle`、`portrait_panel_stop_high`、`pip_disabled_toast`、`live_play_room_details`；删掉不再用的 `pip_disabled_title`、`pip_disabled_body`（A07.8 加的，3.x 没有）。
- 测试：当时 `apps/pure_live` 全部 863 个通过；改之前跑过、会失败的新测试：c1 单击立即显示、c1 双击不按到按钮、c2 角标、c3 溢出、c6 只用 `exists`。

## 验证

- 自动测试：
  - `apps/pure_live/test/features/live_play/live_play_layouts_test.dart`（+7）：单击后同一帧控制层出现、隔 1 秒两下是两次单击、100 毫秒内两下进出全屏；双击落在暂停键位置不暂停；锁定时没有双击；左边刘海 40 时角标 `left` = 52；360、300、280 宽、文字 1.3 倍竖屏全屏不溢出、第二行可滚动、退出全屏在屏幕内；三档面板读“中间 / 最高 / 最低”、拖到最高档进竖屏全屏再返回仍是最高；宽屏把手在播放器右缘中间、4 秒后随控制层淡出且不接点击；电量字 ≥ 11。
  - `live_play_page_test.dart`（+1）：点飞行弹幕同一帧打开面板，100 毫秒内再点一下面板关上、进全屏。
  - `chat_list_follow_test.dart`（+1）：往上翻 → 进全屏 → 来 20 条 → 返回，位置不变、显示“20 条新弹幕”；“醒目留言”标签进出全屏仍在；回到底部后仍跟随。
  - `test/features/recorder/recorder_centre_test.dart`（+1）：`IOOverrides` 换掉 `File`，只调用 `exists`。
  - `test/shared/emotes_test.dart`（+1）、`chat_feed_test.dart`：同一消息同一张表返回同一个列表。
  - 改了的已有测试：开播时长断言、画中画被关掉改成提示条、屏蔽关键词第二页（`room_popups_test.dart`，横屏全屏时仍在右侧 360）、录制“查看原因”展开、顶栏头像、`TabLabel`、`AppChip`。
- 真机：待真机，步骤见 [verify.md](verify.md)（从记录的“要在 K90 上看的”十四条整理）。

## 留下的问题

- 需要维护者决定的（记录“需要维护者决定的”）：
  1. 双击弹幕区域：现在点中飞行弹幕立即打开面板，双击时面板一闪再关上进全屏（3.x 和 4.0.0 双击弹幕直接进全屏）→ 已登记为 [A07.14](../A07.14-双击飞行弹幕面板一闪/README.md)。
  2. 单击后 300 毫秒内控制层不接受点击（为了双击不按到刚出现的按钮）。
  3. c3 选了横向滚动，没有把方向、画面模式收进“更多”。
  4. c4 切换直播间时清空标签和聊天位置，只保留档位。
  5. B-19 选了随控制层隐藏，把手在播放器右缘中间（很宽很矮的窗口里在 16:9 框的右缘，不在分隔线上）。
  6. 全屏里还剩一个居中对话框：弹幕设置面板“小窗弹幕”一节的“弹幕颜色”（`features/live_play/danmaku/danmaku_settings_panel.dart:197` 调 `shared/danmaku/danmaku_color_dialog.dart:66` 的 `showDanmakuColorDialog`）——可以改成在行下面展开色板，要不要做（没有任务）。
  7. c8 多做了录制面板“查看原因”展开。
  8. c9 窄栏时整个标签缩小（A02.1 c12）；头像是键盘焦点停靠点，名字区域仍可点但不再单独占焦点。
- 可能冲突的文件（记录）：`player/player_view.dart`、`player/player_controls.dart`、`live_play_page.dart`、`layout/portrait_panel.dart`、`danmaku/chat_list.dart`、`chat_panel.dart`、`message_panel.dart`、`record/record_panel.dart`、`mini/room_mini_window.dart`、`shared/danmaku/emotes.dart`、翻译文件。
