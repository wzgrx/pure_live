# A15.2 关于和版本：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../../A06-首页和全局/README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：关于页、版本更新页（含下载源对话框、获取失败）、版本历史页（手机列表和详情对话框、宽屏左右分栏、下载确认）、启动时的新版本提示
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a152)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a152)
- 评审页：claude.ai 私有页面（已发布，用户评审确认）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公用部分 [src/skit.py](src/skit.py)）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；版本号、日期、大小、下载次数、更新日志是示例；项目地址（含账号名）和 18 个镜像地址换成了占位；作者头像用默认图标

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A15.2-01 | 关于页（`AboutPage`） | 首页 ≡ 菜单“关于”（`common/widgets/menu_button.dart:41-45`） | 竖屏、横屏、宽屏 | 有新版本 / 没有（新）；打不开浏览器（提示条） |
| — | 开源许可证 | 关于页 | 同上 | Flutter 自带的 `LicensePage`，照旧，不出图 |
| A15.2-08 | 版本更新页（`VersionPage`） | 关于页“在线更新”；新版本提示“更新” | 同上 | 检查中、获取失败、有新版本、已是最新、没有本平台的包（v4）、下载中（A06.3） |
| A15.2-09 | 下载源对话框（`_showActionDialog`） | 点“下载源 N” | 同上 | — |
| A15.2-02 | 版本历史页（`VersionHistoryPage`） | 关于页“历史记录” | 同上 | 加载中、出错、空、有列表、刷新中（顶部进度线）、刷新失败（提示条） |
| A15.2-03 | 版本详情对话框（`_showMobileDetailsDialog`） | 手机点一个版本 | 竖屏 | — |
| A15.2-05 | 宽屏详情（`_DesktopChangelogDetailPanel`） | 宽于 760 时右半边 | 横屏、宽屏 | 选中项 |
| A15.2-04 | 下载确认（`_confirmDownload`） | 文件的下载按钮 | 全部 | — |
| A15.2-07 | 新版本提示（`NewVersionDialog`） | 启动时检查到新版本（`modules/home/home_page.dart:211`） | 全部 | 和 A06.3 同一个 |
| A15.2-06 | `NoNewVersionDialog` | 代码里没有调用处 | — | 不出图；“已是最新”放在版本更新页的状态卡里 |
| — | 提示条 | 复制成功、打不开浏览器、下载失败、刷新失败 | 全部 | — |

## v3 的样子

