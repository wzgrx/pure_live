# S01.2 测试覆盖清单：各包测试数和缺口

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证（测试覆盖）
- 来源：模块重构结束后的清点（旧任务清单 T15a.2）；S01.1 修随机失败时发现同类写法很多
- 旧编号：T15a.2
- 相关：决定 D-017；[S01.1](../S01.1-远程同步测试改成等真实服务/README.md)；门禁在 [Z02](../../../Z-工程文档和维护/Z02-门禁/README.md)

## 目标

给维护者一张表：每个包、应用的每个功能目录有多少测试、行覆盖率多少、哪些文件一行都没测到、哪些测试写法容易随机失败。以后补测试按这张表排优先级，而不是凭印象；改到没测过的地方时知道要多做真机。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 测试数量 | `test/` 平铺 464 个文件 | 13 个成员，粗数见[子分类页](../README.md)“现状”（应用 78 个文件约 848 处调用，`live_core` 77 个约 2922 处……） | 每个成员的实际用例数（运行器报的 `+N`） |
| 覆盖率 | 没有统计 | 没有统计 | 每个成员的行覆盖率；应用按 `lib/features/<目录>`、`lib/shared/`、`lib/app/`、`lib/platform/` 分开 |
| 没测的地方 | — | 已知：应用的 `features/about/`、`auth/`、`hot_areas/` 没有测试目录；`live_player`、`live_record`、`live_store` 测试相对少 | 列出覆盖率为 0 的文件和低于 30% 的目录 |
| 容易随机失败的写法 | — | 应用测试里 48 个文件用固定的短等待；按条件等的辅助写了三份 | 列出“固定等待后直接断言”的位置 |
| 时间炸弹 | — | `tools/timeshift/run.sh` 只跑 `live_net`、`live_core`、`live_danmaku` | 评估 `live_iptv`、`live_record` 要不要加 |

## 方案

- c1 跑一遍带覆盖率的测试，记下每个成员的用例数和行覆盖率（命令见 [brief.md](brief.md)）。
- c2 按目录汇总覆盖率，列出 0% 的文件和低于 30% 的目录，按“用户天天用 × 改得多”排风险（直播间、弹幕、录制、关注排前）。
- c3 扫测试代码里的固定等待：`Future<void>.delayed(const Duration(milliseconds: …))` 或 `settle()` 之后紧跟 `expect` 的位置，列成表。
- c4 结论写在本 README 的“结果”一节；每个缺口建议去向（新任务开到哪个组，由维护者登记）。
- 不改测试和代码（只出清单）；合并三份 `until` 辅助、补测试都另开任务。

## 结果（2026-10-08）

- 代码：master `d34ad44d1`（应用和各包的代码；`live_player` 在 `8dfbf7462` 上重跑，这个提交只加了 `tools/device/` 和文档，被测代码相同）。WSL，Flutter 3.47.6。
- 怎么重跑：`tools/coverage/run.sh <仓库外的目录>`，再 `python3 tools/coverage/report.py <同一目录>` 出下面的表（固定等待那张表和这里的格式略有不同，见下）。`run.sh` 按 `pubspec.yaml` 自动分 Flutter 成员和纯 Dart 成员：brief 里的命令把 `live_player` 当成纯 Dart 包，`dart test` 会因为 `flutter_test` 加载失败。
- 行覆盖率只算测试加载过的文件（lcov 里只有它们）；“测试没加载的文件”另列。没加载的文件里有一部分只有常量、抽象接口（`route_path.dart`、`live_http.dart`、`app_icons.dart` 这类，没有可执行的行），不算缺口；只有导出语句的文件（各包的入口文件）已经去掉。
- 全部 14 个工作区成员（应用、11 个包，加 `tools/check_latest`、`tools/live_cli`）带覆盖率跑都通过，没有随机失败；仓库里没留覆盖率文件（`git status` 干净）。

### 各成员

