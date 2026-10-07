# A15 小页面

工具箱、关于和版本。

一句话：几张独立的小页面：工具箱（粘贴直播链接，跳转或获取直链），关于、版本更新、版本历史。

## 范围

- 包括：
  - 工具箱（A15.1）：“平台链接”一组（一个输入框、粘贴 / 清除、“链接跳转”“获取直链”两个按钮、进行中和取消）、支持解析的平台列表（默认收起）、选清晰度和线路的对话框。
  - 关于和版本（A15.2）：关于页（Logo、版本、在线更新、版本历史、开源许可证、项目主页、声明）、版本更新页（状态卡、本平台的安装包和“本机”标签、下载源）、版本历史（列表和详情、宽 840 起分栏）、下载确认。
- 不包括（归哪里）：
  - 链接解析和取直链的逻辑在 [E04 链接解析和分享口令](../../E-直播平台/E04-链接解析和分享口令/README.md)；更新检查、下载、安装的逻辑和发布在 [Y02 更新通道](../../Y-发布和运营/Y02-更新通道/README.md)；页面的功能（入口、动作）在 [I08 小页面](../../I-浏览和发现/I08-小页面/README.md)。
  - 启动时的“发现新版本”对话框和下载进度对话框在 [A06.3 全局弹窗](../A06-首页和全局/A06.3-全局弹窗/README.md)（这里的下载直接调用它）；首页里工具箱、关于的入口在 [A06](../A06-首页和全局/README.md)。
  - 电视的关于和检查更新在 [A17.9](../A17-电视界面/A17.9-电视设置/README.md)；电视的链接放映在 [A17.5](../A17-电视界面/A17.5-电视网络电视和影片/README.md)（用这里的支持列表）。

## 现状：做到哪、怎么工作的

- **工具箱**：首页搜索旁、宽屏侧栏、顶栏菜单进入。组标题“平台链接”在卡片外，卡片里一句说明和多行输入框（空时右边“粘贴”，有字时“清除”），下面“链接跳转”（实心）和“获取直链”（浅色）并排，宽 <320 时上下排；进行中写“正在解析链接… / 正在读取直播流地址…”，右边“取消”。下面一张单独的“支持解析的平台”卡片（默认收起，平台标签）。回到页面时剪贴板里有链接会自动填进去（统一提示条）。内容最宽 720。动作的逻辑在 `ToolboxController`（`features/toolbox/toolbox_actions.dart:45`），平台列表 `linkPlatforms`（`shared/links/supported_platforms.dart:12`）按已注册的平台算。
- **关于**：顶栏只有返回；Logo 不再弹跳；“在线更新”有新版本时右边主色“新版本 v…”（读 `foundUpdate`，`features/version/update_feed.dart:20`，启动检查和版本页检查都会记下）；声明前是信息图标。
- **版本更新**：状态卡，下面“下载文件 · Android”列出本平台的包，每行“ARM64 (64位) · 大小 [本机]”和“下载并安装”（先试最快的源，失败换下一个，用 A06.3 的下载对话框）；“选择下载源（N 个）”点开才显示各下载源；iOS 没有包时显示“打开发布页面”。“本机”按应用自己的架构（`Abi.current()`）。
- **版本历史**：一张卡片的列表，每行“版本 · 发布于 日期”和“最新”“当前”标签；页面宽 ≥840（按父组件，横屏手机 852 也算）左右分栏，左 320；详情头部一行（头像、版本、日期、打开发布页面、✕），日志和文件单独滚动；下载先确认“是否下载“…apk”（38.6 MB）？”，在应用内下载（3.x 的做法；v4 之前直接开浏览器）。
- **完成度**：两个任务都完成（2026-10-01、10-02 合并）。真机：没有单独看过这几页；应用内下载和安装（CHECKLIST 第 5 节第 4 条）归 S02.4。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/toolbox/toolbox_page.dart` | 工具箱页 `ToolboxPage`（:35）：链接卡片 `_LinkCard`（:199）、两个按钮（:329，宽 <320 上下排）、选清晰度和线路的对话框 `ToolboxChoiceDialog`（:288，标题 20 号、每项 ≥56、地址一行） |
| `apps/pure_live/lib/features/toolbox/toolbox_actions.dart` | 两种动作 `ToolboxAction`（:14）、控制器 `ToolboxController`（:45：解析、取直链、取消、自动填充） |
| `apps/pure_live/lib/shared/links/supported_platforms.dart` | 支持解析的平台 `linkPlatforms`（:12）和卡片 `SupportedPlatformsCard`（:21），电视的链接放映也用 |
| `apps/pure_live/lib/features/about/about_page.dart` | 关于页 `AboutPage`（:18，也接 `RoutePath.kVersionHistory` 转给版本页）、`AboutView`（:35）、“新版本”标签（:206） |
| `apps/pure_live/lib/features/version/version_page.dart` | 版本页 `VersionPage`（:77，按路由分更新和历史）、版本更新 `UpdateView`（:96）、本平台的包 `platformPackages`（:22）、“本机” `nativePackageTitle`（:49）、状态卡（:297）、一个包（:367） |
| `apps/pure_live/lib/features/version/release_history_view.dart` | 版本历史 `ReleaseHistoryView`（:27，分栏宽度 840 :20）、标签（:287）、详情头部和正文（:357、:426）、文件卡片和下载确认（:447） |
| `apps/pure_live/lib/features/version/update_feed.dart` | 读 `assets/releases.json` 和 GitHub 发布、包的种类和下载源（:204、:296）、本平台（:305）、记下找到的新版本（:20、:23） |
| `apps/pure_live/lib/features/version/update_download.dart`、`update_prompt.dart`、`download_directory_dialog.dart` | 下载对话框（A06.3）、启动时检查和“发现新版本”对话框（A06.3）、选下载目录 |
| `apps/pure_live/lib/features/version/markdown_text.dart`、`app_version.dart` | 更新日志的 Markdown 显示；版本号比较 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/toolbox/toolbox_page_test.dart` | 竖屏（组标题、粘贴 / 清除、两个按钮的顺序和高度、支持列表收起）、进行中、对话框、852×393 和 1280×800 |
| `apps/pure_live/test/features/version/version_page_test.dart` | 关于页的行和图标、“新版本”标签、不弹跳；版本更新页的包、本机、下载源、下载源对话框；版本历史的标签、分栏（839 / 852）、详情关闭、下载确认 |
| `apps/pure_live/test/features/version/update_dialogs_test.dart` | A06.3 的新版本和下载对话框（这里的下载用它） |

