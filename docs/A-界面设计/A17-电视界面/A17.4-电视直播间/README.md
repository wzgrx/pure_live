# A17.4 电视直播间：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：电视直播间的播放、信息栏、控制栏、飞行弹幕、左侧直播间列表（含切换直播间）、右侧播放设置（清晰度、线路、画面比例、弹幕、屏蔽、录制……）、各种状态。下面的界面清点表是这一批出图的清单
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a174)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a174)；计划书 [specs/UI.md](../../../specs/UI.md) 第 5.5 节
- 基线：pure_live_TV（`~/ref/pure_live_TV/lib/modules/live/playback/`），不是 v3；同一功能用手机版的同一个组件：小菜单、弹幕设置、录制面板照 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md)（已确认），全屏按钮照 [A07.4](../../A07-直播间界面/A07.4-横屏全屏/README.md)，屏蔽管理照 [A08.1](../../A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md)，状态照 [A07.7](../../A07-直播间界面/A07.7-直播间的状态/README.md)，信息照 [A07.1](../../A07-直播间界面/A07.1-竖屏普通布局/README.md)
- 评审页：claude.ai 私有页面（已发布，用户评审确认），由 `page.json` 生成（`tools/ui/mock/page.py`）；效果图源文件 [src/gen.py](src/gen.py)（电视的公共样式在 [src/tvkit.py](src/tvkit.py)，A17.5 也用）
- 图片：pure_live_TV 按代码还原，尺寸是它的 1920×1080 设计像素折半画在 960×540 上（出图 1920 宽）；文字取自 pure_live_TV 的 `assets/translations/zh.json`（`i18nOr` 的键也查了）；画面和头像是示意图片

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A17.4-01 | 直播间（`LivePlayPage`、`TvVideoSurface`） | 任何房间卡片；换台 | 电视全屏 | 播放中；进房和换台后几秒（信息栏）；纯音频 |
| A17.4-02 | 信息栏（`_RoomInfoBar`）+ 换台提示条（`_ChannelBannerToast`） | 进房、换台自动出现 5 秒；确认键 | 同上 | 加载中、播放中、出错时；换台时带“第几个” |
| A17.4-03 | 控制栏（`VideoControllerPanel`） | 确认键 | 同上 | 焦点在某个按钮；清晰度 / 线路 / 比例的小菜单打开；切换中按钮转圈 |
| A17.4-04 | 左侧：切换直播间（`PlaylistPanel` + `RoomSwitchDialog` 合并） | 左键；控制栏“切换直播间”；未开播页按钮 | 同上 | 四个标签；某个标签为空（“当前没有已开播的关注房间”“暂无观看记录”）；菜单键的关注小菜单 |
| A17.4-05 | 右侧：播放设置（新） | 右键、菜单键、控制栏最后一个按钮 | 同上 | 第一屏；行上的小菜单 |
| A17.4-06 | 弹幕设置（`DanmakuSettingsPanel`） | 控制栏、播放设置 | 同上 | 焦点在滑块行（左右调值）；完整内容 |
| A17.4-07 | 屏蔽管理（`ShieldPanel`） | 播放设置（pure_live_TV 在控制栏） | 同上 | 有关键词；手机远程服务启动中（“正在启动手机远程服务...”）；删除后可撤销；空（“暂无屏蔽关键词”） |
| A17.4-08 | 录制（新，A07.6 录制面板） | 控制栏录制按钮、播放设置 | 同上 | 没在录（其余 8 种同 A07.6） |
| A17.4-09 | 状态（`PlaybackFailureOverlay`、`NotLivingVideoWidget`、加载、`AudioOnlySurface`） | 自动 | 同上 | A07.7 的 18 种里电视用得上的全部；图里画 8 种 |
| A17.4-10 | 提示条 | — | 同上 | “没有可切换的频道”；“已移除‘…’ · 按菜单键撤销”；pure_live_TV 的“双击关注 / 双击取消关注 / 已关注 / 已取消关注”去掉 |
| — | 弹幕列表（`DanmakuListView`） | pure_live_TV 写了组件但没有任何地方用到 | — | 不出图（电视没有弹幕列表，A08.1 已这样定） |