| 成员 | 测试文件 | 用例（运行器 `+N`） | 行覆盖率 | 行（命中/总数） | 库文件 | 测试没加载的文件 |
|---|---:|---:|---:|---:|---:|---:|
| `apps/pure_live` | 87 | 1026 | 86.1% | 29625/34423 | 292 | 4 |
| `packages/live_cast` | 7 | 57 | 84.9% | 493/581 | 8 | 0 |
| `packages/live_core` | 78 | 3666 | 98.4% | 19096/19410 | 90 | 2 |
| `packages/live_danmaku` | 38 | 1595 | 98.7% | 7223/7315 | 45 | 0 |
| `packages/live_iptv` | 5 | 42 | 89.0% | 1062/1193 | 13 | 0 |
| `packages/live_media` | 6 | 49 | 78.9% | 1060/1343 | 15 | 0 |
| `packages/live_net` | 10 | 86 | 95.9% | 1044/1089 | 19 | 1 |
| `packages/live_player` | 5 | 58 | 76.0% | 934/1229 | 12 | 0 |
| `packages/live_record` | 8 | 64 | 84.8% | 1723/2032 | 16 | 0 |
| `packages/live_store` | 7 | 59 | 89.0% | 1109/1246 | 15 | 0 |
| `packages/live_ui` | 19 | 196 | 85.6% | 3499/4086 | 56 | 4 |
| `packages/live_vod` | 3 | 48 | 64.7% | 1153/1783 | 16 | 0 |
| `tools/check_latest` | 1 | 5 | 38.2% | 47/123 | 1 | 0 |
| `tools/live_cli` | 4 | 64 | 74.1% | 573/773 | 9 | 0 |

### 应用按目录

| 目录 | 文件 | 测试加载的 | 行覆盖率 | 行（命中/总数） | 0% 的文件 |
|---|---:|---:|---:|---:|---:|
| `lib/app` | 30 | 30 | 71.1% | 1913/2690 | 0 |
| `lib/features/about` | 1 | 1 | 85.4% | 82/96 | 0 |
| `lib/features/account` | 12 | 12 | 85.6% | 899/1050 | 0 |
| `lib/features/area_rooms` | 2 | 2 | 94.6% | 70/74 | 0 |
| `lib/features/areas` | 7 | 7 | 83.3% | 539/647 | 0 |
| `lib/features/auth` | 1 | 1 | 95.8% | 46/48 | 0 |
| `lib/features/backup` | 4 | 4 | 55.4% | 326/588 | 1 |
| `lib/features/favorite` | 4 | 4 | 90.1% | 447/496 | 0 |
| `lib/features/history` | 4 | 4 | 94.9% | 336/354 | 0 |
| `lib/features/home` | 4 | 4 | 87.9% | 217/247 | 0 |
| `lib/features/hot_areas` | 1 | 1 | 89.8% | 97/108 | 0 |
| `lib/features/iptv` | 5 | 5 | 91.4% | 884/967 | 0 |
| `lib/features/live_play` | 64 | 64 | 92.2% | 7983/8654 | 0 |
| `lib/features/multiview` | 10 | 10 | 91.1% | 1605/1761 | 0 |
| `lib/features/popular` | 3 | 3 | 92.0% | 206/224 | 0 |
| `lib/features/record_settings` | 3 | 3 | 88.2% | 410/465 | 0 |
| `lib/features/recorder` | 4 | 4 | 84.0% | 476/567 | 0 |
| `lib/features/remote_receiver` | 4 | 4 | 86.8% | 605/697 | 0 |
| `lib/features/search` | 9 | 9 | 90.4% | 1131/1251 | 0 |
| `lib/features/settings` | 14 | 13 | 85.2% | 2623/3077 | 1 |
| `lib/features/shield` | 1 | 1 | 100.0% | 11/11 | 0 |
| `lib/features/splash` | 1 | 1 | 100.0% | 65/65 | 0 |
| `lib/features/tags` | 3 | 3 | 93.8% | 318/339 | 0 |
| `lib/features/toolbox` | 2 | 2 | 88.4% | 205/232 | 0 |
| `lib/features/version` | 8 | 8 | 84.6% | 1036/1224 | 0 |
| `lib/features/web_dav` | 5 | 5 | 89.6% | 714/797 | 0 |
| `lib/i18n` | 1 | 1 | 100.0% | 67/67 | 0 |
| `lib/main.dart` | 1 | 0 | 0.0% | 0/0 | 1 |
| `lib/platform` | 11 | 11 | 50.7% | 363/716 | 2 |
| `lib/routes` | 6 | 5 | 70.3% | 121/172 | 1 |
| `lib/shared` | 39 | 38 | 91.1% | 3730/4096 | 1 |
| `lib/tv` | 28 | 28 | 79.5% | 2100/2643 | 1 |

### 低于 30% 的目录

没加载的文件不计行数；`lib/main.dart` 是入口，测试不加载。

| 成员 | 目录 | 行覆盖率 | 行（命中/总数） | 文件（加载/全部） |
|---|---|---:|---:|---:|
| `apps/pure_live` | `lib/main.dart` | 0.0% | 0/0 | 0/1 |
| `tools/live_cli` | `lib/src/probe` | 0.0% | 0/59 | 1/1 |
| `tools/live_cli` | `lib/src` | 19.2% | 15/78 | 1/1 |
| `packages/live_media` | `lib/src/inputs` | 19.7% | 14/71 | 1/1 |

