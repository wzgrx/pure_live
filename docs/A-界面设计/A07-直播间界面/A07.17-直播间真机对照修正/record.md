# A07.17 直播间真机对照修正：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5，本机工作区，没有真机）
- 分支和提交：本机工作区，代码 `dc87bcac4`，文档和对照图在其后的 `[A07.17]` 提交
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)；决定：D-003（c2 由维护者选 A，用户 2026-10-08 交给维护者选，没有出评审页）

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 信息行一行、高度固定 | 做了 | 按宽度依次：全部 → 去掉“看过”（三个数以上时）→ 时长短格式“6:45” → 整行缩到 `bodySmall` → 再从后往前去掉数字（只留第一个和时长）。最后一步是 README 没写的：300 宽的右栏里放上画质、线路后，前四步都放不下，不加就只能截成“1.0…”。第二行固定 48 高（画质、线路按钮的触摸高度），加载中、可播、受限的房间都一样，数字和按钮垂直居中 |
| c2 手机横屏（建议 A） | 做了 | 顶栏保留（返回、关注、录制、菜单都在那里）；画面占满顶栏下的高度，右边 280 只有弹幕列表（哔哩哔哩访客时上面仍有“去登录”提示条，B06 c1）。信息行收进画面上栏：标题加“⌄”，下面一行小字是人数、热度、看过、时长（同一个 `AudienceStrip`，同样按宽度取舍），点标题开/关详情（盖在弹幕列表上）。画质、线路挪到画面下栏右边。只在手机上这样排，桌面矮窗口仍是 A07.5 的分栏；宽度 ≥ 840 且高度 ≥ 480 的分栏没动。3.x 的样子没有在模拟器截（本任务不用 adb），对照用的是 V03.4 的真机截图 |
| c3 竖屏流 5 行、输入框收成按钮、没有黑边 | 做了 | 默认“均衡”本来就是中间档（44%），没改档位；输入框在竖屏流面板里收成弹幕列表右下角的星形按钮，点开后输入行贴在屏幕底部（有键盘时贴键盘），发出或点别处收起；“新消息”按钮相应左移，不和星形按钮重叠。最低档不再为输入框多留 72（`portraitPanelComposer` 删了）。普通竖屏（16:9 上下排）的输入框仍在列表下面，没收 |
| c4 窄输入框短提示 | 做了 | 按输入框宽度量：放得下长提示“发送本地弹幕，只有你看得到”就用长的，否则用短的“发送一条本地字幕”（3.x 的原文，新键 `local_message_hint_short`）。竖屏全屏、窄横屏的输入行都是这条规则 |
| c5 竖屏流控制层底部暗角 | 做了 | 见“根因”：原来就有暗角，只是太短；竖屏流面板上的下栏暗角往上多伸 28（共 108），颜色还是 `OnVideoColors.shade` |
| c6 详情 | 做了 | “已开播”放不下格子时用短格式（“6:45”，超过一天“1 天 2 时”，新键 `duration_days_short`）；链接显示时去掉 `https://`/`http://`，复制仍是完整地址；没关注时详情的关注按钮实心主色（和顶栏同一个样子，图标仍是 3.x 的心），已关注时浅色。另外修了 280 宽右栏里详情“平台 · 分区 ›”一行溢出 2 像素（分区和箭头改成一段文字，一起截断） |

## 根因

- 信息行折行：`AudienceStrip`（改前 `room_info_bar.dart:193-240`）是 `Wrap`，放不下就折到第二行，信息行变高，和右边的按钮对不齐。
- 手机横屏太挤：`roomPageLayout`（改前 `room_layout.dart:66-70`）高度 < 480 时返回 `landscape`，页面把它当宽屏分栏（改前 `live_play_page.dart:1105-1106`），300 宽的右栏里放信息行（折三行）、四个标签、“去登录”提示条和输入框，弹幕列表只剩一行。
- 竖屏流画面上方黑边：面板布局里画面铺满整个区域（顶栏下到屏幕底），`LiveVideoView` 按 `BoxFit.contain` 居中。竖屏画面按宽度放大后比区域矮，多出的高度上下各一半：上面露出一条黑边（K90 约 26–34 dp，和截图一致），下面那一半藏在面板后面，画面反而被面板多挡住一截。改成贴顶对齐（`LiveVideoView.alignment`，media_kit 的 `Video` 本来就有这个参数）。
- 竖屏流弹幕只露两行：面板中间档 44%，里面有拖动行 48、信息行 94、标签 48，再加列表下的输入框 72，K90 上列表只剩约 100。输入框收成按钮后列表约 170，5 行。
- 竖屏控制层暗角：下栏一直有暗角（`player_controls.dart` 的 `_bar` → `_ShadedBar`，60% 黑渐隐，伸出栏外 28，共 80 高），横屏全屏也是同一个。竖屏流里下栏在画面中段（面板上沿），不在画面边上，80 高的渐变在亮画面上看不出来；改成伸出 56。
- 详情“12 小...”：四格平分宽度，“已开播”用的是长格式“12 小时 13 分”，22 号字放不下。

## 改了哪些文件

