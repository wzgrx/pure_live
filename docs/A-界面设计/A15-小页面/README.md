# A15 小页面

几张独立的小页面：工具箱（粘贴直播链接或分享口令，跳转进直播间或获取直链）；关于、版本更新、版本历史。

## 范围

- 包括：
  - 工具箱（A15.1）：“平台链接”一组（一句说明、多行输入框、粘贴 / 清除、“链接跳转”“获取直链”两个按钮、进行中的说明和“取消”）、单独一张“支持解析的平台”卡片（默认收起）、选清晰度和选线路的对话框 `ToolboxChoiceDialog`、自动填充的提示条。
  - 关于和版本（A15.2）：关于页（Logo、版本、在线更新和“新版本 v…”标签、版本历史、开源许可证、项目主页、声明）、版本更新页（状态卡、“下载文件 · 平台”里本平台的安装包和“本机”标签、收起的下载源、下载源对话框、更新日志）、版本历史（列表和详情，页面宽 840 起左右分栏）、下载确认。
- 不包括（归哪里）：
  - 链接解析和取直链的逻辑在 [E04 链接解析和分享口令](../../E-直播平台/E04-链接解析和分享口令/README.md)；分享口令的识别在 O03.2；更新检查、下载、安装的逻辑和发布在 [Y02 更新通道](../../Y-发布和运营/Y02-更新通道/README.md)；页面的功能（模块重构时的入口、动作）在 [I08 小页面](../../I-浏览和发现/I08-小页面/README.md)。
  - 启动时的“发现新版本”对话框、下载进度对话框、选下载目录（`update_prompt.dart`、`update_download.dart`、`download_directory_dialog.dart`）在 [A06.3 全局弹窗](../A06-首页和全局/A06.3-全局弹窗/README.md)（这里的下载直接调用它）；首页里工具箱（`HomeAction.openLink`）、关于（更多菜单）的入口在 [A06](../A06-首页和全局/README.md)；页面标题居中还是靠左（D-011）在 A02.1。
  - 电视的关于和检查更新在 [A17.9](../A17-电视界面/A17.9-电视设置/README.md)；电视的链接放映在 [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md)（要用这里的 `SupportedPlatformsCard` / `linkPlatforms`）。

## 现状：做到哪、怎么工作的

- **用户看得到的**：
  - **工具箱**：从首页搜索旁的链接按钮、宽屏侧栏、顶栏菜单进入（都是 `HomeAction.openLink`，`features/home/menu_button.dart:100`、`:117`）；标题居中（照 3.x，D-011）。组标题“平台链接”在卡片外，卡片里一句 13 号说明和多行输入框（空时右边“粘贴”，有字时“清除”）；下面“链接跳转”（实心）和“获取直链”（浅色）各 48 高并排，可用宽度 <320 时上下排。进行中写“正在解析链接… / 正在读取直播流地址…”，两个按钮变灰，右边“取消”。下面一张单独的“支持解析的平台”卡片（默认收起，展开是平台标签）。打开或回到页面时剪贴板里有链接会自动填进空框（提示条）。获取直链：先选清晰度、再选线路（对话框标题 20 号，每项 ≥56 高、地址一行截断），复制后提示。除了链接，也认 3.x 的分享口令（O03.2）。内容最宽 720 居中；窗口高 <480（横屏手机）时顶栏 48 高。
  - **关于**：顶栏只有返回；Logo 直接显示（不再弹跳），下面应用名和版本；“关于”一组：在线更新（有新版本时右边主色“新版本 v…”）、版本历史、开源许可证；“项目”一组：项目主页（地址和外链图标）、声明（信息图标 + 整段 `about_legalese`）。最宽 720。
  - **版本更新**：右上角刷新；检查中、失败（`AppStatusView` + “重试”）、结果三种；状态卡写“发现新版本 / 已是最新版本”、已安装和最新版本号、预发布标记；“下载文件 · Android”列出本平台的包，每行“ARM64 (64位) · 大小 [本机]”和右边“下载并安装”（先试最快的源，失败换下一个，用 A06.3 的下载对话框）；“选择下载源（N 个）”点开才显示各下载源按钮，点一个出对话框（“ARM64 (64位) · 下载源 3”、文件名、地址，“在应用内下载”“在浏览器中下载”“复制链接”）；没有本平台的包（iOS）时说明并给“打开发布页面”；下面是更新日志（Markdown）。
  - **版本历史**：列表是一张卡片，每行“版本 · 发布于 日期”和“最新”“当前”标签，懒加载；页面宽 ≥840 且字体放大不超过 1.5 倍时左右分栏（左 320），横屏手机 852 也是分栏；窄时点一行出详情对话框。详情头部一行（头像、版本、日期、打开发布页面、✕），日志和文件单独滚动；返回键、Esc、点外面关。文件卡片有“复制链接”和“下载”，下载先确认“是否下载“…apk”（38.6 MB）？下载完成后会打开安装。”，确认后在应用内下载（3.x 的做法）。
