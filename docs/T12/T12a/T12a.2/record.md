# T12a.2 多画面

- 日期：2026-10-01
- 设计：[docs/T12/T12a/T12a.2/README.md](README.md)（用户已确认；待选 W1～W4 按建议 A 做）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、7、8、9 节，附录 A 第 7、13 条
- 范围：`apps/pure_live/lib/features/multiview/`（重做）、`apps/pure_live/lib/shared/`（从直播间移来的共用部分）、`packages/live_ui`（只做添加：T05g.1 的小菜单按钮移入，多画面的图标和画面上的两个颜色角色）、翻译文件、门禁基线、文档
- 直播间本身没有改：只把多画面要用的 T05g.1 组件移出 `features/live_play`，直播间的引用跟着改（见“移动的组件”）
- 没有改原生部分，没有构建 APK；没有往手机安装

## 逐条对照

### 改动 c1～c15

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留：入口、四种布局（默认 2×2）、点格子换声音来源、1+3 点小格变大格、长按 / 右键、点空格选台、选台内容、沉浸和全屏（手机全屏自动横屏）、返回和 Esc 先退模式、弹幕只在声音来源格（1+3 是大格）、格数上限、小格省流、房间音量记住 | ✅ | 入口（首页菜单、宽屏导航栏）没有动；格数上限改为按设备能力（见下面“性能”） |
| c2 | 竖屏：格子按 16:9 在上（1×2 上下排、1+3 大格在上三小格一排），下面是选中格的控制和选台 | ✅ | 画面区高度按宽度算，最多占页面一半（1×2 上下两格时格子相应缩小）；控制在上、选台在下 |
| c3 | 横屏和宽屏右栏：宽屏 360 同时放控制和选台；横屏手机平时放控制，点空格或“换台”换成选台（✕ 回到控制）；按宽度不按平台；能收起 | ✅ | 宽度 ≥840 按宽屏排（平板、电脑一样），高度 <480 且横向按横屏手机排；横屏手机右栏宽度 = 页面宽度 − 画面区宽度（240～360）。收起把手在画面区右边缘中间（22×56） |
| c4 | 选中格的控制一处齐全：清晰度、线路（T05g.1 两个按钮和小菜单）、暂停、刷新、换台、关闭这一格、房间音量；点哪一格就是哪一格（同时成为声音来源） | ✅ | 竖屏：房间行右边“原画 ⌄”“线路1 ⌄”，下一行五个按钮 + 音量；右栏和全屏面板里每样一行。音量拖动即时生效，松手保存到房间音量（3.x 同一个存储键） |
| c5 | 进入直播间 | ✅ | 打开前暂停所有格，回来后继续（v4 已有） |
| c6 | 格子编号、声音来源 2 像素描边、选台目标虚线框“正在为这一格选台” | ✅ | 描边和虚线用 `OnVideoColors.accent`（主色的浅色调，深浅主题都一样，画面区总是黑底） |
| c7 | 空格、解析中、未开播、出错都是黑底白字，深浅主题一样 | ✅ | |
| c8 | 暂停的格子压暗并写“已暂停” | ✅ | |
| c9 | 已在格子里的直播间标“第 N 格”、排最后、点了选中那一格（W4） | ✅ | 同时提示“这个直播间已在第 N 格播放”（v4 已有的提示，T12a.2-k） |
| c10 | 工具条一行：布局（手机只写文字，宽屏带图标）、弹幕开关和弹幕设置（直播间的两个图标，开着时浅色底）、全部静音；小格省流只在 1+3 出现，小格上标“省流”；音量挪进选中格；横屏手机工具条并进顶栏 | ✅ | 全部静音的图标照设计图：有声时 `volume_up_line`，静音时 `volume_mute_line`（主色容器底） |
| c11 | 弹幕设置用 T05g.1 的面板，竖屏在画面下方、横屏和宽屏在右侧；所有布局都能打开 | ✅ | 标题旁写“只在声音来源这一格显示 · 改动立即生效”；内容就是直播间的 `DanmakuSettingsContent`（没有“弹幕列表”一组，多画面没有聊天列表） |
| c12 | 沉浸和全屏的退出按钮同一位置（左上角）、同一样子；落在黑边里 | ✅ | 安全区内 12、48 圆形；16:9 屏幕没有黑边时，被按钮盖住的格子把编号和名字右移（拿不准第 2 条） |
| c13 | 沉浸 / 全屏时长按 / 右键格子打开格子面板（内容同选中格的控制），横屏在右侧、竖屏在下方 | ✅ | 同 T05g.1 的面板组件，浮在画面上时带圆角；点空格时同一位置打开选台面板 |
| c14 | 1+3 大画面控制条只在沉浸 / 全屏出现，清晰度线路换成两个按钮和小菜单（W3） | ✅ | 按钮顺序照 v3：暂停、刷新、弹幕、弹幕设置、原画 ⌄、线路1 ⌄、音量（打开格子面板）、全屏；放不下时横向滑动 |
| c15 | 按父组件宽高排 | ✅ | 页面和画面区都用 `LayoutBuilder` |

