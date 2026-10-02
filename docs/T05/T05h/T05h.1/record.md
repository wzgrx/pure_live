# T05h.1 竖屏全屏上下滑换台

- 日期：2026-10-02
- 设计：[docs/T05/T05c/T05c.1/README.md](../../T05c/T05c.1/README.md) 的 c14（X1 选 A，用户已确认）和末尾“T05h.1”一节（对比和 c1～c5）；[T05c.1 的记录](../../T05c/T05c.1/record.md)“没做的”第 1 条
- 改动的目录：`apps/pure_live/lib/features/live_play/`、`features/favorite/`、`features/search/`（只改进直播间时带上列表）、`routes/`、`features/settings/settings_catalog.dart`（一行设置，另把它加进本页的“恢复默认”）、`shared/rooms/room_grid.dart`（一处，见“偏差”2）、`packages/live_store`（只加一个设置）、翻译、文档。没有原生改动，没有构建 APK。

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 关注、热门、分区房间、搜索点卡片进直播间时带上当前列表；从链接、观看记录等进来的没有列表 | ✅ | 路由参数新增 `LiveRoomArgs(room, playlist)`（`routes/route_args.dart`，参照电视 `TvRoomArgs`）；`AppNavigator.toLiveRoomDetail` 加 `playlist:`，只留平台可用、有房间号的，除了当前房间没有别的就仍然只传 `LiveRoom`（`liveRoomArguments`）。关注：当前分组（含“未开播”的行）的全部房间；热门和分区房间：`RoomFeedView` 已加载的全部房间（电脑分页时也是整个列表）；搜索：房间结果（主播结果不带，见“没做的”）。页面设置里的参数仍是 `LiveRoom`，电脑窗口标题照旧读得到主播名 |
| c2 | 设置“竖屏全屏上下滑换台”，默认关 | ✅ | 新键 `portraitFullscreenSwipeSwitch`（`player` 节，默认 `false`，随备份）；在“竖屏直播适配”的“全屏、小窗与弹幕”组、“竖屏全屏画面模式”下面，只在手机上显示（`_mobile`），图标用“切换直播间”的；本页“恢复默认”也会把它关掉 |
| c3 | 开关开、有列表时竖屏全屏分三竖条，中间换台；最下面上滑回面板；锁定不能滑；关或没有列表照旧、不提示 | ✅ | `logic/room_layout.dart` 的 `pictureDragAt`：有换台时按三等分（左亮度、中换台、右音量），否则照旧左右两半；`PlayerGestureLayer` 先判断最下面 96（回面板），再看三等分；锁定时整层手势关闭（原样）。只在 `RoomDisplay.portraitFullscreen`、手机、开关开、列表至少两个直播间时有换台（`live_play_page.dart` 的 `_buildFullscreen`） |
| c4 | 拖动时画面跟手，下一个（上一个）的封面和名字跟上来；过三分之一或快速滑动松手就换，否则弹回；到头回到开头 | ✅ | `player/room_swipe.dart`：`RoomSwipeController`（拖动、松手判定、220 毫秒的移出或弹回动画）和 `RoomSwipeStage`（整块播放器 `Transform.translate`，空出来的地方放 `RoomSwipePreview`：沉浸背景 + 封面 + 15% 黑 + 胶囊卡片：头像、主播名、“平台 · 分区”，过了三分之一再加“松手换到这个直播间”）。判定 `swipeSwitchStep`：距离 ≥ 屏幕高 1/3，或速度 ≥800 且拖了 ≥48；反方向快甩不换。往没有直播间的方向拖不动（列表只有两个时上下都是另一个）。顺序 `logic/room_playlist.dart` 的 `RoomPlaylist`：照列表顺序，首尾相接，进来的房间不在列表里时放在最前（同电视） |
| c5 | 同一个页面、同一个播放器换台；留在竖屏全屏；横屏直播居中加沉浸背景；连续快滑只播最后一个 | ✅ | `_switchRoom`：新建这个直播间的 `RoomRuntime`（逻辑、弹幕、方向、断线计数、后台策略）但沿用旧的 `PlaybackSession`；旧的 `RoomRuntime.dispose(keep:)` 停掉播放器后才让新的 `start()`。页面不变（不走路由），显示状态留在竖屏全屏；页面里属于这个直播间的部分（播放器控件、面板、本地互动、小窗按钮）用新的 key 重建。换到横屏直播时用 `PicturePresentation.ambient`（居中、上下沉浸背景）。停止是排队的：上一个还没停完时又滑，中间那个直播间不会开始加载，只有最后一个开始（见“根因”2）。观看记录照常给每个直播间记一条 |

