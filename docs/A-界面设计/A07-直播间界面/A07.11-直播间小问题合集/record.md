# A07.11 记录：直播间小问题合集

- 日期：2026-10-02
- 任务单：[tasks/B09.md](brief.md)（c1～c5，加“D04.1 之后补充”的 c6、c7 和“A07.12 之后补充”的 c8、c9）；审查报告 B-8、B-10、B-11、B-12、B-15～B-19、B-20 的后续。
- 本地 worktree 任务：开工前合并了本地 master（A07.10～D04.1、A02.2、R02.2～A03.2）；做 c9 前又合并了一次（A02.1、R01.1：c9 要用 A02.1 新加的 `TabLabel`、`AppChip`、可点的 `CommonAvatar`），提交前再合并了一次（A08.5）。三次都没有冲突。没有改 Android 原生代码，没有构建 APK；没有改 `packages/live_ui`。

## 逐条对照

| 编号 | 条目 | 做了没有 | 内容和偏差 |
|---|---|---|---|
| c1 | B-8 单击不再等双击超时 | 完成 | 画面的 `GestureDetector` 去掉 `onDoubleTap`，单击在手指抬起时立即生效：显示或隐藏控制层，点中飞行弹幕时立即打开它的面板。`kDoubleTapTimeout`（300ms）内、`kDoubleTapSlop`（100）以内的第二下算双击：先撤销第一下（控制层回到原来的样子，或关掉刚打开的弹幕面板），再切全屏。A07.10 的规则不变：暂停时单击只显示或隐藏控制层，不继续播放；锁定时单击只显示或隐藏解锁按钮，没有双击。**补了一处**：单击刚让控制层出现时，在这 300ms 内控制层不接受点击，否则双击的第二下会落在刚出现的按钮上（例如在底栏位置双击会按到暂停）；以前控制层要等超时后才出现，所以没有这个问题 |
| c2 | B-10 录制小角标横屏让开左边刘海 | 完成 | 控制层隐藏时左上角的录制角标 `left: 12 + padding.left`（全屏时；普通页面不变），和回放标记、识别状态一致 |
| c3 | B-11 竖屏全屏上下栏第二行宽度不够 | 完成（选横向滚动） | 上栏第二行（时钟、电量 … 切换、纯音频、投屏、小窗）和下栏第二行（播放、刷新、弹幕开关、弹幕设置 … 画面模式、方向）改用和普通页面底栏同一个 `_InlineRow`：放得下时左右分开，放不下时横向滚动；下栏的“退出全屏”固定在最右，不跟着滚走。没有采用“收进更多”（会多一层操作）。顺带修了两处同类溢出：普通页面 16:9 画面在宽度不到 285 时上下栏（80+80）比画面高、竖向溢出（改成两条栏各贴上下边，最多阴影重叠）；信息条的人数、开播时长在大字体下横向溢出（改成省略） |
| c4 | B-12 退出全屏后标签、滚动位置、三档面板档位保持 | 完成 | 页面 State 里新 `RoomViewMemory`（`layout/room_view_memory.dart`）：聊天区标签序号；聊天列表停住时（往上翻过）的那批行、计数和滚动位置；竖屏三档面板停在哪一档（最低 / 中间 / 最高，按档位存不按像素，换方向后仍是一档）。普通布局和全屏、宽屏和窄屏、切走标签再切回来，都从这里恢复。跟随最新时恢复后仍跟随。切到另一个直播间（上下滑换台、切换直播间）时清空，只保留面板档位 |
| c5 | B-15 取消关注 | A07.12 已做 | A07.12 已把确认按钮写成红色“取消关注”，取消后提示条“已取消关注 X · 撤销”；`live_play_page_test` 里有测试。本任务没再改 |
| c5 | B-16 开播时长 | 完成 | 信息条和详情里的开播时长改用卡片同一个 `elapsedText`：“2 小时 18 分”“18 分钟”“2 天 3 小时”（原来“2:18”，像录制的分:秒）。删掉 `formatOnAir` |
| c5 | B-17 三档面板把手读屏 | 完成 | `Semantics` 的 value、加减后的值读“最低 / 中间 / 最高”（原来“250 px”） |
| c5 | B-18 电量数字 | 完成 | 9 号改 11 号；电池框从 35×15 改成最少 36×17，字大了框跟着变大，不会裁字 |
| c5 | B-19 聊天栏收起把手 | 完成（选跟控制层一起隐藏） | 宽屏聊天栏、网络电视节目单的收起把手放进播放器控制层（`RoomPlayer.edge`），和控制层一起淡入淡出，隐藏时不接受点击，不再挡画面右缘的音量手势和弹幕点按。底栏的“收起聊天栏”按钮照旧 |
| c6 | 录制中心任务卡构建时同步 `existsSync` | 完成 | D04.1 录制面板的做法提成共用的 `shared/record/saved_file.dart`（`SavedFileCheck`：构建时用上次的结果，后台 `File.exists()`，同一时间一次，结果变了才重建），录制面板和录制中心任务卡都用它 |
| c7 | 表情解析两处各一次；`EmoteTable` 预编译正则 | 完成 | `chatSegments` 用 `Expando` 把“消息 + 表情表”的解析结果挂在消息上，聊天列表（`ChatLine.segments`）和飞行弹幕层拿到同一个不可改的列表；`EmoteTable.of` 预先编好表里代码的正则，消息自带表情（哔哩哔哩、CHZZK、YouTube）时才现编 |
| c8 | 全屏里不再有居中对话框 | 完成（多做一处） | “无法打开画中画”改成提示条：“无法打开画中画：系统设置里关掉了“纯粹直播”的画中画”，带“去设置”和 ✕，不自动消失（A02.2 c13“要用户选的”）。“屏蔽关键词…”改成长按弹幕面板的第二页：标题“屏蔽弹幕关键词”、左上 ←、输入框（单行、预填弹幕并全选、字数 40、说明行）、“屏蔽”；屏蔽后关面板、提示“关键词已加入弹幕屏蔽列表”。**多做的一处**：录制面板里“查看原因”原来也是居中对话框（`showRecordFailureReason`，A07.12 记录里没列），改成在状态卡下面展开全文（可选中、“收起”）；录制中心页面里的同一个按钮仍是对话框（不在全屏里） |
| c9 | A02.1 留给直播间的 | 完成 | 聊天区四个标签改用 `TabLabel`（弹幕列表的未读数、醒目留言数是它的角标；键盘焦点框；窄栏时整个标签缩小，不再把数字挪到字的右上角，这是 A02.1 c12 定的）；录制面板清晰度芯片改用 `AppChip`（圆角 8、选中带勾）；顶栏头像改用可点的 `CommonAvatar`（悬停变暗、按下变暗、键盘焦点框，提示“直播间详情”），点头像和点名字一样打开详情 |

