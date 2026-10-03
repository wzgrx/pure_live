# A07.12 直播间子弹窗：设计（第 1 版，按建议定稿，已开发，待真机）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：直播间右上角菜单（四宫格）里的定时关闭、房间音量、投屏、获取直链、画面比例；画面上的方向按钮（本直播间画面方向）；取消关注的确认；长按弹幕和屏蔽关键词；全屏时提示条的位置。也就是 A07.6 当时说“下一批出图”的那几个（切换直播间已在 [A07.13](../A07.13-切换直播间面板/README.md)，本地互动在 A08.2）
- 来源：审查报告 B-3、B-7、B-13、B-14、B-15（[docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)）；云端任务 [A07.12](brief.md)；A02.2 记录末尾“直播间里还没换的弹窗”表
- 规则照 [A07.6](../A07.6-直播间弹窗/README.md) 已确认的统一规则（直播间里的“设置”和“选择”用面板或贴着按钮的小菜单）和 [A02.2](../../A02-组件/A02.2-弹窗组件/README.md) 的组件（小菜单、对话框、面板、提示条）
- 评审页：本机 `~/ref/design/compare/U.2n.html`（`python3 tools/ui/mock/page.py docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/page.json`）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（直播间的画面和栏借用 A07.13 的生成器）
- 旧编号：U.2n、B07、T05g.2；相关决定 D-003（N1～N5 按建议 A）、D-021（直播间里取消关注用贴着按钮的小菜单）
- 图片：“现在”是 4.0.0（弹法就是 v3 的：居中对话框、长按弹幕底部表单）；文字取自 `zh.json`；画面和头像是示意图片
- 生成：`python3 docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/src/gen.py && python3 tools/ui/mock/render.py docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/src --annotate`

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A07.12-a | 定时关闭（`RoomPanelKind.sleepTimer`） | 右上角菜单“定时关闭” | 竖屏画面下方、竖屏全屏底部、横屏和平板右侧 | 关着；开着（还剩 X 分钟）；自定义出错 |
| A07.12-b | 房间音量（`RoomPanelKind.volume`） | 右上角菜单“房间音量” | 同上 | 有声、静音；手机（系统音量）/ 电脑（这个直播间的音量） |
| A07.12-c | 获取直链（`RoomPanelKind.streamLink`） | 右上角菜单“获取直链”（播放中） | 同上 | 清晰度页、读取中、线路页、出错（需要应用内会话、读取失败）、回放地址 |
| A07.12-d | 投屏（`RoomPanelKind.cast`） | 右上角菜单“投屏”、全屏顶栏的投屏按钮（Android） | 同上 | 清晰度页、线路页、设备页（搜索中、没找到、失败、搜索中断、正在投、已投）|
| A07.12-e | 画面比例 | 右上角菜单“画面比例”、横屏下栏的画面比例按钮 | 小菜单（贴着按钮） | 当前项 |
| A07.12-f | 本直播间画面方向 | 画面下栏的方向按钮（手机） | 小菜单（贴着按钮） | 当前项、记住开关 |
| A07.12-g | 取消关注 | “已关注”按钮（顶栏、详情、全屏下栏） | 小菜单 + 提示条（撤销） | — |
| A07.12-h | 长按弹幕（`RoomPanelKind.message`） | 弹幕列表长按、画面弹幕点按或长按 | 面板 | 普通、本地弹幕（没有屏蔽用户）、打码的名字（没有屏蔽用户） |
| A07.12-i | 屏蔽弹幕关键词 | 长按弹幕“屏蔽关键词…” | 输入对话框（A02.2） | 空、输入中、键盘弹出 |
| A07.12-j | 右上角菜单 | 四宫格按钮 | 小菜单 | 说明行（定时剩余、当前比例）、不可用项（投屏、获取直链在没播时） |
| A07.12-k | 全屏的提示条 | 各种操作结果 | 横屏全屏、竖屏全屏 | 一句、带操作 |
| — | 无法打开画中画 | 小窗按钮（系统关了画中画） | 消息对话框（A02.2 已有这张图） | — |

