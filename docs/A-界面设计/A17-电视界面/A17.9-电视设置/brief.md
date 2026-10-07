# A17.9 电视设置：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15i、T18e.2）。设计第 1 版 2026-10-01 评审确认（设计合并 `fda6baec2`，确认记录 `7dd67b133`“U.11a-c, U.12a-d and U.15i confirmed”；用户“后续全部通过”），待选按建议 A（D-003）：导航栏和平台的显示、排序照手机合成一页（N1）；pure_live_TV 另有的 8 个弹幕引擎参数先不放（D1，等 D03.1 渲染选型）；设置页顶栏“返回”按钮保留、默认焦点在第一行（T1）；行首图标保留（I1）。设计正文在本文件夹 [README.md](README.md)（49 个页面的种类和对应的手机任务、12 种页面、c1～c18、P1～P19、焦点路线、“交给其他任务的”），评审页导出在 `page/`。
- 跨任务记录（2026-10-01）：电视去掉“主题模式”（只有深色，A11.2 → 这里；A17.1 已去掉）；电视设置面板的颜色列表加品牌蓝；电视设置的文字、图标、顺序照手机，手机设置开发时改了文字，电视跟着同步；设置在外壳里是整页还是侧边栏的一格随 A17.2 定。设计写的时候手机 A11.1～A11.5、A12.x、A10.2、A09.10 还在设计，**现在都已完成**：电视的文字、顺序、行样式以现在的手机代码为准（`features/settings/settings_catalog.dart`）。
- 现象：电视的“设置”是一页常用项（`apps/pure_live/lib/tv/pages/tv_settings_pane.dart`：界面模式、主题颜色、文字大小、焦点放大、默认清晰度、弹幕三项、网络与代理、更多设置），其余都要点“更多设置”进手机设置页——手机的行没有电视焦点描边、字小、选择框是手机样子。
- 为什么现在做：第三档（D-004）。电视阶段在 A17.2 之后、A17.5 和 A17.8 之前（它们的入口和扫码组件在这里）。
- 半成品：旧分支 M14.5，工作区 `/home/wzgrx/projects/pure_live/.claude/worktrees/agent-af3e4f5945df78e33`，提交 `37ef8cbf0`（“WIP M14.5 (stopped 2026-10-01 at the UI redesign; not merged)”，基于 `09c352cb7`，提交之后工作区里没有再改动的文件）：`tv/remote/web_remote_server.dart`（348 行，手机网页遥控服务）、`tv/remote/tv_remote_actions.dart`（137）、`packages/live_store/lib/src/legacy/tv_backup.dart`（183，把 pure_live_TV 的备份和设备同步文件按 3.x 的格式读进来，列出读不了的项）和测试 `tv_backup_test.dart`（126）、备份页预览的改动（旧目录 `lib/pages/backup/`）。扫码到手机（c15）和“从 pure_live_TV 导入数据”可以参考它；`tv_backup.dart` 是 J 组（备份恢复）的逻辑，要单独审。

## 目标和验收

