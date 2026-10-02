# T07i.4 关于和版本

- 日期：2026-10-02
- 设计：[docs/T07/T07i/T07i.4/README.md](README.md)（第 1 版，用户已确认；N1～N3 按建议 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、7–10 节
- 一并处理的跨任务待同步：T07i.4 → T07a.6（新版本提示用同一个组件：照任务书用 T07a.6 已做好的对话框，见 c14）；“历史记录”改名（T07g.2 已把观看历史改名“观看记录”，这里的版本历史改名“版本历史”）
- 改动的目录：`apps/pure_live/lib/features/about/`、`apps/pure_live/lib/features/version/`、`packages/live_ui`（只加图标）、翻译文件、门禁基线、文档。没有改原生部分（“本机”用 `dart:ffi` 的 `Abi.current()`），没有构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 三页的结构、顺序、图标、下载源、复制、更新日志、宽屏分栏、刷新、提示文字 | ✅ | 关于页顶栏只有返回（v3，v4 原来有标题“关于”）；图标回到 v3 的 Remix：在线更新 `download_cloud_2_line`、版本历史 `history_line`、开源许可证 `shield_user_line`、项目主页 `code_s_slash_line`、下载源 `link_m`、文件 `box_3_line`、作者 `user_line`、发布页面 `link`、下载 `download_2_line`（`AppIcons.onlineUpdate` 等，见下） |
| c2 | “历史记录”改名“版本历史”（N1 A），页面同名 | ✅ | 新键 `version_history`；副标题仍是“历史版本更新记录” |
| c3 | 在线更新写副标题；有新版本时显示“新版本 v…” | ✅ | `update_feed.dart` 新加 `foundUpdate`：启动检查（`checkForUpdateOnStartup`）和版本页检查到更新时记下，关于页读它显示主色小标签；没有新版本或没检查过就不显示（被“不再提醒”的版本也显示） |
| c4 | 声明用现在的文字，信息图标 | ✅ | `about_legalese`（没有 Firebase），`AppIcons.infoLine` 次要色，正文色 13 号，整段显示 |
| c5 | 图标不弹跳 | ✅ | 直接显示（去掉 1 秒 `elasticOut`） |
| c6 | 状态卡 | ✅ | v4 原来就有；图标换成 `AppIcons.updateAvailable/upToDate` |
| c7 | 每个包“下载并安装”、本机标签，下载源收起（N2 A） | ✅ | 一行“ARM64 (64位) · 大小 [本机]”，右边“下载并安装”（T07a.6 的下载：先试最快的源，失败换下一个）；“⌄ 选择下载源（N 个）”点开是原来的下载源按钮（2/3/4 列）。“本机”：Android 按应用自己的架构（`Abi.current()`），Windows 标在 EXE 安装包，macOS 标在通用包；启动时的新版本提示也改为下载本机的包（原来固定取第一个，arm64） |
| c8 | 下载源对话框三个按钮 | ✅ | 标题改为“ARM64 (64位) · 下载源 3”（原来只有架构名），文件名、地址，然后“在应用内下载”“在浏览器中下载”“复制链接”，底部“取消”；按钮 14 号 |
| c9 | 刷新 | ✅ | v4 原来就有 |
| c10 | 按父组件 840 分栏（N3 A） | ✅ | `LayoutBuilder`，≥840 左右分栏（左 320），852×393 横屏手机也是分栏；原来按整屏 >760 |
| c11 | 列表写“发布于 日期”，标“最新”“当前”，去掉文件大小 | ✅ | 列表是一张卡片、行间分隔线，懒加载；“最新”是按日期排第一的版本，“当前”是已安装的版本 |
| c12 | 详情关闭在右上角 | ✅ | 头部一行：头像、版本、日期、打开发布页面、✕；下面的日志和文件单独滚动；返回键、Esc、点外面也关 |
| c13 | 下载确认写清 | ✅ | “下载安装包 / 是否下载“…apk”（38.6 MB）？下载完成后会打开安装。/ 取消、下载”，确认后在应用内下载（T07a.6 的下载对话框，同 v3 `downloadAndInstallApk`）。**v4 原来点下载直接用浏览器打开、不确认**，回到 v3 的做法 |
| c14 | 新版本提示写版本号（T07a.6 同一个组件） | ✅（有偏差） | 照任务书用 T07a.6 已做好的 `NewVersionDialog`：标题“发现新版本 v…”、“当前 v…”和“本软件开源免费”链接、更新内容、“不再提醒这个版本”、按钮“其他下载方式 / 取消 / 下载并安装”。设计图里的“项目主页 / 以后再说 / 去更新”三个按钮和“发布于 …”**没有照做**（见“需要决定的事”） |

### 各客户端