## pure_live_TV 的样子

文件都在 `lib/modules/live/playback/` 下。尺寸写“设计像素”（1920 宽），电视上的逻辑像素是一半。

**按键**（`widgets/player_key_scope.dart`）：没有浮层时确认键呼出控制栏和房间卡片（:120-123）；上下键换台，300 毫秒内连按累加后一次切换（:144-170），首尾循环，没得换时提示“没有可切换的频道”（:165）；左键双击关注或取消关注，单按弹“双击关注 / 双击取消关注”（:173-202）；右键打开播放列表（:137-140）。控制栏开着时上下键仍然换台（:108-118），左右和确认归控制栏。失败、未开播的画面上，左右和确认归画面上的两个按钮，上下键换台（:91-101）。返回键：先关侧面板，再收控制栏和卡片，再离开（:206-224）。控制栏和卡片 5 秒没按键自动收起（`controllers/live_play_controller.dart:1086-1090`）。

**房间卡片**（`widgets/video_player/tv_video_surface.dart:306-396`）：顶部黑色渐变上一张 42% 黑的圆角卡片：头像（半径 30）、标题（t28 粗体）、一行“平台 ID 大写的小胶囊（BILIBILI）+ 主播名（t18）+ 人数胶囊（`whatshot`）”，右边竖线、`time_line` 和时钟（t28）。进房时自动显示（`live_play_controller.dart:240-246`），请求房间信息时、出错时也显示。换台后卡片下面另有 2 秒的主播名提示条（t24，蓝色细边，:398-427；`live_play_controller.dart:1041`）。

**控制栏**（`widgets/video_player/video_controller_panel_parts.dart`）：底部 82% 黑渐变，按钮带是 55% 黑、高 84（:567-601）。12 个胶囊按钮，每个图标 + 文字（t20），选中的蓝底（`#00A1FF`，:632-723）：已关注（`favorite`）、暂停、重试、弹幕开（`danmu_open.svg`）、弹幕设置（`danmu_setting.svg`）、弹幕关键词过滤（`dynamic_feed`）、原画（`high_quality`）、线路 1（`density_small`）、默认比例（`video_settings`）、视频模式 / 仅播放音频（`Remix.tv_2_line` / `headphone_line`）、切换直播间（`swap_horiz`）、Mpv播放器（内核，`memory`）（:312-392）。一行放不下时横向滚动（:579-600）。按钮里没有音量（:17-18）。清晰度、线路、比例、内核点开是屏幕正中一个 380 宽的黑色列表（标题“清晰度 / 线路 / 画面比例 / 内核切换”，:232-238、:491-565），上键进入、左键关闭（:139-147），选了不关（:152-159），内核选了才关（:422-437）。

**侧面板**（`pages/live_play_page.dart:43-73`）：浮在画面上，离右边 24、上下 24，宽 400，圆角 20，底色 `#121212` 92%，蓝色细边；可在设置里换到左边、改离边距离和字号（`player_panel_layout.dart`）。面板底下固定一行“↑↓ 选择 · OK 确认 · ← 关闭”（:101-107），面板自己还有一行提示（`player_index_panel.dart:326-334`）。