1. （c1）49 个页面、入口、按模式（直播 / 视频 / 音乐）过滤目录的规则、每个设置项和取值、电视专有的页（模式、音乐、点播视频、导航图标、日志、账号密码锁）都在；按键：确认打开或切换，开关左关右开，滑块左右调、到头放行，返回逐级退出；返回后焦点回到原来那一行。v4 没有的功能（README 对照表里手机没有的项，例如账号密码锁、Exo / IJK / Fvp 内核）不做，在 record.md 列清。
2. （c2、c6）设置行用手机设置行组件的电视样式（A17.1 的 `TvSettingsRow` 一族）：标题 18、副标题 14、组标题 15；右边当前值加 `›`、开关、滑块、计数四种；同一个设置项的文字、图标、顺序照手机。
3. （c3）页面留左右 48、上下 28；内容一列最宽 720 居中，编辑页（颜色）用满 864。
4. （c4，T1 A）打开时焦点在第一行（从子页回来在原来那一行）；“返回”按钮保留，第一行按上到它。
5. （c5）焦点 3 像素近白描边 + 行放大 1.02（按钮、色块 1.05）+ 底色变亮；组卡片用表面容器色，看得出分组。
6. （c7）选项对话框：当前项主色加勾，焦点项近白描边，分得开；底部“取消”；确认即选用并关闭（A17.1 的 `showTvChoice` 已经是这样）。
7. （c8、c9、c10）目录的组和顺序照手机设置总览（A11.1）；电视专有的“模式设置”在最前、“关于”在最后；目录顶栏有“配置预览”按钮，配置预览可聚焦、上下键滚；直播模式目录有“视频设置 → 视频”（手机视频设置里电视用得上的项，含弹幕设置入口）。
8. （c11，N1 A）导航栏的显示和顺序合成一页：确认显示或隐藏（只剩一个时不让关，提示“侧边菜单至少要保留一个入口”），长按确认或菜单键进入移动、上下移动、确认放下、返回取消；“图标”一行；平台显示同样合成一页。编辑的就是 A17.2 的电视入口设置。
9. （c12）选择颜色：色块网格（常用一行 18 个、色板 18 色 × 3 深浅），不写英文名，下方显示焦点颜色的色值和当前值；颜色列表里有品牌蓝。
10. （c13，D1 A）弹幕设置用手机已确认的弹幕设置组件（`DanmakuSettingsContent`，A17.4 做的电视样式），文字照手机；pure_live_TV 另有的 8 个引擎参数不放。
11. （c14）播放内核页照手机分组（内核、解码、网络、MPV 高级设置）；“MPV 官方文档”弹二维码在手机上看；“恢复默认设置”先确认。
12. （c15、c16）扫码到手机统一一个组件：二维码在左，右边标题、服务状态、编号步骤、地址；用在 Cookie、备份浏览、日志、代理、屏蔽词、标签、设备同步、项目主页、MPV 文档；日志页加“启用本地日志”开关。
13. （c17）哔哩哔哩扫码块：右边写状态和步骤，“刷新二维码”一直在（有默认焦点）；状态文字照手机（正在加载二维码…、正在核验账号…）。
14. （c18）关于照手机关于页（在线更新、历史记录、开源许可证、项目主页、项目声明）；在线更新和版本更新合成一页：状态卡（发现新版本 + 下载并安装）、安装包、下载源、渲染器、更新日志、版本历史。
15. 手机设置一点不变；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 电视设置：`apps/pure_live/lib/tv/pages/tv_settings_pane.dart`（164 行）：`tvThemeColors`（`:20`，6 个预设，没有品牌蓝以外的手机色板）、`tvTextScales`（`:30`）、`tvDanmakuSizes`（`:33`）、`tvDanmakuOpacities`（`:36`）、`TvSettingsPane`（`:46`）；三组：界面模式 `TvChoiceRow`（`:62`）、主题颜色（`:75`）、文字大小（`:87`）、焦点放大 `TvSwitchRow`（`:96`）；默认清晰度（`:108`）、显示弹幕（`:118`）、弹幕大小（`:125`）、弹幕透明度（`:133`）；网络与代理（`:145-150`，打开手机设置的“网络”分区）、更多设置（`:152-157`，打开手机设置页 `RoutePath.kSettings`）。
- 电视设置行组件：`tv/widgets/tv_settings_rows.dart`（470 行）：`TvSettingsGroup`（`:12`）、`TvSettingsRow`（`:60`）、`TvSwitchIndicator`（`:166`）、`TvSwitchRow`（`:202`）、`TvLinkRow`（`:261`）、`TvChoiceRow`（`:295`）、`TvSliderRow`（`:365`）。没有计数行、排序行、色块网格、扫码块。
- 手机设置（全部完成）：目录和每一项的定义在 `apps/pure_live/lib/features/settings/settings_catalog.dart`（1785 行，`settingsCatalog` `:321`，`settingsGroupNotes` `:297`，内核设置 `kernelSettings` `:1776`）；分区视图 `settings_section_view.dart`；行 `settings_tiles.dart`；编辑框 `settings_editors.dart`；对话框 `settings_dialogs.dart`；外观（颜色、导航栏 `HomeMenusList` `appearance_pages.dart:1176`）、字体 `font_manager_page.dart`、数据 `data_tools.dart`、观看数据 `audience_pages.dart`、弹幕页 `danmaku_page.dart`。账号 `features/account/`、`auth/`；备份 `features/backup/`；WebDAV `features/web_dav/`；设备同步 `features/remote_receiver/`；版本 `features/version/`；标签 `features/tags/`；屏蔽 `features/shield/`。
- 电视路由：`apps/pure_live/lib/routes/tv_router.dart` 把手机的全部 `pageRoutes` 原样保留，所以现在“更多设置”打开的是手机页面。
- 设置键：`packages/live_store/lib/src/settings/settings.dart`，电视专有的只有 `uiMode`（`:1389`）、`tvFocusZoom`（`:1400`）。
- 局域网：设备同步的服务 `features/remote_receiver/remote_sync_service.dart`（`HttpServer` `:192`）；扫码到手机要的网页遥控服务没有（旧分支 M14.5 有半成品，A17.5 的任务书也提到）。