- **内部怎么工作**：
  - 工具箱：`ToolboxPage`（`apps/pure_live/lib/features/toolbox/toolbox_page.dart:35`）持有 `ToolboxController`（`features/toolbox/toolbox_actions.dart:45`）；`jump`（`:99`）、`directLink`（`:108`）都走 `_run`（`:155`：一次只做一件、`CancelToken` 取消、错误按动作和原因给提示 `:175`），链接先经 `_resolve`（`:194`：先认分享口令 `:196`、下线平台的链接 `:201`、再用 `LinkParser`）；平台列表 `linkPlatforms`（`apps/pure_live/lib/shared/links/supported_platforms.dart:12`）按已注册、实现了链接规则（`LiveSiteLinks`）的平台算，去掉网络电视（`:12-15`）。剪贴板经 `toolboxClipboardProvider`（`toolbox_page.dart:14`），测试里可替换。
  - 版本：`UpdateFeed`（`features/version/update_feed.dart:316`，`updateFeedProvider` `:369`）读仓库的 `assets/version.json` 和 GitHub 发布（3.x 已装的应用也读这份，格式不能改）；`UpdateInfo.isNewer`（`:88`）只比版本号（`isNewerVersion`，`features/version/app_version.dart:34`），构建号不参与（Y02.1）。启动检查和版本页检查都经 `noteCheckedUpdate`（`update_feed.dart:23`）记进 `foundUpdate`（`:20`），关于页用 `ValueListenableBuilder` 读它（`about_page.dart:138`）。本平台的包由 `platformPackages`（`version_page.dart:22`）挑、`nativePackageTitle`（`:49`，按 `Abi.current()`）标“本机”；下载源 `downloadSources`（`update_feed.dart:296`，GitHub 原址加镜像前缀 `:273`）。
  - 路由：`RoutePath.kAbout`、`kVersionHistory` 都由 `AboutPage`（`about_page.dart:18`）接，`kVersionHistory` 转给 `VersionPage`（`:27`）；`kVersionPage` 直接是 `VersionPage`（`routes/app_router.dart:77`），按路由分成 `UpdateView` 和 `ReleaseHistoryView`。版本历史放在 `features/version/`，因为它的下载要用 `showUpdateDownload`，放在 `about` 里就多一条跨功能引用（门禁不允许）。
- **完成度**（和 3.x 对照）：
  - 一致的：工具箱两个动作、自动填充、选清晰度和线路、提示文字；关于的各行和链接；版本页的下载源、复制、更新日志、刷新；版本历史的分栏、详情、应用内下载（v4 之前直接开浏览器，A15.2 c13 改回 3.x）。
  - 确认过的改动：A15.1 c2～c9（Y1、Y2 按 A）、A15.2 c1～c14（N1～N3 按 A；c14 用 A06.3 的对话框，有偏差），都按 D-003 由维护者选建议 A。
  - 还缺：两个任务都**没有 K90 结果**（S02.2、S02.3 没看这几页；应用内下载和安装归 S02.4，未开始）；新版本对话框以 A06.3 还是 A15.2 的设计为准没定（见“已知问题”）。

## 代码地图