## 3.x 基线

- 工具箱：`git show v3.2.11:lib/modules/toolbox/toolbox_page.dart`（151 行，两张可折叠卡片各一个输入框）、`toolbox_controller.dart`、`toolbox_direct_link_flow.dart`。
- 关于：`lib/modules/about/about_page.dart`（160 行，Logo 用 `elasticOut` 弹跳 1 秒）、版本历史 `lib/modules/about/version_history.dart`（801 行，按整屏 >760 分栏）、新版本对话框 `lib/modules/about/widgets/version_dialog.dart`。
- 版本更新：`lib/modules/version/version_page.dart`（472 行）、`version_controller.dart`；下载并安装 `downloadAndInstallApk`（下载确认后在应用内下载）。
- 必须保留：`assets/version.json`、`assets/releases.json` 留在 master（D-015，3.x 从这里检查更新）；项目主页和下载源地址照 3.x。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 启动时的新版本提示用 A06.3 的对话框（“其他下载方式 / 取消 / 下载并安装”），没照 A15.2 设计图的“项目主页 / 以后再说 / 去更新”和“发布于” | `update_prompt.dart` 的 `NewVersionDialog` | 两个任务的设计图不一致，现在以 A06.3 为准 | A15.2 记录“偏差 1”，需要维护者定以哪个为准（没有登记任务） |
| 同版本换包时应用内收不到更新提示（只比较版本号） | `update_feed.dart`、`app_version.dart` | 4.0.0 覆盖发布后已装的用户收不到提示 | [Y02.1](../../Y-发布和运营/Y02-更新通道/README.md)（D-008） |
| “本机”按应用自己的架构判断，64 位手机装了 32 位包时标的是 32 位包 | `version_page.dart` 的 `nativePackageTitle` | 装回同一种架构，和已装的一致 | 不改（A15.2 偏差 2） |
| 跨功能引用 `about -> version/app_version.dart`、`about -> version/update_feed.dart` | `tools/gate/ui_baseline.json` | 门禁基线里 2 条 | 版本信息挪到 `shared/` 时去掉 |
| 应用内下载、没有安装权限时的引导没在真机上看 | 版本更新 | 安装流程依赖系统 | [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) |

## 相关决定和规范

- D-003（A15.1 的 Y1、Y2，A15.2 的 N1～N3 按建议 A）、D-008（4.0.0 覆盖发布的后果）、D-015（`assets/version.json`、`assets/releases.json` 不能删）。
- [specs/UI.md](../../specs/UI.md) 第 5.3 节（阅读型内容最宽 720、分栏按父组件 840）、第 7 节（下载确认是对话框）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/toolbox test/features/version`。网络请求和下载用测试替身（`updateDownloadToolsProvider`、`updateFeedProvider`），不访问 GitHub。
- 真机：[S02 的 CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 4 条（装一个低版本测试包，版本页“下载并安装”、没有安装权限时引导到系统页）。工具箱没有专门的清单条目，粘贴链接跳转可以和第 4 节第 2 条一起看。

## 路线

1. [Y02.1](../../Y-发布和运营/Y02-更新通道/README.md)：版本比较带上构建号或以后一律改版本号，改完回看版本页的状态卡。
2. 定下新版本对话框以 A06.3 还是 A15.2 的设计为准，必要时开一个小的界面任务统一。
3. [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)：应用内更新的真机流程。

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