## 3.x 基线

- 手机 3.x 的设置是手机任务的基线（A11.x、A12.x 的 README 各有文件:行）；电视设置的基线是 pure_live_TV（设计用 `b9d2f739`，本机 `37660afc`，开工前看 `git log b9d2f739..HEAD -- lib/features/settings`）：外壳 `core/widgets/tv_page_scaffold.dart:111-121`、`tv_page_shell.dart:163-171`；目录 `features/settings/tv_settings_page.dart:21-229`；行 `core/widgets/tv_settings_row.dart:73-238`、`tv_settings_switch_tile.dart:34-43`、`tv_settings_slider_tile.dart:39-61`、`tv_settings_option_tile.dart:10-18`；选项对话框 `core/dialog/tv_select_dialog.dart`、`tv_dialog_option_tile.dart:63-73`；代表页面见 README“pure_live_TV 的样子”（刷新、播放内核、弹幕、颜色、导航、哔哩哔哩、扫码页、关于、在线更新）。
- 设置键名和含义照 3.x 和手机（D-018），电视只加不改。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 5.5 节、第 7 节。
3. 本文件夹 `README.md`（尤其 49 页对照表、页面种类、“交给其他任务的”）和 `page/`。
4. 手机设置：`docs/A-界面设计/A11-设置界面/` 下 A11.1～A11.5 的 README 和 record.md；`A12-账号和数据界面/` 下 A12.1、A12.2、A12.4、A12.6；`A15-小页面/A15.2-关于和版本/README.md`；`A09-浏览界面/A09.10-标签管理/README.md`；`A08-弹幕界面/A08.3-弹幕屏蔽页/README.md`。
5. 电视：`A17.1`（组件）、`A17.2`（导航栏入口设置、设置是整页还是一格）、`A17.4-电视直播间/brief.md`（弹幕设置的电视样式）、`A17.5-电视网络电视和影片/brief.md`（局域网服务）。
6. 代码：上面“现状”列的文件；旧分支 M14.5 的 `tv/remote/`、`tv_backup.dart`（只读）。

## 范围

- 可以改：`apps/pure_live/lib/tv/`（新目录 `tv/settings/`：目录、各种页面、扫码块）；`routes/tv_router.dart`（电视的设置路由换成电视页面，手机页面仍可从“更多”进）；手机设置组件为了让电视用同一份目录和定义而做的拆分（`settings_catalog.dart` 的定义本来就是数据，电视直接读；手机样子和测试不变）；`packages/live_store`（只加电视需要的新设置，例如导航入口、导航图标、背景，D-018）；翻译文件（只加键）；`test/tv/`；本文件夹。
- 不能改：手机设置的样子、顺序和文字（电视跟着手机，不是反过来）；设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 外壳和目录（c3、c4、c5、c8、c9、c10）：电视设置目录读手机 `settingsCatalog`，按模式过滤；“配置预览”；行和组的电视样式；默认焦点第一行、返回回到原来那一行 | `tv/settings/`、`tv_settings_pane.dart`（换成目录）、`tv_router.dart` | 新用例：目录组和顺序和手机一致（逐组断言）、电视专有组的位置；默认焦点；子页回来焦点在原来的行；配置预览上下键滚 |
| 2 | 通用页面种类（c2、c6、c7）：开关列表、选择列表和选项对话框、单选页、滑块页（含计数行）、跳转页；用手机定义生成，覆盖 A11.2～A11.5 的全部项 | `tv/settings/`、`tv/widgets/tv_settings_rows.dart`（加计数行） | 新用例：每种页面一个（刷新设置、播放内核、弹幕之外的滑块页）；开关左关右开；选项对话框当前项和焦点项分得开；禁用项写原因 |
| 3 | 编辑页（c11、c12）：导航栏显示和顺序一页（A17.2 的入口设置）、平台显示一页、选择颜色、导航图标 | `tv/settings/` | 新用例：只剩一个入口时不让关；长按进入移动、上下、确认放下、返回取消；颜色网格 18 × 3、焦点色值、品牌蓝 |
| 4 | 扫码到手机组件（c15、c16）和用到它的页（Cookie、备份浏览、日志、代理、屏蔽词、标签、设备同步）；哔哩哔哩扫码块（c17）；弹幕设置（c13，用 A17.4 的电视样式）；播放内核（c14） | `tv/settings/`、局域网服务（和 A17.5 共用，先做的那个任务建，另一个用） | 新用例：扫码块三种状态；日志页“启用本地日志”；哔哩哔哩“刷新二维码”默认焦点；“恢复默认设置”先确认 |
| 5 | 关于和在线更新（c18）；音乐设置、视频设置（点播）两页（随 A17.6、A17.7，那两个没合并时不显示） | `tv/settings/`、`features/version/` 的拆分 | 新用例：在线更新一页的状态卡、下载并安装；版本历史 |