| 文件 | 职责 | 设计 |
|---|---|---|
| `apps/pure_live/lib/features/toolbox/toolbox_page.dart`（375 行） | `toolboxClipboardProvider`（`:14`）、`ToolboxPage`（`:35`，自动填充 `_fillFromClipboard` `:88`、粘贴 `:98`、两个动作 `:104`、`:109`、“平台链接”组 `SettingsGroup` `:167`、最宽 720 `ReadableContent` `:187`、标题 `centredPageTitle` `:156`、矮窗口顶栏 48 `:153-157`）、`_LinkCard`（`:199`，说明、输入框、粘贴 / 清除、进行中和取消）、`ToolboxChoiceDialog`（`:288`）、`_ActionButtons`（`:329`，<320 上下排 `:361`） | A15.1 c2～c9 |
| `apps/pure_live/lib/features/toolbox/toolbox_actions.dart`（226） | `ToolboxAction`（`:14`）、`toolboxLinksProvider`（`:23`）、`toolboxSiteProvider`（`:28`）、`ToolboxChooser`（`:33`）、`ToolboxCancelled`（`:36`）、`ToolboxController`（`:45`，`jump` `:99`、`directLink` `:108`、`_run` `:155`、`_resolve` `:194`） | A15.1 c1、c6；O03.2（口令） |
| `apps/pure_live/lib/shared/links/supported_platforms.dart`（71） | `linkPlatforms`（`:12`）、`SupportedPlatformsCard`（`:21`，默认收起的平台标签卡片）；A17.5 开发时也用 | A15.1 c4 |
| `apps/pure_live/lib/features/about/about_page.dart`（228） | `AboutPage`（`:18`，按路由分关于和版本历史 `:26-27`）、`AboutView`（`:35`，打开项目主页 `:46`、许可证 `showLicensePage` `:59`、矮窗口顶栏 48 `:75-78`、两组行 `:135-190`、最宽 720 `:194`）、`_NewVersionBadge`（`:206`） | A15.2 c1～c5 |
| `apps/pure_live/lib/features/version/version_page.dart`（593） | `platformPackages`（`:22`）、`nativePackageTitle`（`:49`）、`nativePackageTitleProvider`（`:59`）、`VersionPage`（`:77`）、`UpdateView`（`:96`，刷新 `:164`、检查中和失败 `:177-189`）、`_Details`（`:206`，“下载文件 · 平台” `:228`、没有包时 `:257-274`、更新日志 `:283`）、`_StatusCard`（`:297`）、`_Package`（`:367`，“本机” `:417`、“下载并安装” `:431`、“选择下载源” `:459`、下载源对话框的三个按钮 `:550-574`） | A15.2 c6～c9 |
| `apps/pure_live/lib/features/version/release_history_view.dart`（555） | `releaseHistorySplitWidth` 840（`:20`）、`ReleaseHistoryView`（`:27`，分栏判断 `:95`、左栏 320 `:132`、窄时详情对话框 `_showDetails` `:252`）、`_Badge`（`:287`）、`_VersionLine`（`:313`，“发布于”和标签 `:341-347`）、`_ReleaseHeader`（`:357`）、`_ReleaseBody`（`:426`）、`_FileCard`（`:447`，下载确认 `_download` `:458-464`） | A15.2 c10～c13 |
| `apps/pure_live/lib/features/version/update_feed.dart`（389） | `updateRepository`（`:12`）、`projectUrl`（`:15`）、`foundUpdate`（`:20`）、`noteCheckedUpdate`（`:23`）、`supportedAndroidAbis`（`:26`）、`UpdateInfo`（`:31`，`isNewer` `:88`）、`ReleaseFile`（`:92`）、`ReleaseInfo`（`:118`）、`PackageKind`（`:204`）、`downloadMirrorPrefixes`（`:273`）、`downloadSources`（`:296`）、`currentUpdatePlatform`（`:305`）、`UpdateFeed`（`:316`） | A15.2 c3、c7；Y02 |
| `apps/pure_live/lib/features/version/app_version.dart`（61） | `pubspecVersion` 4.0.0（`:5`）、`pubspecBuild` 5001（`:8`）、`appVersion`（`:12`）、`isNewerVersion`（`:34`）、`compareVersions`（`:48`） | Y02.1 |
| `apps/pure_live/lib/features/version/markdown_text.dart`（322） | `MarkdownText`（`:10`，标题、列表、引用、代码、表格、行内链接）：更新日志和版本详情的正文 | A15.2 c1 |
| `apps/pure_live/lib/features/version/update_prompt.dart`（306）、`update_download.dart`（643）、`download_directory_dialog.dart`（83） | 启动时检查 `checkForUpdateOnStartup`（`update_prompt.dart:34`）和 `NewVersionDialog`（`:108`）；`showUpdateDownload`（`update_download.dart:74`）和 `UpdateDownloadDialog`（`:191`）；选下载目录 | A06.3（A15.2 只改了挑本机的包和记下新版本） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/toolbox/toolbox_page_test.dart`（10） | 打开链接的直播间、离线认分享口令（O03.2 加）、选清晰度和线路后复制、取消选择、各种失败的提示、自动填充和平台列表；竖屏（组标题在卡片外、一个框、粘贴 / 清除、两个按钮的顺序图标和高度、支持列表收起）；进行中（说明、按钮变灰、对话框标题 20 号、选项 ≥56、地址一行）；852×393 和 1280×800；平台列表只含有链接规则的平台 |
| `apps/pure_live/test/features/version/version_page_test.dart`（19） | 关于页（没有标题、两组五行、图标、“版本历史”、没有 Firebase、声明、“新版本 v9.0.0”、不弹跳）；启动检查和版本页记下 / 清掉新版本；版本更新页的包、“本机”、下载源收起和展开、下载源对话框；版本历史的标签、关闭在右上、Esc、839 / 852 分栏、下载确认；852×393 和 1280×800 最宽 720 |
| `apps/pure_live/test/features/version/update_dialogs_test.dart`（10） | A06.3 的新版本、下载、下载目录对话框（这里的下载用它） |

## 3.x 基线

文件都在 `git show v3.2.11:lib/modules/` 下（本机副本 `~/ref/v3ref/lib/modules/`）：

- 工具箱：`toolbox/toolbox_page.dart`（151 行）：`ToolBoxPage`（`:7`），两张卡片（`_buildToolCard` `:21`、`:35`，各一个 `ExpansionTile` `:71` 包着输入框 `:79`，一张跳转、一张取直链）；`toolbox/toolbox_controller.dart`（305，`autoCheckClipboard` `:250`）、`toolbox/toolbox_direct_link_flow.dart`（72，选清晰度和线路）、`toolbox/toolbox_action_scope.dart`（74）。入口：`common/widgets/search_button.dart:12-19`、`modules/home/tablet_view.dart:121-127`、`common/widgets/common_appbar_actions.dart:45-55`。
- 关于：`about/about_page.dart`（160，Logo 用 `Curves.elasticOut` 弹跳 1 秒 `:33-34`）。
- 版本历史：`about/version_history.dart`（801）：`VersionHistoryPage`（`:14`），按整屏宽 >760 且字体放大不超过 1.5 分栏（`:76`），窄时 `_showMobileDetailsDialog`（`:308`），下载确认 `_confirmDownload`（`:391`，确认后应用内下载），`_DesktopChangelogDetailPanel`（`:477`）；`about/widgets/release_history_repository.dart`（116）。
- 新版本对话框：`about/widgets/version_dialog.dart`（87，`NoNewVersionDialog` `:6`、`NewVersionDialog` `:26`）。
- 版本更新：`version/version_page.dart`（472，`VersionPage` `:16`，下载源按钮 `:331`、`_showActionDialog` `:353`、`downloadAndInstallApk` `:460`）、`version/version_controller.dart`（106）。
- 必须保留：`assets/version.json`、`assets/releases.json` 留在 master，格式不变（D-015，3.x 从这里检查更新）；项目主页和下载源地址照 3.x；下载先确认再在应用内下载、交给系统安装器（3.x `downloadAndInstallApk`）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 两个任务登记为“完成”，记录里没有 K90 结果（S02.2、S02.3 没看这几页） | A15.1、A15.2 的 `record.md` | 不符合 PROCESS“完成要有真机结果” | 写进本单元报告；应用内下载归 [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)，页面本身建议在 [S03.1](../../S-质量和验证/S03-统一验证/README.md) 补看 |
| 启动时的新版本提示用 A06.3 的对话框（“其他下载方式 / 取消 / 下载并安装”），没照 A15.2 设计图的“项目主页 / 以后再说 / 去更新”和“发布于” | `features/version/update_prompt.dart:108` 的 `NewVersionDialog` | 两个任务的设计图不一致，现在以 A06.3 为准 | A15.2 偏差 1，要维护者定以哪个为准（没有登记任务） |
| 同版本换包时应用内收不到更新提示（只比版本号） | `update_feed.dart:88`、`app_version.dart:34` | 4.0.0 覆盖发布后已装的用户收不到提示 | [Y02.1](../../Y-发布和运营/Y02-更新通道/Y02.1-同版本换包时应用内收不到更新/README.md)（D-008） |
| “本机”按应用自己的架构判断，64 位手机装了 32 位包时标的是 32 位包 | `version_page.dart:49` | 装回同一种架构，和已装的一致 | 不改（A15.2 偏差 2） |
| 跨功能引用 `about -> version/app_version.dart`、`about -> version/update_feed.dart` | `tools/gate/ui_baseline.json:3-4` | 门禁基线里 2 条 | 版本信息挪到 `shared/` 时去掉（没有登记任务） |
| 工具箱、关于、版本更新、版本历史在电脑上按 Esc 不返回（只有版本历史的详情能 Esc 关） | `toolbox_page.dart:152`、`about_page.dart:72`、`version_page.dart:156`、`release_history_view.dart:74` 都没有 `EscapeBack` | 规范 5.4 的 Esc 返回链不全 | A05.1 c3 |
| 代码注释里还用旧编号（`U.12a`、`U.12b`、`U.3a c5`、`F.0a`） | `toolbox_page.dart`、`toolbox_actions.dart:193`、`menu_button.dart:99` 等 | 按注释找文档要先查 [MAPPING.md](../../MAPPING.md) | Z 组一次性替换 |

## 相关决定和规范

- D-003：A15.1 的 Y1、Y2，A15.2 的 N1～N3 由维护者按建议 A 定。
- D-008（4.0.0 覆盖发布，同版本换包收不到提示）、D-011（页面标题按 3.x 居中或靠左：工具箱居中，关于、版本靠左）、D-015（`assets/version.json`、`assets/releases.json` 不能删）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（阅读型内容最宽 720、分栏按父组件 840）、第 7 节（下载确认是对话框）、第 3 节（同一件事一种做法：新版本对话框只有 A06.3 一个）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/toolbox test/features/version`（39 个用例声明）。网络请求和下载用测试替身（`updateDownloadToolsProvider`、`updateFeedProvider`、`toolboxClipboardProvider`、`toolboxLinksProvider`），不访问 GitHub 和平台。缺：没有真正下载、安装的测试；深色主题只断言颜色值。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 4 条（装一个版本号更低的测试包，版本页“下载并安装”，没有安装权限时引导到系统页；S02.4 只验证到系统安装器出现、点取消）。工具箱没有专门的清单条目，粘贴链接跳转可以和第 4 节第 2 条（链接和口令）一起看；S02.5 的 4A-01 会看工具箱标题居中。