### 待选和拿不准的地方

| 编号 | 处理 |
|---|---|
| W1～W4 | 都按 A |
| 拿不准 1（竖屏 2×2 每格小） | 照设计 2×2；窄格子里声音来源角标宽度不够 160 时只留图标 |
| 拿不准 2（16:9 屏幕没有黑边） | 名字右移避开退出按钮（`nameInset`） |
| 拿不准 3（恢复上次的提示） | 保留，在格子上方 |
| 拿不准 4（“正在直播”的颜色） | 绿点照旧，颜色用语义色“成功绿”（v3 的 `#31C24C` 白底上对比只有约 2.4:1）；T07d.1 定了直播标记再跟着改 |
| 拿不准 5（电脑 1+3 超过 4 格） | 1+3 在“小格在下”和“小格在右”两种排法里取大格更大的一种：1280×800 的宽屏是小格在大格下面一排（不和右栏并排），横屏手机和全屏是小格在右边一列 |

### 协调员补充（多格的播放器）

| 要求 | 做到 | 说明 |
|---|---|---|
| 最大格数按设备能力（计划书 9.3） | ✅ | `multiviewMaxCells`：手机 4 格（照 v3，四种布局都要 4 格）；电脑 8 个处理器以上 9 格（v3），6～7 个 6 格，更少 4 格 |
| 看不见的格子暂停解码 | ✅ | 1+3 小格那一列滚出视野的格子、应用整个被隐藏（切到后台、窗口最小化）时的所有格子：关掉视频解码（只留声音，静音的格本来就是 0 音量）、停掉画面停住检测；回到视野再打开。用的是会话已有的 `setAudioOnly` 和 `setPresentationVisible`（T12a.1 记下的“留给后续”） |
| 小格自动降画质 | ✅（照 v3） | 就是“小格省流”：1+3 里小格自动用最低清晰度，变成大格时换回正常清晰度（按钮 8 的说明）；Windows 照 v3 按格子实际像素设输出尺寸。没有另加“按格子大小自动降清晰度”，见文末“需要决定的事” |
| v3 已有的照旧 | ✅ | 每格只挂一次画面（`GlobalKey`，换布局、晋升大格、横竖屏切换都是移动）；弹幕只在一个格子 |

另外：拖动音量时不再让整页重建（控制器只在松手保存时通知）。

## 和 v3 / v4 的差别（偏差和原因）