每个阶段都要能单独合并（阶段 1 合并后目录可用，没做的页面先打开手机页面，不能是坏界面）。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表拆开。

## 测试

- 改之前会失败：`test/tv/` 加“电视设置是目录，组和顺序和手机设置总览一致”（现在是一页常用项）。
- `test/tv/tv_test.dart` 的“电视设置”用例（菜单走到设置、界面模式改成手机）照新目录改并通过。
- 每个阶段的用例见上表；用手机设置测试里已有的假存储（照 `test/features/settings/` 的写法）；不访问网络（更新用假 feed，扫码服务用假服务）；定时器至少 1 秒。
- 1080p@2x 和 720p 各一个布局测试：内容最宽 720 居中、48 / 28 边距、字不小于 14。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 导航栏“设置” | 目录，焦点在第一行“切换模式”；组和顺序和手机设置一样 |
| 2. 进“刷新设置”，在开关上按左、右 | 左关右开；“关注自动刷新”关掉时间隔行变灰并写原因 |
| 3. 返回 | 焦点回到“刷新设置”那一行 |
| 4. 播放内核 → 内核切换 | 选项对话框焦点在当前项，当前项主色加勾、焦点项白框，分得开 |
| 5. 外观 → 导航栏显示控制，长按一个入口 | 进入移动，上下移、确认放下；只剩一个时关不掉 |
| 6. 选择颜色 | 18 × 3 网格，下方色值；选了返回，主题色变 |
| 7. 账号 → 哔哩哔哩（没登录） | 扫码块，焦点在“刷新二维码”，状态文字照手机 |
| 8. 备份与恢复 → 手机扫码导入 / 导出 | 二维码在左、步骤在右；手机扫码能打开网页 |
| 9. 关于 → 在线更新 | 一页：状态卡、下载源、渲染器、更新日志、版本历史 |

## 风险和注意

- 规模大（49 页），一定按页面种类做通用组件、用手机的定义生成，别一页一页手写；手机改设置时电视自动跟着。
- 电视专有、v4 没有的功能（账号密码锁、多内核、pure_live_TV 的引擎参数、应用定时退出等）不要顺手加：列进 record.md，新功能走 V01 提议（D-026）。
- “从 pure_live_TV 导入数据”（旧分支 `tv_backup.dart`）是 J 组的事：建议另开 J 组任务，本任务只在备份页留入口的位置。
- 可能冲突的文件：`features/settings/`（A11 后续任务、A08.6）、`routes/tv_router.dart`（A17.2）、`tv/widgets/tv_settings_rows.dart`、`live_store` 的 `settings.dart`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.9` 或本机工作区；提交信息以 `[A17.9]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；49 页逐页的状态（做了 / 打开手机页 / v4 没有不做）；用手机定义生成电视页的做法；局域网服务在哪个任务建的；测试数量（改之前失败几个）；新设置和翻译键；要在电视上看的；可能冲突的文件。
