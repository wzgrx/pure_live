# A17.8 电视壁纸：任务书

## 背景

- 来源：界面重做的电视部分（旧编号 U.15h、T18e.1）。设计第 1 版 2026-10-01 评审确认（“后续全部通过”，确认记录 `1e4b0b24e`），待选按建议 A（D-003）：预览里调填充、模糊、遮罩只作用在预览上，设为背景时一起保存（Z1）；静态图在设为背景时模糊一次存下来，视频壁纸不能模糊（Z2）；壁纸从设置 → 主题外观 → 背景设置进（Z3，照 pure_live_TV，不在导航轨单独一项）。设计正文在本文件夹 [README.md](README.md)（界面清点表、h1～h8、W1～W7、焦点路线），评审页导出在 `page/`。
- **还没有定的一件事**（设计“拿不准的地方”第 3 条，旧界面任务表 2026-10-01 记“设计照代码保留，等用户定”）：pure_live_TV 内置的随机壁纸接口里有“性感美女”分组和“黑丝”“白丝”等来源（本机 `~/ref/pure_live_TV/lib/features/wallpaper/wallpaper_api_source.dart:140`、`:309-318`）。电视常是全家一起用。**已定（2026-10-07，D-032）：去掉“性感美女”分组和“黑丝”“白丝”等来源，其余保留**；用户仍可自己加接口地址。
- 现象：电视界面的背景是纯色（`apps/pure_live/lib/tv/tv_theme.dart:216` 的 `TvBackground`），导航轨里“壁纸”是不显示的占位（`tv/home/tv_home_page.dart:54`，`available: false`），没有背景设置。
- 为什么现在做：第三档（D-004）。电视阶段的最后：入口在 A17.9 的设置目录，背景层要在 A17.2 的外壳里。
- 已经做过的：无。旧分支 M14.5（`37ef8cbf0`）的名字是“壁纸”阶段，但内容是网页遥控和 pure_live_TV 备份导入，**没有壁纸代码**。

## 目标和验收

1. （h1）四种来源：纯色和渐变、视频壁纸、壁纸库（来源 → 分类 → 网格）、随机壁纸 API（分组 → 来源）；显示设置：填充模式（7 种）、遮罩（0～100%）、高斯模糊（关闭、2、4、6、8、12、16、24、32、48）、清除背景；默认值照 pure_live_TV（等比覆盖、遮罩 35%、不模糊，`background_config_model.dart:12-16`）；壁纸在电视界面所有页面后面。
2. （h2）预览按钮写“填充 · 等比覆盖”“遮罩 · 35%”“模糊 · 关闭”；填充弹小菜单（`showAnchoredMenu` 电视样式），遮罩和模糊弹滑块。
3. （h3，Z1 A）预览里调的只作用在预览上，按“设为背景”时一起保存；不设就退出，正在用的背景不变。
4. （h4）背景设置页里遮罩、模糊是设置滑块行（`TvSliderRow`），←→ 调整，到头才放行。
5. （h5）清除背景先确认，焦点在“取消”。
6. （h6）沉浸式里 ←→ 和 ↑↓ 都换图；全部叫“设为背景”（不再有“设为壁纸”）。
7. （h7，Z2 A）静态图在设为背景时模糊一次、存成文件；视频壁纸选模糊时说明“视频壁纸不能模糊”；运行时不用 `ImageFiltered` 每帧模糊（[specs/UI.md](../../../specs/UI.md) 第 9.3 节）。
8. （h8）子页面默认焦点在第一行 / 第一张；设置行有自己的底色（字不压在亮壁纸上）；网格里正在用的写“✓ 当前”。
9. 随机 API 的敏感来源按维护者的决定处理（见“背景”）。
10. 手机界面一点不变；没有壁纸时电视界面和现在一样；`flutter test` 全部通过；`tv` 直接写的颜色和图标保持 0。

## 现状（读代码得出，写文件:行）