验收：

- 每条 c 都有测试（见“测试”）；竖屏全屏在 360、300、280 宽、文字 1.3 倍时不溢出，有测试。

## 根因（核对过）

- **B-8**：画面的 `GestureDetector` 同时有 `onTap` 和 `onDoubleTap`，Flutter 的单击识别器要等双击识别器放弃（`kDoubleTapTimeout`，300ms）才回调 `onTap`。3.x 也一样（`v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart` 的 `GestureDetector` 同时挂 `onTap` 和 `onDoubleTap`），所以 3.x 单击也慢半拍。
- **B-10**：控制层隐藏时的角标 `Positioned(left: 12)` 没加 `padding.left`，别的角标都加了。
- **B-11**：竖屏全屏两条第二行是普通 `Row` + `Spacer`，7 个 48 的按钮加左右 8 共 352；分屏或“显示大小”调大后宽度只有 300 左右。
- **B-12**：`_page` 按 `_display` 在普通布局和全屏之间换整棵树，`ChatPanel`、`ChatList`、`PortraitPanelLayout` 的 State 随之销毁；重建时 `TabController` 从 0 开始、`ScrollController` 是新的、面板高度为空（回到初始档）。
- **B-16**：`formatOnAir` 写 `H:MM`。**B-17**：把手 `Semantics.value` 是 `'${current.round()} px'`。**B-18**：`fontSize: 9`。**B-19**：把手是页面里叠在画面右缘的 `Positioned`，一直在。
- **c6**：`recorder_task_card.dart` 的 `onPlay` 在 `build` 里调 `File(output).existsSync()`。
- **c7**：`ChatLine.segments` 只在行上缓存；飞行层 `_segments` 对同一条消息再调一次 `chatSegments`，而 `chatSegments` 每次都 `RegExp(...)` 现编整张表的正则。
- **c8**：`showAppMessageDialog`、`showAppInputDialog`、`showAppDialog` 都是根导航器上的居中对话框，全屏时压在画面中间。