- **播放列表**（`widgets/panels/playlist_panel.dart`）：标题“播放列表”；行（`player_room_row.dart`，大行 88 高）：头像、标题 + “关注 / 已关注”小框、主播名、右边平台 ID 和人数（没有人数写“人数待更新”，回放写“重播”）；正在播的行淡蓝底，选中蓝底。上下选、OK 换台、左右键关注或取消关注（:55-57）。列表是进房时的列表 + 观看记录里在播的（`live_play_controller.dart:958-975`）。
- **弹幕设置**（`widgets/panels/danmaku_settings_panel.dart:40-257`）：16 行，图标 + 名字 + 数值：弹幕开关（弹幕开 / 弹幕关）、弹幕字号（16）、弹幕速度（120 px/s）、弹幕透明度（100%）、弹幕描边（开）、描边宽度（4 px）、弹幕字重（500）、弹幕帧率（60 fps）、自动帧率（关）、显示区域（100%）、顶部安全距离（0 px）、底部占用高度（0 px）、表情显示（开）、面板位置（右）、左右距离（24）、面板字号（100%）。左右键按档位调（`controllers/danmaku_option_steps.dart`），OK 在开关行切换、在数值行加一档（:269-273）。
- **弹幕关键词过滤**（`widgets/panels/shield_panel.dart`）：标题“弹幕关键词过滤 · 3”；上面“弹幕关键词屏蔽”+ 二维码（手机网页编辑）+“手机扫码编辑屏蔽词”，服务没起来时“正在启动手机远程服务...”（:113-166）；下面每个词一行，`block` 图标 + 词 + “删除”，OK 直接删（:99-108）；空时“暂无屏蔽关键词”。没有已屏蔽用户（:16-18）。

**切换直播间**（`dialogs/room_switch_dialog_parts.dart`）：居中对话框，宽 1160，高为屏幕 72%（:262-266）；标题“切换直播间”；三个标签“已开播 (8) / 录播 (1) / 观看记录 (30)”（:312-356）；列表同播放列表的大行（没有关注框）；空时“当前没有已开播的关注房间 / 暂无观看记录”（:358-375）。从控制栏和未开播页打开。

**状态**：加载中是转圈 +“正在加载房间信息... / 正在缓冲...”（`tv_video_surface.dart:206-221`）；播放失败（`widgets/video_player/playback_failure_overlay.dart:81-140`）整片 72% 黑，`error_outline`、“播放失败”或错误原文、提示“↑↓ 选择 · ←→ 调整 · OK 确认”、两个按钮“重试播放”“刷新房间”；未开播（`widgets/placeholder/not_living_video_widget.dart:103-219`）整片 86% 黑，带下播标记的头像、标题、“该房间未开播或已下播”“请切换其他直播间进行观看吧”、同样的提示行、“切换直播间”“刷新房间”；仅播放音频（`widgets/video_player/audio_only_surface.dart`）是头像放大做底、圆框头像、标题、主播名、“仅播放音频”胶囊。

**按宽度分支**：没有；纯音频画面在高度 <500 时紧凑（`audio_only_surface.dart:50`）。字号跟“字体大小”设置和 720p 面板放大（`core/theme/tv_text_scale.dart`）。

**v4 现在**（`apps/pure_live/lib/tv/room/tv_live_play_page.dart`、`tv_room_overlays.dart`，X03.1 的基础版）：确认键出控制栏（清晰度、线路、弹幕、关注、刷新、直播间列表）；左、右、菜单键都打开右侧的直播间列表；清晰度和线路是居中的选择对话框（`showTvChoice`）；状态是 `TvRoomStatus` 一行字；没有弹幕设置、屏蔽、播放设置。