### 覆盖率最低的 10 个目录（至少 50 行）

| 成员 | 目录 | 行覆盖率 | 行（命中/总数） | 文件（加载/全部） |
|---|---|---:|---:|---:|
| `tools/live_cli` | `lib/src/probe` | 0.0% | 0/59 | 1/1 |
| `tools/live_cli` | `lib/src` | 19.2% | 15/78 | 1/1 |
| `packages/live_media` | `lib/src/inputs` | 19.7% | 14/71 | 1/1 |
| `tools/check_latest` | `lib` | 38.2% | 47/123 | 1/1 |
| `apps/pure_live` | `lib/platform` | 50.7% | 363/716 | 11/11 |
| `apps/pure_live` | `lib/features/backup` | 55.4% | 326/588 | 4/4 |
| `packages/live_vod` | `lib/src` | 58.1% | 660/1135 | 9/9 |
| `apps/pure_live` | `lib/routes` | 70.3% | 121/172 | 5/6 |
| `apps/pure_live` | `lib/app` | 71.1% | 1913/2690 | 30/30 |
| `packages/live_ui` | `lib/src/theme` | 71.3% | 346/485 | 7/8 |

### 0% 的文件

“没加载”里 `route_path.dart`、`loading_style_names.dart`、`live_http.dart`、`input_recipe.dart`、`legacy_placeholders.dart`、`app_icons.dart`、`custom_icons.dart`、`tv_icons.dart`、`tv_colors.dart` 只有常量或抽象接口；`under_construction.dart` 没有任何文件引用（死代码）。

| 成员 | 文件 | 情况 |
|---|---|---|
| `apps/pure_live` | `lib/features/backup/file_browser.dart` | 0/87 行 |
| `apps/pure_live` | `lib/features/settings/loading_style_names.dart` | 没加载 |
| `apps/pure_live` | `lib/main.dart` | 没加载 |
| `apps/pure_live` | `lib/platform/plugins.dart` | 0/46 行 |
| `apps/pure_live` | `lib/platform/secret_cipher.dart` | 0/29 行 |
| `apps/pure_live` | `lib/routes/route_path.dart` | 没加载 |
| `apps/pure_live` | `lib/shared/under_construction.dart` | 没加载 |
| `apps/pure_live` | `lib/tv/pages/tv_area_rooms_page.dart` | 0/63 行 |
| `packages/live_core` | `lib/src/input_recipe.dart` | 没加载 |
| `packages/live_core` | `lib/src/legacy_placeholders.dart` | 没加载 |
| `packages/live_net` | `lib/src/live_http.dart` | 没加载 |
| `packages/live_ui` | `lib/src/icons/app_icons.dart` | 没加载 |
| `packages/live_ui` | `lib/src/icons/custom_icons.dart` | 没加载 |
| `packages/live_ui` | `lib/src/icons/tv_icons.dart` | 没加载 |
| `packages/live_ui` | `lib/src/theme/tv_colors.dart` | 没加载 |
| `packages/live_ui` | `lib/src/widgets/card_dialog.dart` | 0/50 行 |
| `packages/live_ui` | `lib/src/widgets/network_image.dart` | 0/13 行 |
| `tools/live_cli` | `lib/src/patrol/danmaku.dart` | 0/26 行 |
| `tools/live_cli` | `lib/src/probe/probe_command.dart` | 0/59 行 |

### 固定等待

怎么算（`report.py` 的 `scan_waits`）：一处“固定等待”是写死时长的 `Future.delayed`（包括 `tester.runAsync(() => Future.delayed(...))`），或者调用本文件里包着它的辅助函数（`settle()`、`_settle()`、`_wait()`、`_close()`、`submit()` 这类，固定轮数的循环也算）。按条件等的辅助（`until`、`_until`、`_eventually`、`settleSettings`，或者循环里查条件、查截止时间的）不算，循环里的那一处 `delayed` 也不算。后面三个非空行里先出现 `expect` 就记为“直接断言”。`audio_focus_test.dart` 的 `settle()` 是 `pumpEventQueue()`（只清微任务），不算。

| 范围 | 文件 | 固定等待 | 后面直接断言 |
|---|---:|---:|---:|
| `apps/pure_live/test` | 48 | 799 | 495 |
| `packages/live_danmaku/test` | 29 | 190 | 145 |
| `packages/live_net/test` | 3 | 10 | 7 |
| `packages/live_store/test` | 2 | 4 | 3 |
| `packages/live_record/test` | 1 | 3 | 3 |
| `packages/live_core/test` | 2 | 2 | 1 |
| `packages/live_ui/test` | 1 | 2 | 2 |
| `packages/live_media/test` | 1 | 1 | 1 |
| 合计 | 87 | 1011 | 657 |

