# A07.12 直播间子弹窗统一：任务书

> 设计按建议定稿、代码已在 2026-10-02 合并（`edd0da117`），登记表状态“待真机”。这份任务书保留原来交给执行者的全部要求（旧编号 B07 的任务单和“A02.2 之后补充”，下面“方案和阶段”的阶段 1、2），并写清剩下的事：阶段 3 真机验证和维护者要定的几处。

## 背景

- 来源：审查报告 B-3、B-7、B-13、B-14、B-15（`docs/V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md`）；A07.6 当时说“下一批出图”的子弹窗；A02.2 记录末尾“直播间里还没换的弹窗”表（`docs/A-界面设计/A02-组件/A02.2-弹窗组件/record.md`）。
- 现象（修之前，4.0.0）：定时关闭、房间音量、获取直链、投屏、画面比例（从菜单进）、画面方向都是居中对话框，横屏全屏时压在画面正中并压暗；手机上“房间音量”调的是播放器音量、和画面右侧上下滑（系统音量）不是一个数，下次进房也不恢复；取消静音直接跳 100%；获取直链进了线路页回不去、不标当前线路；取消关注按钮写“确认”、取消后没有提示；长按弹幕是底部表单；全屏时提示条压在下栏上。
- 为什么做：第一档；规则照 A07.6 已确认的统一规则（直播间里的设置用面板、选一项用贴着按钮的小菜单）。
- 原任务单的约定：规模中；依赖 A02.3、A07.13 之后；直播间组依次做；出设计：要（先出对比页和效果图，再实现；用户已授权“所有决定你选择”，“需要你选的”按建议 A 直接做）。
- 已经做过的：A02.2（统一弹窗组件 `AppDialog`、`showAppConfirmDialog`、`showAppOptionDialog`、`showAppInputDialog`、`DialogOptionRow`、`PanelFrame`、`showAdaptivePanel`、`AppToast`；`AppNavigator.showToast`）；A07.13（切换直播间面板和 `RoomPanelKind` 挂法）。

## 目标和验收

1. c1 先出设计（产出放本文件夹）：定时关闭、房间音量、投屏（选设备）、获取直链（清晰度 → 线路）、画面比例在竖屏、横屏、全屏下用面板（`RoomSidePanel`）还是贴着按钮的小菜单，和录制、弹幕设置面板一致；横屏全屏不再出现压在画面中间的居中对话框。
2. c2 B-3：手机上“房间音量”直接调系统音量（和手势、v3 一致），不再另存一层 mpv 音量；平板同手机。
3. c3 B-13：获取直链和投屏里，线路页能返回清晰度页；标出当前正在播的清晰度和线路；对勾用 `AppIcons.selected`。B-14：取消静音恢复到静音前的音量。
4. c4 画面比例：从菜单进和从横屏底栏进是同一个组件，当前项主色加勾。
5. A02.2 之后补充：`buttons/follow_button.dart` 取消关注（按钮写“取消关注”，确认后带“撤销”的提示条，B-15）；`dialogs/room_dialogs.dart` 定时关闭、房间音量；`dialogs/stream_dialogs.dart` 获取直链、投屏；`dialogs/player_dialogs.dart` 画面比例（从菜单进也用贴着按钮的小菜单）、画面方向；`danmaku/chat_list.dart` 屏蔽关键词输入（`showAppInputDialog`）、长按弹幕的底部表单（面板）；`mini/room_mini_window.dart` 无法打开画中画（`showAppMessageDialog`，带“去设置”）；`dialogs/iptv_guide.dart`、`record/record_panel.dart`、`danmaku/danmaku_settings_panel.dart` 没有直播间页面时的底部表单 → `showAdaptivePanel`；`local_interaction/local_style_panel.dart` 本地弹幕样式 → `RoomSidePanel` 或 `showAdaptivePanel`；`buttons/room_menu_button.dart` 右上角菜单换成 `AppMenuButton`（B-7）；全屏时提示条压在下栏上：全屏布局把提示条的下边距调到下栏以上。
6. 维护者已定（可放 A02.1 做）：设置类对话框主要按钮写明动作（“确认”改“保存”等）；剩下 3 个原生 `PopupMenuButton`（录制中心任务卡片“⋮”、字体管理“⋮”、翻页栏“每页条数”）换成 `showAppMenu`。
7. 这些弹窗在三种布局里样子和操作一致，不再压在全屏画面中间；房间音量和手势音量是同一个音量。测试：每个弹窗三种布局的位置；音量联动；直链和投屏的返回和当前项。
8. （阶段 3）在 K90 上照 `verify.md` 逐条通过，登记表改“完成”。

