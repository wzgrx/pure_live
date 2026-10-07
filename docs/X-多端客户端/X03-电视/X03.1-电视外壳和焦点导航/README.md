# X03.1 电视外壳、焦点导航、直播浏览、基本直播间

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：模块重构计划 M14（电视）的第一步：以 liuchuancong 的 pure_live_TV（AGPL-3.0，提交 `b9d2f739`）为基线，把电视界面并进 4.x 的同一个应用。
- 旧编号：M14.1、T18a.1
- 相关：决定 D-004（电视是第三个客户端）；后续 A17.1～A17.9（电视各界面）、L03（点播和音乐）；用到 I01.2 的共用模块和 M13 各页公开的控制器；记录 [record.md](record.md)

## 目标

同一个 APK 装在电视或盒子上时自动进电视界面（也可以在设置里手动切）：左侧菜单、关注、推荐、分区、历史、搜索、网络电视、设置；遥控器的方向键、OK、返回走得通；能进直播间看、上下键换台；手机上的行为不变。

## 3.x 和现状

| 方面 | 3.x 手机版（`v3.2.11`）和电视版（pure_live_TV `b9d2f739`） | 做完以后（`d28963a5c` 合并） | 现在 |
|---|---|---|---|
| 电视界面 | 手机版没有；电视版是另一个应用（另一个包名、另一套平台层和 Hive 存储） | 同一个应用里的电视模式：`uiMode` 设置（自动 / 手机 / 电视），自动时按 `UiModeManager` 和 `leanback` 特性判断（`apps/pure_live/lib/app/ui_mode.dart:37-67`）；切换立即换路由 | 同左；A17.1 加了电视设计系统和组件 |
| 焦点 | 电视版用 dpad 包和 `TvFocusRestorer`（连续几帧重新请求焦点） | Flutter 自带的焦点：几何方向导航 + 网格按下标（`lib/tv/widgets/tv_grid.dart:24`）+ 路由焦点作用域恢复；OK 和长按门（`tv_focusable.dart:59`） | 同左 |
| 页面 | 电视版 `lib/modules/live/{hot,favorite,areas,favorite_areas,history,search,iptv}` | `lib/tv/pages/` 8 个页面，数据和规则复用手机的控制器（`popularCatalogProvider`、`favoriteControllerProvider`、`AreaCatalog`、`SearchModel`……） | 同左 |
| 直播间 | 电视版 `modules/live/playback` | `lib/tv/room/tv_live_play_page.dart`：全屏画面 + 飞行弹幕，复用 `LiveRoomController`；上下换台、左右房间列表、OK 控制层；完整的电视直播间（节目单、回看、弹幕设置面板……）留给后续 | A17.4（已确认，未开发） |
| 文字输入 | 电视版用 `android_tv_text_field` 平台视图 | 原生对话框里的 `EditText`（`MainActivity.kt:257` `inputText`） | 同左 |
| 清单 | `leanback required="true"`、触摸屏必需、横屏锁定 | 都“不强制”（手机行为不变）；横幅换成电视版的 `app_banner`（320×180）；加 `android.hardware.wifi required=false`（只有网线的盒子） | 同左（`AndroidManifest.xml:57`、`:75`、`:149-152`） |

## 结果

- 提交：`99eb3de1d`（电视首页、直播页面、基本直播间、界面模式）、`620f02662`（遥控器路径的测试）、`781586ff7`（记录；Wi-Fi 不强制，登记表的 `commit`）、`029c3dc3e`（计划），合并 `d28963a5c`（2026-10-01）。
- 新增：`apps/pure_live/lib/tv/`（当时的外壳、组件、页面、直播间）、`lib/app/ui_mode.dart`、`lib/routes/tv_router.dart`；改动：`lib/app/app.dart`（路由可替换、电视外包 `TvAppFrame`）、`lib/app/bootstrap.dart`（`TvDevice.detect()`）、设置目录加“界面模式”一行、`MainActivity.kt`（`isTelevision`、`inputText`）、清单和横幅、`packages/live_store` 加 `uiMode`（`SettingScope.internal`）、翻译加 `tv_` 69 个、`ui_mode*` 6 个。
- 和电视版的逐项对照、做了 / 换了做法 / 没做的，见 [record.md](record.md)“与电视版的对照”；用户授权的界面改进（菜单 OK 直接进入、回到最后看的房间、“再按一次返回键退出”、失败时 OK 重试、换台横幅、设置左右键改值、主题色和手机共用）见记录“界面改进”。
- 偏差：没做的留给后续——完整电视直播间（M14.2，现在 A17.4）、视频 / 音乐 / 壁纸（M14.3～M14.5，现在 A17.6～A17.8、L03）、关注的筛选和排序、搜索的主播模式、IPTV 管理的电视化页面、菜单折叠、标题跑马灯、命名主题。
- 测试：新增 `apps/pure_live/test/tv/tv_test.dart` 8 个、`live_store` 1 个；当时应用 213 个测试 212 个通过（`live_play_more_test.dart` 的“纯音频 / 助眠计时暂停”在并行时偶发失败一次，真实时间的 40 毫秒计时器，和本任务无关，后来 S01 处理这类问题）。

## 验证

- 自动测试：`apps/pure_live/test/tv/tv_test.dart`（模式和网格规则、自动模式和切换、首页焦点、进房换台返回、长按 OK、搜索、电视设置、可聚焦控件）；现在 `test/tv/` 共 37 个（加上 A17.1 的 `tv_components_test.dart` 29 个）。
- 构建：`flutter build apk --debug` 通过；`aapt2 dump badging` 看到 `leanback-launchable-activity` 是 `MainActivity`、横幅、`leanback`/`touchscreen`/`camera`/`wifi` 都不强制。
- 真机：**没有**。记录“没验证的部分”列了要在真电视上看的：`isTelevision` 判断、`LEANBACK_LAUNCHER` 和横幅、遥控器 OK 的按键码、长按 OK 的重复事件、返回键、原生输入对话框和电视输入法（含语音）、720p 盒子的文字放大、mpv 在电视芯片上的硬解和画质切换、飞行弹幕性能。登记表是“完成”，和 PROCESS 第 3.2 节“完成必须有真机结果”不符。

## 留下的问题

- 真电视、盒子上的验证 → 建议维护者把本任务改回“待真机”，或在 A17 的第一个电视开发任务里一起做（需要一台设备）。
- 完整电视直播间 → A17.4；视频、音乐、壁纸 → A17.6、A17.7、A17.8 和 L03；电视设置的其余项 → A17.9。
- 旧分支 M14.2～M14.5 的半成品（工作区 `agent-af79805552a6c7d0e`、`agent-a3224b95b79a5b0be`（M14.3）、`agent-a38e678e236092db4`（M14.4）等）→ A17.2 的 `note`；清理时不要删（Z07.1）。