## 3.x 的样子和问题

4.0.0 的这些弹窗是从 3.x 搬过来的，弹法一样：

- 定时关闭（`room_dialogs.dart:10`，3.x `RoomTimerDialog`）：`AlertDialog`，宽 440；“启用当前直播间定时停止”开关、8 个时长 `ChoiceChip`、“停止前播放时长”输入框；“取消”“确认”。
- 房间音量（`room_dialogs.dart:136`）：`AlertDialog`，宽 380；静音按钮、滑块（20 档）、百分比；“取消”“确认”。拖动时改 mpv 音量，“确认”时存进 `roomVolumes`。3.2.11 的“房间音量”对话框改的是全局默认（全局静音、手机默认音量、电脑默认音量），手机上实际生效的是系统音量（`video_controller.dart:823` `_usesSystemVolume`）。
- 获取直链、投屏（`stream_dialogs.dart:26`，3.x `KnownRoomLinkDialog`）：`AlertDialog`，宽 420；清晰度列表（当前项 `Icons.check_rounded`）→ 点一档后**替换成**线路列表（回不去）；只有一条线路时直接用。投屏再弹一个“DLNA投屏”对话框（`CastDialog`，3.x `LiveDlnaPage`）。
- 画面比例（`player_dialogs.dart:43`）：`_ChoiceDialog`，`ListTile` + 勾，文字不变色；横屏下栏的同一设置是小菜单（`bar_parts.dart:218`）。
- 本直播间画面方向（`player_dialogs.dart:77`，3.x `PortraitOrientationPickerDialog`，A07.2 c10）：`AlertDialog`，三项带说明 + “记住单个直播间方向”开关 + “关闭”。
- 取消关注（`follow_button.dart:79`）：`AlertDialog`，“取消”“确认”两个文字按钮；取消后没有提示。
- 长按弹幕（`chat_list.dart:627`，3.x `DanmakuMessageActions`）：底部表单，“弹幕”和 ✕、弹幕卡片、复制 / 屏蔽此用户 / 屏蔽关键词…；屏蔽关键词（`chat_list.dart:766`）是自己写的 `AlertDialog`，按钮“确认”，没有字数。
- 右上角菜单（`room_menu_button.dart:282`）：原生 `PopupMenuButton` + `ListTile`（图标 20、dense）。
- 提示条：`AppToast`（A02.2），主题下边距 16；全屏时压在下栏上。

**3.x 和 4.0.0 的问题**（评审页“问题”一节；4.0.0 的行号是当时的）

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 定时关闭、房间音量、获取直链、投屏、画面比例、方向都是居中对话框；横屏全屏压在画面中间、画面压暗（B-7） | `room_dialogs.dart:10、136`、`stream_dialogs.dart:26、195`、`player_dialogs.dart:45、78` |
| P2 | 手机上“房间音量”改 mpv 音量并存进 roomVolumes，但进房一律 1.0、下次不恢复；手势调系统音量，两层互不知道（B-3） | `room_controller.dart:554`、`room_dialogs.dart:136` |
| P3 | 取消静音直接跳 100%（B-14） | `room_dialogs.dart:160` |
| P4 | 获取直链和投屏：进了线路页回不去；不标当前线路；对勾写死 `Icons.check_rounded`（B-13） | `stream_dialogs.dart:120-160` |
| P5 | 画面比例从菜单进是居中对话框，从横屏下栏进是小菜单，两种东西 | `player_dialogs.dart:43`、`bar_parts.dart:218` |
| P6 | 右上角菜单是原生 `PopupMenuButton` + `ListTile`（图标 20），和应用的小菜单不一样（B-7） | `room_menu_button.dart:282` |
| P7 | 取消关注按钮写“确认”，取消后没有反馈（B-15） | `follow_button.dart:79` |
| P8 | 长按弹幕是底部表单，全屏时压在画面上；屏蔽关键词是自己写的对话框（按钮“确认”、没有字数） | `chat_list.dart:607、627` |
| P9 | 全屏时提示条压在下栏上 | `app_toast.dart`（主题下边距 16） |

