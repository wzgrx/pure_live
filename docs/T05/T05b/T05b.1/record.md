# T01（直播间部分）+ T05b.1 竖屏直播间

- 日期：2026-10-01
- 设计：[docs/T05/T05b/T05b.1/README.md](README.md)（用户已确认）；计划书 [specs/UI.md](../../../specs/UI.md) 第 4–7、9 节
- 范围：`packages/live_ui`（只做添加）、`packages/live_store`（只加一个设置）、`apps/pure_live/lib/features/live_play/`、翻译文件、门禁基线
- 协调员补充（开工后）：直播间里点按钮弹出来的界面（录制选项、画质和线路列表、弹幕设置面板、右上角菜单及其子对话框）这次**保持原样**，等弹窗设计确认后另开任务（T05g.1）；菜单里照原任务新增“画面比例”，选择界面用现有的简单列表样式。
- 不往手机安装，没有改原生部分，没有构建 APK。

## 做了什么

### T01：设计系统里直播间要用的部分（`packages/live_ui`）

| 内容 | 文件 | 说明 |
|---|---|---|
| `AppIcons` | `lib/src/icons/app_icons.dart` | 按用途命名的图标入口，每个用途对应 v3 在该位置用的图标（Remix、Material、`CustomIcons.float_window` 0xe806，已对照字体核对） |
| `DanmakuIcon` | `lib/src/icons/danmaku_icon.dart` | v3 的 `danmu_open/close/setting.svg`（复制进 `assets/images/video/`，新依赖 `flutter_svg` 2.3.0，`remixicon` 4.9.3 已是最新），颜色和大小跟随图标主题，阴影用一份下移 1 像素的副本（不做模糊） |
| `RecordGlyph`、`RecordingBadge` | `lib/src/widgets/record_glyph.dart` | 录制按钮的“灰圈红点”“红底白点”（闪烁，系统要求减少动态效果时常亮）；“● 录制中 12:34”角标（等宽数字，紧凑形式只留红点和时间） |
| 颜色和文字角色 | `lib/src/theme/live_colors.dart` | `OnVideoColors`（画面上的前景白、次要白、60% 黑渐变、阴影、黄色“非默认”）、`LiveSemanticColors`（直播红 `#D92D20` 配白字、录制红、成功、警告，取归档 v4 已验算对比度的固定值）、`InkOnColor`（平台给的颜色上用深字还是浅字）、`tabular`/`regular`/`emphasis`（等宽数字、字重只用 400/600） |
| `ListenableSelector` | `lib/src/widgets/listenable_selector.dart` | 只在选中的那部分变化时重建（人数、时长、标题各自刷新，不随每条弹幕重建） |

### T05b.1：竖屏直播间（`features/live_play/`）

| 区域 | 文件 |
|---|---|
| 顶栏 | `layout/room_header.dart`、`buttons/follow_button.dart`、`buttons/record_button.dart`、`buttons/room_menu_button.dart` |
| 画面控制层 | `player/player_view.dart`、`player/player_controls.dart`、`player/player_status.dart`、`player/recording_badge.dart`、`player/player_gestures.dart` |
| 信息行 | `layout/room_info_bar.dart` |
| 直播间详情 | `layout/room_details.dart`、`logic/area_lookup.dart` |
| 标签和弹幕列表 | `danmaku/chat_panel.dart`、`danmaku/chat_list.dart` |
| 选择界面 | `dialogs/player_dialogs.dart`（画面比例、画面方向，简单列表） |
| 逻辑（新增，纯 Dart） | `logic/room_orientation.dart`（本直播间画面方向）、`logic/reconnect_watch.dart`（断流计数） |
| 逻辑（小改） | `logic/room_controller.dart`：系统消息同一句 3 秒内只显示一次（v3 `_addStatusMessage`）；新增 `blockKeyword` |
| 页面 | `live_play_page.dart`：布局、详情的开关、返回键顺序 |

旧的 `layout/room_panels.dart`（信息条、关注按钮、底部信息卡片）拆进上面几个文件后删除。

## 和设计稿的对照

