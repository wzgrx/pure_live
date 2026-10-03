# A09.8 网页搜索：设计（第 1 版，已定稿并实现）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02；功能清点 F-SRC-04 是“没验证”，真机交给 S02.6，见“实现和验证”）
- 旧编号：U.5b、T07f.3（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：网页搜索页（应用内网页、认出直播间、加载失败、系统浏览器页）
- 对应：[inventory/UI.md](../../../inventory/UI.md#a098)（A09.8-01）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a098)；入口在 [A09.7](../A09.7-搜索/README.md)；功能点 F-SRC-04（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；应用内网页组件 `apps/pure_live/lib/shared/in_app_web.dart` 是 O03.1 的；认出直播间的规则在 E04（链接解析）；相关决定 D-003（Y1～Y3 按建议 A）
- 评审页：claude.ai 私有页面；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；网页是示意网页，不是任何平台的真实页面
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A09.8-01 | 网页搜索页 | 搜索页选了单个平台时“继续网页搜索”（筛选行、失败横幅、空状态按钮；`search_controller.dart:523-551`） | 竖屏、横屏、宽屏 | 加载中（进度条）、已加载、加载失败（重试）、地址无效（关闭）、Linux 系统浏览器页（打开中） |
| — | 认出直播间对话框 | 网页地址是支持的直播间链接时（`web_search_controller.dart:312-377`） | 同上 | 取消后同一个房间不再问 |
| — | 提示条 | 获取直播间信息失败,请重新获取；系统浏览器未打开，请检查默认浏览器设置 | 全部 | — |
| — | 开发者工具按钮 | 只在调试版（`kDebugMode`） | — | 用户看不到，不出图 |

## 3.x 的样子和问题

### 3.x 的样子（`git show v3.2.11:lib/modules/search/`：`web_search_page.dart` 215 行、`web_search_controller.dart`、`web_search_room_parser.dart`）

- **顶栏**：标题“网页搜索”居中（主题 `centerTitle`），左边 `BackButton`（先在网页里后退，退到第一页才关闭，`web_search_controller.dart:407-434`），右边 `Icons.close`“关闭”（直接关闭）；调试版多一个 `Icons.bug_report`“打开网页开发者工具”（`web_search_page.dart:33-49`）。
- **网页**：`InAppWebView` 占满；固定用 Windows Chrome 的 User-Agent、`useWideViewPort`、`loadWithOverviewMode`，所以手机上也是缩小的电脑版网页（`web_search_controller.dart:141-144`、`web_search_page.dart:60-94`）；只放行 http(s)，拒绝不受信任的证书（`:297-310`、`:281-289`）。
- **加载**：顶部 `LinearProgressIndicator`，有进度时按进度，否则来回跑（`web_search_page.dart:95-105`）。
- **失败**：盖住网页的表面色页：`Icons.wifi_off_rounded` 48（错误色）、“网页搜索暂不可用”（15 号 600）、“网页加载失败，请检查网络或代理后重试。”（13 号次要色）、`FilledButton.icon` 刷新“重试”；地址无效时文字是“网页搜索地址无效，请返回搜索页后重试。”、按钮是 ✕“关闭”（`:106-114`、`:158-195`）。
- **认出直播间**：`Utils.showAlertDialog`：标题“提示”，内容“检测到房间号，是否打开直播间？”，按钮“取消”“确认”（都是文字按钮，`plugins/utils.dart:395-445`、`web_search_controller.dart:514-521`）；确认后用 `offAndToRoomDetail` 替换掉网页搜索页（`:523-525`）；失败提示“获取直播间信息失败,请重新获取”。
- **Linux**：不建网页，显示 `Icons.open_in_browser_rounded` 48（主色）、“Linux 版使用系统浏览器继续网页搜索；应用内原生搜索、直播详情和播放功能保持可用。”、`FilledButton.icon` `open_in_new_rounded`“使用系统浏览器打开”（打开中转圈，`web_search_page.dart:119-156`）。从搜索页点进来时 Linux 直接打开浏览器，不经过这一页（`search_controller.dart:541-545`）。
- **按宽度分支**：没有。

### 问题

| 编号 | 问题 | 位置 |
|---|---|---|
| W1 | 认出直播间的对话框看不出是哪个平台、哪个房间 | `web_search_controller.dart:514-521` |
| W2 | 每打开一个直播间页面就弹一次对话框，打断浏览 | `web_search_controller.dart:338-377` |
| W3 | 标题只有“网页搜索”，看不出平台和关键词 | `web_search_page.dart:33-35` |
| W4 | Android、Windows 没有“用系统浏览器打开” | `web_search_page.dart:36-48`、`:119-156` |
| W5 | 加载失败只能重试 | `web_search_page.dart:158-195` |
| W6 | 进入直播间后网页搜索被替换，返回回不到网页 | `web_search_controller.dart:523-525` |
| W7 | Linux 页没说找到直播间后怎么回来 | `web_search_page.dart:119-156` |

### 设计时 v4 的偏差

v4（I05.1、O03.1）：有应用内网页时打开 `InAppWebPage`，顶栏去掉了 ✕、加了“使用系统浏览器打开”；认出直播间的对话框标题改为“这个网页是一个直播间，要进入吗？”、内容是网址；进入时不替换网页。没有应用内网页时显示系统浏览器页（说明怎么粘贴回来）。这一版：✕ 加回来（v3 有），对话框改成底部提示条（Y1）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 竖屏加载、认出直播间（提示条）、加载失败、横屏、宽屏、不能在应用里打开时；7 个问题、8 条改动、三处待选 | 用户确认；Y1～Y3 按建议 A（D-003） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [横屏和宽屏](page/03-横屏和宽屏.jpg)
- [不能在应用里打开时](page/04-不能在应用里打开时-Linux-等.jpg)
- [v3 的问题](page/05-v3-的问题.jpg)
- [改了什么](page/06-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/07-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/08-各客户端.jpg)
- [需要你选的](page/09-需要你选的.jpg)
- [性能要点](page/10-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-web-phone.jpg](v3-web-phone.jpg)、[v4-web-phone.jpg](v4-web-phone.jpg) | 竖屏加载中 |
| [v3-web-room.jpg](v3-web-room.jpg)、[v4-web-room.jpg](v4-web-room.jpg)、[v4-web-room-n.jpg](v4-web-room-n.jpg) | 认出直播间：v3 对话框 / 新设计提示条 / 按钮编号 |
| [v3-web-failed.jpg](v3-web-failed.jpg)、[v4-web-failed.jpg](v4-web-failed.jpg) | 加载失败 |
| [v3-web-land.jpg](v3-web-land.jpg)、[v4-web-land.jpg](v4-web-land.jpg) | 手机横屏 852×393 |
| [v3-web-wide.jpg](v3-web-wide.jpg)、[v4-web-wide.jpg](v4-web-wide.jpg) | 宽屏 1280×800 |
| [v3-web-linux.jpg](v3-web-linux.jpg)、[v4-web-linux.jpg](v4-web-linux.jpg) | 不能在应用里打开时（Linux） |

## 确认的改动

用户确认（第 1 版的“改动（待确认）”原样）：

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 返回先后退、✕ 直接关闭、进度条、失败页、只放行 http(s)、取消过的房间不再问 | — |
| c2 | 修改 | 标题下加“平台 · 关键词”，两行靠左 | W3 |
| c3 | 增强 | 顶栏加“使用系统浏览器打开”（v4 已有） | W4 |
| c4 | 修改 | 认出直播间时底部提示条（平台、房间号、进入、✕） | W1、W2 |
| c5 | 修改 | 进入直播间不替换网页（v4 已是） | W6 |
| c6 | 修改 | 失败页多“使用系统浏览器打开” | W5 |
| c7 | 修改 | 系统浏览器页写清怎么回来、显示网址（v4 已有） | W7 |
| c8 | 保留 | 手机上照 v3 用电脑版网页 | — |

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 网页里后退，退到第一页再按就关闭；返回键、滑动返回、Esc 一样 |
| 2 | 标题 | 网页搜索；下面是平台和关键词 |
| 3 | 使用系统浏览器打开 | 把当前网页交给系统浏览器 |
| 4 | 关闭 | 直接回到搜索页 |
| 5 | 进入 | 打开认出的直播间；返回时回到网页 |
| 6 | 提示条 ✕ | 这个直播间不再提示 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏、横屏如图；横屏提示条靠右宽 420 |
| 宽屏（平板、Windows、iPad、macOS） | 同图；提示条右下角宽 440；悬停显示名称；Esc 等于返回；Windows 缺 WebView2 见 A09.7 的 X4 |
| Linux | 系统浏览器页 |
| 电视 | 不适用 |
| 苹果平台差异 | 用系统网页组件；iOS 左边缘滑动等于返回 |

## 待选和决定

- Y1 认出直播间时：A 底部提示条；B 照 v3 弹对话框但写清平台和房间号。**用了 A**（D-003）。
- Y2 从直播间返回：A 回到网页；B 照 v3 回到搜索页。**用了 A**。
- Y3 手机上的网页：A 照 v3 用电脑版；B 用手机版。**用了 A**。

### 设计时拿不准的地方

- v3 固定用电脑版 User-Agent 的原因代码里没写；推测是避开手机网页跳 App 和让房间链接格式统一（Y3 的说明按这个写）。
- 提示条里只能写平台和房间号（从网址认出来的），拿不到直播间标题，除非再请求一次房间信息；这一版不请求。
- 新文字（“这是一个直播间”、标题第二行）定稿后要加进翻译。

结论：提示条只写平台和房间号，不额外请求直播间标题；新文字（“这是一个直播间”、标题第二行）加进了翻译。

### 性能要点（评审页）

- 网页组件只在这一页存在，关闭时先停止加载再释放（v3 已是）。
- 进度条只重绘自己；提示条是盖在网页上的小部件，不重建网页。
- 认出房间号在网址变化时做，不读网页内容。

## 实现和验证

- 实现：c1～c8、Y1～Y3 都做了（逐条见 [record.md](record.md)）。现在的代码：
  - `apps/pure_live/lib/features/search/web_search_view.dart`（452 行）：`WebSearchRequest`（`:15`，3.x 的 `{url, platform}` 照旧可用，新的可选 `keyword`）、`WebSearchView`（`:65`）：Esc 返回（`EscapeBack` `:163`）、两行标题 `PageTitle`“网页搜索 / 平台 · 关键词”靠左（`:167-169`）、应用内网页 `InAppWebPage(desktopSite: true)`（`:197`）；`WebSearchRoomBar`（`:264`，平台标志、“这是一个直播间”、“平台 · 房间号 N”、“进入”、✕；竖屏左右 12、离底 16；页宽 600 起靠右宽 420；1200 起右下角 24、宽 440；翻到不是直播间的网页时收起；✕ 后这个房间不再提示）；`WebSearchFailure`（`:346`，错误色断网图标、“网页搜索暂不可用”、说明、“重试”实心、下面“使用系统浏览器打开”文字按钮）；`_StateBody`（`:382`）。地址无效时照 v3：“网页搜索地址无效，请返回搜索页后重试。”和“关闭”。
  - `apps/pure_live/lib/shared/in_app_web.dart`：`desktopUserAgent`（`:37`，v3 的 Windows Chrome User-Agent）、`InAppWebPage`（`:45`，`desktopSite` `:73`；返回先 `canGoBack` 后退 `:93`，退不了用 `Navigator.pop` `:96-98`；`desktopSite` 时 `useShouldOverrideUrlLoading: true` `:106`，只放行 http(s) 才真正生效）。
  - 系统浏览器页（没有应用内网页时：Linux、Windows 缺 WebView2 选了系统浏览器）：进页立刻打开一次系统浏览器，按钮可再开、打开中转圈；顶栏没有“使用系统浏览器打开”。
- 修的问题（根因，记录“修的问题”）：
  1. 网页第一页按返回会一直转：`InAppWebPage` 用 `PopScope(canPop: false)` 接返回，退不了时调 `maybePop()`，又被同一个 `PopScope` 拦下，没有尽头；改为 `Navigator.pop()`。哔哩哔哩网页登录也用这个组件，一起受益。
  2. “只放行 http(s)”之前没生效：要 `useShouldOverrideUrlLoading: true` 才会调 `shouldOverrideUrlLoading`；网页搜索打开了，哔哩哔哩登录没动。
- 和设计 / v3 不一样（记录）：提示条只写平台和房间号；记录当时建议哔哩哔哩网页登录成功后改用 `pop(true)`——已经改了（`d2ec7bbfc`，`apps/pure_live/lib/features/account/bilibili_web_login.dart:123-125`）。
- 没有新设置。门禁：`search` 的直接颜色和图标在 A09.7 一起降到 0；`shared/` 不计入门禁。
- 提交：`773f31fa5`（`feat(app): U.5b web search as designed`，登记表写的是这个）；合并 `f294308a3`（2026-10-02）。
- 自动测试：新文件 `apps/pure_live/test/features/search/web_search_test.dart`（记录写 6 个；现在 4 个用例声明，有的按 393 / 852 / 1280 循环）：3.x 的参数、无效参数和关键词的读取（无效地址页的文字和“关闭”）；系统浏览器页（进页立刻打开一次、两行标题靠左、说明和网址、顶栏没有外开按钮、按钮再开）；提示条在 393 / 852 / 1280 宽的位置和宽度、从左到右的顺序、“进入”和 ✕；失败页的“重试”和“使用系统浏览器打开”。应用内网页本身（平台视图）测试里跑不起来，没有覆盖。
- 真机：**没验证**。功能清点 F-SRC-04（网页搜索，应用内浏览器认出直播间后问是否进入）是“没验证”，交给 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)（[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 3 条）；Windows 上的 `useShouldOverrideUrlLoading` 和 WebView2 缺失时的流程留给 [S03.1](../../../S-质量和验证/S03-统一验证/S03.1-统一验证/README.md)。登记表却是“完成”（见[子分类页](../README.md)“已知问题”）。
- 留下的问题：真机（上一条）；电视不适用。