- `apps/pure_live/lib/features/live_play/layout/room_info_bar.dart`：`fitAudience`、`AudienceStrip`（一行、可放在画面上）、`roomFiguresRowHeight`、`OnAirClock.fitWidth`。
- `apps/pure_live/lib/features/live_play/logic/room_layout.dart`：`roomPageLayout(mobile:)`、`phoneLandscapeChatWidth`；删 `portraitPanelComposer`。
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：`_phoneLandscape`；竖屏流面板贴顶、输入框收起。
- `apps/pure_live/lib/features/live_play/player/player_view.dart`、`player_controls.dart`：`onTitle`（标题即信息行）、`pickersInBar`、`overPanel`（暗角）、画面对齐。
- `apps/pure_live/lib/features/live_play/local_interaction/local_composer.dart`：`localComposerHint`、`LocalComposerChatStar`、`LocalComposerBelow.collapsed`。
- `apps/pure_live/lib/features/live_play/danmaku/chat_panel.dart`、`chat_list.dart`：收起参数、“新消息”按钮让位。
- `apps/pure_live/lib/features/live_play/layout/room_details.dart`、`buttons/follow_button.dart`：详情三处。
- `apps/pure_live/lib/shared/rooms/room_texts.dart`：`shortElapsedText`。
- `packages/live_player/lib/src/video_view.dart`：`LiveVideoView.alignment`。没动 `packages/live_ui`。
- 文档：本文件、README、对照图 `v4-*.jpg`、A07.5 README（手机横屏一条改了）、`docs/specs/UI.md` 5.3 节、登记表。

## 新设置、翻译键、门禁基线

- 新翻译键（zh、en）：`duration_days_short`、`local_message_hint_short`。没删键，没改设置键（D-018）；`localInteractionEnabled` 不再影响面板最低档的高度。

## 测试

- 新增 `apps/pure_live/test/features/live_play/room_on_phone_test.dart`，10 个，先写、看到失败再改：
  - c1：393×852 和 882×800（300 宽右栏）信息行一行、第二行 48 高、和画质按钮居中对齐，393 宽时去掉“看过”；`fitAudience` 各步；`shortElapsedText`。
  - c2：869×400 手机横放：顶栏还在、画面高 344、右栏 280、没有信息行、标签和输入框、访客提示条在时仍至少 5 行弹幕、标题下有人数、下栏有画质线路、点标题开详情（在右栏）、返回先关详情；Windows 869×400 仍是分栏。
  - c3、c5：竖屏流中间档至少 5 行弹幕、星形按钮在列表右下角、点开输入行能发出并收起、画面贴顶、下栏暗角贴着面板且 ≥ 100 高；“沉浸”最低档 250；普通竖屏仍是输入条和长提示。
  - c4：竖屏全屏输入框是短提示。
  - c6：393 宽详情“6:45”、链接不带 `https://`、复制是完整地址、没关注实心主色、关注后浅色；时钟放得下时用长格式。
- 改了 3 个旧测试（行为按设计变了）：`live_play_layouts_test.dart` 的“沉浸最低档”（不再加 72）和“740×360 手机横放”（新排法）、布局函数加桌面矮窗口；`live_play_tabs_test.dart` 的“手机横放”（右栏只有列表）。
- 整个 `apps/pure_live` 的 `flutter test`：886 个全部通过（另有 4 个临时的截图测试，只用来出对照图，没提交）。`dart analyze --fatal-infos`、`check_ui_structure.py`、`docs.py --check` 通过。
- 测试里竖屏流的 5 行是登录状态（没有哔哩哔哩访客提示条，和抖音房间一样）；访客时提示条占约 1.5 行，393×852 的中间档是 3–4 行。

## 真机上要看的

照[任务书](brief.md)“真机验证”，K90（先确认手机没被别的会话占用）：

1. 哔哩哔哩热门第一个房间（在线、热度、看过三个数）：信息行一行，数字和画质、线路按钮垂直居中；放不下时先少了“看过”，再是时长变“6:45”。点“详情”：四格不截断，链接不带 `https://`，复制出来是完整地址；没关注时详情和顶栏的关注按钮都是实心。
2. 手机横放（自动旋转开，不进全屏）：画面在左占满顶栏下的高度，右边只有弹幕列表（访客时上面有“去登录”条），至少 5 行；画面上栏标题下有人数和时长，点标题开详情、再点或返回关；画质、线路在画面下栏右边能切换；横屏全屏进出正常（和 O05.3 一起看）。
3. 抖音竖屏直播：画面贴着顶栏、上方没有黑边；面板中间档至少 5 行弹幕；输入框是列表右下角的星形按钮，点开后输入行在键盘上方，发出后收起；面板上沿的下栏有明显的底部暗角。
4. 竖屏全屏：输入框提示是“发送一条本地字幕”，不再截断。
5. 平板或电脑宽屏（≥ 840）的分栏和以前一样（K90 看不了，下次在 Windows 上顺带看）。

## 停在哪（没做完时写）

- 做完的阶段：1、2（没有评审页，c2 按 D-003 选 A）。
- 下一步：K90 上按上面 1～5 看；看完改登记表状态。