### 改动清单

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| 1 | 顶栏主播名 15/600，“平台 · 分区” 12 次要色 | ✅ | |
| 2 | 画面上栏：标题 + 纯音频、投屏、小窗；竖屏也显示 | ✅ | 照 v3 `resolveTopActionTrailingSlots`：纯音频都有，投屏和小窗只在 Android（小窗还要设备支持画中画）；全屏另有返回和切换直播间 |
| 3 | 渐变 60% 黑并向画面内延伸，图标加淡阴影 | ✅ | 栏外再延伸 28；渐变层不挡点击，点到画面照常显示/隐藏控制层 |
| 4 | 竖屏下栏：播放/暂停、刷新、弹幕开关、弹幕设置｜方向、全屏；没有“已关注” | ✅ | 弹幕开关和设置用 v3 的 SVG；弹幕设置按钮打开现有的弹幕设置面板（底部面板，样式不变）；全局弹幕显示关闭时两个弹幕按钮不显示（v3 同） |
| 5 | 画面比例移到全屏下栏，菜单里加“画面比例” | ✅ | 全屏下栏是 v3 的文字按钮（点一下换下一种）；菜单项打开六种比例的列表 |
| 6 | 信息行第一行：回放/受限标签 + 标题 + “详情 ⌄”；点这一行展开详情 | ✅ | 展开后变“收起 ⌃” |
| 7 | 信息行第二行：在线/热度/累计观看（平台给几个显示几个）+ 开播时长，等宽数字 | ✅ | 图标 + 数字，口径名放在提示里；时长 `H:MM`，自己每 20 秒刷新 |
| 8 | 画质、线路改成带下拉箭头的按钮，点击区域 48 | ✅ | 按钮高 32，触控高 48；弹出的列表不变 |
| 9 | “醒目留言”显示条数 | ✅ | 窄的右侧栏里条数改成角标，不截断文字 |
| 10 | 系统消息居中灰色小标签 | ✅ | 同一句 3 秒内一次 |
| 11 | 弹幕列表默认紧凑行 | ✅ | “用户名：”次要色，弹幕有颜色时用该颜色（按深浅主题调亮度保证看得清）；内容正常色；表情图片照旧 |
| 12 | 关注：未关注“＋ 关注”主色实心，已关注“✓ 已关注”灰色 | ✅ | 处理中转圈；确认框期间不转圈 |
| 13 | 录制：灰圈红点 / “自动录” / 红底白点闪烁 + 角标 | ✅ | 角标在控制层显示时放在上栏标题前，隐藏时左上角只留红点和计时；全屏、画中画也有 |

### 直播间详情

| 要求 | 做到 | 说明 |
|---|---|---|
| 盖在信息行下面的标签和弹幕区，不盖画面，不加整屏遮罩 | ✅ | 宽屏时盖在右侧聊天栏上 |
| 主播（头像、名字、平台图标、可点的分区、关注按钮） | ✅ | 房间只带分区名，点分区时从平台的分区列表按名字找到分区，再用路由打开分区房间页；找不到时提示 |
| 状态行（红底“直播”+ 开播时间 + 已播时长；回放、未开播、受限相应变化，受限附原因） | ✅ | “今天 19:18 开播 · 已播 2 小时 18 分”；昨天、更早写日期 |
| 完整标题（最多三行） | ✅ | |
| 四格数字（在线、热度、累计观看、已开播，只显示平台有的） | ✅ | |
| 公告、简介（各两行，可展开） | ✅ | 简介和公告相同时不重复 |
| 房间号、链接（复制） | ✅ | |
| 分享、在平台打开 | ✅ | 没有官方网页的房间（网络电视）不显示 |
| 关闭：收起、再点信息行、下拉、返回键 | ✅ | 返回键和 Esc 的顺序：全屏 → 详情 → 离开 |
| 关注按钮和顶栏同步 | ✅ | 两处读同一个关注状态 |

### 其他优化

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| E1 | 点顶栏头像或名字展开详情 | ✅ | 菜单里“直播间信息”也打开详情 |
| E2 | 进房时名字、信息行、人数先显示占位 | ✅ | 静止的灰条，没有扫光 |
| E3 | 断流时“正在重连（第 N 次）”+“换线路” | ✅（有偏差） | 播放会话没有公开重连次数（只有“缓冲中”状态），见“没做的” |
| E4 | 第一次关画面弹幕提示一次“列表照常显示” | ✅ | 记在 `meta` 的 `live_play.danmakuOffHinted` |
| E5 | 纯音频时封面 + “纯音频播放中” | ✅ | 封面上盖 70% 黑纯色，不用透明度层 |
| E6 | 方向不是“自动”时图标变黄，长按显示当前设置 | ✅ | 长按提示“画面方向：强制横屏”；方向按房间记在 3.x 的 `portraitRoomOverrides`（“记住单个直播间方向”关闭时只在本次运行有效） |

### 选择

| 编号 | 决定 | 做到 |
|---|---|---|
| A | 弹幕列表默认紧凑行，卡片样式做成设置项 | ✅ 设置“弹幕列表样式：紧凑 / 卡片”，卡片照 v3 `DanmakuItem`（改用主题表面色） |
| B | 菜单保留 v3 四宫格 | ✅ |
| C | 竖屏下栏去掉“已关注”，全屏显示 | ✅ 全屏宽度不足 600 时也不显示（v3 的 `compact`） |
| D | 取消关注先确认 | ✅ 顶栏、详情、全屏三处都确认 |