- 背景：`apps/pure_live/lib/tv/tv_theme.dart:216` 的 `TvBackground`：一个 `ColoredBox(color: palette.background)` 加默认文字和图标颜色；在 `tv/home/tv_home_page.dart` 的 `Scaffold` 里（`backgroundColor: palette.background` 加 `TvBackground`，`build` `:320` 起）。直播间、分区房间、搜索这些单独的路由页没有这一层，各自画纯色。壁纸要放在导航器下面一层（pure_live_TV 是 `core/widgets/tv_scaffold_background.dart`），各页面背景透明，面板和设置行有自己的底色。
- 外框：`tv/tv_app.dart:28` 的 `TvAppFrame` 包在导航器外面（`app/app.dart:239`），壁纸层可以放在这里。
- 入口：`tv/home/tv_home_page.dart:54` 的 `TvPane.wallpaper` 占位（Z3 A 定了不在导航轨，开发时删掉这个占位或保持不显示）；设置目录是 A17.9 的，现在电视设置只有一页（`tv/pages/tv_settings_pane.dart:46`）。
- 存储：`live_store` 没有背景设置。图片缓存：应用已有 `shared/images.dart`（网络图片），下载的壁纸和模糊后的图要存到应用目录（看 `app/` 里现有的文件目录用法）。
- 视频壁纸：播放用 `packages/live_player` 的会话（静音、循环）；电视盒子性能有限，视频壁纸和直播同时解码的情况要避开（进直播间时暂停视频壁纸）。

## 3.x 基线

- 3.x 和手机版没有界面壁纸。基线是 pure_live_TV（设计用 `b9d2f739`，本机 `37660afc`，开工前看 `git log b9d2f739..HEAD -- lib/features/wallpaper lib/services/background_config`）：`lib/features/wallpaper/`（17 个文件：`wallpaper_page.dart` 背景设置 `:77-99`、`wallpaper_display_options.dart:18-44`、`wallpaper_library_page.dart`、`wallpaper_gallery_page.dart`、`wallpaper_api_page.dart`、`wallpaper_api_group_page.dart`、`wallpaper_api_source.dart`、`wallpaper_items_page.dart`、`wallpaper_tile.dart:78`、`wallpaper_preview_page_parts.dart:285-355`、`wallpaper_immersive_page.dart:151`、`:241`）、`lib/services/background_config/background_config_model.dart:12-16`、`background_blur.dart:17`、`lib/core/widgets/tv_scaffold_background.dart`；入口 `features/settings/` 的 `theme_settings_section.dart:65`。壁纸库的来源和分类来自远端目录（`backgroundCatalogProvider`），代码里没有具体名字。
- 要保留（h1）：四种来源、列表、分类、网格、预览、沉浸式、显示设置的选项和默认值、视频壁纸。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）。
2. `docs/specs/ENGINEERING.md`（第 5 节 AGPL）；`docs/specs/UI.md` 第 5.5 节、第 9.3 节（不用模糊）。
3. 本文件夹 `README.md` 和 `page/`；`A17.9-电视设置/README.md`（设置行、滑块行、目录）、`A17.2-电视外壳/README.md`（外壳）、`A17.6-电视点播/README.md`（字号、焦点、子页面默认焦点）。
4. 代码：`apps/pure_live/lib/tv/tv_theme.dart`、`tv/tv_app.dart`、`tv/home/tv_home_page.dart`、`tv/widgets/tv_settings_rows.dart`、`packages/live_ui/lib/src/widgets/anchored_menu.dart`。

## 范围