1. **格子菜单变成选中格的控制**（设计的对照）：长按菜单的换台、选择清晰度、关闭该格 → 选中格的换台、原画 ⌄、关闭这一格。普通模式下长按 / 右键 = 选中这一格（下方 / 右栏显示它的控制，不改声音来源）；沉浸和全屏下长按打开格子面板。未开播、失败的格子也能长按，用“刷新”重新检查、“关闭这一格”关掉。
2. **去掉了 v4 格子右上角的“更多”按钮**和其中的“播放这一格的声音”（就是点格子）；去掉了未开播格子里的“重新检查”按钮：点未开播格子照 v3 重新选台，重新检查用选中格的“刷新”（设计写的“并进未开播格子的点击”）。
3. **去掉了 v3 1+3 大格左下角的清晰度小入口**：平时在下方 / 右栏，沉浸 / 全屏在大格控制条里，同一个小菜单。
4. **按钮 40、工具条开关 38**：照设计图尺寸（竖屏一行放五个按钮加音量），比计划书 5.4 的 48 小；控制条按钮仍是 48。
5. **横屏手机选台连续进行**：有空格时选完一个直播间选台留在右栏，目标跳到下一个空格；格子都满了回到控制。
6. **全部格子满时**：选台目标是选中的格子，标题“第 N 格换台 / 点直播间换掉“X””（设计图 1+3 的样子）；这时不画虚线框。
7. **未开播的文字**：普通下播照 v3 写“该直播间未开播”；封禁、轮播、状态不明保留 v4 的说明。
8. **1+3 的排法**：按大格面积选“小格在下”或“小格在右”（上面拿不准 5）。

## 移动的组件（只做移动和参数化）

| 原位置（`features/live_play`） | 新位置 | 说明 |
|---|---|---|
| `buttons/stream_menu.dart` 的 `StreamMenuButton`、`streamMenuMinWidth` | `packages/live_ui/lib/src/widgets/stream_menu_button.dart` | 原样移动；`StreamPickers`（直播间的两个按钮）留在原处 |
| `layout/room_panel.dart` 的 `RoomSidePanel`、`PanelLink`、`PanelGroupTitle`、`PanelCard`、`roomSidePanelWidth` | `lib/shared/panels/side_panel.dart` | `RoomSidePanel` 加可选圆角；`room_panel.dart` 再导出它们，直播间各文件的引用不用改 |
| `danmaku/danmaku_settings_panel.dart` 的设置内容、行组件、`danmakuFontWeightNames`、`danmakuTemplateDescription` | `lib/shared/danmaku/danmaku_settings_content.dart`（`DanmakuSettingsContent`，`extra` 放额外的组） | 直播间的 `RoomDanmakuSettings` 名字和键不变，把“弹幕列表”一组作为 `extra` 传进去 |
| `danmaku/danmaku_templates.dart` | `lib/shared/danmaku/danmaku_templates.dart` | 原样移动 |
| `logic/record_state.dart` 的 `resolvedDanmakuFps` | `lib/shared/danmaku/danmaku_templates.dart` | 原样移动 |
| `lib/shared/danmaku/danmaku_settings.dart` 的旧 `DanmakuSettingsPanel` | 删除 | 只有旧多画面在用 |

测试里跟着改了两处 import（`live_play_more_test`、`live_play_popups_test`）。

## v3 文件 → v4 文件

| v3（`lib/modules/multiview/`） | v4（`features/multiview/`） |
|---|---|
| `multiview_page.dart`（显示模式、顶栏、工具条、格子区、1+3、大画面控制条、各底部面板） | `multiview_page.dart`（排法、选中和选台目标、面板、返回链）、`widgets/toolbar.dart`、`widgets/wall.dart`、`widgets/focus_bar.dart`、`widgets/cell_controls.dart` |
| `multiview_page.dart` 的 `_MultiviewCellView`、`_AddCellSlot` | `widgets/cell_view.dart` |
| `widgets/multiview_room_picker.dart` | `widgets/room_picker.dart` |
| `widgets/multiview_fullscreen_surface.dart` | `multiview_page.dart` 的沉浸 / 全屏部分（`_ExitButton`） |
| `widgets/focus_rail_visibility.dart` | `logic/multiview_geometry.dart`（`visibleRailRange`，格子位置 `WallGeometry`，格数 `multiviewMaxCells`） |
| `multiview_controller.dart` | `logic/multiview_controller.dart`（加了 `setOffscreen`） |