### 弹幕列表（任务说明里的要求）

| 要求 | 做到 |
|---|---|
| 长按/右键菜单：复制、屏蔽此用户、屏蔽关键词（补上 v3 有而 v4 缺的） | ✅ 屏蔽关键词先弹输入框（预填弹幕内容），加入后列表里含该词的弹幕去掉 |
| 双击复制 | ✅ 复制“用户名: 内容”（v3） |
| “N 条新弹幕”按钮照 v3 | ✅ 右下角主色按钮；没有新弹幕时写“回到底部” |
| 四个等宽标签 | ✅ |
| 详情打开期间来的新弹幕数显示在“弹幕列表”上 | ✅ 关闭详情后显示，点标签或碰列表后消失 |

### 性能（计划书第 7 节）

- 画面、飞行弹幕、控制层各自 `RepaintBoundary`；控制层显隐只在 200 毫秒动画期间有透明度层。
- 人数、开播时长、录制计时、标题、纯音频按钮各自订阅（`ListenableSelector`、独立计时器），每条弹幕只重建弹幕列表和未读数。
- 没有模糊；纯音频和未开播的封面改成“图片 + 纯色遮罩”，去掉了原来的 `Opacity`。
- 视频不裁圆角。

## 新设置项

| 键 | 值 | 默认 | 说明 |
|---|---|---|---|
| `danmakuListStyle`（`danmaku` 分区，随备份） | `compact` / `card` | `compact` | 弹幕列表样式；v4 新增（3.x 只有卡片）。设置入口在直播间的“弹幕设置”标签和画面上的弹幕设置面板 |

另外开始使用 3.x 已有、v4 之前没用上的 `portraitRoomOverrides`、`rememberPortraitRoomOverride`（画面方向按钮）。

## 门禁

- `live_play` 里直接写的颜色和图标：**115 → 28**，`tools/gate/ui_baseline.json` 已改为 28。
- 剩下的 28 处都在这次按协调员要求保持原样的弹窗里：录制选项面板 6、菜单项 11、弹幕观看模板卡片 2、`dialogs/`（房间音量、节目单、切换直播间、获取直链/投屏）9。等弹窗设计确认（T05g.1）后换成 `AppIcons`。
- 没有新增跨功能引用（`live_play -> recorder/recorder_texts.dart` 是 T00b.1 前就有的）；`logic/` 没有引用 material。

## v3 文件 → v4 文件

| v3（`lib/modules/live_play/`） | v4（`features/live_play/`） |
|---|---|
| `widgets/layout/live_play_header.dart` | `layout/room_header.dart` |
| `widgets/button/favorite_floating_button.dart`、`video_controller_panel.dart` 的 `FavoriteButton` | `buttons/follow_button.dart` |
| `widgets/button/record_action_button.dart`、`record_action_content.dart` | `buttons/record_button.dart`（按钮样子）＋ `live_ui` 的 `RecordGlyph` |
| `widgets/button/live_play_menu_button.dart` | `buttons/room_menu_button.dart` |
| `video_controller_panel.dart` 的 `TopActionBar`、`BottomActionBar` 和各按钮 | `player/player_controls.dart` |
| `video_controller_panel.dart` 的 `ErrorWidget`、`placeholder/not_living_video_widget.dart`、`playback_failure_overlay.dart` | `player/player_status.dart` |
| `video_controller_panel.dart` 的 `BrightnessVolumnDargArea` | `player/player_gestures.dart` |
| `video_player/video_player.dart` | `player/player_view.dart` |
| `video_player/portrait_playback_picker_dialog.dart`、`common/services/settings/player_settings_controller.dart` 的方向部分 | `dialogs/player_dialogs.dart`、`logic/room_orientation.dart` |
| `resolution_selector/*`（`resolutions_row`、`audience_info`、`resolution_selector`、`line_selector`） | `layout/room_info_bar.dart` |
| （无，v4 原来是底部信息卡片） | `layout/room_details.dart` |
| `widgets/danmaku/danmaku_list_view.dart`、`danmaku_message_actions.dart` | `danmaku/chat_list.dart` |
| `widgets/danmaku/danmaku_tab.dart`、`pages/super_chat_page.dart`、`pages/keyword_block_page.dart` | `danmaku/chat_panel.dart` |
| `widgets/layout/live_play_content.dart`（竖屏堆叠、宽屏左右分栏） | `live_play_page.dart` |
| `controllers/danmaku_controller.dart` 的 `_addStatusMessage` | `logic/room_controller.dart` |
| `assets/images/video/danmu_*.svg`、`common/widgets/custom_icons.dart` | `packages/live_ui`：`DanmakuIcon`、`AppIcons` |

## 没做的和原因