3.x 的出处（`git show v3.2.11:lib/modules/live_play/...`）：定时关闭 `dialogs/room_timer_dialog.dart`、房间音量 `dialogs/room_volume_dialog.dart`（3.2.11 的“房间音量”改的是全局默认；手机上实际生效的是系统音量，`widgets/video_player/video_controller.dart:823` 的 `_usesSystemVolume`）、获取直链 `dialogs/known_room_link_dialog.dart`、投屏 `dialogs/live_dlna_dialog.dart`、方向 `widgets/video_player/portrait_playback_picker_dialog.dart:17-80`、长按弹幕 `widgets/danmaku/danmaku_message_actions.dart`、菜单 `widgets/button/live_play_menu_button.dart`。

必须保留的操作习惯（[specs/UI.md](../../../specs/UI.md) 附录 A）：第 6 条（长按弹幕的复制和屏蔽）、第 7 条（返回先关面板）、第 10 条（进入直播间不改设备音量——房间音量面板只在用户拖动时改系统音量）、第 18 条（定时关闭）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 设置类用直播间面板、选一项用贴着按钮的小菜单；面板的每一页和状态；右上角菜单；全屏的提示条；五处选择 | 2026-10-02 按建议定稿（用户已授权“所有决定你选择”，N1～N5 按建议 A，D-003），直接开发 |

## 对比页（按章节导出）