## 测试

改之前会失败的新测试，改之前跑过、都失败：c1 单击立即显示、c1 双击不按到按钮、c2 角标、c3 溢出、c6 任务卡只用 `exists`。

- `live_play_layouts_test.dart`（+7）：单击后同一帧控制层出现，隔 1 秒的两下是两次单击，100ms 内两下进出全屏；双击落在暂停键位置不暂停、之后按钮照常可点；锁定时没有双击；横屏左边刘海 40 时角标 `left` = 52；360、300、280 宽、文字 1.3 倍竖屏全屏不溢出，两条第二行可滚动、退出全屏在屏幕内、窄时拖动后方向按钮在退出全屏左边；三档面板读“中间 / 最高 / 最低”，拖到最高档、进竖屏全屏再返回仍是最高档；宽屏把手在播放器右缘中间、4 秒后随控制层淡出且不接受点击，点画面后能用；电量字 ≥ 11（加在原测试里）。
- `live_play_page_test.dart`（+1）：点飞行弹幕同一帧打开面板，100ms 内再点一下面板关上、进全屏、弹幕不再停住。
- `chat_list_follow_test.dart`（+1）：往上翻 → 进全屏 → 全屏时来 20 条 → 返回：滚动位置、同一行的位置不变，显示“20 条新弹幕”；切到“醒目留言”进出全屏仍在该标签；回到底部后进出全屏仍跟随。
- `recorder_centre_test.dart`（+1）：用 `IOOverrides` 换掉 `File`，文件出现后“播放”出现，只调用了 `exists`。
- `emotes_test.dart`（+1）、`chat_feed_test.dart`（加断言）：同一消息同一张表返回同一个列表、列表不可改、换表重新解析、同样文字的另一条消息另算；聊天行和飞行层拿到同一个解析结果。
- 改了的已有测试：开播时长断言改成“30 分钟”“2 小时 18 分”（`live_play_room_test`、`live_play_page_test`）；画中画被关掉改成断言提示条（文字、“去设置”、不自动消失、点了调 `openSettings`、没有对话框）；屏蔽关键词断言面板第二页（无对话框、← 回到操作、✕ 关闭），横屏全屏时第二页仍在右侧 360、能屏蔽（`room_popups_test`）；录制面板“查看原因”断言在面板里展开、可选中、可收起；顶栏头像是可点 `CommonAvatar`、有焦点框、点了打开详情；聊天区 4 个 `TabLabel`、醒目留言角标；清晰度芯片是 `AppChip`、圆角 8。
- `apps/pure_live`：最后一次合并 master 后 `flutter analyze` 无问题，`dart format` 无改动，全部 `flutter test` **863 条通过**。根目录 `python3 tools/gate/check_ui_structure.py` 通过。没有改 `packages/live_ui`，没有跑它的测试。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/`：
  - `player/player_view.dart`（c1 单击 / 双击、c2、c3 两条栏贴边、B-19 `edge`）、`player/player_controls.dart`（c3）、`player/bar_parts.dart`（B-18）；
  - `live_play_page.dart`（c4 记忆、B-19 把手移进播放器）、`layout/room_view_memory.dart`（新）、`layout/portrait_panel.dart`（c4 档位、B-17）、`layout/room_info_bar.dart`（B-16、省略）、`layout/room_header.dart`（c9 头像）；
  - `danmaku/chat_list.dart`（c4）、`danmaku/chat_panel.dart`（c4 标签、c9 `TabLabel`）、`danmaku/message_panel.dart`（c8 第二页）；
  - `record/record_panel.dart`（c6 共用检查、c8 查看原因、c9 `AppChip`）、`mini/room_mini_window.dart`（c8 提示条）。
- `apps/pure_live/lib/features/recorder/recorder_task_card.dart`（c6）。
- `apps/pure_live/lib/shared/record/saved_file.dart`（新，c6）、`apps/pure_live/lib/shared/danmaku/emotes.dart`（c7）。
- `apps/pure_live/assets/translations/zh.json`、`en.json`。
- 测试见上。
- 任务单写的“可以改”是 `features/live_play/` 和 `features/favorite/`；c6、c7 按补充条目改了 `features/recorder/recorder_task_card.dart`、`shared/record/`、`shared/danmaku/emotes.dart`。`features/favorite/` 没动。

## 新设置和翻译键

- 没有新设置。
- 新翻译键（zh / en）：`portrait_panel_stop_low`（最低）、`portrait_panel_stop_middle`（中间）、`portrait_panel_stop_high`（最高）、`pip_disabled_toast`（无法打开画中画：系统设置里关掉了“{app}”的画中画）、`live_play_room_details`（直播间详情）。
- 删掉不再使用的：`pip_disabled_title`、`pip_disabled_body`（A07.8 加的，3.x 没有）。

## 要在 K90 上看的地方（Redmi K90 Pro Max，Android 17，120Hz）

1. 进一个横屏直播间，等控制层自动隐藏，单击画面：控制层立即出现（不再慢半拍）；再单击立即隐藏。双击画面：进全屏；全屏里双击：退出。在底栏按钮的位置双击：只切全屏，不会暂停或刷新。
2. 打开“点击弹幕”，点一条飞行弹幕：面板立即打开；在同一处快速双击：面板一闪关上、进入全屏。
3. 暂停后单击画面：只显示或隐藏控制层，不继续播放（A07.10 规则）。全屏锁定后单击：只显示或隐藏解锁按钮，双击不退出全屏。
4. 开分屏（上下分屏）或把系统“显示大小”调到最大，进一个竖屏直播的竖屏全屏：上下两行按钮不出现黄黑条；放不下时第二行能左右拖，下栏最右的“退出全屏”一直在。
5. 横屏全屏（刘海在左边）开着录制，等控制层隐藏：左上角“● 录制中”角标不被刘海挡住。
6. 普通页面切到“醒目留言”，或在“弹幕列表”往上翻一段，进全屏再退出：仍在原标签、原位置，底部按钮显示全屏期间来的新弹幕数。竖屏直播把面板拖到最高档，进竖屏全屏再退出：仍是最高档。
7. 信息条和详情里的开播时长写“2 小时 18 分”这样的字。全屏顶栏电量数字比以前大、清楚。
8. 打开 TalkBack，聚焦竖屏直播面板的把手：读“弹幕面板高度，中间”，上下调整读“最高”“最低”。
9. 平板横放（宽屏，聊天栏在右）：聊天栏收起把手随控制层出现和消失；控制层隐藏时在画面右缘上下滑调音量不被挡。
10. 系统设置里关掉本应用的画中画，点小窗按钮：底部（全屏时在下栏上方）出现提示条“无法打开画中画：…”，带“去设置”和 ✕，不自动消失；点“去设置”到系统页面。
11. 横屏全屏长按一条弹幕（或点飞行弹幕）→“屏蔽关键词…”：右侧面板换成第二页（左上 ←），输入框预填弹幕、键盘弹出；改成一个词点“屏蔽”：面板关上、提示“关键词已加入弹幕屏蔽列表”。
12. 录制失败的直播间打开录制面板，点“查看原因”：全文在状态卡下面展开，可以长按选择复制，“收起”收回；全屏里也不弹居中对话框。
13. 录制中心里已保存的任务卡：“播放”按钮正常出现，滑动列表不卡。
14. 聊天区标签的未读数、醒目留言数是蓝色小圆角标；录制面板的清晰度芯片是圆角 8、选中带勾；按住顶栏头像时头像变暗，点了打开详情。

## 需要维护者决定的

1. **双击弹幕区域**：现在点中飞行弹幕立即打开面板，双击时面板会一闪再关上进全屏；以前（3.x 和 4.0.0）双击弹幕直接进全屏、不打开面板。如果觉得一闪不好，可以只在点中弹幕时保留等待（单击其他地方仍立即响应）。
2. **单击后 300ms 内控制层不接受点击**（为了双击不按到刚出现的按钮）：极快地“点出控制层马上点按钮”会差这一下，正常操作感觉不到。
3. **c3 选了横向滚动**，没有把方向、画面模式收进“更多”。
4. **c4 切换直播间时清空**标签和聊天位置（新直播间的聊天是另一份），只保留三档面板档位。
5. **B-19 选了随控制层隐藏**；把手在播放器右缘中间。宽屏横屏直播的 16:9 画面框比画面区窄时（很宽很矮的窗口），把手在画面框的右缘，不在聊天栏分隔线上。
6. **全屏里还剩一个居中对话框**：弹幕设置面板“小窗弹幕”一节的“弹幕颜色”选择（`showDanmakuColorDialog`，`shared/danmaku/`）。可以改成在行下面展开色板，要不要做。
7. **c8 多做的**：录制面板的“查看原因”改成在面板里展开（任务单只列了画中画和屏蔽关键词）。
8. **c9 的标签**：按 A02.1 c12，窄栏时整个标签缩小，不再把数字放到字的右上角（`chat_panel.dart` 原来自己的 `_TabLabel` 删掉了）。头像是键盘的焦点停靠点，名字区域仍可点但不再单独占一个焦点。

## 可能和别的任务冲突的文件

- `apps/pure_live/lib/features/live_play/player/player_view.dart`、`player/player_controls.dart`、`live_play_page.dart`、`layout/portrait_panel.dart`：直播间组后续任务。
- `apps/pure_live/lib/features/live_play/danmaku/chat_list.dart`、`chat_panel.dart`、`message_panel.dart`。
- `apps/pure_live/lib/features/live_play/record/record_panel.dart`、`features/recorder/recorder_task_card.dart`（A02.1、A08.5 改过同文件，这次合并没有冲突）。
- `apps/pure_live/lib/features/live_play/mini/room_mini_window.dart`（R01.1 在 `mini/` 目录；`floating_window.dart` 没碰）。
- `apps/pure_live/lib/shared/danmaku/emotes.dart`（弹幕相关任务）。
- `apps/pure_live/assets/translations/zh.json`、`en.json`（按键名排序插入；删了两个键）。
- 测试：`live_play_layouts_test.dart`、`live_play_page_test.dart`、`live_play_room_test.dart`、`live_play_popups_test.dart`、`room_popups_test.dart`、`live_play_mini_window_test.dart`、`chat_list_follow_test.dart`、`recorder_centre_test.dart`。

## K90 复查（2026-10-08，master ce7640a5b）

- 第 1 条：哔哩哔哩直播间，控制层隐藏后双击画面进横屏全屏，全屏里再双击退出、回到竖屏 ✓。单击的响应速度、底栏位置双击没单独看。
- 第 12 条：录制面板的状态卡、“停止录制”都在面板里，没有居中对话框 ✓（A10.3 复查）。
- 第 13 条：录制中心已保存的卡片有“播放”，滑动不卡 ✓（S02.6 阶段 5）。
- 其他条没看。

## K90 复查（2026-10-08 晚，提交 `9e84b6f7b`）

- 第 2 条：见 A07.14（点飞行弹幕打开面板，双击直接进全屏）✓。
- 第 3 条：全屏锁定后只剩锁按钮，4 秒后隐藏，单击只把锁按钮叫出来，双击不退出全屏 ✓；暂停后单击只显示 / 隐藏控制层 ✓（A07.14 复查时看到，D-038 的规则）。
- 第 6 条：切到“醒目留言”，进全屏再退出，仍在“醒目留言” ✓。
- 第 7 条：开播时长写“11 小时 24 分”，全屏顶栏电量数字清楚 ✓。
- 第 11 条：横屏全屏长按飞行弹幕 →“屏蔽关键词…”：右侧面板换成第二页（左上 ←），输入框预填弹幕并选中、键盘弹出 ✓（没有真的加词，点 ✕ 关掉）。
- 还剩：第 4 条（分屏或最大显示大小下竖屏全屏两行按钮）、5（刘海和录制角标）、8（TalkBack）、9（平板）、10（关掉画中画权限后的提示条）、14（角标和芯片的样子，部分已在截图里看到）。