- **关于**（`modules/about/about_page.dart`）：顶栏只有返回、没有标题；图标 80（桌面 96）圆角 24、浅主色描边和阴影，进场 1 秒 `Curves.elasticOut` 弹跳（`:31-55`）；“纯粹直播”20 号粗；版本小标签 11 号（`:57-77`）。组“关于”：在线更新（`Remix.download_cloud_2_line`，右边主色容器小标签写当前版本）→ 历史记录（`Remix.history_line`，“历史版本更新记录”）→ 开源许可证（`Remix.shield_user_line`）。组“项目”：项目主页（`Remix.code_s_slash_line`，副标题是地址）→ 项目声明（`Remix.error_warning_line` 错误色，副标题是整段声明，不能点）（`:82-128`）。
- **版本更新**（`modules/version/version_page.dart`）：标题“版本更新”；本平台一张卡片（Android：`Remix.android_line` +“适用于 Android 移动端系统”；Windows、macOS 各自的卡片）；每种包一个小标题（ARM64 (64位)、ARM32 (通用)、x86_64 (Arch)；EXE 安装包、MSIX 安装包、便携 ZIP；macOS 通用 ZIP），下面两列（桌面 2–4 列）“下载源 1…19”按钮（`Remix.link_m`，开了“只用 GitHub 官方源”时只有一个“GitHub 官方源”）；然后“更新日志”卡片（Markdown）。失败：`Icons.cloud_off_rounded` 48 +“更新信息获取失败”+“请检查网络和更新源后重试。”+“重试”。
- **下载源对话框**（`:343-438`）：圆形 `Remix.download_cloud_2_line` + 架构名 + “下载源 N”；地址（可选中）；实心“点击下载”、描边“复制链接”；“取消”。
- **版本历史**（`modules/about/version_history.dart`）：标题“历史版本更新记录”，右边刷新（`Remix.refresh_line`）。屏宽 ≤760：卡片列表（版本小标签 + 日期 +“文件大小: …”+ 箭头），点开大对话框（圆角 28，最高 640）：头像、版本、“发布于 …”、打开发布页面（`Remix.link`）→ 更新日志 →“下载文件”→ 每个文件（`Remix.box_3_line`、文件名、“大小 · 已被下载 N 次”、复制 `Remix.file_copy_2_fill`、下载 `Remix.download_2_line`）→ 最后“关闭”。屏宽 >760：左边 320 的列表（圆点、版本、日期、箭头，选中主色描边），右边详情。
- **下载确认**（`:391-438`）：“点击下载 / 是否下载“{name}”？/ 取消、点击下载”。
- **新版本提示**（`widgets/version_dialog.dart:26-86`）：“检查更新”→“本软件开源免费”链接 → 更新日志 →“取消”“更新”。
- **按宽度分支**：版本历史 760（整屏宽）、头部 420、文件卡片 420 / 300；版本更新页桌面按 800 / 500 分 4 / 3 / 2 列。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| A1 | “历史记录”和观看历史同名同图标；页面又叫“历史版本更新记录” | `about_page.dart:102-106`、`version_history.dart:83` |
| A2 | 在线更新右边是当前版本，看不出有没有新版本 | `about_page.dart:85-101` |
| A3 | 声明里还有 Firebase | `zh.json app_legalese` |
| A4 | 声明红色错误图标、十行浅色小字 | `about_page.dart:121-127` |
| A5 | 图标弹跳 | `about_page.dart:31-37` |
| V1 | 版本更新页不说有没有新版本 | `version_controller.dart:57-59` |
| V2 | 每个包 19 个下载源，Android 共 57 个，不说该下哪个 | `plugins/update.dart:26-47`、`version_page.dart:245-341` |
| V3 | 点下载源还要再点“点击下载” | `version_page.dart:343-438` |
| V4 | 没有刷新 | `version_page.dart:22-35` |
| H1 | 按整屏 760 分栏 | `version_history.dart:73-76` |
| H2 | 列表写第一个文件的大小 | `version_history.dart:256`、`:270` |
| H3 | 看不出当前和最新 | `version_history.dart:226-300` |
| H4 | 详情“关闭”在最下面 | `version_history.dart:307-363` |
| H5 | 下载确认标题按钮都叫“点击下载” | `version_history.dart:404-426` |
| D1 | 新版本提示不写版本号 | `widgets/version_dialog.dart:26-86` |

## v4 现在的偏差（`apps/pure_live/lib/features/about/`、`version/`）

