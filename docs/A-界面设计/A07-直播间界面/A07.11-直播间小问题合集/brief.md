# A07.11 直播间小问题合集：任务书

> 代码已在 2026-10-02 合并（`df67f1147`），登记表状态“待真机”。这份任务书保留原来交给执行者的全部要求（旧编号 B09 的任务单和两次补充，下面“方案和阶段”的阶段 1），并写清剩下的事：阶段 2 真机验证和维护者要定的几处。

## 背景

- 来源：审查报告 B-8、B-10、B-11、B-12、B-15、B-16、B-17、B-18、B-19（`docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md`）；D04.1 之后补充 c6、c7；A07.12 之后补充 c8、c9（维护者已定）。
- 现象（修之前）：单击画面控制层慢半拍才出现；横屏开着录制时左上角的“● 录制中”被刘海挡住；分屏或系统“显示大小”调大时竖屏全屏底栏出现黄黑条；进出全屏后聊天回到第一个标签、滚动到最新、三档面板回到初始档；开播时长写“2:18”像录制的分秒；把手读屏“250 px”；电量数字 9 号看不清；宽屏聊天栏收起把手一直压在画面右缘、挡住音量手势；录制中心任务卡构建时同步读文件；表情解析两次；全屏里还会弹居中对话框（画中画被关掉、屏蔽关键词）。
- 为什么做：第一档（审查报告里用户每天碰到的问题）。
- 原任务单的约定：规模中；出设计：不用（照已确认的设计和本任务单）；依赖 A07.12 之后；直播间组依次做（A07.10 → A07.13 → A07.12 → A07.11）。
- 已经做过的：B-15（取消关注写“取消关注”、取消后提示条带“撤销”）由 A07.12 做完。

## 目标和验收

