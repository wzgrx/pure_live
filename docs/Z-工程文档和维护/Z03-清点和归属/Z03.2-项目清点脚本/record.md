# Z03.2 项目清点脚本：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `0a776db72` 开始），三个阶段一次做完
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 规则和路径表 | 做了，按 A | 新文件 `docs/inventory/OWNERS.toml`。`path`、`site`、`channel`、`setting` 用内联表的数组（一条规则一行，和 `[[path]]` 是同一种 TOML 结构，短得多）；`[setting_sections]` 放在最后（TOML 的表头之后不能再写顶层键） |
| c2 脚本 | 做了 | `tools/docs/owners.py`，只用标准库。除了任务书列的检查，还报“一条规则一个文件都没匹配到”（文件删了，或者被前面的规则全部拿走）、重复的条目、FEATURES.md 里重复的功能点编号；`--who` 查一个路径、设置键、来源或通道归谁，`--files [子分类]` 列文件 |
| c2 OWNERS.md | 做了，有偏差 | 每个子分类列的是**路径规则**而不是逐个文件，也不写文件数：这样加删代码文件不会让 OWNERS.md 过期（否则每个加文件的分支都要重新生成、合并时冲突）；要看具体文件用 `--files <子分类>` |
| c3 门禁 | 做了 | `gate.sh` 在“docs”之后加 `step "owners" python3 tools/docs/owners.py --check`；仓库检查每次都跑（不只是改了 docs/、tools/ 时），所以在成员里加了没归属的文件也会拦住。`docs.py` 的“代码：”一行改为从 OWNERS 取没做（任务书写“可选，维护者定”） |
| 验收 5 | 做了 | `docs/inventory/README.md` 加了两个文件的说明和用法；冲突见下 |

## 根因

- 问题：哪个子分类管哪些代码只写在 `docs/tasks.toml` 每个 `[[sub]]` 的 `code` 文字里，设置、平台、通道没有任何归属记录，也没有脚本核对。
- 一开始（没有归属表时）：667 个代码文件、219 个设置、35 个来源、14 个通道全都没有归属。拿 `code` 字段当路径规则粗算：54 个文件没有任何子分类写到（`tv/` 28 个——`code` 写的是“电视模式代码”，`shared/` 下 12 个，`tools/` 下 brotli、release、timeshift、ui 的 15 个……），486 个被两个以上子分类同时写到（主要是 A 组界面子分类和功能子分类写了同一个目录）。
- 处理：按下面的分法逐个目录写进 OWNERS.toml（196 条路径规则、23 个分节默认值、69 个单独指定的设置、35 个来源、14 个通道），没有放宽检查；在当前 master 上 `--check` 通过。

## 分法

- 一个文件只归一个子分类：改它最多、对它负责的那个。
- 界面（页面、组件）归 A 组的界面子分类，逻辑、数据和平台代码归功能子分类——照各组说明里“界面在 A07”这类写法。先按目录写，混在一起的目录按文件写例外（例如 `features/popular/` 归 A09，`popular_catalog.dart` 归 I02）。没有声明 widget 的文件当逻辑文件看。
- 设置按 `section` 给默认，跨子分类的单独指定（例如 `app` 分节默认 J01，24 个按功能分出去）。
- 来源：播放按 E01（国内五大）、E02（其他国内）、E03（海外）、L01（网络电视）；弹幕有实现或 D01 有任务的归 D01，其余写“无”（`cc`、`inke`、`xiaohongshu`、`weibo`、`iptv`）。

## 和 tasks.toml `code` 字段的冲突（请维护者定）

`code` 字段没改（任务书不让改）。拿它粗算，667 个文件里 72 个的归属不在 `code` 写到的子分类里；去掉“整个包”这种粗写法带来的（例如 K02 的 `code` 写了 `packages/live_danmaku`、A03 写了 `packages/live_ui`），实质的是这些：