已经按条件等的（文件里有 `until`、`_until`、`_eventually`、`settleSettings`）：应用里 `live_play_more_test.dart`（同一文件也还有 21 处 `settle()`）、`remote_sync_test.dart`、`update_dialogs_test.dart`、`settings_harness.dart`、`settings_page_test.dart`、`settings_general_test.dart`、`settings_danmaku_test.dart`；`live_danmaku` 的 30 个测试文件（有固定等待的 29 个都在其中，和 `_wait()` 混用）；`live_record` 的 `recorder_test.dart`、`applied_quality_test.dart`、`merge_empty_test.dart`、`chat_test.dart`；`live_net` 的 `socket_test.dart`（`_eventually`）。

最危险的 5 处（预算最短、等的是真实异步链，机器忙时最容易不够）：

| 位置 | 等多久 | 为什么危险 |
|---|---|---|
| `packages/live_net/test/socket_test.dart:154`、`:200` | 10 毫秒 | 关掉假通道或放开握手后只等 10 毫秒就断言失败回调、关闭次数；同文件已经有 `_eventually`，没用上 |
| `apps/pure_live/test/features/live_play/live_play_controller_test.dart`（`settle()` 49 处，`:110` 定义） | 20 毫秒 | 直播间控制器的启动链（取房间、选清晰度、写历史、连弹幕）全靠 20 毫秒，S01.1 修过的 `remote_sync_test` 是同一种写法 |
| `apps/pure_live/test/features/multiview/multiview_controller_test.dart`（`_settle()` 11 处，`:13` 定义） | 20 毫秒 | 多画面分配、静音切换后等 20 毫秒看音量 |
| `apps/pure_live/test/features/live_play/live_play_popups_test.dart:622`、`:640`、`:649` | 5 轮 × 10 毫秒 | 录制面板选清晰度、自动录制后的弹窗 |
| `apps/pure_live/test/features/search/search_test.dart`（17 处直接断言，`submit()` `:360` 定义） | 50 毫秒 | 多平台并发搜索、写搜索记录后马上看结果和失败横幅 |

`live_danmaku` 的 145 处直接断言多数是本机假服务器上的 `_wait(Duration)`（时长由调用处给），数量多但每个文件都已经有 `_until` 可以替换，排在应用之后。

应用的全部位置（按“直接断言”从多到少；“直接断言的行”按等待方式分组，只列直接断言的行）：