| 客户端 | 做到 | 说明 |
|---|---|---|
| 手机竖屏 | ✅ | 如图 |
| 手机横屏 | ✅ | 关于、版本更新最宽 720；版本历史左右分栏；窗口高度 <480 时顶栏 48 高 |
| 宽屏（平板、Windows、Linux） | ✅ | 关于、版本更新最宽 720 居中；版本历史左右分栏；Windows 的“本机”在 EXE 安装包 |
| 电视 | — | T18e.2 |
| 苹果平台 | — | iOS 没有安装包，版本更新页显示“这个版本暂时没有本平台的安装包”和“打开发布页面”（v4 原来就有，放进了“下载文件”组）；macOS 菜单栏的“关于”在 T19b.1 |

## 结构上的改动

- **版本历史挪到 `features/version/release_history_view.dart`**（原在 `features/about/`）：历史页的下载要用版本功能里的 `showUpdateDownload`，留在 `about` 里就要新增跨功能引用（门禁不允许）。`RoutePath.kVersionHistory` 仍由 `AboutPage` 接，它转给 `VersionPage`（入口页，门禁允许），路由表没有改。`VersionPage` 现在按路由分成 `UpdateView`（原来的版本更新）和 `ReleaseHistoryView`。
- 门禁基线里 `about -> version/markdown_text.dart` 这条跨功能引用随之去掉。

## 偏差

1. **c14 新版本提示**：见上，用 T07a.6 的对话框，没有改它的按钮。
2. **“本机”的判断**：设计“拿不准的地方”第 1 条说按设备支持的 ABI 列表的第一个；这里用应用自己的架构（`Abi.current()`，不用加原生代码）。64 位手机装了 32 位包时标的是 ARM32（装回同一种架构，和已装的一致）。
3. **获取失败**用 `AppStatusView`（云朵图标、标题、说明、“重试”），按钮是 T01c.1 统一的浅色实心（设计图照 v3 画的深色实心）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/about/about_page.dart` | `features/about/about_page.dart` |
| `modules/about/version_history.dart` | `features/version/release_history_view.dart` |
| `modules/about/widgets/version_dialog.dart` | `features/version/update_prompt.dart`（T07a.6；本任务只改了挑包和记下新版本） |
| `modules/version/version_page.dart`、`version_controller.dart` | `features/version/version_page.dart`（`VersionPage`、`UpdateView`、`platformPackages`、`nativePackageTitle`） |

## 新设置、新文字

- 设置：无。
- 文字：中英各加 9 条：`version_history`“版本历史”、`about_new_version`“新版本 v{version}”、`update_choose_source`“选择下载源（{count} 个）”、`update_native_package`“本机”、`version_latest_badge`“最新”、`version_current_badge`“当前”、`update_download_package_title`“下载安装包”、`update_download_confirm_named`、`update_download_action`“下载”。原来的 `version_history_desc`、`about_installed_version`、`version_file_size`、`download`（“点击下载”）这几处不再用，留在翻译文件里。

## `live_ui` 的添加

`AppIcons.onlineUpdate`、`versionHistory`、`licenses`、`projectPage`、`updateAvailable`、`upToDate`、`downloadPackage`、`downloadSource`、`openInBrowser`、`releaseFile`、`releaseAuthor`、`releasePage`。

## 门禁

- `about` 直接写的颜色和图标 **16 → 0**，`version` **11 → 0**（`ui_baseline.json` 去掉这两项）；跨功能引用少了一条（`about -> version/markdown_text.dart`），没有新增。

## 测试

- `test/features/version/version_page_test.dart`：9 → 18 个。新增：关于页（没有标题、两组五行的顺序、六个图标、“版本历史”、没有 Firebase、声明不是红色图标、有新版本时的“新版本 v9.0.0”、图标不弹跳、点“版本历史”）；关于页 852×393 和 1280×800 最宽 720；启动检查和版本页记下 / 清掉新版本；版本更新页的包（“下载文件 · Android”、三个包的顺序、“下载并安装”在右、48 高、“本机”只在本机的包、下载源收起和展开、下载源对话框的标题和三个按钮的顺序、取消）；版本更新页 852×393 和 1280×800 最宽 720；版本历史（标题、“最新”“当前”、没有文件大小、关闭在右上角且在滚动内容上方、没有底部“关闭”、Esc 关）；按父组件 839 / 852 宽分栏；文件的复制和下载按钮顺序、下载确认的标题、文字、按钮；`nativePackageTitle` 的对应。
- 和新设计冲突、照实改了的原有断言：

| 原断言 | 改为 | 原因 |
|---|---|---|
| 下载源按钮直接可点 | 先点“选择下载源”展开 | c7（N2 A） |
| 失败页的重试按 `version-update-retry` 找 | 按文字“重试”找 | 换成 `AppStatusView` |
| 历史列表有“当前安装” | （去掉，新测试查“当前”标签） | c11 |
| “发布于 2026-09-27”只出现一次 | 在详情对话框里出现一次 | c11：列表也写“发布于 日期” |

- `test/features/version/update_dialogs_test.dart`（T07a.6）9 个照旧通过。