## 现状（读代码得出，写文件:行）

`apps/pure_live/lib/features/live_play/` 省略前缀：

- 面板：`layout/room_panel.dart:11`（`RoomPanelKind`）、`:84`（`showRoomPanelSheet`）；`live_play_page.dart:807`（`_panelOf`）、`:913`、`:935`、`:947`（三种位置）。
- 定时关闭 `dialogs/room_dialogs.dart:43`（`RoomSleepTimerPanel`）；房间音量 `:275`（`RoomVolumePanel`，`DeviceControls.available` `:294`，`unmuteFallbackVolume = 0.5` `:265`）。
- 获取直链、投屏 `dialogs/stream_dialogs.dart:50`（`RoomStreamPanel`，三页 `:41`）、`:290`（`CastDevices`）。
- 画面比例、方向 `dialogs/player_dialogs.dart:49`、`:83`。
- 右上角菜单 `buttons/room_menu_button.dart:316`（`AppMenuButton`）、`:308`（说明行）。
- 取消关注 `buttons/follow_button.dart:77-95`；`apps/pure_live/lib/shared/rooms/room_menu.dart:77`（`unfollowRoom`）、`:158`（首页卡片用的 `confirmUnfollowRoom`）。
- 长按弹幕 `danmaku/message_panel.dart:20`、`:50`（A07.11 后屏蔽关键词是第二页 `:81-95`）。
- 全屏提示条 `live_play_page.dart:967`（`_toastsAboveBars`）、`player/player_controls.dart:45`（`fullscreenBottomBarHeight`）。
- 手势音量 `player/player_gestures.dart:87`（`_reading`）、`:115-135`。

## 3.x 基线

- `git show v3.2.11:lib/modules/live_play/dialogs/room_timer_dialog.dart`、`room_volume_dialog.dart`、`known_room_link_dialog.dart`、`live_dlna_dialog.dart`：都是居中对话框（4.0.0 照搬）。
- `git show v3.2.11:lib/modules/live_play/widgets/video_player/video_controller.dart:823`：手机上调音量走系统音量（`_usesSystemVolume`）——c2 恢复的就是这个。
- `git show v3.2.11:lib/modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart:17-80`：方向对话框。
- `git show v3.2.11:lib/modules/live_play/widgets/danmaku/danmaku_message_actions.dart`：长按弹幕底部面板、屏蔽关键词对话框。
- 要保留的：每个弹窗的内容和功能一项不少（定时的 8 个时长和自定义、音量静音、清晰度和线路列表、DLNA 设备）；附录 A 第 6、7、10、18 条。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 4.1 节界面任务、第 5、8、10、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3 节第 7、8 条、第 7 节。
3. 本文件夹的 `README.md`（设计和实现）、`record.md`、`verify.md`；`docs/A-界面设计/A02-组件/A02.2-弹窗组件/README.md`；`docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗/README.md`（统一规则）。

## 范围