关于页“在线更新”有副标题“检查新版本并下载安装包”，声明换成 `about_legalese`（没有 Firebase）；版本更新页有状态卡、刷新、每个包“下载并安装”（下载源仍全部展开）、下载源对话框三个按钮、没有本平台包时的说明；版本历史仍按 760 分栏、仍叫“历史记录”。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 三页和对话框的对比、三处待选 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [关于](page/02-关于.jpg)
- [版本更新](page/03-版本更新.jpg)
- [版本更新的对话框和状态](page/04-版本更新的对话框和状态.jpg)
- [版本历史](page/05-版本历史.jpg)
- [版本详情](page/06-版本详情.jpg)
- [横屏和宽屏](page/07-横屏和宽屏.jpg)
- [v3 的问题](page/08-v3-的问题.jpg)
- [改了什么](page/09-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/10-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/11-各客户端.jpg)
- [需要你选的](page/12-需要你选的.jpg)
- [性能要点](page/13-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-about.jpg](v3-about.jpg)、[v4-about.jpg](v4-about.jpg)、[v4-about-n.jpg](v4-about-n.jpg) | 关于 |
| [v3-about-land.jpg](v3-about-land.jpg)、[v4-about-land.jpg](v4-about-land.jpg)、[v3-about-wide.jpg](v3-about-wide.jpg)、[v4-about-wide.jpg](v4-about-wide.jpg) | 关于：横屏、宽屏 |
| [v3-version.jpg](v3-version.jpg)、[v4-version.jpg](v4-version.jpg)、[v4-version-n.jpg](v4-version-n.jpg) | 版本更新 |
| [v3-version-full.jpg](v3-version-full.jpg)、[v4-version-full.jpg](v4-version-full.jpg) | 版本更新完整内容 |
| [v3-version-dialogs.jpg](v3-version-dialogs.jpg)、[v4-version-dialogs.jpg](v4-version-dialogs.jpg) | 下载源对话框、已是最新、获取失败、新版本提示 |
| [v3-history.jpg](v3-history.jpg)、[v4-history.jpg](v4-history.jpg)、[v4-history-n.jpg](v4-history-n.jpg) | 版本历史 |
| [v3-history-detail.jpg](v3-history-detail.jpg)、[v4-history-detail.jpg](v4-history-detail.jpg)、[v4-history-detail-n.jpg](v4-history-detail-n.jpg) | 详情对话框、下载确认 |
| [v3-history-land.jpg](v3-history-land.jpg)、[v4-history-land.jpg](v4-history-land.jpg)、[v3-history-wide.jpg](v3-history-wide.jpg)、[v4-history-wide.jpg](v4-history-wide.jpg) | 版本历史：横屏、宽屏 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 三页的结构、顺序、图标、下载源、复制、更新日志、宽屏分栏、刷新、提示文字 | — |
| c2 | 修改 | “历史记录”改名“版本历史”（N1） | A1 |
| c3 | 修改 | 在线更新写副标题；有新版本时显示“新版本 v…” | A2 |
| c4 | 修改 | 声明用现在的文字，信息图标 | A3、A4 |
| c5 | 修改 | 图标不弹跳 | A5 |
| c6 | 增强 | 状态卡（v4 已有） | V1 |
| c7 | 修改 | 每个包“下载并安装”、本机标签，下载源收起（N2） | V2 |
| c8 | 修改 | 下载源对话框三个按钮（v4 已有） | V3 |
| c9 | 增强 | 刷新（v4 已有） | V4 |
| c10 | 修改 | 按父组件 840 分栏（N3） | H1 |
| c11 | 修改 | 列表写日期，标“最新”“当前” | H2、H3 |
| c12 | 修改 | 详情关闭在右上角 | H4 |
| c13 | 修改 | 下载确认写清 | H5 |
| c14 | 修改 | 新版本提示写版本号（A06.3 同一个组件） | D1 |

新文字：“版本历史”“新版本 v{version}”“选择下载源（{count} 个）”“本机”“最新”“当前”“发布于 {date}”（已有）“下载安装包”“是否下载“{name}”（{size}）？下载完成后会打开安装。”“以后再说”“去更新”。其余用 v3、v4 已有的键（`about_update_subtitle`、`about_legalese`、`new_version_info`、`version_installed`、`version_newest`、`version_prerelease`、`update_download_install`、`update_download_in_app`、`update_open_in_browser`）。

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 在线更新 | 打开版本更新页 |
| 2 | 版本历史 | 打开版本历史页 |
| 3 | 开源许可证 | 系统许可证页 |
| 4 | 项目主页 | 浏览器打开 |
| 5 | 下载并安装 | 自动试下载源，完成后安装 |
| 6 | 选择下载源 | 展开 19 个下载源 |
| 7 | 版本 | 手机打开详情；宽屏右边显示 |
| 8 | 打开发布页面 | 浏览器打开 |
| 9 | 复制链接 | 复制下载地址 |
| 10 | 下载 | 确认后下载 |
| 11 | 关闭 | 关闭详情 |
| 12 | 刷新 | 重新读取 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；版本历史横屏左右分栏 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 关于、版本更新最宽 720；版本历史左右分栏；Windows 的“本机”标在 EXE 安装包 |
| 电视 | A17.9：pure_live_TV 的关于、应用更新、更新历史，内容和顺序对齐这里 |
| 苹果平台差异 | iOS 没有安装包，显示“打开发布页面”；macOS 菜单栏有“关于纯粹直播”（A18.2） |