## pure_live_TV 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| P1 | 字太小：t14–t20 设计像素（电视上逻辑 7–10），面板只有 200 宽；计划书要求正文不低于 14 | `video_controller_panel_parts.dart:677`、`player_index_panel.dart:398-405`、`player_room_row.dart:90-93`、`live_play_page.dart:52` |
| P2 | 按键提示写错：面板底下两行互相矛盾；播放列表里左键其实是关注；失败、未开播页写“↑↓ 选择 · ←→ 调整”，上下键其实是换台 | `live_play_page.dart:101-107`、`player_index_panel.dart:326-334`、`playback_failure_overlay.dart:110`、`not_living_video_widget.dart:141` |
| P3 | 左键双击关注，看不到、容易误按 | `player_key_scope.dart:133-136,173-202` |
| P4 | 控制栏 12 个带字按钮一行放不下要滚；顺序和手机不同 | `video_controller_panel_parts.dart:299-393,579-600` |
| P5 | 选项列表在屏幕正中，离按钮远；选了不关 | `video_controller_panel_parts.dart:152-159,499-503` |
| P6 | 选直播间两个界面（播放列表面板、切换对话框），样子和按键不同 | `playlist_panel.dart:49-70`、`room_switch_dialog_parts.dart:264-303` |
| P7 | 列表左右键、控制栏关注按钮取消关注都不确认（手机先确认） | `playlist_panel.dart:56-57,79-86`、`video_controller_panel_parts.dart:316-324` |
| P8 | 播放设置没有直接入口：清晰度是控制栏第 7 个按钮 | `player_key_scope.dart:120-141` |
| P9 | 弹幕设置和手机是两套名字和分组，少观看模板和合并重复弹幕，又混进三项面板布局 | `danmaku_settings_panel.dart:40-257` |
| P10 | 每项都是“名字 + 数值”，看不出范围，开关和数值一个样；数值行按 OK 加一档 | `danmaku_settings_panel.dart:265-271` |
| P11 | 屏蔽 OK 直接删、不能撤销；二维码占半个面板、网址缩到看不清 | `shield_panel.dart:105-108,150`、`core/widgets/tv_qr_card.dart:75-88` |
| P12 | 屏蔽少已屏蔽用户、平台过滤、相似过滤 | `shield_panel.dart:16-18` |
| P13 | 卡片平台写英文 ID；只有一个人数；没有分区、开播时长 | `tv_video_surface.dart:29-34,352-369` |
| P14 | 换台时卡片和主播名提示条同时出现；看不出在列表第几个 | `tv_video_surface.dart:256-286` |
| P15 | 状态三种样子；“播放失败”不写原因；没有受限、重连、回放播完 | `playback_failure_overlay.dart:81-140`、`not_living_video_widget.dart:114-166`、`tv_video_surface.dart:206-221` |
| P16 | 没有手机直播间的录制、定时关闭、房间音量、分享、获取直链 | `video_controller_panel_parts.dart:312-392` |
| P17 | 所有侧面板同一侧，浮在画面上离边 24 | `live_play_page.dart:43-73`、`player_panel_layout.dart:21-55` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 进房换台、信息栏和控制栏、左右两个面板、弹幕设置、屏蔽、录制、状态；四处选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：进房和换台](page/02-对比-进房和换台.jpg)
- [对比：确认键（信息栏和控制栏）](page/03-对比-确认键-信息栏和控制栏.jpg)
- [对比：左键（直播间列表、切换直播间）](page/04-对比-左键-直播间列表-切换直播间.jpg)
- [右键：播放设置（新）](page/05-右键-播放设置-新.jpg)
- [对比：弹幕设置](page/06-对比-弹幕设置.jpg)
- [对比：屏蔽](page/07-对比-屏蔽.jpg)
- [录制（新）](page/08-录制-新.jpg)
- [对比：状态](page/09-对比-状态.jpg)
- [pure_live_TV 的问题](page/10-pure_live_TV-的问题.jpg)
- [改了什么](page/11-改了什么.jpg)
- [按钮用法：控制栏](page/12-每个按钮是干什么的-怎么用-控制栏.jpg)、[左右两个面板](page/13-每个按钮是干什么的-怎么用-左右两个面板.jpg)、[弹幕设置、屏蔽、录制](page/14-每个按钮是干什么的-怎么用-弹幕设置-屏蔽-录制.jpg)
- [遥控器按键和焦点路线](page/15-遥控器按键和焦点路线.jpg)
- [各客户端](page/16-各客户端.jpg)
- [需要你选的](page/17-需要你选的.jpg)
- [性能要点](page/18-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-entry.jpg](v3-entry.jpg)、[v4-switch.jpg](v4-switch.jpg) | 换台后：pure_live_TV 卡片 + 主播名 / 新设计信息栏带“播放列表 2 / 24”，正在进入 |
| [v3-controls.jpg](v3-controls.jpg)、[v4-info.jpg](v4-info.jpg)、[v4-info-n.jpg](v4-info-n.jpg) | 确认键：卡片 + 12 个带字按钮 / 信息栏 + 一行图标按钮（焦点在刷新） |
| [v3-quality.jpg](v3-quality.jpg)、[v4-quality.jpg](v4-quality.jpg) | 清晰度：屏幕正中的列表 / 贴着按钮的小菜单 |
| [v3-playlist.jpg](v3-playlist.jpg)、[v3-switch.jpg](v3-switch.jpg) | pure_live_TV 的播放列表面板、切换直播间对话框 |
| [v4-list.jpg](v4-list.jpg)、[v4-list-n.jpg](v4-list-n.jpg)、[v4-list-live.jpg](v4-list-live.jpg) | 新设计左侧切换直播间：播放列表标签（焦点在行）/ 已开播标签（焦点在标签） |
| [v4-settings.jpg](v4-settings.jpg)、[v4-settings-n.jpg](v4-settings-n.jpg)、[v4-settings-quality.jpg](v4-settings-quality.jpg)、[v4-settings-full.jpg](v4-settings-full.jpg)、[v4-settings-full-n.jpg](v4-settings-full-n.jpg) | 右侧播放设置：第一屏、行上的小菜单、完整内容 |
| [v3-danmaku.jpg](v3-danmaku.jpg)、[v3-danmaku-full.jpg](v3-danmaku-full.jpg)、[v4-danmaku.jpg](v4-danmaku.jpg)、[v4-danmaku-n.jpg](v4-danmaku-n.jpg)、[v4-danmaku-full.jpg](v4-danmaku-full.jpg) | 弹幕设置 |
| [v3-shield.jpg](v3-shield.jpg)、[v4-shield.jpg](v4-shield.jpg)、[v4-shield-n.jpg](v4-shield-n.jpg)、[v4-shield-undo.jpg](v4-shield-undo.jpg)、[v4-shield-full.jpg](v4-shield-full.jpg) | 屏蔽：pure_live_TV / 新设计、删除后撤销、完整内容 |
| [v4-record.jpg](v4-record.jpg)、[v4-record-n.jpg](v4-record-n.jpg) | 录制（新） |
| [v3-states.jpg](v3-states.jpg)、[v4-states.jpg](v4-states.jpg) | 状态：pure_live_TV 四种 / 新设计八种 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 始终全屏；上下键换台（300 毫秒合并、循环）；确认键呼出、5 秒自动收起；返回键逐级退出；进房换台先显示信息；换清晰度时按钮转圈；失败时上下键照样换台 | — |
| c2 | 修改 | 字号大一级（正文 ≥14）；面板宽 400；48 / 28 安全边距 | P1 |
| c3 | 修改 | 左键左侧切换直播间，右键右侧播放设置，菜单键也开播放设置；去掉双击左键关注 | P3、P8（T1） |
| c4 | 修改 | 控制栏 = 手机全屏上下栏按钮一行，顺序同手机；图标按钮，焦点按钮上方显示名字 | P4（T4） |
| c5 | 修改 | 清晰度、线路、比例用手机的小菜单，贴按钮、选完就关 | P5 |
| c6 | 修改 | 播放列表 + 切换直播间合成左侧面板四个标签；OK 换台，菜单键关注 | P6、P7（T2） |
| c7 | 增强 | 右侧播放设置：画面、弹幕、直播间、面板四组 | P8、P16 |
| c8 | 修改 | 弹幕设置用 A07.6 组件，一项不少；左右键调值；“画面弹幕交互”电视不显示 | P9、P10 |
| c9 | 修改 | 屏蔽用 A08.1 组件；遥控器输入或扫码；删除可撤销（菜单键） | P11、P12 |
| c10 | 增强 | 录制用 A07.6 录制面板 | P16（T3） |
| c11 | 修改 | 信息栏 = 手机顶栏 + 信息行内容；换台写“播放列表 2 / 24”，不另弹提示条 | P13、P14 |
| c12 | 修改 | 状态用 A07.7 组件，默认焦点第一个按钮，底部写按键 | P2、P15 |
| c13 | 修改 | 每个面板只一行按键提示，写对 | P2 |
| c14 | 修改 | 取消关注先确认 | P7 |
| c15 | 修改 | 面板贴边，列表固定左、设置固定右；去掉“面板位置”，“左右距离”“面板字号”移到播放设置 | P9、P17 |
| c16 | 去掉 | 内核切换（v4 只有 mpv） | — |
| c17 | 保留 | 飞行弹幕；电视没有弹幕列表和醒目留言 | — |

