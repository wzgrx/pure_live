# T18a.1 电视模式：外壳、焦点导航、直播浏览和基本直播间

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/tv/`（新）、`lib/app/ui_mode.dart`（新）、`lib/app/app.dart`、`lib/app/bootstrap.dart`、`lib/routes/tv_router.dart`（新）、`lib/pages/settings/settings_catalog.dart`（只加一行）、`android/`、`packages/live_store`（只加一个设置）、翻译文件（只加键）
- 电视版来源：pure_live_TV（`~/ref/pure_live_TV`，AGPL-3.0，提交 `b9d2f739`）的 `lib/core/widgets/`（`tv_focusable.dart`、`tv_focus_style.dart`、`tv_focus_restorer.dart`、`tv_room_card.dart`、`tv_tab_bar.dart`、`tv_input_field.dart`）、`lib/core/utils/dpad_long_press_gate.dart`、`lib/core/theme/`（`tv_theme_data.dart`、`tv_text_scale.dart`、`tv_palette_defaults.dart`）、`lib/core/dialog/`（`tv_dialog.dart`、`tv_select_dialog.dart`、`tv_confirm_dialog.dart`）、`lib/features/home/home_page.dart`、`lib/services/theme_settings/theme_settings_controller.dart`（网格列数）、`lib/modules/live/{hot,favorite,areas,favorite_areas,history,search,iptv}`、`lib/modules/live/playback/widgets/player_key_scope.dart`、`android/app/src/main/AndroidManifest.xml` 和 `res/drawable*/app_banner.png`
- 用到的 v4 模块：`live_core` 的平台、`live_store` 的设置/关注/历史/关注分区、`lib/shared/` 的卡片数据（`AudiencePolicy.cardOf`）、取数（`RoomFeed`、`AreaRoomSource`）、卡片菜单（`showRoomMenu`、`followRoom`、`unfollowRoom`）和飞行弹幕层，T07a.1 的 provider，M13 各页公开的控制器（`popularCatalogProvider`、`favoriteControllerProvider`、`AreaCatalog`、`SearchModel`、`SearchHistory`、`LiveRoomController`、`RoomBackgroundPolicy`）

## 做法

### 模式判断

- 新设置 `uiMode`（`live_store`，只做添加）：`auto`（默认）/`phone`/`tv`。作用域是 `internal`：只留在本机，不进备份，重置设置也不动它——手机的备份恢复到电视上不会把电视切成手机界面。
- “是不是电视”在启动时问一次（`AppBootstrap.start` → `TvDevice.detect()`）：Android 经原生通道 `pure_live/app` 的 `isTelevision`，`UiModeManager.currentModeType == UI_MODE_TYPE_TELEVISION` 或有 `android.software.leanback` 特性就算电视；其他系统一律不是。结果放在 `televisionDeviceProvider`（测试可覆盖）。
- `PureLiveApp` 每次构建按 `uiMode` 和设备算出要不要电视界面；变了就**直接重建**路由（电视用 `buildTvRouter`，否则 `buildAppRouter`），从首页开始，旧路由在下一帧释放，不用重启。电视界面外面再包一层 `TvAppFrame`。
- 设置入口两处：手机/桌面设置页“外观 → 主题”组里加了“界面模式”一行（三选一，说明“切换后立即生效”）；电视设置页第一行也是它。

### 路由和外壳

- `lib/routes/tv_router.dart`：根路径是电视首页 `TvHomePage`；`RoutePath.kLivePlay`、`kAreaRooms`、`kSearch` 换成电视页面，所以任何地方调用 `AppNavigator.toLiveRoomDetail`、`toCategoryDetail`（卡片菜单“进入直播间”、分区、深链、命令行房间）在电视上都会进电视页面；其余 `pageRoutes` 原样保留，“更多设置”、账号、备份、IPTV 管理等打开的就是现有页面（它们靠 Flutter 自带的方向键焦点也能操作）。
- `TvAppFrame`（在主题之下、导航器之上）：`MediaQuery.navigationMode = directional`（停用的控件也能停留，滑块要先选中再左右调）、小屏文字放大（见下）、电视调色板 `TvTheme`、Esc 当返回。
- 首页（`tv/home/tv_home_page.dart`，对照电视版 `HomePage`）：左侧菜单（时钟、关注、推荐、分区、历史、搜索、网络电视，设置在最下），右侧是当前目的地。访问过的目的地保留在 `IndexedStack` 里（电视版的 keep-alive 栈），切回来标签、滚动位置和焦点都在。M14.3 视频、M14.4 音乐、M14.5 壁纸在枚举 `TvPane` 里已占位（`available: false`，先不显示，内容是“建设中”）。
- 启动后的事和手机首页一样：主窗口 2 秒后检查更新、命令行房间进电视直播间、后台 15 秒以上回来发 `HomeSignals.resumedAfterBackground`（关注自己刷新、推荐页刷新当前平台）。

### 主题和尺寸（对照电视版 `lib/core/theme/`）

- 调色板 `TvPalette.of(colorScheme)`：照电视版的 HSL 色阶，从应用主题的主色派生——深色是带主色色相的深底、卡片、聚焦卡片，浅色是暖纸色；焦点色是提亮的主色。所以“主题模式”“主题颜色”用的就是 v4 已有的 `themeMode`、`themeColorSwitch`，不另存电视主题。
- 尺寸 `TvScale`：按 1920×1080 设计稿换算（取宽、高比例的较小者）；`text()` 用于装文字的盒子，跟着文字大小变；文字在物理分辨率低于 1080 行的面板上放大（720p 盒子 1.5 倍，最多 1.6，电视版 `legibilityLift`），用户的文字大小（`textScaleFactor`）叠在上面。
- 房间网格列数照电视版：4 列，文字 >100% 少 1 列，>130% 少 2 列；宽高比 4/3 列 1.3、5 列 1.25、6 列 1.5；间距用已有的网格间距设置。
- 电视设置里的“文字大小”“主题颜色”“弹幕”等写的都是 v4 已有的设置（`textScaleFactor`、`themeColorSwitch`、`danmaku*`），同一台设备切回手机界面时也是这些值；只有 `uiMode` 是新的。

## 焦点方案

**用 Flutter 自带的焦点系统，不用 dpad 包。** 理由：
1. 不加依赖（`dpad` 是第三方包，根 `pubspec.lock` 会变），和手机页面、共享对话框、现有设置页用的是同一套焦点树；
2. 电视版自己的记录里，dpad 的“回退恢复”和页面恢复互相抢（`TvFocusRestorer` 为此要连续几帧重新请求焦点），Flutter 的路由焦点作用域本来就会在返回时把焦点还给原控件；
3. 测试直接用 `sendKeyEvent` 模拟方向键、OK、返回，结果确定。

具体规则：
- **方向键**：默认走 `WidgetsApp` 的 `DirectionalFocusIntent`（按几何位置找最近的控件，回头时沿原路返回）；需要自己的规则时在 `TvFocusable.onKey` 里先处理：
  - 网格（`TvGrid`）按下标移动：左右在行内，上下跨一行；目标行先滚进视野（直接跳，不做动画，和电视版一样避免按住方向键时动画互相打架）再取焦点，所以还没建出来的行也能到；第一列按左交给几何（到菜单），第一行按上交给 `onLeaveUp`（当前标签）；最后一行按下请求下一页；接近最后两行时预取；
  - 菜单项按右进入目的地，落在该目的地上次停留的控件（没有就第一个）；标签栏按下进入网格上次的卡片；
  - 从外面回到网格（菜单、标签）时落回上次的卡片（电视版 `TvTabView` 的 memory）。
- **OK**：`select`、Enter、小键盘 Enter、手柄 A、空格都算。没有长按功能的控件按下即触发；有长按的（房间卡片、搜索历史）按住 0.5 秒触发长按，松开前不触发点击，长按松开也不会再触发点击（电视版 `DpadLongPressGate`）。触摸和鼠标也能用：点按是 OK，长按或右键是长按。
- **视觉**（电视版 `TvFocusStyle`）：聚焦放大（卡片 1.04、按钮 1.05）、主色描边、深色主题加主色光晕（浅色只描边，光晕在白底上发灰）；获得焦点 120 毫秒动画，失去焦点立即复原，按住方向键不会留下一串半亮的卡片。
- **返回键逐级退出**：目的地自己的一层（搜索结果 → 输入框）→ 回到菜单 → “再按一次返回键退出”（2 秒内再按退到后台，同手机的 `moveToBack`）。直播间：房间列表 → 控制层 → 退出。
- **焦点恢复**：从直播间回来，焦点落在**最后看的那个房间**的卡片上（换过台就是换到的那个，不在当前列表里才回原卡片）；对话框关闭后 Flutter 自己把焦点还给打开它的卡片。
- **长按 OK 的卡片菜单**直接用 T07a.2 的 `showRoomMenu`（进入直播间、标签、分享、复制链接、关注/取消关注、历史页的“删除这条记录”）；菜单打开后自动把焦点放到第一个选项（共享菜单本身不设初始焦点，`tvFocusFirstInRoute` 补上）。

## 页面

| 页面 | 文件 | 做法 |
|---|---|---|
| 关注 | `tv/pages/tv_favorites_pane.dart` | `favoriteControllerProvider`（刷新规则、排序和手机一样）；标签：直播中/回放/未开播（带数量），关注的平台多于一个时第二行是平台；当前标签再按 OK 刷新可见的关注 |
| 推荐 | `tv/pages/tv_popular_pane.dart` | `popularCatalogProvider` 的每平台 `RoomFeed`（和手机共用：排序、隐藏不能播放的房间、分页）；平台标签走过只移动高亮，OK 才切换，当前标签再按 OK 刷新；网格到底取下一页（每次 24 个） |
| 分区 | `tv/pages/tv_areas_pane.dart`、`tv_area_rooms_page.dart` | 第一个标签“关注的分区”（`followAreas`），之后每个平台：第二行是分类，下面是分区网格（6 列，随文字减少）；OK 进分区（网络电视频道直接播、CC 官方入口开浏览器，同手机 `openArea`），长按 OK 关注/取消关注分区；分区房间页用 `AreaRoomSource`，顶部有关注按钮 |
| 历史 | `tv/pages/tv_history_pane.dart` | `history.watchAll()`，卡片带观看时间；卡片菜单多“删除这条记录”，上方“清空历史”（先确认） |
| 搜索 | `tv/pages/tv_search_page.dart` | `SearchModel` + `SearchHistory`；输入见下；平台标签（全部 + 平台列表）；结果网格到底加载更多；没搜索时显示最近搜索（OK 再搜，长按 OK 删除，可清空）；首页里和单独路由（`kSearch`）都能用 |
| 网络电视 | `tv/pages/tv_iptv_pane.dart` | IPTV 平台的推荐（内置热门列表）和分类（导入的播放列表）：左边播放列表，右边频道（带编号）；进频道后上下键在这个播放列表里换台；“IPTV管理”打开现有的导入管理页 |
| 设置 | `tv/pages/tv_settings_pane.dart` | 界面模式、主题模式、主题颜色（6 个预设，选了就关掉系统动态色）、文字大小（90%～160%）、默认画质、弹幕开关、弹幕大小、弹幕透明度；网络与代理、更多设置打开现有设置页（代理直接定位到“网络与代理”分区）。OK 打开选项对话框（当前项打勾并聚焦），左右键直接切换上一个/下一个值，开关类 OK 直接翻转 |

**遥控器输入**（搜索框，`TvInputField` + `TvTextInput`）：输入框平时只是显示（方向键照常移动），按 OK 才输入。Android 上调原生通道 `pure_live/app` 的 `inputText`，弹出原生对话框里的 `EditText`，由它唤起系统输入法（电视自带输入法、支持的盒子可以语音输入），确认或输入法的“完成/搜索”键返回文字。电视版遇到的问题是 Flutter 的文字输入在部分电视盒子上打不开输入法（flutter#154924），它用原生平台视图解决；这里用原生对话框，不需要平台视图和额外的包。其他系统（桌面、测试）用 Flutter 对话框里的输入框。

## 基本直播间（`tv/room/`）

- 全屏画面（`LiveVideoView`，画面比例用 `videoFitIndex`）+ 飞行弹幕层（`DanmakuOverlay`，样式 `danmakuLookOf`，开关 `enableDanmakuDisplay`/`hideDanmaku`）。
- 逻辑全部复用手机直播间的 `LiveRoomController`（进房、画质、线路、弹幕连接和过滤、观看历史、定时刷新）和 `RoomBackgroundPolicy`（后台暂停/后台播放），每个房间一个控制器和一个播放会话；只调用公开接口，没有改 `pages/live_play/`，也没有复制它的界面。播放器配置规则同手机（`tvEngineConfig`）。
- 按键（对照电视版 `PlayerKeyScope`）：
  - OK：显示/隐藏控制层；房间失败、未开播、受限、播放出错时 OK 改为重试/刷新（画面上写着“按 OK 重试，上下键换台”）；
  - 上/下（以及遥控器的频道键）：在进来的那一页的房间里换台，300 毫秒内连按会累加成一次切换，首尾循环；换台后左上角显示 3 秒“编号、主播、平台 · 标题 · 第几个/共几个”；
  - 左/右/菜单键（`contextMenu`、`info`）：右侧打开房间列表，当前房间高亮并聚焦，OK 切过去；左键关闭；
  - 返回：先关房间列表或控制层，再退出，并把最后看的房间告诉上一页。
- 控制层：标题、主播 · 平台 · 分区 · 人数（在线/热度/累计，同手机口径）；按钮：画质（对话框选，平台降级提示由控制器负责）、线路（多于一条时）、弹幕开/关、关注/已关注（取消关注先确认，可撤销）、刷新、房间列表；打开时焦点在第一个按钮，6 秒没有按键自动隐藏。
- 换台是在同一页面里换控制器，不是替换路由：少一次页面动画，返回时也只回一层。

## 与电视版的对照

| 电视版（b9d2f739） | 本次 | 说明 |
|---|---|---|
| `core/widgets/tv_focusable.dart`、`tv_focus_style.dart`、`utils/dpad_long_press_gate.dart` | 做了 | `tv/widgets/tv_focusable.dart`（Flutter 焦点，见上） |
| `core/widgets/tv_focus_restorer.dart` | 做了（换了做法） | 路由焦点作用域 + 网格按“最后看的房间”恢复 + 目的地焦点记忆 |
| `core/widgets/tv_room_card.dart`、`tv_cover_chip.dart` | 做了 | `tv_room_card.dart`；数据用共享卡片模型（人数口径、房间标记同手机）；跑马灯标题没做（超长截断） |
| `core/widgets/tv_area_card.dart` | 做了 | 分区网格里的卡片 |
| `core/widgets/tv_tab_bar.dart`、`tv_tab_view.dart` | 做了 | `tv_tabs.dart`；OK 切换、再按刷新、加载线 |
| `core/pagination/`（`BasePagedTvView`、`PagingCore`） | 做了（换了做法） | `TvGrid` + 共享的 `RoomFeed` |
| `core/widgets/tv_input_field.dart` | 做了（换了做法） | 原生输入对话框，不用 `android_tv_text_field` 平台视图 |
| `core/dialog/`（`tv_dialog`、`tv_select_dialog`、`tv_confirm_dialog`） | 做了 | `tv_dialogs.dart`；`tv_input_dialog`、`tv_multi_select_dialog`、`tv_dialog_lock_provider` 没做（不需要） |
| `core/theme/`（调色板、文字缩放、自适应网格） | 做了 | `tv_theme.dart`；电视版的 5 套命名主题和视频/图片背景没做，主题跟随 v4 的主题色（壁纸属于 M14.5） |
| `features/home/`（侧边栏、时钟、模式切换按钮、退出确认、更新弹窗） | 做了大部分 | 模式切换（直播/视频/音乐）留给 M14.3/M14.4；退出确认改成“再按一次返回”；菜单折叠/展开两种宽度没做（固定展开） |
| `modules/live/hot`、`favorite`、`favorite_areas`、`areas`、`history`、`search` | 做了 | 见“页面”；关注页的标签筛选、手动排序，搜索的主播模式、排序和“仅看开播”没做 |
| `modules/live/iptv`（列表、频道） | 做了浏览和播放 | 导入、同步、请求头管理沿用现有 IPTV 页（`iptv_*_section.dart` 的电视化留给后续） |
| `modules/live/playback`（直播间） | 做了基本部分 | 节目单、回看、弹幕设置面板、左键双击关注、清晰度记忆、画中画等是 M14.2 |
| `modules/live/movie_playback` | 没做 | 属于 M14.3 视频 |
| `features/settings/tv_settings_page.dart` | 做了常用项 | 其余进现有设置页 |
| `AndroidManifest.xml`（leanback、触摸屏、`LEANBACK_LAUNCHER`、banner） | 做了 | v4 清单已有 leanback/触摸屏可选和 `LEANBACK_LAUNCHER`，本次把 banner 换成电视版的 `app_banner`（320×180，放 `drawable` 和 `drawable-xhdpi`，原来是一张 512×512 的方形图标）；电视版的 `leanback required="true"`、`type.television required` 和横屏锁定**没有照搬**（同一个应用要装在手机上，手机行为不变） |
| 视频、音乐、壁纸、网页遥控、34 个平台的旧平台层、Hive 存储 | 不搬 | 平台和数据用 v4 的；视频/音乐/壁纸是 M14.3～M14.5 |

## 界面改进（用户授权，以 v3/电视版为基线）

- 菜单上按 OK 打开目的地的同时把焦点移进去（电视版只切换，还要再按右）；按右也能进，落在上次停留的地方。
- 返回直播列表时焦点落在**换台后最后看的那个房间**上，而不是最初点开的卡片。
- 退出改成“再按一次返回键退出”的提示（电视版是确认对话框），少一个对话框。
- 直播间失败/未开播时 OK 直接重试或刷新，画面上写明按键；换台有横幅提示位置“第几个/共几个”；控制层底部有按键说明。
- 设置页左右键直接改值，不必每次打开对话框。
- 主题颜色和手机共用一个设置，在电视上选的颜色手机界面也一样（反之亦然）。

## 没验证的部分

- **真电视/盒子**：本次没有设备，只在测试里用键盘事件模拟。需要实机看：`isTelevision` 判断、`LEANBACK_LAUNCHER` 和横幅显示、遥控器 OK 键实际发的是 `select` 还是 `enter`、长按 OK 的重复事件、返回键走系统返回、原生输入对话框和电视输入法（含语音）、720p 盒子的文字放大、mpv 在电视芯片上的硬解和画质切换、飞行弹幕的性能。
- 手机上的变化只有设置页多一行和启动时问一次是否电视（非电视返回 false，界面不变）。

## 构建

`flutter build apk --debug` 通过（包名 `com.mystyle.purelive.v4dev`），没有往任何设备安装。`aapt2 dump badging` 看到：`leanback-launchable-activity` 是 `MainActivity`，`banner='res/drawable/banner.png'`；`leanback`、`touchscreen`、`camera`、`wifi` 都是“不强制”。清单为此加了一行 `android.hardware.wifi required=false`（Wi-Fi 权限会隐含要求 Wi-Fi，只有网线的电视盒子没有）。

构建时 FFmpeg 构建钩子每次都从 GitHub Release 重新下载根 `pubspec.yaml` 里的 Android 包（远程地址不读缓存），这次经代理下载总在中途断开；验证时临时把那一行指向主仓库已下载的同一个文件，构建后已还原，没有提交。合并的人如果遇到同样的断流可以照此处理，长期办法是让钩子先查缓存（另议）。

## 测试

新增 `apps/pure_live/test/tv/tv_test.dart`（8 个，加速流程只测主要路径，按键都用 `sendKeyEvent` 模拟，返回键用 `handlePopRoute`）：

| 用例 | 内容 |
|---|---|
| 模式和网格规则 | `UiMode` 解析和三种选择；列数随文字大小 4/3/3/2/2；设置页有“界面模式”一行 |
| 自动模式和切换 | 电视设备上 `auto` 进电视首页（方向导航模式）；设置改成手机立即换成手机首页，改回电视立即换回 |
| 首页焦点 | 启动焦点在“关注”；下移到“推荐”，OK 打开并进入（平台标签）；下进网格；左右上下按下标走，最后一行停在最后一个；从第一行上到标签，再下回到上次的卡片；左两次回到**选中的**菜单项；右回到目的地上次的卡片；返回：先回菜单，再提示“再按一次返回键退出” |
| 进房、换台、返回 | OK 进房（列表 10 个、位置正确）；300 毫秒内连按两次下只换一次、换两格，出现横幅；上键换回；观看历史记下看过的房间；OK 打开控制层且焦点在第一个按钮，返回关闭；右键打开房间列表并聚焦当前房间，下 + OK 换台；返回离开，焦点落在最后看的房间的卡片 |
| 长按 OK | 卡片上按住 1 秒出卡片菜单、不进房，菜单自动拿到焦点；Esc 关闭后焦点回到卡片 |
| 搜索 | OK 进搜索落在输入框；OK 通过 `TvTextInput`（测试替换）输入，结果出现在网格；返回回到输入框和最近搜索 |
| 电视设置 | 菜单走到设置，OK 进入；界面模式一行按左从电视改成手机，应用立即换成手机界面 |
| 可聚焦控件 | 没有长按功能时按下即触发；有长按时，按住 1 秒只触发长按（中间的重复事件不触发），松开不再点击 |

`live_store` 加 1 个（`uiMode` 默认值、取值范围、作用域）。

`flutter analyze` 无问题。`flutter test` 共 213 个：212 个通过；`live_play_more_test.dart` 的“纯音频 / 助眠计时暂停”在整套并行跑时失败一次，单独重跑通过（它用真实时间的 40 毫秒计时器，负载高时偶发，和本次改动无关，没有改它）。`live_store` 的 `dart test` 31 个通过。

## 留给后续

| 内容 | 去向 |
|---|---|
| 完整电视直播间：节目单、回看、弹幕设置面板、左键双击关注、按房间记忆画质、线路自动切换提示、画中画 | M14.2 |
| 视频、音乐、壁纸模式和菜单入口（`TvPane.video/music/wallpaper` 已占位） | M14.3～M14.5 |
| 关注页的标签筛选和排序选项、搜索的主播模式和排序、分区的筛选框 | 电视版对应页面的后续 |
| IPTV 导入/同步/节目单的电视化页面 | 后续（现在用现有 IPTV 页） |
| 菜单折叠宽度、卡片标题跑马灯、电视版的命名主题和背景视频 | 后续 / M14.5 |
| 真机检查（上一节） | 有电视设备时 |

## 合并时注意（冲突点）

- `lib/app/app.dart`：`_router` 由 `late final` 改成可替换，`build` 里按 `uiMode` 选路由并在电视界面外包 `TvAppFrame`；T13c.1 等改 `app.dart` 的分支合并时保留这几处。
- `lib/app/bootstrap.dart`：`start` 里加了一行 `await TvDevice.detect()`。
- `lib/routes/`：只新增 `tv_router.dart`，没有改 `app_router.dart`（`pageRoutes` 被它复用，以后加页面两边自动都有）。
- `lib/pages/settings/settings_catalog.dart`：“外观 → 主题”组语言一行后面加了 `ui_mode` 一行。
- `android/`：`MainActivity.kt` 的 `pure_live/app` 通道加了 `isTelevision`、`inputText`；清单加了注释和 `android.hardware.wifi required=false`；`res/drawable/banner.png` 换图，新增 `res/drawable-xhdpi/banner.png`。
- 翻译：只加键（`tv_` 前缀 69 个、`ui_mode*` 6 个），两个文件仍按键名排序、4 空格缩进。
- `packages/live_store`：`Settings.uiMode` 和 `all` 末尾一项，测试加 1 个。
