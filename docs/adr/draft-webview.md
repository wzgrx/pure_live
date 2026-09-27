# NNNN 内置网页组件：接口隔离，Android 用 webview_flutter，Windows 用 webview_all_windows

- 状态：提议
- 日期：2026-09-28

## 背景

- 三个功能要用内置网页：B 站网页登录（F-ACC-01，spec/sites/bilibili.md §8.4）、没有原生搜索的平台的网页搜索兜底（F-SRC-02）、Twitch 列表翻页要的完整性令牌（spec/sites/twitch.md §8）。
- PLAN §04 把 3.x 用的 flutter_inappwebview 列为【隔离】：最后一个正式版 6.1.5 发布于 2024-10-08，之后只有 6.2.0-beta.1 到 beta.3（beta.3 在 2026-02-04），3.x 实际用的是第三方 beta 分支，违反“只用最新稳定版”（宪法原则 3）。PLAN 要求把网页组件封装在接口后面，再评估替代。
- 要求：Android 和 Windows 两个平台可用（原则 10）；登录后能读到 HttpOnly 的 Cookie（B 站的 `SESSDATA`）；能在导航发生前拦下来（登录结束、房间链接、`bilibili://` 这类应用链接）；能在页面里执行脚本（列出页面里的链接）；Windows 要能判断 WebView2 运行时在不在；许可证宽松（原则 11）。

## 调研（2026-09-28，pub.dev 接口和包内源码）

| 包 | 最新稳定版 | 发布日期 | 许可证 | 平台 | 读 Cookie（含 HttpOnly） | 结论 |
|---|---|---|---|---|---|---|
| webview_flutter | 4.14.1 | 2026-07-07 | BSD-3-Clause | Android、iOS、macOS | 4.14.0 起 `WebViewCookieManager.getCookies` | **Android 选用** |
| webview_flutter_android（随上） | 4.14.1 | 2026-08-28 | BSD-3-Clause | Android | 4.12.0 起；见“已知限制” | 随上 |
| webview_windows | 0.4.0 | 2024-02-17 | BSD-3-Clause（不是 MIT） | Windows（WebView2，纹理渲染） | 没有，只有 `clearCookies` | 放弃 |
| webview_all_windows | 1.4.2 | 2026-09-25 | MIT | Windows（WebView2，纹理渲染） | 有（WebView2 的 CookieManager） | **Windows 选用** |
| webview_all（伞包） | 1.4.2 | 2026-09-25 | MIT | 全平台 | 有 | 不用伞包：Android 用官方实现 |
| webview_win_floating | 3.0.3 | 2026-05-09 | BSD-3-Clause | Windows、Linux（原生窗口浮在 Flutter 画面上） | 没有（实现的接口停在 2.13） | 放弃 |
| flutter_inappwebview | 6.1.5 | 2024-10-08 | Apache-2.0 | 含 Windows | 有 | 放弃：正式版近两年没更新，之后只有 beta |
| webview_cef | 0.6.2 | 2026-08-25 | — | 桌面，自带 CEF/Chromium | — | 放弃：体积大，运行时要随包分发 |

webview_all_windows 和 webview_windows 同源（同样的 CMake、同样用 NuGet 拉 Microsoft.Web.WebView2 1.0.1418.22 和 WIL），但在持续维护（1.3.x–1.4.2 修了初始化、渲染恢复、退出崩溃），并补上了读 Cookie、离屏页面、`callAsyncJavaScript`、运行时检测和下载页。pub 得分 150/160，发布者 abandoft.com。

## 决定

1. **接口**：`apps/pure_live/lib/core/web/web_engine.dart` 定义 `WebEngine`（可用性、打开页面、按地址读 Cookie、清空 Cookie）和 `WebPage`（事件流、加载、刷新、后退、当前地址、执行脚本、视图、释放），功能代码只依赖接口；测试用假实现（test/web/fake_web.dart）。
   - 可用性三种：可用、缺 WebView2 运行时（入口保留，点开说明怎么装）、不支持（入口隐藏）。
   - 每个引擎都拦下非 HTTP(S) 的导航；主框架导航先过功能给的过滤器（可以异步）。