**弹幕设置项对照**（pure_live_TV → 新设计，一项不少）：

| pure_live_TV | 新设计（A07.6 组件） |
|---|---|
| 弹幕开关 | 控制栏“弹幕开关”、播放设置“显示弹幕” |
| 弹幕字号、弹幕速度、弹幕透明度、弹幕描边、描边宽度、弹幕字重 | 样式：字体大小、滚动速度（像素/秒）、透明度、弹幕描边、描边宽度、字体粗细 |
| 弹幕帧率、自动帧率 | 流畅度：弹幕帧率跟随界面刷新率、弹幕帧率 |
| 显示区域、顶部安全距离、底部占用高度 | 显示范围：画面顶部占用高度、顶部留白（像素）、区域底部留白（像素） |
| 表情显示 | 样式：纯文字模式（隐藏表情）（意思相反） |
| 面板位置、左右距离、面板字号 | 播放设置“面板”一组（面板位置去掉，见 c15） |
| — | 新增（手机有）：观看模板、存为我的模板、合并相同弹幕、合并时间 |

## 按钮的作用和用法

见对比页“每个按钮是干什么的”三节（控制栏 1–12，左面板标签和行，右面板 1–15，弹幕设置、屏蔽、录制各 1–4）。

## 焦点路线

| 在哪 | 默认焦点 | 上下 | 左右 | 确认 | 菜单（长按确认） | 返回 |
|---|---|---|---|---|---|---|
| 看直播（没有浮层） | — | 换台 | 左：切换直播间；右：播放设置 | 信息栏 + 控制栏 | 播放设置 | 离开直播间（回到进来时的卡片，焦点在刚才看的直播间） |
| 控制栏 | 上次的按钮（第一次播放 / 暂停） | 换台 | 按钮间走，首尾循环 | 执行 | 播放设置 | 收起 |
| 控制栏的小菜单 | 当前项 | 选项 | — | 选定并关闭 | — | 关闭 |
| 左侧切换直播间 | 播放列表里“正在播放”那行 | 行；第一行再按上到标签 | 标签上换标签；行上按右关闭 | 换台（面板收起，信息栏出现） | 关注 / 取消关注 | 关闭 |
| 右侧播放设置 | 上次的行（第一次清晰度） | 行 | 左：关闭 | 开关、弹小菜单（贴行左边）、进子面板 | — | 关闭 |
| 子面板（弹幕设置、屏蔽、录制） | 第一项 | 行 | 调值；在模板、小标签间走 | 开关、删除、开始录制 | 撤销刚才的删除 | 回到播放设置，焦点回到原来的行 |
| 状态 | 第一个按钮 | 换台 | 按钮间 | 执行 | 播放设置 | 离开直播间 |

