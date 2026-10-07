# X03 电视

电视（Android TV、电视盒子）客户端的“底座”：怎么判断是电视、电视模式的外壳和路由、遥控器的方向键和 OK 键怎么走焦点、遥控器怎么输入文字、清单里的 leanback 部分；以 liuchuancong 的 pure_live_TV（AGPL-3.0）为基线并进同一个应用。

## 范围

- 包括：
  - 电视模式的判断和切换：`apps/pure_live/lib/app/ui_mode.dart`（`UiMode` 自动 / 手机 / 电视、`TvDevice.detect`）、设置 `uiMode`（`packages/live_store/lib/src/settings/settings.dart:1389`，本机设置、不进备份）、`apps/pure_live/lib/app/app.dart:120`、`:129`（按模式换路由）。
  - 电视的路由和外壳：`apps/pure_live/lib/routes/tv_router.dart`、`apps/pure_live/lib/tv/tv_app.dart`（`TvAppFrame`：方向导航模式、文字放大、电视调色板、Esc 当返回）。
  - 焦点和遥控器：`lib/tv/widgets/tv_focusable.dart`（OK、长按、焦点样式）、`tv_grid.dart`（网格按下标移动、预取）；Android 原生 `MainActivity.kt` 的 `isTelevision`（`:252`、`:348`）和 `inputText`（`:257`，原生输入框唤起电视输入法）。
  - Android 清单的电视部分：`LEANBACK_LAUNCHER`（`AndroidManifest.xml:75`）、横幅 `android:banner`（`:57`）、`leanback`、触摸屏、Wi-Fi 都“不强制”（`:151-152`）。
  - 真电视、盒子上的验证（遥控器按键码、输入法、720p 盒子的文字、mpv 硬解）。
- 不包括（归哪里）：
  - 电视的每个界面（设计系统、外壳、直播浏览、直播间、网络电视、点播、音乐、壁纸、设置）→ A17（A17.1～A17.9）；X03.1 当时一起做的界面现在归 A17 继续。
  - 点播和音乐的核心包 `packages/live_vod` → L03。
  - 直播间的逻辑（`LiveRoomController`，电视直接复用）→ C 组。

## 现状：做到哪、怎么工作的

- X03.1（2026-10-01，`781586ff7`，旧编号 M14.1）完成：
  - 启动时问一次是不是电视（`AppBootstrap.start` → `TvDevice.detect()`，`ui_mode.dart:52`；Android 经 `pure_live/app` 通道，`UiModeManager` 是电视或有 `android.software.leanback` 特性就算），结果放 `televisionDeviceProvider`（`:67`）；`PureLiveApp` 按 `uiMode` 和设备选电视路由 `buildTvRouter`（`tv_router.dart:26`）或手机路由，设置里切换立即重建路由（`app.dart:123-129`），不用重启。
  - 电视路由把 `kLivePlay`、`kAreaRooms`、`kSearch` 换成电视页面（`tv_router.dart:17-19`），其他页面沿用手机的（靠 Flutter 自带的方向键焦点也能操作）。
  - 焦点用 Flutter 自带的焦点系统，不用 dpad 包：方向键默认按几何找最近的控件；网格按下标走（`TvGrid`，`tv_grid.dart:24`），先把目标行滚进视野再取焦点；OK（select、Enter、小键盘 Enter、手柄 A、空格）；有长按的控件按住 0.5 秒才触发长按（照电视版 `DpadLongPressGate`）；返回逐级退出，最后“再按一次返回键退出”；从直播间回来焦点落在最后看的那个房间。
  - 基本直播间 `lib/tv/room/tv_live_play_page.dart`（`TvLivePlayPage` `:59`）：全屏画面 + 飞行弹幕，复用手机的 `LiveRoomController`；上下键换台（300 毫秒内连按合并）、左右键房间列表、OK 控制层。
  - 遥控器输入：原生对话框里的 `EditText` 唤起系统输入法（电视版遇到 Flutter 文字输入在部分盒子上打不开输入法，flutter#154924）。