1. c1 B-8 单击不再等双击超时：单击立即显示或隐藏控制层（点弹幕立即响应），第二下到来时撤销并切全屏。
2. c2 B-10 控制层隐藏时的录制小角标，横屏时左边距加上 `padding.left`。
3. c3 B-11 竖屏全屏上下栏第二行宽度不够时横向滚动（或把方向、画面模式收进“更多”）；分屏、系统“显示大小”调大时不溢出；360 宽、“显示大小”最大时竖屏全屏不溢出。
4. c4 B-12 退出全屏后聊天区标签、滚动位置、竖屏三档面板档位保持（存到页面 State 或 `PageStorage`）。
5. c5 B-15 取消关注确认按钮写“取消关注”，取消成功给提示；B-16 开播时长写“2 小时 18 分”；B-17 三档面板把手读屏改成“最低 / 中间 / 最高”；B-18 电量数字至少 11 号；B-19 聊天栏收起把手放到画面和聊天栏的分隔线上，或跟控制层一起隐藏。
6. c6 录制中心 `features/recorder/recorder_task_card.dart` 在构建时同步调 `existsSync`，照 D04.1 c3 的做法改成异步检查并缓存。
7. c7 表情在聊天列表（已缓存在 `ChatLine.segments`）和飞行弹幕层各解析一次：`shared/danmaku/emotes.dart` 让两处共用一次解析结果，`EmoteTable` 预编译正则。
8. c8 全屏里不再有居中对话框：“无法打开画中画”改成带“去设置”的提示条；屏蔽关键词输入做成长按弹幕面板（`danmaku/message_panel.dart`）的第二页（左上 ← 返回）。
9. c9 A02.1 留给直播间的：`chat_panel` 的标签改用 live_ui 的 `TabLabel`；录制清晰度芯片圆角 8；直播间顶栏头像可点时的悬停、按下、焦点框（`CommonAvatar`）。
10. 每条 c 至少一个测试；门禁通过。
11. （阶段 2）在 K90 上照 `verify.md` 逐条通过，登记表改“完成”。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/` 省略前缀：

- c1：`features/live_play/player/player_view.dart:333-366`（`_onTap`）、`:197-208`（双击窗口、`_controlsSettling`）。
- c2：`player_view.dart:717-724`。
- c3：`features/live_play/player/player_controls.dart:803` 的 `_InlineRow`（上栏 `:319`、下栏 `:748`）。
- c4：`features/live_play/layout/room_view_memory.dart:10`（`RoomViewMemory`）、`:28`（`ChatListMemory`）；`features/live_play/live_play_page.dart:191`（页面持有）、`:373`（换房间时只留档位）。
- c5：`shared/rooms/room_texts.dart:66`（`elapsedText`），`features/live_play/layout/room_info_bar.dart:323`；`features/live_play/layout/portrait_panel.dart:9`、`:255`（读屏）；`features/live_play/player/bar_parts.dart:120`（电量框）；`player_view.dart:770`（`edge`）、`live_play_page.dart:1327`（`_ColumnHandle`）。
- c6：`shared/record/saved_file.dart:12`（`SavedFileCheck`），`features/recorder/recorder_task_card.dart:139`。
- c7：`shared/danmaku/emotes.dart:112`、`:122`。
- c8：`features/live_play/mini/room_mini_window.dart:316`（`showPipDisabledToast`）；`features/live_play/danmaku/message_panel.dart:81-95`（第二页）；`features/live_play/record/record_panel.dart:84`（`_FailureReason`）。
- c9：`features/live_play/danmaku/chat_panel.dart:106-109`（`TabLabel`）；`record/record_panel.dart:468`（`AppChip`）；`layout/room_header.dart:163`（`CommonAvatar`）。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller_panel.dart:196-249`：画面同时挂 `onTap` 和 `onDoubleTap`，3.x 单击也慢半拍；双击全屏（附录 A 第 3 条）要保留。
- `:1508-1558`：3.x 竖屏全屏下栏是 `Row`，窄屏去掉刷新和关注（4.x 改成横向滚动、一个不少）。
- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_tab.dart:22-25`：3.x 的标签控制器在 `LivePlayController` 里，进出全屏标签保留；`danmaku_list_view.dart:62` 滚动控制器在列表自己的 State，`widgets/layout/live_play_content.dart:146` 面板高度在 State 里，全屏时弹幕区不构建（`:590-595`），回来后位置和档位丢了。4.x 三样都保留。
- 要保留的：单击显示或隐藏、暂停时单击不继续播放（D-012）、锁定时单击只显示或隐藏解锁按钮、双击全屏。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、10、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.4 节、第 7 节（全屏里不用居中对话框的规则来自 A07.12）、附录 A 第 1、3 条。
3. 本文件夹的 `README.md`、`record.md`、`verify.md`；`docs/A-界面设计/A02-组件/A02.1-通用组件/README.md`（`TabLabel`、`AppChip`、`CommonAvatar`）；`docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/README.md`。

## 范围

- 可以改（阶段 1 当时的范围）：`apps/pure_live/lib/features/live_play/`、`features/favorite/`（只在关注按钮需要时）；补充条目要求的 `features/recorder/recorder_task_card.dart`、`shared/record/`、`shared/danmaku/emotes.dart`；对应测试；翻译文件。
- 阶段 2 只改本文件夹（`verify.md`、`verify/`）和登记表。
- 不能改：其他组的界面和逻辑；`packages/live_ui`（这次不需要）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已完成，`df67f1147`） | c1～c9 | 见“现状” | 每条有测试（c1、c2、c3、c6 的新测试改之前会失败）；全部 `flutter test` 通过；门禁通过 |
| 2（待做） | 真机验证 | `verify.md`、`verify/`、`docs/tasks.toml` | `verify.md` 每条通过；维护者对“留下的问题”表态 |

## 测试

- 已有（阶段 1）：见 `README.md`“验证”：`live_play_layouts_test.dart`（+7）、`live_play_page_test.dart`（+1）、`chat_list_follow_test.dart`（+1）、`test/features/recorder/recorder_centre_test.dart`（+1）、`test/shared/emotes_test.dart`（+1）和改了的已有测试。
- 真机发现问题要修时：先写改之前会失败的测试；定时器至少 1 秒（`kDoubleTapTimeout` 这类用 `tester.pump` 推时间）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 等控制层自动隐藏后单击画面；再单击；双击；全屏里双击；在底栏按钮位置双击 | 控制层立即出现、立即隐藏；双击进全屏、全屏里双击退出；底栏位置双击只切全屏，不会暂停或刷新 |
| 2. 打开“点击弹幕”，点一条飞行弹幕；在同一处快速双击 | 面板立即打开；双击时面板一闪关上、进全屏（A07.14 要改的现象） |
| 3. 开分屏或把“显示大小”调到最大，进竖屏直播的竖屏全屏 | 上下两行没有黄黑条；第二行放不下时能左右拖，“退出全屏”一直在最右 |
| 4. 横屏全屏（刘海在左边）开着录制，等控制层隐藏 | 左上角“● 录制中”不被刘海挡住 |
| 5. 切到“醒目留言”或在“弹幕列表”往上翻，进全屏再退出；竖屏直播把面板拖到最高档，进竖屏全屏再退出 | 仍在原标签、原位置，底部按钮显示全屏期间的新弹幕数；仍是最高档 |
| 6. 看信息条和详情的开播时长；全屏顶栏电量；TalkBack 聚焦把手 | “2 小时 18 分”；电量数字清楚；读“弹幕面板高度，中间”，上下调整读“最高”“最低” |
| 7. 系统设置关掉本应用画中画后点小窗按钮；横屏全屏长按弹幕 →“屏蔽关键词…” | 底部提示条带“去设置”和 ✕、不自动消失；右侧面板换成第二页（←、预填、键盘），屏蔽后提示“关键词已加入弹幕屏蔽列表” |

完整的表（14 条）和结果栏在 `verify.md`。

## 风险和注意

- c1 的“撤销第一下”依赖时间窗口：真机上手指抖动或点得慢时可能被当成两次单击，属于正常；如果误判多，记下现象再决定是否调整 `kDoubleTapSlop`。
- 同一批文件 A07.14、A07.15 会接着改（`player/player_view.dart`、`player/player_gestures.dart`）；真机发现问题要改代码时和它们协调，不要同时开。
- 只点测试包 `com.mystyle.purelive.v4dev`；TalkBack 用完关掉。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 真机用的构建：master 上包含 `df67f1147` 的提交；在 `verify.md` 写清提交号。
- 要改代码时：分支 `ai/A07.11` 或本机工作区；提交信息以 `[A07.11]` 开头（英文）；不推 master；提交前 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、全部 `flutter test`、`python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`；真机做到一半时把已看的写进 `verify.md`。

## 报告（中文，简洁）

`verify.md` 每条的结果和截图；不通过的现象和根因线索（文件:行）；维护者对八处选择的决定；登记表改了什么。