焦点样式：3 像素近白描边；按钮和卡片放大 1.05 倍，列表行只描边、底色变浅（计划书第 5.5 节；以 A17.1 为准）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 不适用（电视专用）；用到的组件就是手机的组件 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 不适用 |
| 电视 | 本任务 |
| 苹果平台差异 | 不适用（不做 Apple TV） |

## 待选（A 是建议）

- T1 左右键：A 左键切换直播间、右键播放设置（计划书）；B 照 pure_live_TV 左键双击关注、右键播放列表。
- T2 播放列表和切换直播间：A 合成一个左侧面板；B 照 pure_live_TV 分开。
- T3 电视上的录制：A 提供（同手机面板）；B 不提供。
- T4 控制栏按钮名字：A 只有焦点按钮显示名字；B 照 pure_live_TV 每个都带字、左右滚。

## 拿不准的地方

1. **焦点样式和配色**：A17.1（电视设计系统）还没做；图里焦点照计划书第 5.5 节（3 像素近白描边、1.05 倍），配色用手机深色主题的颜色角色。pure_live_TV 自己的调色（`TvThemeData`，v4 已有 `TvPalette`）用不用，随 A17.1 定。
2. **菜单键**：多数遥控器没有菜单键，计划书定“长按确认 = 菜单”；pure_live_TV 的直播间没有长按的用法，所以不冲突。屏蔽“按菜单键撤销”和列表“菜单键关注”都靠它。
3. **控制栏开着时上下键仍换台**：照 pure_live_TV（`player_key_scope.dart:108-118`）；如果嫌容易误换台，可以改成控制栏开着时上下键不起作用。
4. **定时关闭、房间音量、分享、获取直链** 的子界面同手机（A07.6 说的下一批），这里没出图；电视上“分享”“获取直链”打算显示二维码和地址。
5. **录制存哪、录制中心入口**：pure_live_TV 没有录制；电视盒子的存储位置、录制中心在电视上的入口随 A17.9（电视设置）定。
6. **电视不提供的手机项**：投屏（电视就是屏幕）、小窗、方向、本地弹幕输入和本地互动体验（要打字）、在平台打开（电视上一般没有平台 App）。如果要保留本地互动，需要另设计输入方式。
7. **“去登录”** 在电视上是扫码登录（账号页，A17.9 / A12.2）。
8. pure_live_TV 的默认值按代码：速度 8 被 `normalizeSpeed` 换成 120 px/s，底部 0.5 被 `normalizeDistance` 换成 0 px（`services/danmaku_settings/danmaku_settings_model.dart:42-55`）；图里写换算后的值。
9. **面板字号、左右距离的选项**：pure_live_TV 是 80%–150% 六档、0–64 七档（`player_panel_layout.dart:57,80`）；新设计改成点开小菜单选，不再用左右键（播放设置里左键一律是关闭）。