- 之后：A17.1（电视设计系统和通用组件）完成，加了 `tvFocusZoom` 等；A17.2～A17.9 已确认、没开发（A17.2 的 `note` 写了旧分支 M14.2～M14.5 在 `agent-af79805552a6c7d0e` 等工作区，逻辑可参考）。
- **没在真电视或盒子上运行过**（X03.1 记录“没验证的部分”）；只用 `flutter build apk --debug` 构建过并用 `aapt2 dump badging` 看了 `leanback-launchable-activity` 和横幅。登记表的“完成”不符合 PROCESS 第 3.2 节“完成必须有真机结果”。
- 和 3.x 比：3.x 手机版没有电视界面，电视版是另一个仓库 pure_live_TV（X03.1 对照的是 `b9d2f739`，本机 `~/ref/pure_live_TV` 已经更新到 `37660afc`）；4.x 把电视并进同一个应用，同一个 APK 装在手机和电视上。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/ui_mode.dart` | `UiMode`（`:10`）、`TvDevice`（`:37`，`detect` `:52`）、`televisionDeviceProvider`（`:67`） |
| `apps/pure_live/lib/app/app.dart:38-48`、`:120-129` | 按模式选路由、切换时重建 |
| `apps/pure_live/lib/routes/tv_router.dart` | 电视路由：三个电视页面替换、其余复用（`buildTvRouter` `:26`） |
| `apps/pure_live/lib/tv/tv_app.dart`（85 行） | `TvBackIntent`（`:11`）、`TvAppFrame`（`:28`） |
| `apps/pure_live/lib/tv/tv_theme.dart`（238） | `TvPalette`（`:15`，从主题主色派生）、`TvScale`（`:88`，按 1920×1080 换算、低分辨率放大）、`TvTextSize`、`TvRadius`、`TvTheme`、`TvBackground` |
| `apps/pure_live/lib/tv/tv_navigation.dart`（64） | `TvRoomArgs`（`:13`，换台用的房间列表） |
| `apps/pure_live/lib/tv/home/tv_home_page.dart`（462） | `TvPane`（`:28`，视频、音乐、壁纸已占位但不显示）、`TvHomePage`（`:124`，左侧菜单 + 目的地 `IndexedStack`） |
| `apps/pure_live/lib/tv/widgets/tv_focusable.dart`（254） | `TvFocusable`（`:59`，OK、长按门、焦点样式） |
| `apps/pure_live/lib/tv/widgets/tv_grid.dart`（250） | `TvGrid`（`:24`，按下标移动、预取、回到上次的卡片） |
| `apps/pure_live/lib/tv/widgets/` 其余 | 卡片、标签、按钮、对话框、设置行、状态、页面标题、推送确认 |
| `apps/pure_live/lib/tv/pages/`（8 个） | 关注、推荐、分区、分区房间、历史、搜索、网络电视、设置 |
| `apps/pure_live/lib/tv/room/`（2 个） | 电视直播间和它的覆盖层 |
| `apps/pure_live/android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt:252-257`、`:348` | `isTelevision`、`inputText` |
| `apps/pure_live/android/app/src/main/AndroidManifest.xml:57`、`:75`、`:149-152` | 横幅、电视启动器、不强制的硬件特性 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/tv/tv_test.dart`（8 个） | 模式和网格规则；自动模式和切换；首页焦点；进房、换台、返回；长按 OK；搜索；电视设置；可聚焦控件 |
| `apps/pure_live/test/tv/tv_components_test.dart`（29 个） | A17.1 的电视组件 |
| `packages/live_store/test/` 的 `uiMode` 用例 | 默认值、取值范围、作用域 |

## 3.x 基线

- 手机版 3.x（`v3.2.11`）没有电视模式。电视的基线是 pure_live_TV（`~/ref/pure_live_TV`，X03.1 用 `b9d2f739`）：`lib/core/widgets/tv_focusable.dart`、`tv_focus_style.dart`、`tv_focus_restorer.dart`、`lib/core/utils/dpad_long_press_gate.dart`、`lib/core/theme/`、`lib/features/home/home_page.dart`、`lib/modules/live/playback/widgets/player_key_scope.dart`、`android/app/src/main/AndroidManifest.xml`。
- 电视版清单是 `leanback required="true"`、`touchscreen` 必需、横屏锁定；4.x **没有照搬**（同一个 APK 要装在手机上）。
- 要保留：电视版的遥控器习惯（OK 进入、长按 OK 菜单、上下换台、返回逐级退出）；3.x 的设置键（电视设置里改的就是 3.x 的 `themeColorSwitch`、`textScaleFactor` 等）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 没在真电视或盒子上运行过：`isTelevision` 判断、`LEANBACK_LAUNCHER` 和横幅、遥控器 OK 发的是 `select` 还是 `enter`、长按 OK 的重复事件、原生输入框和电视输入法、720p 盒子的文字放大、mpv 在电视芯片上的硬解、飞行弹幕的性能 | X03.1 记录“没验证的部分” | 登记为“完成”但没有真机结果 | 建议维护者改回“待真机”或在 A17 的第一个电视任务里一起验证；需要一台电视或盒子 |
| `~/ref/pure_live_TV` 比对照时新（`37660afc` 对 `b9d2f739`），电视版后来的修复没看过 | `~/ref/pure_live_TV` | 可能漏掉电视版的修复 | W01 每周对照（pure_live_TV 在五个上游里） |
| FFmpeg 构建钩子遇到远程地址每次都重新下载（X03.1 构建时断流） | 根 `pubspec.yaml` 的 `ffmpeg_kit_extended_config` | 构建不稳 | 已由 Z04 的本地缓存（`tools/ffmpeg_kit/fetch.sh`）解决 |
| 旧分支 M14.2～M14.5 的电视界面半成品在代理工作区里（`agent-af79805552a6c7d0e`、`agent-a3224b95b79a5b0be`、`agent-a38e678e236092db4`） | 本机工作区 | 清理时可能被删 | A17.2 的 `note` 记了；Z07.1 的规则“没合并的先问” |

## 相关决定和规范

- D-004（电视是第三个客户端，版本路线 4.2）、D-018（3.x 设置键不变；`uiMode` 是新加的本机设置）。
- [specs/UI.md](../../specs/UI.md) 第 5.4 节（遥控器）；PROCESS 第 10 节（真机验证）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/tv/`（按键用 `sendKeyEvent` 模拟，返回用 `handlePopRoute`）。
- 真机：需要一台 Android TV 或电视盒子；装测试包（`.v4dev`，和手机同一个 APK），检查清单见上表第一行。K90 上把“界面模式”切到“电视”只能看界面，看不到遥控器和电视输入法。

## 路线

- 本子分类登记的任务只有 X03.1（完成）。电视的后续工作在 A17（A17.2 外壳 → A17.3 直播浏览 → A17.4 直播间 → A17.5～A17.9），4.2 发布前要有一次真电视上的验证（建议在 A17.4 完成后开一个 X03 的验证任务，或 S 组的任务）。
- 新的电视底座问题（焦点、输入、清单）在本子分类开任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [X 多端客户端](../README.md)。

- 代码：电视模式代码
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| X03.1 | 电视外壳、焦点导航、直播浏览、基本直播间 | 功能 | 完成 | 2026-10-01 | 781586ff7 | [设计或说明](X03.1-电视外壳和焦点导航/README.md)、[记录](X03.1-电视外壳和焦点导航/record.md) |

<!-- docs:生成结束 -->