| 文件或目录 | `code` 写在 | OWNERS.toml 归 | 理由 |
|---|---|---|---|
| `features/live_play/mini/` 的界面 | A14、C02、O02 | A07（`room_mini_window.dart` 归 C02） | 应用内小窗在 A07 的范围（“小窗”）；A14 是系统画中画窗口的外观 |
| `features/live_play/buttons/`、`dialogs/` | C03 | A07（`record_button.dart` 归 A10） | 都是界面；C03 的功能逻辑在 `room_controller.dart` 等 |
| `features/live_play/danmaku/` | A08、D04 | A08，`chat_feed.dart` 归 D04 | 照 A08 代码地图的分法 |
| `shared/danmaku/` | A08、D02、D05 | 按文件：`danmaku_overlay.dart`、`emotes.dart` D03，`danmaku_settings.dart`、`danmaku_templates.dart` D05，`masked_blocks.dart` D02，其余 A08 | D03 的 `code` 只写了 `danmaku_overlay.dart` |
| `features/shield/` | I07 | A08 | A08 的范围写着“屏蔽页” |
| `features/area_rooms/`、`hot_areas/` 等功能目录 | 功能子分类和 A 组都写了 | A 组，逻辑文件按文件归功能子分类 | 分法第 2 条 |
| `apps/pure_live/lib/platform/` | O04（整个目录） | 按通道的用途分：`display_mode`、`screen_orientation` O05，`native_http`、`twitch_webview_http` Q03，`secret_cipher` J02，`share_channel` O03，`recording_platform` H01，`platform_services` L01，`plugins` I01，`system_*` O04 | 一个目录装了七八个子分类的东西 |
| `app/recording.dart` | H02、H03 | H02 | 录制任务的列表和接线 |
| `RecorderForegroundService.kt`、`RecorderPlugin.kt` | H05 | O01 | O 组是 Android 原生；H05 管 Dart 侧的通知文字（`app/recording_notice.dart`） |
| `app/fonts.dart`、`image_cache.dart`、`iptv_*.dart` | I01（`app/`） | A01、R03、L01 | 按内容 |
| `routes/tv_router.dart`、`tv/` | I01；A17 和 X03 都写“电视模式代码” | A17 | 电视界面；X03 没有专属文件 |
| `packages/live_player` 的 `engine*.dart`、`mpv_*.dart` | G02～G05 | G01 | G01 是引擎（`code` 只写了 `live_media`） |
| `live_player/frame_rate.dart`、`live_ui/widgets/refresh_rate.dart` | G 组、A02/A03 | R02 | 刷新率 |
| `live_player/screen_wake.dart` | G 组 | O05 | 常亮 |
| `live_record` 的 `naming`、`settings`、`storage` | H01、H04 | H03 | 录制设置和存储 |
| `live_store/backup/`、`webdav.dart` | J02 | J03、J04 | 按内容 |
| `live_ui/icons/` | A01（`icons/`）、A03 | A01 | |

## 需要维护者决定的归属

- **本地互动**（`features/live_play/local_interaction/`，含 `logic/`，和 `localInteraction` 分节的 29 个设置）：没有功能子分类，暂归 A08。要不要在 D 组或 C 组开一个子分类？
- `MainActivity.kt`：多个通道的宿主（显示模式、后台播放、返回、应用、画中画、设备控制），O02 和 O05 的 `code` 都写了它，暂归 O02。
- `AppChannelsPlugin.kt`：原生 HTTP、加密、GBK、组播锁四个通道，没有子分类写它，暂归 Q03。
- 通道 `pure_live/app`：回到后台、电视判断、遥控器输入、启动画面主题，暂归 O06。
- `tools/ui/` 下除 `inventory.py` 以外的效果图和评审页工具（`mock/`、`export_compare.py`、`strings.py`、`u0_move.py`）：Z03 说明写“归 A 组的设计流程”，但 A 组没有对应子分类，暂归 Z06。
- `tools/brotli/` 归 Q01、`tools/timeshift/` 归 S01、`tools/release/` 归 Y01：`code` 里都没写，按各子分类说明归的。
- 设置里拿不准的几个：`preferResolution`、`preferResolutionCellular`（C01，进房选画质），`enableNewWindowPlay`（A16），`autoShutDownTime`、`enableAutoShutDownTime`（J01，设置页的定时退出），`cache` 分节（Y02，更新包下载目录）。

## 改了哪些文件

- 新建：`docs/inventory/OWNERS.toml`、`docs/inventory/OWNERS.md`（生成）、`tools/docs/owners.py`、`tools/gate/tests/test_owners.py`、本文件。
- 修改：`tools/gate/gate.sh`（加 `owners` 一步和开头的说明）、`docs/inventory/README.md`、`docs/Z-工程文档和维护/Z03-清点和归属/README.md`（现状、代码地图、已知问题）、`docs/tasks.toml`（Z03.2 完成）。
- 没改（不在范围）：`docs/specs/ENGINEERING.md` 第 3 节和 Z02 说明里列的门禁步骤还没写 `owners`，归 Z02 或 Z06 顺手补。

## 新设置、翻译键、门禁基线

- 没有新设置和翻译键；门禁多一步 `owners`。
- 顺带发现：`Settings.all` 现在是 219 个（`danmaku` 分节 43 个），FEATURES.md 第 15 节写的 218（42）是 A08.6（`b3a3f9d64`）加设置之前数的。

## 测试

- 新增 `tools/gate/tests/test_owners.py` 19 个（临时目录造的小仓库）：干净的树通过并生成 OWNERS.md；扫哪些文件（跳过隐藏目录、`build/`、`__pycache__`）；没匹配的文件报 `unowned:`；第一条规则生效；被前面规则全部拿走的规则报错；`**`、`*`、目录规则的匹配；规则指向不存在的子分类；设置按分节默认和单独覆盖、`...列表` 展开、新分节没有默认值、覆盖了不存在的设置；来源没有归属、弹幕写“无”不报、缺弹幕归属报错、来源已删；通道没有归属、通道已删；FEATURES.md 不存在的任务编号、重复的功能点编号、Windows 表没有“依据”列；OWNERS.md 过期；`--who`。
- `python3 -m unittest discover -s tools/gate/tests`：全过。

## 真机上要看的

- 不适用（工程任务）。