## 根因

1. T05c.1 没做 c14：直播间只认 `LiveRoom` 一个参数（`routes/app_navigator.dart` 原 `:103-118`），不知道是从哪个列表进来的；“切换直播间”换的是整个页面（`dialogs/room_switcher.dart:183`），页面里没有“换一个直播间”的路径；设置不在 T05c.1 能改的目录里。
2. 开发中发现：`PlaybackSession.stop()` 两次叠在一起时（第一次还在等引擎停下），第一次设的 45 秒空闲释放定时器会被第二次覆盖而没有取消（`packages/live_player/lib/src/session.dart:333-351`），45 秒后会把正在播的引擎释放掉。这个任务不改 `live_player`，所以页面这边保证同一时间只有一个停止：换台的停止排队（`_handover`），离开页面时也等排队的停止做完再交给小窗或待机。测试“c5: swipes while the room before still stops …”在排队之前会因为这个定时器失败。**建议另开任务在 `live_player` 里修**（停止开始时先取消旧的空闲定时器）。
3. 开发中发现：画面的状态层（加载中、未开播、出错）原来盖在手势层上面，它的视图会挡住拖动，换到一个未开播或还在加载的直播间后就滑不走了。现在状态层放进手势层里面（`player/player_view.dart`）：状态视图照旧接住点按（按钮照常），拖动交给手势层。

## v3 文件 → v4 文件

v3（v3.2.11）没有这个功能（对比见设计 T05h.1 一节）。对照的是：

| 参照 | v4 |
|---|---|
| v3 `controllers/live_play_controller.dart:884-930` 的 `switchRoom`（同一页面里换直播间） | `live_play_page.dart` 的 `_switchRoom` |
| v3 `widgets/video_player/video_controller_panel.dart:851-930` 的上下滑 | `player/player_gestures.dart`、`logic/room_layout.dart` 的 `pictureDragAt` |
| 电视 `tv/tv_navigation.dart` 的 `TvRoomArgs.playlist`、`tv/room/tv_live_play_page.dart:214-238` 的上下键换台 | `routes/route_args.dart` 的 `LiveRoomArgs`、`logic/room_playlist.dart` |

## 新设置和 3.x 数据

| 键 | 默认 | 说明 |
|---|---|---|
| `portraitFullscreenSwipeSwitch` | `false` | 新加（v3 没有，键名不是 v3 的）；3.x 的设置和数据不受影响，3.x 的备份里没有这一项时按默认关 |

## 偏差

1. 任务书说“设置项和键名照 v3”：v3 没有这个设置（`player_settings_controller.dart:54-70` 和翻译里都没有），只能新加，默认值照设计 X1 A（关）。
2. 任务书说在设置“视频”页加一行：按已确认的设计 X1 A 放在“竖屏直播适配”页（视频页里打开的子页，和其他竖屏全屏设置在一起）。要挪到视频页只需把 `settings_catalog.dart` 里 `portrait_swipe` 这一行搬过去。
3. 热门和分区房间共用 `shared/rooms/room_grid.dart` 的 `RoomFeedView`，列表只能在它那里带上（一处 `onOpen`），这个文件不在任务书列的目录里。
4. 状态层挪进手势层（根因 3）的副作用：在加载中、未开播等状态视图上上下滑，现在也能调亮度和音量（原来没反应）。
5. 设计图上“松手换到这个直播间”在拖动中一直显示；这里只在松手会换台时显示，免得没过三分之一时误导。

## 测试

新增 11 个，改了 3 个原有测试（只加断言或加一行）：

