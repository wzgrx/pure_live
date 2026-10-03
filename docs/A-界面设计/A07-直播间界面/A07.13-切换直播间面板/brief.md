# A07.13 切换直播间面板：任务书

> 设计按建议定稿、代码已在 2026-10-02 合并（`531fcd0ba`），登记表状态“待真机”。这份任务书保留原来交给执行者的全部要求（旧编号 B05 的任务单，下面“方案和阶段”的阶段 1、2），并写清剩下的事：阶段 3 真机验证。

## 背景

- 来源：用户 2026-10-02 的问题 06（“竖屏点击右上角 切换直播间，弹出的切换直播间的ui不太行，需要重新设计优化”）、问题 08（“横屏……切换直播间……和……最右边的功能图标……功能重合……还要考虑和竖屏的联系”）；GitHub issue #37（“感觉旧版那种小的好看看的还多，新版就变了，加个新旧切换开关吧”，V02.4）；审查报告 A-06、A-08（`docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md`）。
- 现象（修之前，4.0.0）：切换直播间是 70% 高的底部表单加普通列表行，没有封面和人数、看不到当前房间、刷新失败不提示；横屏全屏也是这个底部表单，只露两三行、压在画面中间；点一个直播间整页替换：退出全屏、用不上保留的播放器、来源列表丢了；横屏顶栏有 ⇄、菜单里又有“切换直播间”，投屏、画面比例也各两份。
- 为什么做：第一档（用户的问题和 issue）；D-022：默认 3.x 的小卡片网格，可以切换成列表并记住。
- 原任务单的约定：规模大；依赖 A07.10 之后（同一批文件）；直播间组和 A07.10、A07.12、A07.11 依次做；出设计：要（先出对比页和效果图，再实现；用户已授权“所有决定你选择”，“需要你选的”按建议 A 直接做）。
- 已经做过的：A07.3 的原地换台 `_switchRoom` 和来源列表 `LiveRoomArgs.playlist`；A07.6 的面板位置规则；C03.1 的切换直播间刷新按钮（F-RT-07）。

## 目标和验收

1. c1 先出设计（产出放本文件夹，同 A10.3 的做法）：做成直播间面板 `RoomPanelKind.switchRoom`（`RoomSidePanel`，和录制、弹幕设置面板同一套）。位置：竖屏普通布局从画面下沿升起盖住聊天区；竖屏流三档面板里；竖屏全屏底部 60%；横屏全屏和平板右侧 360dp 全高。头部：标题“切换直播间”、刷新（显示上次刷新时间，失败要提示）、关闭；分段：关注在播（数量）/ 来源列表（从热门、分区、搜索进来时才有）/ 观看记录 / 关注回放；按主播名过滤的搜索框。**两种样式，头部有切换按钮（网格 / 列表），选择记住（新设置 `roomSwitcherLayout`，默认网格）**：网格照 v3 `lib/modules/live_play/dialogs/play_other.dart` 的小卡片（`_RoomSwitchCard`、`resolveRoomHistoryColumns`：内边距 6、间距 5、按宽度算列数，封面 + 一行主播名，左上“直播中”和人数），一屏能看到的数量不少于 v3（issue #37）；列表每行：16:9 封面 112×63、主播名、标题一行、“平台 · 分区”。未开播压暗写“未开播 · 上次看 X 前”；最上面固定一行“正在观看”（当前房间，不可点）；空状态和出错状态。
2. c2 实现：点一行调页面已有的 `_switchRoom(room)`（`features/live_play/live_play_page.dart`，和上下滑换台同一条路：同一个播放器、保持全屏和方向、播放列表换成所选分组）；长按弹出卡片菜单（和房间卡片同一个对话框）；去掉旧的 `dialogs/room_switcher.dart` 底部表单。
3. c3 去重（A-08）：保留横屏顶栏和竖屏全屏的 ⇄；`roomMenuGroups` 加参数，画面上的菜单（`onVideo`）不再列出栏上已有的项（切换直播间、投屏、画面比例）；竖屏普通布局的菜单不变。三个入口（竖屏菜单、全屏 ⇄、未开播或失败状态的按钮）都打开这个面板。
4. 三种布局里是同一个面板、同样的分组和样式；网格一屏的卡片数不少于 v3；网格和列表能切换并记住；换台不退出全屏、不重新进页面、复用播放器；菜单里没有和栏上重复的项。
5. 测试：三种布局的面板位置和尺寸；网格列数和 v3 一致（同宽度下）；样式切换并记住；分组切换；点一行原地换台（同一个播放器、全屏保持）；去重后的菜单项列表。
6. （阶段 3）在 K90 上照 `verify.md` 逐条通过，登记表改“完成”。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/features/live_play/` 省略前缀：

- 面板：`switch_room/room_switch_panel.dart:75`（`RoomSwitchPanel`）、`:39`（`showRoomSwitchPanel`）、`:22`（`FollowsRefresher`）、`:409`（刷新按钮）、`:478`（分组条）、`:529`（正在观看）、`:576`（空和出错）；卡片 `switch_room/room_switch_tiles.dart:265`（`RoomSwitchCard`）、`:347`（`RoomSwitchRow`）、`:13`（`agoText`）。
- 规则：`logic/room_switch.dart:10`（分组）、`:25`（样式）、`:60`（列数）、`:70`（卡高）、`:134`（分组列表）、`:172`（筛选）。
- 换台：`live_play_page.dart:342`（`_pickRoom`）、`:360`（`_switchRoom`）。
- 去重：`buttons/room_menu_button.dart:188`（`menuEntriesOnBars`）；三个入口 `buttons/room_menu_button.dart:241`、`player/player_controls.dart:398`、`player/player_status.dart:198`。
- 设置：`packages/live_store/lib/src/settings/settings.dart:394`（`roomSwitcherLayout`）；刷新接线 `apps/pure_live/lib/app/app.dart:86`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/dialogs/play_other.dart`：靠右的圆角 16 对话框（竖屏菜单 `widgets/button/live_play_menu_button.dart:88-94`、全屏 ⇄ `widgets/video_player/video_controller_panel.dart:394-410` 都打开它）；三组：已开播、录播、观看记录；`_RoomSwitchCard` 小卡片；点了 `controller.switchRoom(room)` 在同一页换台（`controllers/live_play_controller.dart:884-930`）。
- `git show v3.2.11:lib/modules/live_play/widgets/content_first_panel_layout.dart:24-50`（对话框大小：可用宽度一半、至少 280、高最多 720）、`:265`（`resolveRoomHistoryCardHeight`）、`:294-310`（最多 2 列）。
- 要保留的：小卡片的样子和一屏数量（issue #37）、原地换台、三组内容、按人数排。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节、第 5、8、10、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节第 7、8 条、第 7 节。
3. 本文件夹的 `README.md`（设计和实现）、`record.md`、`verify.md`；`docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md`（面板位置规则）；`docs/A-界面设计/A07-直播间界面/A07.3-竖屏全屏上下滑换台/README.md`（原地换台）。