| 文件 | 处数 | 直接断言 | 直接断言的行（等待） | 已有按条件等 |
|---|---:|---:|---|---|
| `apps/pure_live/test/features/live_play/live_play_controller_test.dart` | 54 | 49 | settle()：117、136、149、160、166、190、260、267、274、303、312、324、331、345、353、356、372、380、394、412、415、418、426、428、445、463、473、484、502、513、522、533、547、555、565、580、596、601、624、704、717、727、729、739、755、765、776、782、823 | — |
| `apps/pure_live/test/features/multiview/multiview_page_test.dart` | 68 | 47 | _wait()：230、235、249、254、264、268、306、310、314、317、367、370、375、397、421、433、437、443、452、459、468、508、516、520、526、530、536、544、553、557、582、615、621、632、652、656、658、662、683、688、692、709、715、728、732、750、763 | — |
| `apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` | 52 | 29 | _settle()：457、482、490、511、519、551、564、588、624、633、777、808、825、838、851、857、865、870、887、895、945、953、963、975、980、995、999、1002、1005 | — |
| `apps/pure_live/test/features/areas/areas_test.dart` | 33 | 28 | _settle()：179、186、206、211、216、241、244、247、355、363、369、377、380、385、389、503、513、518、524、544、548、554、559、624、628、638、644、660 | — |
| `apps/pure_live/test/shared/shared_test.dart` | 27 | 26 | settle()：183、207、212、214、219、221、225、229、241、246、255、267、274、284、292、294、298、302、307、312、314、323、327、342、344、349 | — |
| `apps/pure_live/test/features/live_play/room_popups_test.dart` | 48 | 22 | _settle()：164、190、240、332、348、439、446、454、458、468、470、477、482、497、501、504、525、537、566、581、598、614 | — |
| `apps/pure_live/test/features/live_play/live_play_more_test.dart` | 26 | 21 | settle()：90、123、132、142、152、171、192、220、242、261、267、300、306、329、351、359、367、372、385、404、406 | 是 |
| `apps/pure_live/test/features/live_play/live_play_room_test.dart` | 35 | 18 | _settle()：177、254、261、263、278、290、331、372、413、448、526、561、578、589、594、610、615、625 | — |
| `apps/pure_live/test/tv/tv_test.dart` | 26 | 18 | _settle()：173、178、219、222、239、249、255、271、280、286、288、304、315、321、324、349、356、380 | — |
| `apps/pure_live/test/features/search/search_test.dart` | 22 | 17 | submit()：387、507、535、582、615、739、862；100 milliseconds：410；50 milliseconds：547、574、597、622、746、850、868、890、1004 | — |
| `apps/pure_live/test/features/web_dav/web_dav_page_test.dart` | 18 | 17 | _settle()：213、220、224、227、239、247、250、274、338、355、358、364、380、394、418、428、431 | — |
| `apps/pure_live/test/features/live_play/live_play_popups_test.dart` | 29 | 15 | _settle()：240、252、267、278、287、317、332、711、809、829、850；10 milliseconds：622、640、649；20 milliseconds：1005 | — |
| `apps/pure_live/test/features/toolbox/toolbox_page_test.dart` | 15 | 15 | _settle()：137、147、156、159、162、171、174、184、189、194、199、205、279、294、301 | — |
| `apps/pure_live/test/features/recorder/recorder_centre_test.dart` | 16 | 13 | _settle()：472、475、518、523、527、534、548、551、554、599、611、636、805 | — |
| `apps/pure_live/test/features/history/history_page_test.dart` | 16 | 12 | _settle()：162、168、177、213、231、255、320、330、343、350、355、363 | — |
| `apps/pure_live/test/features/backup/backup_page_test.dart` | 15 | 12 | _settle()：236、262、277、282、284、336、351、361、367、379、390、398 | — |
| `apps/pure_live/test/features/account/account_page_test.dart` | 14 | 12 | _settle()：298、395、443、450、469、577、589、608、686、719、734、851 | — |
| `apps/pure_live/test/features/multiview/multiview_controller_test.dart` | 11 | 11 | _settle()：41、45、151、154、180、201、209、215、228、253、263 | — |
| `apps/pure_live/test/features/live_play/room_switch_test.dart` | 28 | 10 | _settle()：398、408、432、438、463、478、617、687、696；_close()：708 | — |
| `apps/pure_live/test/features/live_play/live_play_page_test.dart` | 25 | 10 | 50 milliseconds：115、138、145、182；_close()：193、440、538；_settle()：496、533、536 | — |
| `apps/pure_live/test/features/live_play/live_play_tabs_test.dart` | 21 | 9 | _settle()：199、328、332、391、398、405、408、413；_close()：424 | — |
| `apps/pure_live/test/features/shield/shield_page_test.dart` | 10 | 9 | _settle()：107、112、120、130、135、139、144、147、185 | — |
| `apps/pure_live/test/tv/tv_components_test.dart` | 9 | 8 | _settle()：807、816、821、842、848、866、873、884 | — |
| `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` | 48 | 7 | _close()：403、434、581；_settle()：788、808；20 milliseconds：1035、1106 | — |
| `apps/pure_live/test/features/live_play/live_play_states_test.dart` | 18 | 7 | _settle()：445、520、528；_close()：483；20 milliseconds：671、690、703 | — |
| `apps/pure_live/test/features/live_play/room_extras_test.dart` | 15 | 6 | _settle()：308、506、509、512；_close()：405、464 | — |
| `apps/pure_live/test/features/live_play/live_play_more_page_test.dart` | 14 | 6 | 20 milliseconds：174、195、200、278；_settle()：233、241 | — |
| `apps/pure_live/test/features/live_play/chat_names_test.dart` | 11 | 5 | _settle()：138、147、153、166、175 | — |
| `apps/pure_live/test/features/live_play/room_on_phone_test.dart` | 13 | 4 | _close()：197、343；_settle()：341、392 | — |
| `apps/pure_live/test/features/iptv/iptv_page_test.dart` | 6 | 4 | _settle()：335、399、471、550 | — |
| `apps/pure_live/test/features/settings/settings_page_test.dart` | 4 | 4 | frames()：421、429、432、433 | 是 |
| `apps/pure_live/test/features/favorite/favorite_test.dart` | 6 | 3 | 50 milliseconds：463、483、488 | — |
| `apps/pure_live/test/features/popular/popular_test.dart` | 3 | 3 | 20 milliseconds：359；50 milliseconds：641、647 | — |
| `apps/pure_live/test/features/live_play/room_swipe_test.dart` | 11 | 2 | _settle()：330、363 | — |
| `apps/pure_live/test/features/live_play/platform_texts_room_test.dart` | 3 | 2 | _settle()：73、94 | — |
| `apps/pure_live/test/features/settings/settings_data_test.dart` | 3 | 2 | 100 milliseconds：61；50 milliseconds：91 | — |
| `apps/pure_live/test/features/live_play/local_interaction_test.dart` | 2 | 2 | 50 milliseconds：129、559 | — |
| `apps/pure_live/test/features/settings/refresh_rate_limited_test.dart` | 2 | 2 | mode()：60、62 | — |
| `apps/pure_live/test/shared/danmaku_overlay_test.dart` | 2 | 2 | 50 milliseconds：327、373 | — |
| `apps/pure_live/test/features/tags/tags_page_test.dart` | 3 | 1 | _settle()：188 | — |
| `apps/pure_live/test/features/home/home_test.dart` | 2 | 1 | 50 milliseconds：502 | — |
| `apps/pure_live/test/features/live_play/chat_benchmark_test.dart` | 2 | 1 | 20 milliseconds：97 | — |
| `apps/pure_live/test/features/settings/match_frame_rate_test.dart` | 1 | 1 | 20 milliseconds：62 | — |
| `apps/pure_live/test/features/version/version_page_test.dart` | 1 | 1 | 100 milliseconds：245 | — |
| `apps/pure_live/test/platform/system_surfaces_test.dart` | 1 | 1 | 1100 milliseconds：196 | — |
| `apps/pure_live/test/features/live_play/chat_list_follow_test.dart` | 6 | 0 | — | — |
| `apps/pure_live/test/features/remote_receiver/remote_sync_test.dart` | 3 | 0 | — | 是 |
| `apps/pure_live/test/features/live_play/local_interaction_support.dart` | 1 | 0 | — | — |