## 待选（A 是建议）

- N1 关于页“历史记录”：A 改名“版本历史”；B 照 v3。
- N2 下载源：A 收起，每包“下载并安装”；B 全部展开。
- N3 版本历史分栏：A 父组件 ≥840；B 照 v3 屏宽 >760。

## 拿不准的地方

1. “本机”标签要按设备的 CPU 架构判断（Android 用支持的 ABI 列表的第一个），v4 现在没有这一步。
2. 关于页“新版本 v…”标签依赖启动时的检查结果；没开启动检查时不显示，要不要进关于页时再查一次，评审时可以说。
3. 开源许可证页是 Flutter 自带的 `LicensePage`，样子跟主题，没有出图。
4. 下载进度对话框（`downloadAndInstallApk`）属于 A06.3“下载安装包”，这里不出图。

## 需要改工具的地方

- 无。

## 实现和验证

- 定稿：用户确认第 1 版，N1～N3 按建议 A（“历史记录”改名“版本历史”、下载源收起、按父组件 840 分栏）。
- 实现：c1～c13 做到，c14 有偏差，详见 [record.md](record.md)。`apps/pure_live/lib/features/about/about_page.dart`（顶栏只有返回、图标回到 3.x、“新版本 v…”标签、声明的信息图标、Logo 不弹跳）、`features/version/version_page.dart`（本平台的包和“本机”、“下载并安装”、下载源对话框三个按钮）、`features/version/release_history_view.dart`（从 `about/` 挪来，列表“发布于”和“最新”“当前”、按父组件 840 分栏、详情关闭在右上角、下载先确认并在应用内下载）、`update_feed.dart` 加 `foundUpdate`。启动时的新版本提示也改为下载本机的包（原来固定取第一个 arm64 包）。
- 偏差：c14 新版本提示照任务书用 A06.3 已做好的 `NewVersionDialog`，设计图的“项目主页 / 以后再说 / 去更新”三个按钮和“发布于”没照做（需要维护者定以哪个为准）；“本机”按应用自己的架构 `Abi.current()`（设计写按设备 ABI 列表第一个）；获取失败用 `AppStatusView`。
- 新文字：中英各 9 条（`version_history`、`about_new_version`、`update_choose_source`、`update_native_package`、`version_latest_badge`、`version_current_badge`、`update_download_package_title`、`update_download_confirm_named`、`update_download_action`）；没有新设置；`live_ui` 加 12 个 `AppIcons`。
- 提交：`dd2e8cbfb`，在 `6f13ced71` 合并（2026-10-02）。`about` 16 → 0、`version` 11 → 0；跨功能引用 `about -> version/markdown_text.dart` 去掉。
- 测试：`apps/pure_live/test/features/version/version_page_test.dart` 9 → 18 个（关于页、新版本标签、版本更新页的包和下载源、版本历史的标签和分栏、详情、下载确认）；`update_dialogs_test.dart` 9 个照旧通过。
- 真机：没有单独记录。登记表已是“完成”，建议按 CHECKLIST 第 5 节第 4 条（装一个低版本测试包，版本页“下载并安装”）在 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 补看。
- 留下的问题：新版本对话框以 A06.3 还是本任务的设计为准（没有登记）；同版本换包收不到提示（Y02.1）；macOS 菜单栏的“关于”在 A18.2。
