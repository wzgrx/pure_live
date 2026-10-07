# A17.4 电视直播间：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15d、T18c.1）。设计第 1 版 2026-10-01 评审确认（“后续全部通过”），待选 T1～T4 按建议 A（D-003）：左键切换直播间、右键播放设置（T1）；播放列表和切换直播间合成左侧面板（T2）；电视上提供录制（T3）；控制栏只有焦点按钮显示名字（T4）。设计正文在本文件夹 [README.md](README.md)（c1～c17、P1～P17、弹幕设置项对照、焦点路线），评审页导出在 `page/`。
- 跨任务记录（2026-10-01）：焦点样式和配色以 A17.1 为准；“长按确认 = 菜单”（屏蔽撤销、列表里关注都靠它）；网络电视频道的播放设置第一组多一行“节目单”（A17.5 c6，节目单面板本身在 A17.5）。
- 现象（现在的电视直播间，`apps/pure_live/lib/tv/room/`，X03.1 的基础版）：OK 出一排带字的按钮（画质、线路、弹幕、关注、刷新、房间列表）；左、右、菜单键都打开右侧房间列表；画质和线路是屏幕中间的选择框；状态只有一行字；没有播放设置、弹幕设置、屏蔽、录制、节目单、切换直播间的分组（关注、录播、观看记录）。
- 为什么现在做：第三档（D-004）。电视阶段在 A17.2、A17.3 之后：看直播是电视的主要用途。
- 已经做过的：X03.1（进房、换台合并、横幅、控制层、房间列表，逻辑全用手机的 `LiveRoomController`）；A17.1（组件）；手机的直播间界面全部完成或待真机：A07.4 全屏按钮、A07.6 面板和小菜单、A07.7 状态、A07.12 子弹窗统一、A07.13 切换直播间面板、A08.1 弹幕设置和屏蔽组件。
- 半成品：旧分支 M14.2，工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af79805552a6c7d0e`，提交 `69f12f418`（“WIP M14.2 (stopped 2026-10-01 at the UI redesign; not merged)”，基于 `09c352cb7`，提交之后工作区里没有再改动的文件）。内容：`tv/room/tv_room_panel.dart`（665 行：`TvIndexPanel` 按下标走的侧面板、`TvPanelFrame`、`TvScrollPanel`、`TvRoomBar` 底部按钮带）、`tv_room_panels.dart`（706 行：`TvDanmakuPanel` 左右调值、`TvShieldPanel`、`TvRoomInfoPanel`、`TvSuperChatPanel`、`TvRoomRow`、`TvPlaylistPanel`、`TvChatSidebar`）、`tv_room_switch.dart`（322 行：`TvRoomSwitchDialog` 四个标签和搜索）、`tv_iptv_room.dart`（575 行：网络电视的频道面板和节目单，归 A17.5）、`tv_live_play_page.dart` 改了 1028 行。它照 pure_live_TV 做，**是界面重做之前的样子**（居中对话框、自己的弹幕面板，不是 A07.6 / A08.1 的组件），而且建在重构前的目录（`lib/pages/`）：只参考按键处理和逻辑接线，界面照新设计重写，不要合并这个分支。

## 目标和验收

1. （c1）保留：始终全屏；上下键（和频道键）换台，300 毫秒合并、首尾循环；确认键呼出信息栏和控制栏、5 秒没按键自动收起（现在是 6 秒，改成 5 秒）；返回键逐级退出（小菜单 → 面板 → 控制栏 → 离开，回到进来时的卡片、焦点在最后看的直播间）；进房和换台先显示信息；换清晰度时按钮转圈；失败时上下键照样换台。
2. （c3，T1 A）没有浮层时：左键打开左侧“切换直播间”面板，右键和菜单键（长按确认）打开右侧“播放设置”面板；没有“双击左键关注”。
3. （c4，T4 A）控制栏是手机全屏上下栏按钮的同一行、同一顺序（A07.4），图标按钮，只有焦点按钮上方显示名字；一屏放下不滚动。
4. （c5）清晰度、线路、画面比例用手机的贴着按钮的小菜单（A02.3 `showAnchoredMenu` 的电视样式），选完就关。
5. （c6，T2 A）左侧面板四个标签（播放列表 / 已开播 / 录播 / 观看记录，内容同手机 A07.13 的分组）：OK 换台（面板收起、信息栏出现），菜单键关注 / 取消关注（取消先确认）；空标签写“当前没有已开播的关注房间”“暂无观看记录”。
6. （c7）右侧播放设置四组：画面（清晰度、线路、画面比例、仅播放音频……）、弹幕（显示弹幕、弹幕设置、屏蔽管理）、直播间（关注、录制、定时关闭、房间音量、分享 / 获取直链用二维码……）、面板（左右距离、面板字号）；网络电视频道第一组多一行“节目单”（打开 A17.5 的节目单面板）。
7. （c8）弹幕设置用手机 A07.6 / A08.1 的同一份内容（`DanmakuSettingsContent`）的电视样式，一项不少（见 README 的对照表），左右键调值；“画面弹幕交互”两项电视不显示。
8. （c9）屏蔽用 A08.1 的屏蔽管理组件（`DanmakuBlockManager`）的电视样式：关键词、已屏蔽用户、平台过滤、相似过滤；遥控器输入或扫码；删除后菜单键撤销（4 秒）。
9. （c10，T3 A）录制用 A07.6 的录制面板（`RoomRecordPanel`）。
10. （c11、c12、c13）信息栏 = 手机顶栏加信息行内容（平台中文名、分区、人数口径同手机、开播时长、时钟）；换台时写“播放列表 2 / 24”，不另弹提示条；状态用 A07.7 的组件（`RoomStatusLayer`）的电视样式，默认焦点在第一个按钮，底部一行按键提示写对；每个面板只有一行按键提示。
11. （c2、c15）字号大一级（正文 ≥14）；面板宽 400（设计像素，逻辑 200 的两倍以上，按 A17.1 的尺寸换算），贴屏幕边、留 48 / 28 安全边距；列表固定左、设置固定右，没有“面板位置”设置。
12. （c14）取消关注先确认（焦点在“取消”）。
13. （c16、c17）没有内核切换；有飞行弹幕，没有弹幕列表和醒目留言。
14. 手机直播间一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 页面：`apps/pure_live/lib/tv/room/tv_live_play_page.dart`（473 行）：`TvLivePlayPage`（`:59`）、`TvLivePlayPageState`（`:71`）。时长常量：控制层 6 秒（`controlsTimeout` `:90`）、换台合并 300 毫秒（`switchWindow` `:93`）、横幅 3 秒（`bannerTime` `:96`）。没得换时提示 `tv_no_other_room`（`:217`）。按键 `_onKey`（`:256-299`）：面板开着时只处理左键关闭（`:259-265`）；上下和频道键换台（`:267-273`）；控制层开着时其余交给按钮（`:274-278`）；OK 在失败 / 未开播时重试或刷新（`:279-290`，`_blocked` `:246`）；左、右、`contextMenu`、`info` 都打开房间列表（`:291-297`）。画质、线路是 `showTvChoice`（`:307`、`:325`）。画面 `_Picture`（`:451`）用 `LiveVideoView` 和 `DanmakuOverlay`。
- 浮层：`tv/room/tv_room_overlays.dart`（468 行）：`TvRoomStatus`（`:14`，加载、失败、未开播、播放出错四种，一行字加“按 OK 重试”）、`TvChannelBanner`（`:101`，“平台 · 标题 · 2/10”）、`TvRoomControls`（`:162`，按钮 `:266-316` 带字，底部提示 `tv_room_keys_hint` `:323`）、`TvRoomList`（`:338`，右侧一列房间）。
- 逻辑（不改）：`apps/pure_live/lib/features/live_play/logic/room_controller.dart` 的 `LiveRoomController`（`:84`），`features/live_play/logic/background_playback.dart`。
- 手机组件（要用它们的电视样式）：面板外壳 `shared/panels/side_panel.dart:24` 的 `RoomSidePanel`；小菜单 `packages/live_ui/lib/src/widgets/anchored_menu.dart:47` 的 `showAnchoredMenu`；弹幕设置 `shared/danmaku/danmaku_settings_content.dart:48` 的 `DanmakuSettingsContent`（直播间的 `features/live_play/danmaku/danmaku_settings_panel.dart:76` `RoomDanmakuSettings` 在它后面加“弹幕列表”“小窗弹幕”两组，电视都不要）；屏蔽 `shared/danmaku/block_manager.dart:29` 的 `DanmakuBlockManager`；状态 `features/live_play/player/player_status.dart:32` 的 `RoomStatusLayer`、`:158` 的 `PictureStateView`、`:333` 的 `AudioOnlyCover`；录制 `features/live_play/record/record_panel.dart:46` 的 `RoomRecordPanel`、`:145` 的 `RecordPanelBody`；切换直播间分组 `features/live_play/switch_room/room_switch_panel.dart:75`（逻辑在 `features/live_play/logic/room_switch.dart`）；节目单 `features/live_play/dialogs/iptv_guide.dart:78` 的 `IptvGuideView`。这些组件大多带手机的触摸手势和 `InkWell`，没有电视焦点样子。
- 测试：`apps/pure_live/test/tv/tv_test.dart` 的“进房、换台、返回”用例（右键打开房间列表、控制层焦点在第一个按钮）照设计要改。

## 3.x 基线

- 3.x 没有电视直播间；基线是 pure_live_TV（`~/ref/pure_live_TV/lib/modules/live/playback/`，设计用 `b9d2f739`，本机 `37660afc`）：按键 `widgets/player_key_scope.dart`（`:91-224`）、信息卡片 `widgets/video_player/tv_video_surface.dart:306-427`、控制栏 `widgets/video_player/video_controller_panel_parts.dart:299-723`、侧面板 `pages/live_play_page.dart:43-107`、播放列表 `widgets/panels/playlist_panel.dart`、弹幕设置 `widgets/panels/danmaku_settings_panel.dart:40-273`、屏蔽 `widgets/panels/shield_panel.dart`、切换 `dialogs/room_switch_dialog_parts.dart:262-375`、状态 `playback_failure_overlay.dart`、`placeholder/not_living_video_widget.dart`、`audio_only_surface.dart`。README 的“文件对照”表写了 pure_live_TV 文件和 4.x 文件的对应。
- 默认值：pure_live_TV 的弹幕速度 8 被换算成 120 px/s、底部 0.5 换成 0 px（`services/danmaku_settings/danmaku_settings_model.dart:42-55`）；4.x 的弹幕设置用手机已有的键和默认值（D-018），不按 pure_live_TV 改。
- 要保留：c1 那一行；手机附录 A 第 14 条（长按 = 菜单键）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节）；`docs/specs/UI.md` 第 5.5 节（直播间按键）、第 7 节（面板和小菜单）、附录 A。
3. 本文件夹 `README.md`（尤其“改动”“弹幕设置项对照”“焦点路线”“拿不准的地方”）和 `page/`。
4. 手机：`docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏/README.md`（按钮顺序）、`A07.6-直播间弹窗/README.md`、`A07.7-直播间的状态/README.md`、`A07.12-直播间子弹窗统一/README.md`、`A07.13-切换直播间面板/README.md`；`docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页/README.md`；`docs/A-界面设计/A02-组件/A02.3-贴着按钮的小菜单/README.md`。
5. `docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件/README.md`；`docs/X-多端客户端/X03-电视/X03.1-电视外壳和焦点导航/record.md`（“基本直播间”一节）。
6. 代码：上面“现状”列的文件；旧分支的 `tv/room/tv_room_panel.dart`、`tv_room_panels.dart`、`tv_room_switch.dart`（只读，在上面的工作区里）。

## 范围

- 可以改：`apps/pure_live/lib/tv/room/`、`tv/widgets/`；手机组件为了让电视用同一份内容而做的拆分（把内容和外框分开、加 `focusable` 之类的参数），放在原文件或挪到 `apps/pure_live/lib/shared/`，**手机样子和测试不变**；`packages/live_ui` 的 `anchored_menu.dart`（只加电视样式的参数）和 `TvIcons`（只加）；`packages/live_store`（只加面板左右距离、面板字号两个设置，如果手机没有对应的）；翻译文件（只加键）；`test/tv/`；本文件夹。
- 不能改：手机直播间的样子和行为；`LiveRoomController` 的逻辑（要改另开 C 组任务）；弹幕、屏蔽、录制的设置键名和含义（D-018）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；原生代码。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 按键和控制栏（c1、c3、c4、c5、c13）：左键左面板、右键 / 菜单键右面板；控制栏照 A07.4 的按钮和顺序、图标按钮、焦点按钮显示名字；清晰度、线路、比例用小菜单；5 秒收起 | `tv/room/tv_live_play_page.dart`、`tv_room_overlays.dart`、`live_ui` 小菜单的电视样式 | `tv_test.dart` 直播间用例照新按键改并通过；新用例：控制栏按钮顺序和手机一致、只有焦点按钮有名字、清晰度小菜单贴按钮、选完就关、5 秒收起 |
| 2 | 信息栏和状态（c11、c12）：信息栏内容、换台写“播放列表 2 / 24”；状态用 `RoomStatusLayer` 的电视样式（受限、重连、回放播完、纯音频都有） | `tv_room_overlays.dart`、手机 `player_status.dart` 的拆分 | 新用例：各状态默认焦点第一个按钮、底部提示文字；换台不另弹提示条 |
| 3 | 左侧切换直播间（c6、c14）：四个标签、OK 换台、菜单键关注、取消先确认 | 新 `tv/room/tv_room_switch_panel.dart`；`room_switch.dart` 的分组逻辑直接用 | 新用例：四个标签内容和空状态；OK 换台后面板收起；菜单键关注、取消关注确认框焦点在“取消” |
| 4 | 右侧播放设置（c7、c15）和弹幕设置（c8）、屏蔽（c9）：四组、子面板、返回回到原来那一行；面板贴边、安全边距 | 新 `tv/room/tv_play_settings_panel.dart`；`DanmakuSettingsContent`、`DanmakuBlockManager` 的电视样式 | 新用例：四组顺序；弹幕设置项和手机一致（按 README 对照表逐项断言）、左右调值；屏蔽删除后菜单键撤销 |
| 5 | 录制（c10）和直播间组其余项（定时关闭、房间音量、分享 / 获取直链二维码）；网络电视“节目单”一行（A17.5 的面板做好前先不显示） | `tv_play_settings_panel.dart`、`RoomRecordPanel` 的电视样式 | 新用例：录制面板打开、状态卡和手机一致；分享出二维码 |

每个阶段都要能单独合并。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表把“开发”拆开。

## 测试

- 改之前会失败：`test/tv/tv_test.dart` 加“直播间里按左键打开左侧切换直播间面板”（现在左右键都打开右侧房间列表，`tv_live_play_page.dart:291-297`）。
- 每个阶段的用例见上表。另外：
  - 控制栏开着时上下键仍换台（照 pure_live_TV，README“拿不准的地方”第 3 条）；
  - 返回键逐级：小菜单 → 面板 → 控制栏 → 离开，离开后焦点在最后看的房间的卡片；
  - 1080p@2x 和 720p（1280×720@1）各一个布局测试：面板贴边、留 48 / 28、字不小于 14。
- 用测试里的假平台和假播放会话（照 `tv_test.dart`、`test/features/live_play/` 的写法），不访问真实平台；定时器至少 1 秒。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 从关注进一个直播间 | 全屏，先出信息栏（平台中文名、分区、人数、开播时长、时钟），几秒后收起 |
| 2. 按下键两次（快） | 一次换两个台，信息栏写“播放列表 3 / N” |
| 3. 按 OK | 控制栏一排图标、焦点按钮上方有名字；5 秒不按自动收起 |
| 4. 控制栏上走到清晰度按 OK | 小菜单贴着按钮，选一档后菜单关闭、按钮转圈后变成新清晰度 |
| 5. 收起后按左 | 左侧面板四个标签，焦点在“正在播放”那一行；菜单键（或长按 OK）关注一个，再按取消关注时先确认 |
| 6. 按右（或菜单键） | 右侧播放设置；进“弹幕设置”，左右调字体大小，画面上立即变；返回回到“弹幕设置”那一行 |
| 7. 进“屏蔽管理”删一个词，马上按菜单键 | 词回到原位 |
| 8. 进“录制”，开始录制再停止 | 状态卡和手机一样；录制中心里有这个任务 |
| 9. 进一个没开播的房间 | 状态页焦点在第一个按钮，底部按键提示写对；上下键照样换台 |
| 10. 一路按返回 | 逐级关闭，最后回到列表，焦点在最后看的房间 |

## 风险和注意

- 手机组件（`DanmakuSettingsContent`、`DanmakuBlockManager`、`RoomRecordPanel`、`RoomStatusLayer`）里的控件是触摸用的（滑块拖动、`InkWell`）：给它们加电视样式时要让方向键能走到每一项、滑块能左右调，又不改手机。先挑一个（弹幕设置）做通，再推广；做法写进 record.md，A17.6、A17.9 会照着用。
- 录制在电视盒子上存哪（README“拿不准的地方”第 5 条）：随 A17.9 的录制设置定；本任务只放面板，存储位置用现有设置。
- 本地弹幕和本地互动、投屏、小窗、方向、在平台打开这些手机项电视不提供（README 第 6 条），菜单里不要出现。
- 网络电视频道的“节目单”一行依赖 A17.5；两个任务改同一个播放设置面板，先做 A17.4。
- 可能冲突的文件：`tv/room/` 全部（A17.5 也改）、`features/live_play/player/player_status.dart`、`shared/danmaku/`（A08.6、A08.7 也改）、`packages/live_ui/lib/src/widgets/anchored_menu.dart`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.4` 或本机工作区；提交信息以 `[A17.4]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；手机组件怎么加的电视样式（改了哪些手机文件、手机测试是否不改断言照样通过）；从旧分支 M14.2 借了哪些逻辑；测试数量（改之前失败几个）；新设置和翻译键；要在电视上看的；可能冲突的文件。