- 可以改（阶段 1、2 当时的范围）：`features/live_play/dialogs/`、`buttons/`、`player/`、`packages/live_cast`（只读）、`packages/live_ui`（只添加）、本文件夹；实现时另外必须改了 `layout/`、`live_play_page.dart`、`logic/`（新面板要在页面上挂、系统音量要给测试一个开关）。
- 阶段 3 只改本文件夹（`verify.md`、`verify/`）和登记表。
- 不能改：其他组的界面和逻辑（首页卡片的取消关注确认不在这里）；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1（已完成） | c1 出设计：18 张效果图、评审页 `page.json` 和 14 张章节导出图、README；N1～N5 按 A 定稿 | 本文件夹 | 设计定稿（按 D-003） |
| 2（已完成，`edd0da117`） | c2～c4 和 A02.2 之后补充的 1～10 条（补充 11 留给 A02.1） | 见“现状” | 各布局的位置和音量联动有测试；`features/live_play/` 里没有居中对话框和底部表单；门禁通过 |
| 3（待做） | 真机验证 | `verify.md`、`verify/`、`docs/tasks.toml` | `verify.md` 每条通过；维护者对“留下的问题”表态 |

## 测试

- 已有（阶段 2）：`apps/pure_live/test/features/live_play/room_popups_test.dart`（12 个）、`packages/live_ui/test/menu_additions_test.dart`（4 个），和 7 个已有测试文件里随设计改的断言（见 README“验证”）。
- 真机发现问题要修时：先写改之前会失败的测试；定时器至少 1 秒（房间音量面板每秒读一次系统音量，测试里用假的 `DeviceControls`）；不访问真实平台（投屏用假的设备列表）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 横屏全屏 → 四宫格 →“定时关闭”，点“30 分钟” | 右侧 360 面板，画面不变暗；开关打开，第二行“30 分钟后暂停（HH:mm）”；返回键关面板仍在全屏 |
| 2. 同一处“房间音量”，拖到 30%，关面板后画面右侧上下滑；按音量键；静音再取消 | 百分比和系统媒体音量一致；手势从 30% 起算；面板一秒内跟上音量键；取消静音回到静音前 |
| 3. 菜单“获取直链”（或横屏顶栏投屏） | 当前清晰度主色加勾写“正在播放”；← 能回清晰度页；获取直链点一条提示“已复制直链”并关面板 |
| 4. 横屏下栏方向按钮、画面比例按钮；竖屏菜单“画面比例” | 小菜单贴着按钮（下栏的在上方）；方向的“记住”拨动不关菜单；竖屏菜单里的画面比例贴着四宫格 |
| 5. 已关注时点“已关注”（竖屏顶栏、横屏下栏） | 贴着按钮的小菜单，红色“取消关注”；提示条“已取消关注 X · 撤销”，4 秒内能撤销 |
| 6. 横屏全屏复制直链或取消关注；竖屏全屏同样 | 提示条在下栏上方，不压住按钮 |

完整的表（11 条）和结果栏在 `verify.md`。

## 风险和注意

- 房间音量在 Android 上就是系统媒体音量：验证时会改手机的音量，验完调回原来的值。
- 投屏要同一个 Wi-Fi 下有电视或盒子；没有时只看设备页的“搜索中”“没找到”，写明跳过。
- 文件和别的任务共用：`live_play_page.dart`、`layout/room_panel.dart`、`player/player_controls.dart`、`player/player_gestures.dart`（A07.11、A07.14、A07.15）；`packages/live_ui` 的 `app_menu.dart`、`stream_menu_button.dart`、`app_dialog.dart`、`app_icons.dart`（A02.1）。
- 只点测试包；不碰 3.x（D-019）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 效果图（要改设计时）：`python3 docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/src/gen.py && python3 tools/ui/mock/render.py docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/src --annotate`；评审页 `python3 tools/ui/mock/page.py docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一/page.json`。
- 真机用的构建：master 上包含 `edd0da117` 的提交；在 `verify.md` 写清提交号。
- 要改代码时：分支 `ai/A07.12` 或本机工作区；提交信息以 `[A07.12]` 开头（英文）；不推 master；提交前 format、analyze、全部测试、`python3 tools/gate/check_ui_structure.py`、`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `next`、`branch`；真机做到一半时把已看的写进 `verify.md`。

## 报告（中文，简洁）

`verify.md` 每条的结果和截图；不通过的现象和根因线索（文件:行）；维护者对取消关注两种确认、剩下的“弹幕颜色”对话框的决定；登记表改了什么。