## 文件对照

| pure_live_TV | v4 |
|---|---|
| `pages/live_play_page.dart`、`widgets/player_key_scope.dart` | `apps/pure_live/lib/tv/room/tv_live_play_page.dart` |
| `widgets/video_player/tv_video_surface.dart`（卡片、提示条、加载） | `tv/room/tv_room_overlays.dart`（`TvChannelBanner`、`TvRoomStatus`） |
| `widgets/video_player/video_controller_panel_parts.dart` | `tv/room/tv_room_overlays.dart`（`TvRoomControls`）；小菜单 `live_ui` 的菜单组件（A07.6） |
| `widgets/panels/playlist_panel.dart`、`player_room_row.dart`、`dialogs/room_switch_dialog_parts.dart` | `tv/room/tv_room_overlays.dart`（`TvRoomList`）；切换直播间组件（A07.6 下一批） |
| `widgets/panels/danmaku_settings_panel.dart` | `shared/danmaku/danmaku_settings.dart`（A07.6 组件） |
| `widgets/panels/shield_panel.dart` | `features/shield/`（A08.1 屏蔽管理组件） |
| `widgets/video_player/playback_failure_overlay.dart`、`placeholder/not_living_video_widget.dart`、`audio_only_surface.dart` | `features/live_play/player/player_status.dart`（`RoomStatusLayer`，A07.7） |
| — | `features/recorder/`（录制面板，A07.6） |
