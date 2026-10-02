# T05c.1 竖屏流和竖屏全屏

- 日期：2026-10-01
- 设计：[docs/T05/T05c/T05c.1/README.md](README.md)（第 1 版，用户已确认；X1～X4 按建议 A）
- 和 T05d.1、T05e.1 一起做，控制层是同一个组件的“内嵌”和“竖屏全屏”排法；共用部分见 [T05d.1 的记录](../../T05d/T05d.1/record.md)。
- 改动的目录：`apps/pure_live/lib/features/live_play/`、`packages/live_ui`（`AmbientBackdrop`）、`packages/live_player`（`LiveVideoView.fill`）、翻译文件、文档。

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 三档面板、起始档、拖动吸附、拖过最低档或点把手进竖屏全屏、把手提示、双击、底部上滑恢复、进入提示、四种画面模式、方向和“记住”、设置页、只在手机上有竖屏全屏 | ✅ | `layout/portrait_panel.dart` 照 v3 `PortraitLiveRoomLayout`：44% / 68%、“均衡”从中档、“沉浸”从最低档；松手吸附最近一档；最低档再往下拖超过面板 30%（72–144）或快速下滑（≥900 且 ≥28）进竖屏全屏；无障碍的“增大 / 减小”和点按照旧。竖屏全屏底部 96 内或下栏上滑 ≥64（或快速上滑）恢复面板。“竖屏直播适配”设置页的设置项全部照旧生效（页面没动）。竖屏全屏在 Android 和 iOS（手机、平板）有，电脑没有 |
| c2 | 控制层、飞行弹幕、加载出错、亮度音量只排在面板上方；下栏贴面板上沿；松手后才改一次 | ✅ | `RoomPlayer.overlayBottom`：画面铺满，覆盖层只在露出的部分；拖动中不变，松手吸附时改一次 |
| c3 | “横屏全屏”挪到把手行右边 | ✅ | 32 高灰色胶囊（`surfaceContainerHighest`），点击区 48；一次性横屏，退出后转回竖屏再放开方向（附录 A 第 11 条，3 秒后放开） |
| c4 | 面板内容换成 T05b.1 的信息行、标签、紧凑弹幕；顶角 16；最低档 250 | ✅ | 最低档 250（把手 48 + 两行信息 92 + 标签 48 + 两条弹幕 62）；本地互动开着时弹幕列表下面多 T06f.1 的输入框一行，最低档加 72（322），仍露出两条弹幕；区域再小时不超过区域高度 |
| c5 | 全屏按钮在竖屏流里进竖屏全屏；手机上竖屏源全屏只有竖屏全屏一种排法（含“兼容 16:9”） | ✅ | 全屏按钮、双击、F 都一样；“兼容 16:9”布局下竖屏源点全屏也是竖屏全屏，退出回到 16:9 排法。“进入全屏时的方向”设成“始终横屏”时照设置走横屏全屏（两边沉浸背景）；“跟随系统”时不锁方向，屏幕竖着就是竖屏全屏的排法 |
| c6 | 竖屏全屏上方两行 | ✅ | 第一行：返回、标题（看得到七八个字）、关注胶囊、录制、菜单；第二行：时间电量在左，切换直播间、纯音频、投屏、小窗在右 |
| c7 | 下方两行 | ✅ | 第一行：本地弹幕输入框（本地互动开着时，T06f.1 提供）、原画 ⌄、线路1 ⌄（没有输入框时两个按钮靠右）；第二行：播放、刷新、弹幕开关、弹幕设置｜画面模式、方向、退出全屏 |
| c8 | 画面模式按钮固定“画面比例”图标，非默认变黄 | ✅ | `AppIcons.aspectRatio`；不是“沉浸背景”时 `OnVideoColors.active` |
| c9 | 画面模式改成贴按钮的小菜单 | ✅ | 标题“竖屏全屏画面模式”，四项各带 v3 的说明，当前项主色加勾；画面不变暗；在按钮上方，选了就关、马上生效 |
| c10 | 方向对话框：每项说明、主色加勾、“记住”一拨就生效、“关闭” | ✅ | 新加三行说明（照设计图的文字）；`RoomOrientationChoice.setRemember` 拨动开关时就把本直播间当前的方向在“本次运行”和“记住”之间移动 |
| c11 | 渐变 60%，切换直播间去掉圆底 | ✅ | 同 T05d.1 |
| c12 | 沉浸背景不每帧模糊 | ✅ | `live_ui` 的 `AmbientBackdrop`：v3 的兜底渐变 + 封面按 24 像素宽解码一次、用平滑缩放放大 1.14 倍铺满（缩小这一步就是一次模糊）+ 15% 黑；没有 `ImageFiltered`。画面层用透明底（`LiveVideoView.fill`），否则 media_kit 默认的黑底会盖住背景 |
| c13 | 宽屏里竖屏流用满画面区高度，两边沉浸背景 | ✅ | 不再放进 16:9 框；横屏全屏里的竖屏流同样两边沉浸背景（固定沉浸背景，不看画面模式设置，v3 同） |
| c14 | 竖屏全屏上下滑换台（C-9，X1 选 A，设置开关默认关） | ❌ 没做 | 需要的几块都不在这个任务能改的范围：①换台顺序是“从哪个列表进来就在哪个列表里换”，要关注、热门、分区、搜索各页把列表随路由传进来（别的功能目录）；②开关放在设置页“竖屏直播适配”（`features/settings`，T09a.4）。建议另开一个小任务：路由参数加列表（参照电视的 `TvRoomArgs.playlist`）、设置页加开关、直播间加中间竖条手势和下一个直播间的预览 |