2. **Android**：webview_flutter 4.14.1，用系统 WebView。插件自带的清单合并即可，应用已有 `INTERNET` 权限，`MainActivity.kt` 和 `AndroidManifest.xml` 都不用改。
3. **Windows**：webview_all_windows 1.4.2（加 webview_platform_interface 1.4.2，直接用它的平台接口类，不引入伞包）。
   - WebView2 的用户数据目录放在应用数据目录下的 `WebView2/`：默认位置在可执行文件旁边，装在不可写的目录里会起不来。
   - 用 `getWebViewVersion()` 判断运行时；没有时弹出中文说明：Windows 11 和更新过的 Windows 10 一般自带，否则到微软下载页（https://developer.microsoft.com/microsoft-edge/webview2/）装“常青版引导程序”，装好后重开应用。
   - WebView2 运行时是系统组件，不随安装包分发，符合原则 11。
4. **其它平台**（Linux、macOS、iOS）：没有引擎，网页登录和网页搜索入口都不显示。
5. **Twitch 完整性令牌**：不做。理由写在 spec/sites/twitch.md §8“2026-09-28 调研结论”：旧版的演变说明浏览器外重放令牌不可靠；这条路本质是让平台的反自动化脚本给非浏览器客户端放行，本项目不伪造令牌、不以绕过风控为目标，要不要做需要用户决定并先在真机验证。`live_core` 不加令牌来源接口，`TwitchSite` 保持第一页。

## 备选方案与放弃理由

- **继续用 flutter_inappwebview**：功能最全，但正式版停在 2024-10，后续只有 beta；PLAN §04 已经决定隔离它。
- **webview_windows（任务最初的候选）**：许可证是 BSD-3-Clause，不是 MIT；最后发布是 2024-02，没有读 Cookie 的接口，做不了 B 站网页登录（`SESSDATA` 是 HttpOnly，页面脚本读不到）。要用就得自己维护一个分支补 `Network.getCookies`，不如用已经补好的同源包。
- **webview_win_floating**：原生窗口浮在 Flutter 画面上，Flutter 的弹窗、底部面板画不到它上面；也读不了 Cookie。
- **伞包 webview_all**：Android 会用它自己的实现而不是 Flutter 团队维护的 webview_flutter_android。
- **自己写平台通道**：Android 读 Cookie 只要几行 Kotlin，但要改 `MainActivity`，Windows 的 WebView2 嵌入和纹理渲染工作量大，没必要。

## 影响

- 新依赖：webview_flutter 4.14.1（传递 webview_flutter_android 4.14.1、webview_flutter_wkwebview 3.26.1、webview_flutter_platform_interface 2.15.1）、webview_all_windows 1.4.2、webview_platform_interface 1.4.2，锁在根 `pubspec.lock`。
- Windows 首次构建要联网从 NuGet 下载 WebView2 SDK 和 WIL（和 webview_windows 一样）。
- **已知限制**：
  - webview_flutter_android 4.14.1 的 `getCookies` 把每一对按所有 `=` 切开，只保留第一段和最后一段，值里带 `=` 的 Cookie 会被截短。B 站登录用到的 `SESSDATA`（URL 编码）、`bili_jct`、`DedeUserID` 都不含 `=`，不受影响；以后接入值里带 `=` 的平台时，要么等上游修，要么在 `MainActivity` 加一个调用 `CookieManager.getCookie` 的通道。
  - 退出 B 站账号会清空内置浏览器的全部 Cookie（spec/sites/bilibili.md §8.2），网页搜索里其它网站的登录状态也会一起清掉。
- **待验证**（本次没有构建 APK/EXE）：Windows 构建时确认 WebView2Loader 是静态链接还是随包的 DLL，并核对 NuGet 包 Microsoft.Web.WebView2 的许可证文本，随包分发的部分在关于页的许可证里补登记；Android 和 Windows 真机各走一遍网页登录和网页搜索。
- Flutter 升级时复查这两个包；webview_all_windows 只有一个发布者，停更时退回自维护分支（接口不变，功能代码不动）。