[说明](page/01-说明.jpg) · [横屏全屏](page/02-对比-横屏全屏.jpg) · [竖屏](page/03-对比-竖屏.jpg) · [其他位置](page/04-其他位置.jpg) · [面板的每一页和状态](page/05-面板的每一页和状态.jpg) · [小菜单](page/06-小菜单-画面比例-方向-取消关注.jpg) · [右上角菜单](page/07-右上角菜单.jpg) · [全屏的提示条](page/08-全屏的提示条.jpg) · [问题](page/09-问题.jpg) · [改了什么](page/10-改了什么.jpg) · [按钮](page/11-每个按钮是干什么的-怎么用.jpg) · [各客户端](page/12-各客户端.jpg) · [需要你选的](page/13-需要你选的-已按-A-定.jpg) · [性能要点](page/14-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [now-timer-landscape.jpg](now-timer-landscape.jpg)、[v4-timer-landscape.jpg](v4-timer-landscape.jpg) | 横屏全屏定时关闭：4.0.0 居中对话框 / 新设计右侧面板 |
| [v4-timer-portrait.jpg](v4-timer-portrait.jpg)、[v4-volume-portrait.jpg](v4-volume-portrait.jpg)、[v4-volume-landscape.jpg](v4-volume-landscape.jpg) | 定时关闭、房间音量：竖屏画面下方、横屏右侧 |
| [now-link-portrait.jpg](now-link-portrait.jpg)、[v4-link-portrait-fullscreen.jpg](v4-link-portrait-fullscreen.jpg)、[v4-cast-tablet.jpg](v4-cast-tablet.jpg) | 获取直链：4.0.0 / 竖屏全屏底部 60% 的线路页；投屏：平板右侧 |
| [v4-panels.jpg](v4-panels.jpg) | 面板的每一页和状态：清晰度、线路、设备、搜索中、正在投、没找到、静音后、定时关着 |
| [now-fit-portrait.jpg](now-fit-portrait.jpg)、[v4-fit.jpg](v4-fit.jpg) | 画面比例从菜单进：4.0.0 居中对话框 / 新设计贴着四宫格按钮的小菜单 |
| [v4-orientation.jpg](v4-orientation.jpg) | 本直播间画面方向：贴着方向按钮的小菜单（横屏向上） |
| [v4-unfollow.jpg](v4-unfollow.jpg) | 取消关注：贴着“已关注”的小菜单 |
| [v4-menu.jpg](v4-menu.jpg) | 右上角菜单：统一的小菜单，带说明行 |
| [v4-message-landscape.jpg](v4-message-landscape.jpg)、[v4-keyword.jpg](v4-keyword.jpg) | 长按弹幕（面板）；屏蔽关键词（统一的输入对话框） |
| [now-toast-fullscreen.jpg](now-toast-fullscreen.jpg)、[v4-toast-fullscreen.jpg](v4-toast-fullscreen.jpg) | 全屏的提示条：压在下栏上 / 下栏上方 |
| [v4-timer-portrait-n.jpg](v4-timer-portrait-n.jpg)、[v4-volume-portrait-n.jpg](v4-volume-portrait-n.jpg)、[v4-panels-n.jpg](v4-panels-n.jpg) 等 `-n` | 按钮编号示意图 |

## 新设计（第 1 版的内容）

| 弹窗 | 形态 | 位置 |
|---|---|---|
| 定时关闭、房间音量、获取直链、投屏、长按弹幕 | 直播间面板（`RoomSidePanel`，和录制、弹幕设置、切换直播间同一个） | 竖屏画面下方；竖屏全屏底部 60%；横屏全屏、平板右侧 360 全高；没有直播间页面时 `showAdaptivePanel` |
| 画面比例、画面方向、取消关注 | 贴着按钮的小菜单（A02.2） | 放得下的一边；全屏下栏的向上 |
| 右上角菜单 | 统一的小菜单（`AppMenuButton` 的样子） | 贴着四宫格按钮 |
| 屏蔽关键词 | 统一的输入对话框（`showAppInputDialog`） | 居中（键盘弹出时在键盘上方） |
| 提示条 | `AppToast` | 全屏时在下栏上方 |

面板内容：

1. **定时关闭**：开关“启用当前直播间定时停止”，下面一行开着时写“X 分钟后暂停（HH:mm）”（主色），关着时写原来的说明；“停止前播放时长”8 个时长，点一个直接开始；“自定义”分钟输入框 + “开始”，超出 1～525600 时框下写原因。改动立即生效，面板留着。
2. **房间音量**：静音按钮、滑块、百分比；下面一行说明：手机、平板上“调的是手机的媒体音量：和画面右侧上下滑、音量键是同一个音量”；电脑上“只对这个直播间生效，下次进来还是这个音量”。静音后再点回到静音前的音量。
3. **获取直链 / 投屏**：第一页“选择清晰度”（`DialogOptionRow`，正在播的主色加勾、写“正在播放”）；点一档读取线路（转圈），第二页“<清晰度> · 选择线路”，← 回第一页，正在播的线路主色加勾，下面一行是地址；获取直链点一条复制、提示“已复制直链”、关面板；投屏点一条到第三页“<清晰度> · <线路> · 投屏到”，← 回线路，列表上方那一行右边是刷新，设备行左边电视图标，点了转圈、投上后主色加勾。只有一档清晰度直接读线路；只有一条线路直接复制（投屏直接到设备页）；回放的节目直接用回放地址。读取失败、需要应用内会话照原文案写在顶上。
4. **长按弹幕**：标题“弹幕”，弹幕卡片，复制 / 屏蔽此用户 / 屏蔽关键词…（内容照 A07.6）；点“屏蔽关键词…”关面板、弹输入对话框（预填弹幕，单行，字数 40，按钮“屏蔽”）。

小菜单：

- **画面比例**：六种比例，当前项主色加勾；从菜单进时贴着四宫格按钮，从横屏下栏进时贴着画面比例按钮——同一个函数。
- **本直播间画面方向**：标题行，三项各带说明，分隔线，“记住单个直播间方向”开关（切换立即生效、不关菜单）。
- **取消关注**：标题行“主播名 · 平台”，红色“取消关注”；点了取消关注，提示条“已取消关注 X · 撤销”（4 秒，点“撤销”放回原来的位置）。

## 确认的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 修改 | 定时关闭、房间音量、获取直链、投屏、长按弹幕改成直播间面板，三种布局同一个，位置照 A07.6 | B-7 |
| c2 | 修改 | 手机、平板上房间音量直接调系统媒体音量，和手势、音量键同一个；不再存 mpv 音量 | B-3 |
| c3 | 修改 | 取消静音回到静音前的音量 | B-14 |
| c4 | 修改 | 获取直链、投屏三页可返回；当前清晰度和线路主色加勾（`AppIcons.selected`） | B-13 |
| c5 | 修改 | 画面比例：菜单和横屏下栏同一个小菜单 | B-7 |
| c6 | 修改 | 画面方向：贴着按钮的小菜单，带说明和“记住”开关 | B-7 |
| c7 | 修改 | 右上角菜单换成统一的小菜单，带说明行 | B-7 |
| c8 | 修改 | 取消关注：小菜单，红色“取消关注”，之后提示条带“撤销” | B-15 |
| c9 | 修改 | 屏蔽关键词用统一的输入对话框 | A02.2 |
| c10 | 修改 | 全屏时提示条在下栏上方 | A02.2 c12 |
| c11 | 修改 | 定时关闭改动立即生效 | N2 |
| c12 | 保留 | 内容和功能一项不少 | — |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”和 `-n` 图。

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 定时 1 | 启用开关 | 开：按选中的时长开始；关：停掉定时 |
| 定时 2 | 预设时长 | 点一个直接开始（开关自动打开） |
| 定时 3 | 自定义 | 输入 1～525600 分钟 |
| 定时 4 | 开始 | 按自定义时长开始；超出范围在框下写原因 |
| 音量 1 | 静音按钮 | 静音；再点回到静音前的音量 |
| 音量 2 | 滑块 | 拖动立即生效（手机上是系统媒体音量） |
| 直链 1 | 清晰度 | 点一档读取线路；当前播的主色加勾 |
| 直链 5 | ← | 回清晰度页 |
| 直链 6 | 线路 | 获取直链：复制并关面板；投屏：去选设备 |
| 投屏 7 | 刷新 | 重新搜索设备 |
| 投屏 8 | 设备 | 投到它；投上后加勾 |
| 9 | ✕ | 关面板；返回键、竖屏往下拖标题栏也能关 |
| — | 画面比例、画面方向、取消关注（小菜单） | 选一项就关；方向的“记住单个直播间方向”拨动立即生效、不关菜单；取消关注后提示条 4 秒内可“撤销” |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 面板：竖屏画面下方、竖屏全屏底部 60%、横屏全屏右侧 360；小菜单贴着按钮 |
| 平板 | 面板在右侧 360 全高；竖着拿（宽 < 840）在画面下方；房间音量同手机（系统媒体音量） |
| 电视、苹果平台 | 不在这一轮 |
| 没有直播间页面时（单独的按钮） | 同一个面板用 `showAdaptivePanel` 弹：窄屏从底部升起，宽屏在右侧 |

## 待选和决定（按建议 A 定稿）

- N1 房间音量放哪：**A** 面板（和定时关闭一样）。B 贴着菜单按钮的小浮层。
- N2 定时关闭：**A** 改动立即生效，面板留着。B 先选好再“保存”。
- N3 取消关注的确认：**A** 贴着“已关注”的小菜单（全屏也不压画面中间）。B 居中危险确认（同首页卡片）。
- N4 画面方向：**A** 小菜单（和竖屏全屏的画面模式一样）。B 面板。
- N5 不知道静音前的音量时取消静音：**A** 50%。B 100%。

## 性能要点

- 面板只在打开时构建；定时关闭的剩余时间每 30 秒重画一行。
- 房间音量拖动时直接调系统音量；面板开着时每秒读一次系统音量（音量键改了也跟着变），拖动中不读。
- 获取直链只在点了清晰度后才解析地址；投屏搜索只在投屏面板的设备页进行，关掉就停。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-02，合并提交 `edd0da117`“Merge B07: the room's dialogs are panels or anchored menus, room volume is the system volume”；登记表记的是记录提交 `c112f5415`）

| 编号 | 做到 | 现在的代码（`apps/pure_live/lib/features/live_play/` 省略前缀） |
|---|---|---|
| c1 | ✅ | 面板种类 `layout/room_panel.dart:11`（`sleepTimer`、`volume`、`streamLink`、`cast`、`message`），面板内容 `live_play_page.dart:807` 的 `_panelOf`；没有直播间页面时 `layout/room_panel.dart:84` 的 `showRoomPanelSheet`（包了 `showAdaptivePanel`） |
| c2 | ✅ | `dialogs/room_dialogs.dart:275` 的 `RoomVolumePanel`：`DeviceControls.available`（`:294`，Android 手机、平板）时读写系统媒体音量，不写 `roomVolumes`，开着时每秒读一次；其他平台是这个直播间的播放器音量，松手存进 `roomVolumes` |
| c3 | ✅ | 静音前的音量记住（系统一份、每个直播间各一份）；不知道时 50%（`unmuteFallbackVolume` `:265`，N5） |
| c4 | ✅ | `dialogs/stream_dialogs.dart:50` 的 `RoomStreamPanel`（获取直链和投屏同一个）：三页 `_Page { qualities, lines, devices }`（`:41`），标题栏 ← 回上一页；当前项 `DialogOptionRow`（主色、600、`AppIcons.selected`），写“正在播放”；投屏设备 `CastDevices`（`:290`）；只有一档直接读线路、只有一条直接复制、回放用回放地址 |
| c5 | ✅ | `dialogs/player_dialogs.dart:49` 的 `showVideoFitMenu`：菜单和横屏下栏都调它，当前项主色加勾；居中的 `_ChoiceDialog` 删掉 |
| c6 | ✅ | `dialogs/player_dialogs.dart:83` 的 `showRoomOrientationMenu`：标题行、三项带说明、`showSmallMenu` 的 `footer` 放“记住单个直播间方向”开关 |
| c7 | ✅ | `buttons/room_menu_button.dart:316` 的 `AppMenuButton`：图标 24、字 14、分组线；定时开着时第二行写“X 分钟后暂停”、画面比例写当前比例（`AppMenuEntry.description`，`:308`）；`onMenu` 让菜单开着时控制层不隐藏 |
| c8 | ✅（形态按 N3） | `buttons/follow_button.dart:77-95`：`showAppMenu` 标题行“主播 · 平台”、红色“取消关注”（`unfollow-confirm`）；选了以后调 `apps/pure_live/lib/shared/rooms/room_menu.dart:77` 的 `unfollowRoom(confirmed: true)`：提示条“已取消关注 X · 撤销”（4 秒） |
| c9 | ✅（后来改了） | 当时用 `showAppInputDialog`；A07.11 c8 改成长按弹幕面板的第二页（`danmaku/message_panel.dart:81-95`） |
| c10 | ✅ | `live_play_page.dart:967` 的 `_toastsAboveBars`：全屏时把提示条主题的下边距调到下栏以上（`player/player_controls.dart:45` 的 `fullscreenBottomBarHeight`：横屏 52 + 16，竖屏全屏两行 + 16） |
| c11 | ✅ | `dialogs/room_dialogs.dart:43` 的 `RoomSleepTimerPanel`：开关开 = 按上次的时长开始，点预设直接开始，自定义点“开始”，超出 1～525600 在框下写原因；开着时第二行主色“X 分钟后暂停（HH:mm）”，每 30 秒更新 |
| c12 | ✅ | 内容和功能一项不少；“无法打开画中画”当时用 `showAppMessageDialog`，A07.11 c8 改成提示条 |
| 补充 7、8 | ✅ | 节目单、录制面板、弹幕设置面板、本地弹幕样式没有直播间页面时都用 `showRoomPanelSheet` |
| 补充 11 | 没做 | 设置类对话框按钮写明动作、3 个原生 `PopupMenuButton` 不在直播间，留给 A02.1 |

- 根因（核对过）：B-3 `room_controller.dart` 的 `_volume()` 在手机上一律返回 1（3.x 适配器的做法），“房间音量”对话框改 mpv 音量并存进 `roomVolumes`，手势改系统音量，两层互不知道；B-14 静音按钮写死 100%；B-13 点了清晰度后用线路列表**替换**清晰度列表，没有返回的状态；B-7 各自 `showDialog` / `showModalBottomSheet`，根导航器上的居中对话框；提示条下边距取主题的 16，全屏时压在 52 高的下栏上。顺手修：画面上下滑开始时读系统音量是异步的，读到之前的第一次移动会从 0 算起，加了 `_reading`（`player/player_gestures.dart:87`）。
- 验收结论（记录）：`features/live_play/` 和 `features/multiview/` 里已经没有 `showDialog`、`showModalBottomSheet`、`AlertDialog`、`PopupMenuButton`（只剩本地弹幕星标行的 `showGeneralDialog`，透明遮罩、不是对话框）；后来 A07.11 又找出弹幕设置面板里的“弹幕颜色”对话框（见“留下的问题”）。
- `live_ui`（只加）：`AppMenuEntry.description`、`showAppMenu(title:)`、`AppMenuButton.onMenu`、`showSmallMenu(footer:)`、`DialogOptionRow.trailing`；`AppIcons.volumeMuted`、`volumeLow`、`volumeHigh`、`castDevice`、`unfollow`。
- 新翻译键：`live_play_block_action`、`live_play_cast_to`、`live_play_stream_lines`、`live_play_timer_left_until`、`live_play_volume_room_hint`、`live_play_volume_system_hint`。没有新设置。
- 门禁：`live_play` 的原始颜色和图标 7 → 0（`ui_baseline.json` 去掉这一项）。
- 改了任务书可改目录以外的 `layout/`、`live_play_page.dart`、`logic/`（新面板要在页面上挂、系统音量要给测试一个开关），改动很小。

**验证**

- 自动测试：`apps/pure_live/test/features/live_play/room_popups_test.dart`（新，12 个）：定时关闭、房间音量、获取直链在竖屏（画面下方）、横屏全屏（右侧 360 全高，顶栏投屏也是，返回键先关面板）、竖屏全屏（底部 60%）、平板（右侧盖在聊天栏上）的位置，没有对话框和底部表单、画面不压暗；长按弹幕面板在横屏全屏右侧；Android 房间音量 = 系统音量（读 80%、拖到 30% 写进系统、不写 `roomVolumes`、静音再取消回到 30%、画面右侧上滑从 30% 起算、音量键一秒内跟上）；电脑上是播放器音量；获取直链当前项、← 返回；画面比例两处同一个小菜单；全屏提示条位置。`packages/live_ui/test/menu_additions_test.dart`（新，4 个）。改了 7 个已有测试文件里随设计变化的断言。当时 `apps/pure_live` 829 个、`live_ui` 165 个全部通过。
- 自己看的渲染图：用临时 widget 测试渲染了 10 个弹窗（本地，没进仓库），和效果图一致；两处和效果图不同，已改效果图（投屏刷新在设备列表上方那一行右边；定时关着时预设时长不变灰）。
- 真机：待真机，步骤见 [verify.md](verify.md)（从记录的“要在 K90 上看的”九条整理）。
- 留下的问题和去向：
  - 取消关注两种确认（直播间小菜单、首页卡片长按居中对话框 `shared/rooms/room_menu.dart:158` 的 `confirmUnfollowRoom`）要不要统一 → 维护者决定（目前按 D-021）。
  - 全屏中间的对话框：“无法打开画中画”和屏蔽关键词已由 A07.11 c8 改掉；还剩弹幕设置面板“小窗弹幕”的“弹幕颜色”（`danmaku/danmaku_settings_panel.dart:197`）→ 无任务，见子分类 README。
  - 定时关闭面板标题用菜单项名“定时关闭”（以前对话框是“当前直播间播放定时器”）。