- 可以改：新目录 `apps/pure_live/lib/tv/wallpaper/`；`tv/tv_theme.dart`、`tv/tv_app.dart`（加壁纸层）、各电视页面的背景（改透明、面板加底色）；`packages/live_store`（只加背景设置：来源、地址、填充、遮罩、模糊，默认值照 h1）；翻译文件（只加键）；`test/tv/`；本文件夹。
- 不能改：手机界面；`live_player` 的行为（视频壁纸只是用它）；设置键名和含义；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 h 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | 定敏感来源；背景层和设置（h1 的存储和“所有页面后面”、h7 的一次性模糊、h8 的设置行底色）：纯色和渐变先能用 | `tv/tv_app.dart`、`tv_theme.dart`、`live_store`、`tv/wallpaper/` | 新用例：设了纯色后首页、直播浏览、设置页后面都是它；面板和设置行有底色；清除后回到现在的样子 |
| 2 | 背景设置页（h4、h5）：四个来源入口、显示设置滑块、清除先确认；入口放进电视设置（A17.9 没做时临时放在现有电视设置页的“外观”组） | `tv/wallpaper/`、`tv/pages/tv_settings_pane.dart` | 新用例：默认焦点第一行；遮罩滑块 ←→ 调、到头放行；清除确认焦点在“取消” |
| 3 | 壁纸库、随机 API、网格、预览（h2、h3）和沉浸式（h6）；静态图模糊存文件（h7） | `tv/wallpaper/` | 新用例：预览里调遮罩，不设为背景退出后全局设置没变；设为背景后一起保存；沉浸式 ←→ 换图；网格“✓ 当前” |
| 4 | 视频壁纸：静音循环播放、进直播间和点播时暂停、选模糊时说明 | `tv/wallpaper/` | 新用例：视频壁纸设好后背景是视频层；进直播间时视频壁纸暂停、回来继续（假播放会话） |

每个阶段都要能单独合并。登记表的阶段（设计 ✓ → 开发 → 真机）开工时按上表拆开。

## 测试

- 改之前会失败：`test/tv/` 加“设置了纯色背景后电视首页后面是这个颜色”（现在没有背景设置）。
- 每个阶段的用例见上表。网络图片和远端目录用假的（不访问壁纸接口）；模糊用小图测“只算一次”（调用次数）；定时器至少 1 秒（沉浸式提示淡出用可注入时长）。
- 1080p@2x 和 720p 各一个布局测试：网格 4 列、预览按钮一行放下。

## 真机验证（维护者在电视或盒子上做）

| 步骤 | 期望 |
|---|---|
| 1. 设置 → 主题外观 → 背景设置 | 焦点在第一行“纯色”；行有底色 |
| 2. 纯色里选一个渐变 | 首页、浏览页、设置页后面都是它 |
| 3. 壁纸库 → 一个来源 → 一张图 → 预览，把遮罩调到 60%，按返回 | 正在用的背景没变 |
| 4. 再进预览调遮罩，按“设为背景” | 背景换成这张图、遮罩 60% |
| 5. 背景设置把模糊调到 16 | 背景变模糊，切页面时不卡（低端盒子上看焦点移动是否流畅） |
| 6. 设一个视频壁纸，进直播间再返回 | 直播时视频壁纸不播（不抢解码），回来继续 |
| 7. 清除背景 | 先确认，焦点在“取消”；清除后回到纯色 |

## 风险和注意

- 性能：低端盒子上全屏图片加遮罩已经有开销，模糊必须预先算好；视频壁纸和直播、点播不能同时解码。
- 存储：下载的壁纸和模糊后的图放应用目录，换背景时删掉旧的，不要越积越多。
- 背景透明后，以前靠页面纯色背景的组件（对话框遮罩、面板、卡片）要各自有底色；逐页看一遍。
- 敏感来源的决定要写进 record.md，并在 DECISIONS 由维护者记一条（不是本任务改 DECISIONS）。
- 可能冲突的文件：`tv/tv_app.dart`、`tv/tv_theme.dart`（A17.1 的组件都依赖它）、`tv/home/tv_home_page.dart`（A17.2）、`tv/pages/tv_settings_pane.dart`（A17.9）、`live_store` 的 `settings.dart`。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A17.8` 或本机工作区；提交信息以 `[A17.8]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条验收做到没有；敏感来源的决定和做法；模糊怎么做、存在哪；视频壁纸和直播怎么避开；测试数量（改之前失败几个）；新设置（键名、默认值）和翻译键；要在电视上看的；可能冲突的文件。