各包的位置：

| 文件 | 处数 | 直接断言 | 直接断言的行（等待） | 已有按条件等 |
|---|---:|---:|---|---|
| `packages/live_danmaku/test/chzzk_test.dart` | 14 | 13 | _wait()：1129、1167、1204、1333、1407、1501、1526、1617、1992、2092、2125、2139、2206 | 是 |
| `packages/live_danmaku/test/huya_test.dart` | 13 | 11 | _wait()：748、953、1003、1028、1032、1052、1081、1085、1164、1191、1256 | 是 |
| `packages/live_danmaku/test/missevan_test.dart` | 13 | 11 | _wait()：865、889、918、950、1074、1264、1293、1368、1784、1902、1929 | 是 |
| `packages/live_danmaku/test/sites/seventeenlive_test.dart` | 13 | 10 | _wait()：986、1101、1190、1284、1287、1327、1368、1389、1507、1831 | 是 |
| `packages/live_danmaku/test/sites/douyin_test.dart` | 10 | 9 | _wait()：811、851、924、943、1166、1209、1362、1390、1394 | 是 |
| `packages/live_danmaku/test/sites/niconico_test.dart` | 11 | 8 | _wait()：680、683、1085、1099、1418、1456、1960、1985 | 是 |
| `packages/live_danmaku/test/picarto_test.dart` | 8 | 7 | _wait()：925、1072、1103、1149、1310、1333、1397 | 是 |
| `packages/live_danmaku/test/sites/kilakila_test.dart` | 8 | 7 | _wait()：839、889、922、947、977、1045、1113 | 是 |
| `packages/live_danmaku/test/twitch_test.dart` | 8 | 7 | _wait()：604、695、713、801、1569、1587、1615 | 是 |
| `packages/live_net/test/socket_test.dart` | 7 | 7 | 55 milliseconds：86；50 milliseconds：94；100 milliseconds：114；30 milliseconds：136；10 milliseconds：154、200；150 milliseconds：354 | 是 |
| `packages/live_danmaku/test/sites/pandalive_test.dart` | 9 | 6 | _wait()：998、1053、1079、1105、1236、1298 | 是 |
| `packages/live_danmaku/test/socket_connection_test.dart` | 8 | 6 | _wait()：274、501、518、630、698、729 | 是 |
| `packages/live_danmaku/test/sites/jdlive_test.dart` | 7 | 6 | _wait()：677、755、883、911、961、994 | 是 |
| `packages/live_danmaku/test/sites/bigo_test.dart` | 8 | 5 | _wait()：857、909、915、1010、1116 | 是 |
| `packages/live_danmaku/test/sites/sixroom_test.dart` | 6 | 5 | _wait()：846、876、893、981、1013 | 是 |
| `packages/live_danmaku/test/sites/twitcasting_test.dart` | 5 | 4 | _wait()：464、594、631、655 | 是 |
| `packages/live_danmaku/test/sites/youtube_test.dart` | 5 | 4 | _wait()：2249、2860、2889、2909 | 是 |
| `packages/live_danmaku/test/sites/looklive_test.dart` | 6 | 3 | _wait()：1164、1210、1230 | 是 |
| `packages/live_danmaku/test/douyu_test.dart` | 4 | 3 | _wait()：386、520、656 | 是 |
| `packages/live_danmaku/test/sites/showroom_test.dart` | 4 | 3 | _wait()：462、570、622 | 是 |
| `packages/live_danmaku/test/sites/yy_test.dart` | 4 | 3 | _wait()：711、765、871 | 是 |
| `packages/live_danmaku/test/soop_test.dart` | 4 | 3 | _wait()：843、1011、1056 | 是 |
| `packages/live_danmaku/test/sites/acfun_test.dart` | 3 | 3 | 20 milliseconds：964、1058；60 milliseconds：1158 | 是 |
| `packages/live_danmaku/test/sites/bilibili_test.dart` | 3 | 3 | 1300 milliseconds：1242；20 milliseconds：1459、1469 | 是 |
| `packages/live_record/test/recorder_test.dart` | 3 | 3 | 3 seconds：278；20 milliseconds：373、402 | 是 |
| `packages/live_danmaku/test/sites/fc2live_test.dart` | 6 | 2 | _wait()：1118、1144 | 是 |
| `packages/live_store/test/shared_store_test.dart` | 2 | 2 | 50 milliseconds：64、68 | — |
| `packages/live_ui/test/widgets_test.dart` | 2 | 2 | 50 milliseconds：137、146 | — |
| `packages/live_danmaku/test/kuaishou_test.dart` | 2 | 1 | _wait()：562 | 是 |
| `packages/live_danmaku/test/sites/steambroadcast_test.dart` | 2 | 1 | _wait()：865 | 是 |
| `packages/live_store/test/stores_test.dart` | 2 | 1 | 50 milliseconds：54 | — |
| `packages/live_core/test/sites/jdlive_site_test.dart` | 1 | 1 | 20 milliseconds：290 | — |
| `packages/live_danmaku/test/sites/baidulive_test.dart` | 1 | 1 | 20 milliseconds：962 | 是 |
| `packages/live_media/test/hls_window_test.dart` | 1 | 1 | 10 milliseconds：95 | — |
| `packages/live_danmaku/test/sites/kugoulive_test.dart` | 3 | 0 | — | 是 |
| `packages/live_danmaku/test/exact_websocket_test.dart` | 2 | 0 | — | 是 |
| `packages/live_net/test/io_http_test.dart` | 2 | 0 | — | — |
| `packages/live_core/test/sites/pandalive_site_test.dart` | 1 | 0 | — | — |
| `packages/live_net/test/race_test.dart` | 1 | 0 | — | — |

