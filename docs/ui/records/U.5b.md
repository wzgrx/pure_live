# U.5b 网页搜索

- 日期：2026-10-01
- 设计：[docs/ui/compare/U.5b/README.md](../compare/U.5b/README.md)（用户已确认；Y1～Y3 按 A）
- 改动的目录：`apps/pure_live/lib/features/search/web_search_view.dart`、`apps/pure_live/lib/shared/in_app_web.dart`（只加可选参数，另修一个死循环，见下）、`packages/live_ui`（`PageTitle`，见 [U.5a 记录](U.5a.md)）、翻译文件。没有改原生部分

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 返回先后退、✕ 直接关闭、进度条、失败页、只放行 http(s)、取消过的房间不再问 | ✅ | 返回、系统返回键、Esc 都先在网页里后退，退到第一页才关；✕ 直接关闭。进度条高 4（v3 默认）。拒绝不受信任的证书照旧；Cookie 由 WebView 保存（默认） |
| c2 | 标题下加“平台 · 关键词”，两行靠左 | ✅ | live_ui `PageTitle`；关键词由搜索页通过新的可选路由参数 `keyword` 传来（3.x 的 `{url, platform}` 照旧可用，没有关键词时只写平台） |
| c3 | 顶栏“使用系统浏览器打开” | ✅ | 打开的是当前显示的网页（不只是第一页） |
| c4 | 认出直播间时底部提示条 | ✅ | `WebSearchRoomBar`：平台标志、“这是一个直播间”、“平台 · 房间号 N”、“进入”、✕；竖屏左右各 12、离底 16；页宽 600 起靠右宽 420；1200 起右下角 24、宽 440。翻到不是直播间的网页时提示条收起；✕ 后这个房间不再提示，别的房间照常 |
| c5 | 进入直播间不替换网页 | ✅ | 压在网页搜索上面打开，返回回到网页（v4 已是） |
| c6 | 失败页多“使用系统浏览器打开” | ✅ | `WebSearchFailure`：错误色断网图标、“网页搜索暂不可用”、说明、“重试”（实心）、下面“使用系统浏览器打开”（文字按钮） |
| c7 | 系统浏览器页写清怎么回来、显示网址 | ✅ | 没有应用内网页时（Linux，Windows 缺 WebView2 选了系统浏览器）显示；进页时立刻打开一次系统浏览器（v3 在 Linux 上直接打开），按钮可再开，打开中转圈；顶栏没有“使用系统浏览器打开”（下面就是） |
| c8 | 手机上照 v3 用电脑版网页 | ✅ | `InAppWebPage(desktopSite: true)`：v3 的 Windows Chrome User-Agent，宽视口、整页缩放（WebView 默认） |

选择：Y1 A ✅；Y2 A ✅；Y3 A ✅。

地址无效时照 v3：错误色断网图标、“网页搜索暂不可用”、“网页搜索地址无效，请返回搜索页后重试。”、“关闭”（v4 之前是断链图标、没有标题）。

## 修的问题（根因）

1. **网页第一页按返回会一直转**：共用的 `InAppWebPage` 用 `PopScope(canPop: false)` 接返回，网页退不了时调 `maybePop()`，而 `maybePop` 又被同一个 `PopScope` 拦下、再调回来，没有尽头。改为 `Navigator.pop()`。B 站网页登录也用这个组件，一起受益。
2. **“只放行 http(s)”之前没生效**：`shouldOverrideUrlLoading` 写了，但 WebView 要 `useShouldOverrideUrlLoading: true` 才会调用它。网页搜索（`desktopSite`）现在打开了；B 站登录没动（不是这个任务）。

## 和设计 / v3 不一样、需要你知道的

1. 提示条只写平台和房间号（设计也这样），不额外请求直播间标题。
2. B 站网页登录成功后调 `maybePop(true)`，会被 `InAppWebPage` 的返回处理拦下：网页能后退时变成网页后退，不能时现在会带着 `true` 关闭（之前是死循环）。登录页本身不在本任务范围，没改，建议 U.10b 开发时改成直接 `pop(true)`。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/search/web_search_page.dart` | `features/search/web_search_view.dart` |
| `modules/search/web_search_controller.dart`（WebView 设置、认出房间、返回） | `shared/in_app_web.dart`（`InAppWebPage`）+ `web_search_view.dart` |
| `plugins/utils.dart` 的确认对话框 | 去掉，改为 `WebSearchRoomBar`（Y1 A） |

## 新设置项

无。

## 门禁

`search` 直接写的颜色和图标已在 U.5a 一起降到 0。`shared/` 不计入门禁。

## 测试

新文件 `test/features/search/web_search_test.dart` 6 个：3.x 的参数、无效参数和关键词的读取（无效地址页的文字和“关闭”）；系统浏览器页（进页立刻打开一次、两行标题靠左、说明和网址、顶栏没有外开按钮、按钮再开）；提示条在 393 / 852 / 1280 宽的位置和宽度、从左到右的顺序、“进入”和 ✕；失败页的“重试”和下面的“使用系统浏览器打开”。应用内网页本身（平台视图）测试里跑不起来，没有覆盖。

## 没做的

- 没在 Windows 和 K90 上看真实网页（这次不安装）；Windows 上 `useShouldOverrideUrlLoading` 和 WebView2 缺失时的流程留给 U.16 真机检查。