1. **弹窗保持原样**（协调员要求）：录制选项面板、画质线路列表、弹幕设置面板、菜单项和各子对话框的外观和行为不变（菜单只加“画面比例”，“直播间信息”改为打开新的详情）。留给 T05g.1。
2. **E3 的次数**：播放会话（`live_player`）自己重连（刷新地址、换线路、有限次重试），但重连次数是私有的，状态里只有“缓冲中”。这次不改 `live_player`，由 `ReconnectWatch` 在界面侧计数：播放中的流变成缓冲/打开、且不是用户换画质或线路时算一次，连续播放 30 秒后从 1 重新计。短暂卡顿也会显示“正在重连（第 1 次）”。准确次数要等 `live_player` 公开重连状态。
3. **“弹幕列表样式”只在直播间里能改**：全局设置页属于 `features/settings`，这次不改其他功能目录，留给 T09。
4. **全屏的时间电量、本地弹幕输入框、Windows 音量和“窗口内全屏”按钮**：属于 T05d.1/U.2d；锁定按钮暂时留在全屏下栏左侧（v3 是画面左侧单独一个）。
5. **小窗按钮只在 Android**：v4 只有 Android 的系统画中画，v3 的 Windows 小窗还没有。
6. **飞行弹幕层**仍在 `shared/danmaku` 里用 `Opacity` 画透明度：属于 T06c.1（弹幕渲染选型）。
7. **外观截图测试**（计划书第 9 节）没加：截图测试需要固定字体，统一在后面搭；这次只在本机用文泉驿字体渲染了竖屏、详情、卡片、宽屏、全屏五张图核对布局，没有提交。
8. **提交按区域分组**（T01、弹幕列表、顶栏、控制层、信息行和详情、测试、文档），中间几个提交单独构建不一定通过，只验证了最终状态。

## 测试

- `live_ui`：新增 `test/design_system_test.dart` 6 个（`AppIcons` 映射、`DanmakuIcon` 三态、`RecordGlyph` 两态和减少动态效果、`RecordingBadge`、`ListenableSelector`、颜色角色）；包内共 45 个，全部通过。
- `live_store`：32 个全部通过。
- `apps/pure_live`：新增 `test/features/live_play/live_play_room_test.dart` 14 个（11 个界面 + 3 个逻辑）：
  - 顶栏顺序、名字字号字重、关注三种状态和取消确认；
  - 竖屏上栏、下栏从左到右的按钮和图标，渐变，E4，E6；
  - 全屏上栏、下栏（已关注、画质、线路、比例）；
  - 信息行内容（等宽数字、时长、下拉按钮 32/48）；
  - E2 占位；
  - 详情不盖画面、内容、关注同步、返回键先关、点名字打开、收起、下拉关闭；宽屏盖在聊天栏、找不到分区；
  - 紧凑行和系统小标签、详情期间的新弹幕数、醒目留言条数、卡片样式设置；
  - 双击复制、长按屏蔽关键词；
  - 菜单里的“画面比例”；
  - E3 重连和换线路、E5 纯音频；
  - `ReconnectWatch`、画面方向的记住与不记住、按名字找分区、时间文字、上栏按钮位置。
- 录制按钮三种状态和录制角标在 `test/features/recorder/recorder_page_test.dart`（替换了 T15b.1 的旧断言）。
- 全部测试：`apps/pure_live` 258 个通过；第二次全量运行时 `services_test.dart` 的日志文件用例（`AppLog` 打开文件的时机）失败一次，和本任务无关，单独重跑三次都通过。`flutter analyze` 无问题；`check_ui_structure.py`、`check_deps.py`、`check_fixtures.py` 通过。

### 和新设计冲突、照实改了的原有断言

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `live_play_page_test` 手机布局 | “哔哩哔哩 / 英雄联盟” | “哔哩哔哩 · 英雄联盟” | 改动 1 |
| 同上 | “热度 12.0万” | 数字“12.0万”，口径“热度”在提示里 | 改动 7 |
| 同上 | 关注后是实心心形 | “✓ 已关注” | 改动 12 |
| `live_play_page_test` 信息卡片 | 底部卡片里的“开播时间”“已开播 30 分钟”，点外面关闭 | 信息行“0:30”，详情里“已播 30 分钟”，返回键关闭 | 直播间详情取代底部卡片；改动 7 |
| `live_play_page_test` 画中画回来 | 下栏衬底是 `Container`、起点 70% 黑 | `DecoratedBox`、起点 60% 黑 | 改动 3 |
| `live_play_more_page_test` 纯音频 | “纯音频模式”、`headphones_rounded` | “纯音频播放中”、v3 的 `Remix.headphone_fill` | E5、改动 2 |
| `recorder_page_test` 录制按钮 | T15b.1 的圆环图标 + 橙点徽标 | 灰圈红点、“自动录”、红底白点、角标 | 改动 13 |