### 时间炸弹

读测试和代码：三个包的被测代码都能注入“现在”，测试里用到的固定日期都配了固定的“现在”。

| 包 | 代码里的“现在” | 测试怎么用 | 结论 |
|---|---|---|---|
| `live_iptv` | `catchup.dart:125` `now ?? DateTime.now()`；`iptv_site.dart:24` `now = DateTime.now` | 回看和节目阶段都传固定的 `now`（`catchup_test.dart:10-13`、`:52`、`:69`、`:145`）；`import_test.dart:66`、`:74` 注入可调的时钟；不传 `now` 的 `playseek`、`timeshift` 结果不依赖“现在” | 没有没固定的地方 |
| `live_store` | `rooms.dart:175` 写观看时间 `now ?? DateTime.now()`；`tags.dart:59` | `support.dart:31` 的 `memoryStore(now:)`；`stores_test.dart:67-107` 传固定时间 | 没有 |
| `live_record` | `task.dart:181`、`:234`、`:425`、`:437`、`:479` `now ?? DateTime.now()`；`capture.dart:162`、`:264` 用 `package:clock` 算已录时长（相对值） | 固定日期都配固定 `now`（`task_test.dart:106-115`、`ffmpeg_test.dart:142-147`、`yy_quality_id_test.dart:25`、`applied_quality_test.dart:51`）；`DateTime.now()` 只用于等待的截止时间（`recorder_test.dart:206`、`merge_*_test.dart`），是相对值 | 没有 |

实测：照 `tools/timeshift/run.sh` 的办法（`LD_PRELOAD` 把时钟往后拨，每个测试文件当普通 Dart 程序跑），三个包在 时钟拨后 30 天、365 天、1825 天时全部测试文件都通过。

建议：`live_iptv`、`live_store` 加进 `tools/timeshift/run.sh`（各十几秒，回看和观看记录以后最可能加上和“现在”比较的逻辑）；`live_record` 不加（跑一遍要起真的 FFmpeg，时间都是相对值，收益小）。改 `run.sh` 归 S01，另开小任务。