## 新设置、存储

没有新设置；存储键都没改（房间音量 `roomVolumes`、上次的画面 `multiview.session`）。

## 新增的文字

翻译文件中英各加 11 条：`multiview_close_this_cell`、`multiview_danmaku_panel_hint`、`multiview_fold_column`、`multiview_unfold_column`、`multiview_opening`、`multiview_pick_hint`、`multiview_pick_target`、`multiview_pick_title`、`multiview_replace_hint`、`multiview_replace_title`、`multiview_saver_mark`。旧键没有删。

## 门禁

- `multiview` 直接写的颜色和图标：**71 → 0**，`tools/gate/ui_baseline.json` 去掉了这一项；`live_play` 仍是 9。
- `live_ui` 只做添加：`AppIcons` 加多画面的 26 个用途（字形照 v3 该位置），`OnVideoColors.error`、`OnVideoColors.accent`，`StreamMenuButton`（移入）。
- 没有新增跨功能引用；`logic/` 不引 material。

## 测试

- `apps/pure_live`：全部 286 个通过（T05g.1 后 278 个）；`flutter analyze` 无问题；`check_ui_structure.py` 通过。多画面 15 个（原来 7 个）：
  - `multiview_page_test.dart`（5）：竖屏（工具条顺序、无图标、弹幕图片、无省流；格子 16:9、编号、黑底、目标虚线；选台后声音来源描边和角标、下一个目标；控制的房间行、两个菜单按钮、五个按钮的顺序和图标、音量；“第 N 格”排最后并选中；附录 A 13 点格子换声音、长按选中不换声音；清晰度小菜单；已暂停；换台标题；关闭这一格；弹幕设置面板在画面下方、返回先关面板；沉浸退出按钮在左上角、返回回到普通）；竖屏 1+3（大格在上、三小格一排、平时没有控制条、省流标记、点小格晋升、应用隐藏时所有格停解码）；横屏手机（工具条在顶栏、右栏位置和宽度、连续选台、点格子显示控制、空格换成选台和返回、收起展开、全屏退出按钮位置和不盖格子、长按面板在右侧 360、Esc 依次关面板和退全屏）；宽屏（布局带图标、右栏 360 控制在选台上方、1+3 加到 9 格、滚出视野的格停解码和滚回来恢复、全屏大格控制条顺序、音量打开格子面板、弹幕设置面板 360、Esc 链）；格子状态（深色主题下未开播和失败的文字、错误色、点未开播格重新选台、长按后刷新恢复）。
  - `multiview_geometry_test.dart`（4）：格数按设备、可见范围、竖屏和横屏的格子位置都是 16:9。
  - `multiview_controller_test.dart` 新增 1：看不见的格只有声音、新流也不开视频、回来恢复。
- `packages/live_ui`：46 个（新增 `OnVideoColors.accent`；`AppIcons` 对照表加了这次的图标）。
- 原有测试和新设计冲突、照实改了的：`multiview_page_test` 的两个旧用例整体重写——旧的“更多”按钮和底部菜单、“为格子 N 选台”的文字、1+3 平时的清晰度入口和控制条都按设计去掉或改了（见上面的偏差 1～3）。
- 没有在真机上看帧时间（不往手机安装）；本地用测试渲染了竖屏、横屏、宽屏、深色、沉浸和全屏的截图核对排版。

## 需要决定的事

1. “小格自动降画质”按“小格省流”（v3，用户手动打开）理解；如果要的是“格子小到一定尺寸就自动选低清晰度”（不用开关），需要再定阈值和是否默认打开。
2. 竖屏控制的按钮 40、工具条开关 38（照设计图），比计划书的 48 小。
3. 合并提醒：另一个代理在改直播间排法，这次动了 `features/live_play` 的 `buttons/stream_menu.dart`、`danmaku/danmaku_settings_panel.dart`、`layout/room_panel.dart`、`logic/record_state.dart`，并移走了 `danmaku/danmaku_templates.dart`（第一个提交，只做移动）。