- `test/features/live_play/room_swipe_test.dart`（9）：c1 路由参数（可用房间、只有自己时不带、`roomOf`）；c4/c5 列表的顺序、首尾相接、进来的房间不在列表里；c3 三等分和两半；c4 松手判定（距离、快甩、太短、反向）；c5 上滑下一个、下滑上一个、首尾相接，同一个 `PlaybackSession`、同一个页面、仍是竖屏全屏、观看记录；c5 停止还没做完时连滑两次只有最后一个开始；c4 拖动中预览跟手、名字和“平台 · 分区”、过三分之一出现“松手换到这个直播间”、不够时弹回；c3 开关关、没有列表、左右两边都不换台；c5 换到横屏直播仍是竖屏全屏、沉浸背景。
- `favorite_test.dart` +1：关注的直播卡片和“未开播”行都带上本组列表。
- `search_test.dart` +1：没有自带打开方式时，房间结果带上全部结果。
- `popular_test.dart`、`areas_test.dart`：原有的“点卡片进直播间”测试加断言，参数是 `LiveRoomArgs`，列表和卡片顺序一致。
- `settings_playback_test.dart` 的竖屏页测试：行的顺序里加 `portrait_swipe`（**和原有断言冲突，照实改**：新加了一行），并检查默认关、点了打开、“恢复默认”关掉。

跑过：`apps/pure_live` 的 `flutter analyze` 无问题、全部 `flutter test` 通过（722 个）；`packages/live_store` 的 analyze、format、`dart test`（43）通过；`python3 tools/gate/check_ui_structure.py` 通过。

## 要在 K90 上看的

1. 设置 → 视频 → 竖屏直播适配，打开“竖屏全屏上下滑换台”；从关注、热门、分区、搜索各进一个竖屏直播，进竖屏全屏，在画面中间上滑、下滑：下一个的封面和名字跟着手指上来，过三分之一后出现“松手换到这个直播间”，松手后换台，画面不黑屏、不重新进页面，弹幕和标题是新直播间的。
2. 不过三分之一松手会弹回；快速一甩也能换；连续快滑几次，只有最后一个出声音和画面。
3. 滑到一个未开播或加载失败的直播间，还能继续滑走。
4. 换到横屏直播：仍在竖屏全屏，画面居中，上下是沉浸背景。
5. 左边三分之一调亮度、右边三分之一调音量，最下面上滑回到面板，锁定后不能滑。
6. 从链接、观看记录、小窗回来的直播间不能滑，也没有提示；开关关掉后照旧。
7. 换台后返回：回到原来的列表页；开着“退出小窗播放”时是最后看的那个直播间进小窗。
8. 拖动时帧时间和内存（specs/UI.md 第 9 节）：拖动只移动画面和一张封面，不应掉帧。

## 合并时注意的冲突点

- `features/live_play/live_play_page.dart`：初始化拆成 `_newRuntime` / `_attachRoom`，`dispose` 里交给小窗或待机的那段改了；`_LayoutSettings` 多一个字段；`build` 外面多一层 `KeyedSubtree`。
- `features/live_play/player/player_view.dart`：状态层挪进了 `PlayerGestureLayer` 里面（T06c.1 弹幕、T05i.1 状态层如果同时在改这一段要手动合并）。
- `features/live_play/player/player_gestures.dart`、`logic/room_layout.dart`：手势起点判断改成 `pictureDragAt`。
- `features/settings/settings_catalog.dart` 竖屏页和 `portraitSettings`；`settings_playback_test.dart` 竖屏页的行顺序。
- `packages/live_store/lib/src/settings/settings.dart` 的 `all` 列表；两个翻译文件（按键名排序）。
- `routes/app_navigator.dart`、`routes/app_router.dart`、`routes/route_args.dart`；`shared/rooms/room_grid.dart` 的 `RoomFeedView`。

## 没做的和原因

1. 设计 X1 A 里“列表后面接观看记录里正在播的”：任务书只要求带进来的列表，没有列表时不能滑；没有加。
2. 搜索的“主播”结果不带列表（多是不在播的主播，滑过去大多是“未开播”）；只带房间结果。
3. `live_player` 里叠加停止漏掉空闲定时器的问题（根因 2）只在页面这边绕开，没有修包本身。
4. 拖动时临时最高刷新率属于 T14b.1。