## 路线

1. [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)（未开始）：应用内更新的真机流程；同一轮在 K90 上看一眼工具箱（粘贴一个哔哩哔哩链接，跳转和获取直链各一次）、关于、版本历史的分栏（横屏）。
2. [Y02.1](../../Y-发布和运营/Y02-更新通道/Y02.1-同版本换包时应用内收不到更新/README.md)：版本比较带上构建号或以后一律改版本号，改完回看版本页的状态卡。
3. 维护者定新版本对话框以 A06.3 还是 A15.2 的设计为准，必要时开一个小的界面任务统一。
4. 以后：A17.5 开发时复用 `SupportedPlatformsCard`；Esc 返回在 A05.1 一起做。新想法写进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [A 界面设计](../README.md)。

- 代码：`features/toolbox/`、`about/`、`version/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| A15.1 | 工具箱 | 界面 | 完成 | 2026-10-01 | b164796dc | [设计或说明](A15.1-工具箱/README.md)、[记录](A15.1-工具箱/record.md)、[评审页](A15.1-工具箱/page/01-说明.jpg) |
| A15.2 | 关于和版本 | 界面 | 完成 | 2026-10-02 | dd2e8cbfb | [设计或说明](A15.2-关于和版本/README.md)、[记录](A15.2-关于和版本/record.md)、[评审页](A15.2-关于和版本/page/01-说明.jpg) |

<!-- docs:生成结束 -->