## 范围

- 可以改（阶段 1、2 当时的范围）：`apps/pure_live/lib/features/live_play/`、`apps/pure_live/lib/shared/rooms/`（只在需要时）、`packages/live_ui`（只添加）、本文件夹；实现时另外必须改了 `packages/live_store`（新设置）、`apps/pure_live/lib/app/app.dart`（刷新接线）、翻译、`tools/gate/ui_baseline.json`。
- 阶段 3 只改本文件夹（`verify.md`、`verify/`）和登记表。
- 不能改：其他组的界面和逻辑（关注页、热门页怎么带列表是 A07.3 做的）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已完成） | c1 出设计：README、`src/gen.py` 和 16 个 HTML、18 张效果图、3 张编号图、`page.json`、14 张章节导出图；X1～X5 按 A 定稿 | 本文件夹 | 设计定稿（按 D-003） |
| 2（已完成，`531fcd0ba`） | c2 面板和原地换台；c3 去重 | 见“现状” | 验收 4、5；门禁通过 |
| 3（待做） | 真机验证 | `verify.md`、`verify/`、`docs/tasks.toml` | `verify.md` 每条通过 |

## 测试

- 已有（阶段 2）：`apps/pure_live/test/features/live_play/room_switch_test.dart`（17 个，一屏卡片数按 v3 代码的公式算，和 `src/gen.py --counts` 同一套）；改了 `room_extras_test.dart`、`live_play_layouts_test.dart`、`packages/live_store/test/stores_test.dart`。
- 真机发现问题要修时：先写改之前会失败的测试；定时器至少 1 秒（“X 分钟前”每分钟一次）；不访问真实平台（关注、观看记录用假的存储）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 竖屏点右上角菜单 → 切换直播间 | 从画面下沿升起，有封面和人数，最上面“正在观看” |
| 2. 切成列表，关掉再打开 | 记住列表 |
| 3. 横屏全屏点 ⇄，点一个直播间 | 右侧面板；画面原地换台，还在全屏 |
| 4. 横屏右上角菜单 | 没有“切换直播间”“投屏”“画面比例” |
| 5. 刷新（正常、断网各一次） | “刚刚”；失败变红并有提示条 |

完整的表（13 条）和结果栏在 `verify.md`。

## 风险和注意

- 来源列表和上下滑换台依赖进直播间时带的列表（A07.3）：从链接、观看记录进来的没有来源列表，是正常的。
- 刷新会请求所有关注的平台：断网测试后记得恢复网络再继续。
- 同一批文件：`live_play_page.dart`（`_panelOf`、`dispose`、`initState`）、`player/player_controls.dart`（`_roomActions` 的 `landscape` 参数）、`buttons/room_menu_button.dart`、`packages/live_ui/lib/src/icons/app_icons.dart`。
- 只点测试包；不碰 3.x（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 效果图（要改设计时）：`python3 docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板/src/gen.py`（`--counts` 打印卡片数表）、`python3 tools/ui/mock/render.py docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板/src --annotate`；评审页 `python3 tools/ui/mock/page.py docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板/page.json`。
- 真机用的构建：master 上包含 `531fcd0ba` 的提交；在 `verify.md` 写清提交号。
- 要改代码时：分支 `ai/A07.13` 或本机工作区；提交信息以 `[A07.13]` 开头（英文）；不推 master；提交前 format、analyze、全部测试、`python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`；真机做到一半时把已看的写进 `verify.md`。

## 报告（中文，简洁）

`verify.md` 每条的结果和截图；不通过的现象和根因线索（文件:行）；登记表改了什么；要不要回复 issue #37（已由维护者关闭，见 V02.4）。
