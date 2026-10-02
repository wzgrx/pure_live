# A07.8 小窗

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A07-直播间界面/A07.8-小窗/README.md](README.md)（第 1 版，用户已确认；J1～J4 按建议 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、9.3 节
- 范围：应用内悬浮小窗、Android 系统画中画、桌面小窗（Windows；Linux、macOS 的代码同一份）和置顶、三种小窗共用的小窗弹幕
- 改动的目录：`apps/pure_live/lib/features/live_play/`（新目录 `mini/`、`logic/` 三个新文件）、`apps/pure_live/lib/app/`（应用外壳挂悬浮层、桌面窗口）、`apps/pure_live/lib/routes/route_observer.dart`（弹层计数）、`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（只加可选参数）、`packages/live_ui`（只加图标和两个画面颜色）、`packages/live_store`（只加一个设置）、Android `MainActivity.kt`、翻译文件、文档
- 同时进行的 A07.2～A07.5（画面三种排法）改画面上栏：小窗按钮由那边放，这里只提供它调用的方法（见“给上栏的接口”）；`player_controls.dart` 没有改
- 原生：改了 Android（画中画状态、去设置、离开时自动进入），`flutter build apk --debug` 通过，没有安装；Windows 没有改原生代码（桌面小窗用 window_manager 已有的接口）

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留：上栏入口和提示“小窗播放”；Android 系统画中画；Windows 主窗口缩成小窗（默认大小、右下角、拖动、拉边改大小、记住位置）；“退出小窗播放”打开时离开直播间变应用内小窗；有弹层时隐藏；进别的直播间或多画面时关掉，回到同一直播间接着播；小窗弹幕的全部设置 | ✅ | 入口按钮由 A07.2～d 放（下面“给上栏的接口”）。桌面小窗尺寸和位置照 v3（横 360、竖高 380、近方形 280，工作区右下 20，记住的位置校正到还在的显示器，最小 140×90）；拉边用 window_manager 的 `DragToResizeArea`，拖动用 `startDragging`。小窗弹幕 13 项设置全部生效（v4 原来只用了字号和区域） |
| c2 | 三种小窗同一套按钮：左上回到直播间（新）、右上关闭（一律停止）、中间播放 / 暂停，45% 黑圆底；手机点一下出按钮 3 秒、按钮显示时点画面回直播间；电脑悬停出按钮、双击回直播间 | ✅ | `mini/mini_player.dart` 的 `MiniPlayerSurface`。角上 48、中间 58（42 的图标），位置 4。悬停按指针类型判断（`MouseRegion` 只对鼠标起作用），不按平台。系统画中画里没有我们的按钮 |
| c3 | 桌面小窗右下角置顶图钉，和“小窗始终置顶”同一个开关，开着是主色 | ✅ | 改了会写回 `windowsPipAlwaysOnTop`，下次进入小窗沿用 |
| c4 | 桌面小窗滚轮调音量、底部音量条；空格暂停、上下键音量、Esc 回到直播间 | ✅ | 滚轮改的是房间音量（停 600 毫秒后存为该房间音量，同直播间）；音量一变（滚轮或上下键）底部出 1.5 秒音量条。空格、上下键、R 沿用页面的快捷键，Esc 在小窗里先回到直播间；F 在小窗里不进全屏 |
| c5 | Linux、macOS 也有小窗按钮和桌面小窗；悬停按有没有鼠标；部分 Wayland 桌面图钉变灰并提示“这个桌面不支持置顶” | ⚠️ 代码完成 | 桌面小窗不再判断平台，只看有没有桌面外壳（`DesktopWindow.miniHost`）。**现在只有 Windows 启动桌面外壳**（Linux 桌面版 M12.6 暂停，macOS 不构建），所以 Linux、macOS 要等外壳接上才出现。Wayland 判断：`XDG_SESSION_TYPE=wayland` 或有 `WAYLAND_DISPLAY` 时一律当作不能置顶（KDE 部分支持也按不支持处理）。macOS 进入小窗时隐藏左上角三个窗口按钮（`setTitleBarStyle(windowButtonVisibility: false)`） |
| c6 | 应用内小窗宽 = 短边 × 0.56（220–360）；竖屏直播高 = 宽 × 1.2；右下角，有底部导航栏时在它上方 16，没有时离底边 16；旋转、缩放后留在屏幕内 | ✅ | `logic/mini_window.dart`。“有底部导航栏”按当前页是首页且宽度不超过 680（首页底栏和侧栏的分界，3.x）判断——功能之间不能互相引用，首页的分界值在这里另写了一份。拖到哪里记住哪里，窗口变小时夹回屏幕内 |
| c7 | 小窗弹幕自动缩放后不小于 10 号字（用户设得更小按用户的），220 宽能排三行 | ✅ | 行高照 3.x 的轨道高度（字号 × 1.8 或字号 + 10，18–44），10 号字一行 20，124 高的一半排 3 行 |
| c8 | 左下录制角标；暂停时播放键一直显示；纯音频只显示头像和“纯音频模式”；断流压暗、转圈、“正在重连”；播放失败显示“播放失败”和中间的刷新键 | ✅ | 另有：打开中（黑底转圈）、播放中缓冲（只转圈不压暗）、主播下播（压暗、显示“未开播”等原因、刷新键）。系统画中画里状态照显示，但没有按钮 |
| c9 | 系统关掉画中画时弹“无法打开画中画”，“去设置”打开本应用的画中画设置；其他失败照 v3 提示 | ✅ | 原生先查 `OPSTR_PICTURE_IN_PICTURE`，关掉时不进入、弹对话框；“去设置”先开系统的应用画中画页，没有时开应用详情页 |
| c10 | 应用内小窗不裁圆角：直角加浮层阴影 | ✅ | 阴影 0 8 24 38% 黑（`OnVideoColors.floatingShadow`），视频不裁剪 |
| c11 | 离开应用时自动画中画（J1，默认关） | ✅（设置行交给 A11.3） | 新设置 `autoPipOnLeave`（默认关）。打开后只有直播间在最上面、画面在播（不是纯音频、暂停、未开播）时才生效：Android 12 起用 `setAutoEnterEnabled`，8–11 在 `onUserLeaveHint` 里进入。**设置页的开关行没有加**（设计写明交给 A11.3，且不改别的功能目录），现在没有入口 |
| J2 | 图钉 | ✅ | 同 c3 |
| J3 | 桌面小窗关闭：停止播放，主窗口回到进直播间前的页面并最小化 | ✅ | 顺序：暂停 → 先隐藏窗口再恢复原大小（避免大窗口闪一下）→ 关掉直播间（不转成应用内小窗）→ 最小化到任务栏。隐藏后最小化若仍不可见，再显示一次再最小化 |
| J4 | 应用内小窗不支持改大小 | ✅ | 大小只按屏幕定 |

### 性能要点

| 要求 | 做到 | 说明 |
|---|---|---|
| 播放器只有一份，进出小窗不重建 | ✅ | 新的 `RoomRuntime` 装着直播间的逻辑、播放器、弹幕连接、后台策略、方向选择。直播间页关闭时交给 `FloatingRoom`（应用内小窗），再打开同一直播间时拿回来，不新建播放器、不重新打开流（测试固定播放器个数和打开次数）；系统画中画和桌面小窗本来就在直播间页里，画面元素用原来的 GlobalKey 保留 |
| 进画中画前先画好只有画面的一帧 | ✅ | 先切到只有画面的样子，等一帧再请求进入；系统确认进入前一直保持（最多 1 秒） |
| 小窗弹幕单独一层，同时最多 6 条，30 帧或跟随刷新率档位 | ✅ | `DanmakuOverlay` 加了可选的“最多几条”“帧率”“统一颜色”“行高”（不传时和原来一样）；排队最多 36 条、超过 3 秒的丢掉（3.x）。v4 的弹幕层没有对象池，3.x 的 32/48/160 缓存上限不适用 |
| 按钮底色 45% 黑，不用模糊；隐藏时不参与绘制 | ✅ | 透明度 0 时不绘制 |
| 录制角标每秒只重绘角标；有弹层时只隐藏、不停播 | ✅ | `Offstage` |

### 给上栏的接口（A07.2～A07.5 用）

画面上栏的小窗按钮放在哪由那边定，调用：

```dart
final mini = RoomMiniScope.maybeOf(context); // 直播间页提供
mini?.supported();      // Future<bool>：是否显示按钮（Android 有画中画；桌面有桌面外壳）
mini?.preparing;        // ValueListenable<bool>：切换中，按钮变灰
mini?.enter(context);   // Android 进系统画中画（含 c9 对话框）；桌面缩成桌面小窗
```

现在 `RoomPlayer` 里原有的 `_pipSupported`、`_enterPip` 已经改为调这三个，按钮本身（`TopBarSlot.pip`，`live-play-pip`）没动；`topBarSlots(android:)` 仍只在 Android 放这个按钮，**桌面要由那边把它加到所有平台**（按钮显不显示由 `supported()` 决定）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `player/core/player_manager.dart:2808-2871`（`enablePip`） | `features/live_play/mini/room_mini_window.dart`（`RoomMiniWindow`）、`logic/background_playback.dart`（`PictureInPicture`）、`MainActivity.kt` |
| `player/core/player_manager.dart:2970-3156`（`showAppFloating`）、`:3215-3287`（`buildPiPOverlay`） | `mini/floating_window.dart`（`FloatingRoomLayer`）、`mini/mini_player.dart`（`MiniPlayerSurface`） |
| `player/core/player_manager.dart:4737-4757`（`resolveAppFloatingSize`） | `logic/mini_window.dart`（`inAppMiniSize`） |
| `player/utils/window_helper.dart:100-460`、`player/utils/pip_window_widget.dart` | `app/desktop/mini_window.dart`（`WindowManagerMiniHost`、`resolveMiniWindowBounds`）、`app/desktop/desktop_window.dart`（`DesktopWindow.enterMini` 等） |
| `modules/live_play/widgets/danmaku/compact_danmaku_overlay.dart`、`common/utils/compact_danmaku_metrics.dart` | `mini/compact_danmaku.dart`、`logic/mini_window.dart`（`CompactDanmakuMetrics`、`compactDanmakuFps`） |
| `player/utils/popup_route_tracker.dart` | `routes/route_observer.dart`（`openPopups`） |
| `routes/navigation_observer.dart:45-121`、`routes/app_navigation.dart:55-63` | `logic/room_runtime.dart`（`RoomRuntime`、`FloatingRoom`）、`live_play_page.dart` |

## 新设置

| 键 | 默认 | 说明 |
|---|---|---|
| `autoPipOnLeave`（`player` 段） | 关 | J1 离开应用时自动小窗。备份带着；3.x 没有这个键，读到时忽略。设置页的开关行交给 A11.3（文字已加：`auto_pip_on_leave`“离开应用时自动小窗”、`auto_pip_on_leave_desc`） |

其余只用现有的键：`floatPlay`、`windowsPipAlwaysOnTop`、`rememberPipPosition`、`windows_pip_*`（位置和大小）、`enablePipDanmaku` 和 `pipDanmaku*` 13 项。改名（A11.3）没有做。

## 新增的文字

中英各 10 条：回到直播间、置顶、取消置顶、这个桌面不支持置顶、正在重连、无法打开画中画（标题和正文）、去设置、离开应用时自动小窗（标题和说明）。“播放失败”“暂停”“播放”“纯音频模式”“关闭”“重试”用已有的。

## `live_ui` 和其他共用部分（只做添加）

| 内容 | 说明 |
|---|---|
| `AppIcons.backToRoom`、`miniPlay`、`miniPause`、`pinned`、`unpinned` | `open_in_full`（新）、3.x 的 `play_circle_filled`/`pause_circle_filled`、Remix 图钉实心 / 空心；关闭、刷新、音量用已有的 |
| `OnVideoColors.button`、`floatingShadow` | 45% 黑按钮底、应用内小窗的阴影 |
| `Settings.autoPipOnLeave` | 见上 |
| `DanmakuOverlay` 的 `maxVisible`、`fps`、`color`，`DanmakuLook.laneHeight` | 可选，不传时和原来完全一样（多画面不受影响） |
| `LiveRouteObserver.openPopups` | 打开着的菜单、对话框、面板个数（包括 `didRemove`） |
| `DesktopWindow.mini`、`miniHost`、`enterMini`、`exitMini`、`setMiniOnTop`、`minimize`、`startDragging`、`resizeArea` | 桌面小窗；`DesktopFrame` 在小窗时隐藏标题栏；桌面外壳在小窗时只记小窗的位置和大小，不覆盖普通窗口的大小 |

## 门禁

- `check_ui_structure.py` 通过；直接写的颜色和图标数没有变化（`live_play` 仍是 9，新文件都用 `AppIcons` 和颜色角色），基线不用改。
- 没有新增功能之间的引用（应用外壳 `app/app.dart` 引用 `features/live_play/mini/floating_window.dart`，外壳不算功能目录）；`logic/` 的新文件没有引用 material。

## 测试

- 新增 `test/features/live_play/live_play_mini_window_test.dart` 22 个：
  - 规则 9 个：应用内小窗大小（手机、横屏、平板、超大、竖屏直播 149×264）；右下角位置、底部导航栏、拖出界后夹回；弹幕 10 号字和三行；弹幕帧率三档和手动；八种状态的映射；什么时候转成应用内小窗（附录 A 第 8 条）；J1 什么时候自动进入；桌面小窗大小和位置（3.x）；纯文字去掉表情代码。
  - 应用内小窗 7 个：离开直播间后在右下角、直角加阴影、同一个播放器；按钮顺序、图标、位置、45% 黑底；3 秒后隐藏、点一下出按钮、再点回到直播间且不新建播放器、不重新打开流；✕ 停止；暂停后播放键常显；断流“正在重连”；纯音频放得下；弹幕 10 号字、行高 20、最多 6 条、30 帧、关掉小窗弹幕；对话框打开时隐藏（不停播）、关掉后恢复；进别的直播间、进多画面时关掉；设置关闭或房间没在播时不留小窗；横屏 852×393 和平板 1280×800 的位置和大小、拖动时 80% 不透明、旋转后留在屏幕内；加载中、下播后刷新键常显、竖屏画面 149×264；鼠标悬停出按钮、单击不动、双击回到直播间（宽屏布局）。
  - 桌面小窗 2 个：进入时窗口缩小（假的窗口系统记录调用）、只剩画面；图钉位置、点了写设置并置顶、变主色；滚轮音量和音量条；Esc 回到直播间；再进入时沿用置顶；✕ 依次隐藏、恢复、回到首页、最小化，且不转成应用内小窗；不能置顶时图钉变灰并提示，双击回到直播间。
  - Android 画中画 3 个：系统关掉时弹对话框（文字照设计）、“去设置”调原生、不尝试进入；进入后只剩画面和弹幕、没有我们的按钮，退出后恢复；失败时提示“打开画中画失败，请重试”；J1 默认不生效，打开后在播时生效、暂停和纯音频时撤销、离开直播间时撤销。
- `live_ui` 45 个（`AppIcons` 对照表加了 5 个图标）；`live_store` 32 个。
- `apps/pure_live` 全部测试 300 个通过（A07.6 后 278 个，加这次 22 个）；`flutter analyze` 无问题；`check_ui_structure.py` 通过。原有测试没有和新设计冲突的断言，没有改（`live_play_support.dart` 的假播放引擎加了一个“已释放”标记）。
- 附录 A：第 8 条（应用内小窗：有弹层时隐藏；手机第一次点击显示控件、再点回到直播间；只有有画面且没有加载错误时才转为小窗）、第 15 条（小窗可选置顶）写成了测试。

## 没有在真机上看的

- Android：系统画中画页（`android.settings.PICTURE_IN_PICTURE_SETTINGS`）在 K90 上能不能直接打开；Android 12 起自动进入的动画；8–11 用 `onUserLeaveHint` 时，从直播间打开分享、文件选择等系统界面也会触发进入（菜单打开时直播间不在最上面，此时不会生效；直接跳出的系统界面会）。
- Windows（需要在 Windows 上构建看）：无标题栏小窗能否拉边改大小、隐藏后最小化是否正常出现在任务栏、置顶切换、记住位置；Windows 11 是否给小窗自动加圆角。