### 缺口和建议去向

| 缺口 | 现状 | 建议去向（子分类归属见 OWNERS） | 新任务？ | 规模 |
|---|---|---|---|---|
| 固定等待后直接断言（应用 495 处，最危险的 5 处见上） | 门禁偶发失败只能重跑 | S01：合并三份 `until` 成一个公用的测试辅助，先改上面 5 处和 `live_play_controller_test.dart`、`multiview_*_test.dart`，再按文件分批改 | 是（S01.3） | 中 |
| `live_danmaku` 145 处 `_wait()` 后直接断言 | 同一文件已有 `_until` | 并进上一条的第二批，或 D 组各平台改弹幕时顺手改 | 并入 S01.3 | 中 |
| `packages/live_player/lib/src/mpv_engine.dart` 3.7%（6/163）、`engine.dart` 36.7%、`video_view.dart` 56.6% | 需要真的 libmpv；会话和恢复（`session.dart`）测得好 | G01：给 `mpv_engine` 的属性映射、错误翻译加假播放器测试；画面部分仍靠真机 | 是 | 中 |
| `packages/live_record/lib/src/storage.dart` 28.4%（23/81） | 录制保存位置、空间检查 | H03 | 是 | 小 |
| `packages/live_media/lib/src/inputs/recipes.dart` 19.7% | 拉流输入的组装 | G01 | 是 | 小 |
| 应用 `lib/platform/` 50.7%：`plugins.dart`、`secret_cipher.dart` 0%，`recording_platform.dart` 37%，`platform_services.dart` 26% | 原生通道的 Dart 一侧，测试里换成了假的 | 不补单元测试；`secret_cipher` 归 J02，K02.1 真机验证覆盖；`recording_platform` 归 H01 | 否 | — |
| 应用 `lib/app/desktop/`（`tray.dart` 15%、`desktop_window.dart` 20%、`mini_window.dart` 24%）、`app/data_root.dart` 2%、`app/intake/system_intake.dart` 17% | 桌面和系统集成，依赖插件 | A16（Windows 验证时，X01.3）、O03；可以给纯逻辑部分拆函数再测 | 否（随 X01.3） | — |
| 应用 `lib/features/backup/`：`file_browser.dart` 0%、`log_page.dart` 1% | 备份文件浏览、日志页没有界面测试 | A12 | 是 | 小 |
| `lib/features/settings/font_manager_page.dart` 0.5% | 字体下载页没有界面测试 | A11（字体逻辑归 A01） | 是 | 小 |
| `lib/features/account/bilibili_web_login.dart` 12% | 网页登录（WebView） | 不补；S02.6 的哔哩哔哩网页登录真机验证覆盖 | 否 | — |
| 电视页面：`tv_area_rooms_page.dart` 0%、`tv_areas_pane.dart`、`tv_iptv_pane.dart`、`tv_history_pane.dart` 约 1～2% | 电视首页的分区、网络电视、历史几栏没有测试 | A17 | 是 | 小 |
| `packages/live_ui`：`card_dialog.dart` 0%（`room_menu.dart:105` 在用）、`json_tree.dart` 26%、`dynamic_color.dart` 35% | 组件和主题 | A02、A01 | 是（合成一个） | 小 |
| `packages/live_vod` 64.7%（`ugc_api.dart` 20%、`pgc_api.dart` 24%） | 应用还没用这个包 | L03，等点播开工时补 | 否 | — |
| `tools/live_cli` 的 `probe` 0%、`tools/check_latest` 38% | 维护工具，靠真实网络 | E07、Z01，不补 | 否 | — |
| `apps/pure_live/lib/shared/under_construction.dart` 没有任何文件引用 | 死代码 | A02：确认后删掉 | 是（顺手） | 小 |
| 原来以为没测试的 `features/about/`、`auth/`、`hot_areas/` | 实际 85%、96%、90%（测试在别的目录） | 不需要 | 否 | — |

需要维护者决定：S01.3（合并 `until`、改固定等待）的范围和先后；`tools/timeshift/run.sh` 要不要加 `live_iptv`、`live_store`；表里“是”的几项开到哪个组。

## 验证

- 清单里的数字能用 brief 里的命令重跑出来（写明提交号和日期）。
- 不需要真机。

## 留下的问题

- 清单已出（上面“结果”）。由维护者在 S01 或目标组登记补测试的任务（“缺口和建议去向”表里标“是”的），并决定 `tools/timeshift/run.sh` 要不要加 `live_iptv`、`live_store`。