### 选择

| 编号 | 决定 | 做到 |
|---|---|---|
| X1 | 上下滑换台做成开关，默认关 | ❌ 见 c14 |
| X2 | “横屏全屏”在把手行右边 | ✅ |
| X3 | 画面模式用小菜单 | ✅ |
| X4 | 画面模式固定“画面比例”图标 | ✅ |

### 各客户端

| 客户端 | 做到 |
|---|---|
| Android 手机 | 三档面板、竖屏全屏、横屏全屏 |
| 600–839 宽（竖着拿的平板、窄窗口） | 手机排法和三档面板；Android 平板也有竖屏全屏 |
| 宽屏 | T05e.1 分栏，竖屏流用满高度、两边沉浸背景；全屏是横屏排法加沉浸背景 |
| 电脑窄窗口 | 三档面板；把手行只有拖动横条，右边按钮叫“全屏”；没有竖屏全屏 |
| iPhone | 同 Android（安全区由 `SafeArea` 处理）；没有构建 |

### 跨任务待同步

| 来源 | 内容 | 做到 |
|---|---|---|
| T05c.1 → T05g.1 | 竖屏全屏时打开录制、弹幕设置等面板放在底部 | ✅ 竖屏全屏时面板从底部升起，占屏幕下方 60% |

## 新增的文字

方向对话框三项的说明（`live_play_orientation_*_desc`）。其余照 v3（`portrait_fullscreen_enter_hint`、`portrait_fullscreen_restore_hint`、`enter_landscape_fullscreen`、四种画面模式和说明都是 v3 已有的键）。c14 的两句没有加（没做）。

## v3 文件 → v4 文件

| v3（`lib/modules/live_play/widgets/`） | v4（`features/live_play/`） |
|---|---|
| `layout/live_play_content.dart` 的 `PortraitLiveRoomLayout`、`portraitPanelRange` | `layout/portrait_panel.dart`、`logic/room_layout.dart` |
| `layout/live_play_content.dart` 的 `PortraitFullscreenPresentation` | `packages/live_ui` 的 `AmbientBackdrop`、`player/player_view.dart` 的 `_picture` |
| `layout/portrait_fullscreen_interaction.dart` | `logic/room_layout.dart`（判定）、`player/player_gestures.dart` 和 `player_view.dart` 的上滑恢复、`player/bar_parts.dart` 的 `PortraitEntryHint` |
| `video_player/portrait_playback_picker_dialog.dart` | `dialogs/player_dialogs.dart`（方向）、`player/bar_parts.dart` 的 `PortraitModeButton`（画面模式小菜单） |
| `player/core/player_manager.dart` 的 `buildPresentationVideoViewport`、`resolvePortraitFullscreenBalancedScale` | `player/player_view.dart`、`logic/room_layout.dart` 的 `balancedScale` |
| `video_player/video_controller.dart` 的 `enterPortraitFullScreen`、`enterLandscapeFullScreen`、`applyFullscreenOrientationPolicy` | `live_play_page.dart` 的 `_enterPortraitFullscreen`、`_enterFullscreen`、`_restoreSystemUi` |

v4 原来的 `portraitVideoHeight`（竖屏流只把画面框加高）删掉，换成三档面板。

## 门禁

`live_play` 直接写的颜色和图标 9 → 9；沉浸背景的兜底渐变和面板、提示的颜色都在 `live_ui`。

## 测试

在 `live_play_layouts_test.dart`（共 24 个，见 T05d.1 记录）里，这个任务的：

- 竖屏流：画面铺满、面板从中档（796 × 44%）开始、把手提示、“横屏全屏”在把手行右边同一行、下栏贴面板上沿、下栏顺序、面板里的信息行和标签；“沉浸”从最低档 250 开始；
- 拖把手：拖动中控制层不动、松手吸附到最高档后控制层跟上；往下拖过最低档进竖屏全屏并锁竖屏方向；
- 竖屏全屏：上方两行、下方两行的顺序和图标，锁定，进入提示 3 秒后淡出，下栏上滑恢复面板，返回键先退出竖屏全屏；
- 画面模式：图标、标题、说明、当前项打勾、画面不变暗、选“铺满裁剪”后生效且按钮变黄；
- 方向对话框：说明、打勾、“记住”一拨就存、“关闭”；
- “横屏全屏”：锁横屏、横屏排法、两边沉浸背景；退出时先转回竖屏、过几秒放开（附录 A 第 11 条）；
- 宽屏竖屏流用满高度、有沉浸背景；“兼容 16:9”是 16:9 排法但全屏仍是竖屏全屏；电脑窄窗口只有拖动横条和“全屏”，没有竖屏全屏；竖屏全屏的面板从底部升起；
- 逻辑：三档高度、吸附、进入和恢复的判定、平衡填充的放大倍数、画面模式和方向设置的解析、尺寸分档。

### 和新设计冲突、照实改了的原有断言

| 测试 | 原断言 | 改为 | 原因 |
|---|---|---|---|
| `live_play_more_test` 竖屏流画面高度 | `portraitVideoHeight` 按布局把画面框加高（440 / 600） | 删掉，由三档面板的测试代替 | c1：恢复 v3 的三档面板 |

## 没做的和原因

1. **c14 上下滑换台**：见上表。
2. **拖面板、滑动时临时最高刷新率**：属于 T14b.1（刷新率）。
3. **iPhone 灵动岛、主屏指示条的细节**没有在真机上看（本机不能构建 iOS）。
