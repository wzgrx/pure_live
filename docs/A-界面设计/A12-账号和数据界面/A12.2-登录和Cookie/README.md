# A12.2 登录和 Cookie：设计（第 1 版，已确认，已开发，待真机）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-01；K90 上没有记录，见“实现和验证”）
- 旧编号：U.10b、T10a.3（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：哔哩哔哩扫码登录、网页登录；虎牙、斗鱼、抖音、快手、YY、Twitch、SOOP 的 Cookie 页（3.x 共用 `AccountCookieEditorPage`），斗鱼多出的续期输入；改了没保存时的确认；新加网易CC 的 Cookie 页
- 对应：[inventory/UI.md](../../../inventory/UI.md#a122)（A12.2-01～11）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a122)；功能点 F-ACC-02～05（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；入口在 [A12.1](../A12.1-账号总览/README.md)；逻辑在 [K01.1](../../../K-账号和登录/K01-账号和登录方式/README.md)；升级 2-1（斗鱼强制续期）、C-22（网易CC）见 [specs/UPGRADES.md](../../../specs/UPGRADES.md)；相关决定 D-003（L1～L3 按建议 A）、D-018
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）。**8 个平台**是账号列表上的 8 个：7 个有 Cookie 页，用同一个页面，只是输入提示和说明不同，所以用虎牙代表画一张完整的，差别列成表；斗鱼多三项，单独画；哔哩哔哩没有 Cookie 页，是扫码和网页登录。图里的 Cookie、名字、ID 都是一眼能看出的假占位（`xxxxxxxx`、`12345678`、“示例用户”），二维码是随机图案，不能扫
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A12.2-10 | Cookie 页（`AccountCookieEditorPage`） | 账号列表点没登录的虎牙、YY、抖音、快手、Twitch、Soop（路由 `kHuyaCookie` 等） | 竖屏、横屏、宽屏（同一列，最宽 960；窄于 360 时边距 12） | 空（提示字）、有已存的值、改了没保存、保存后（提示条“Cookie 已保存在本机”） |
| A12.2-02～06、09 | 各平台的 Cookie 页 | 同上 | 同上 | 只差输入提示和说明（见下表） |
| A12.2-01 | 斗鱼 Cookie 页 | 账号列表点斗鱼（没登录或登录失效时） | 同上 | 多 LTP0、dy_did 两个输入框和“立即续期”；粘贴 passport Cookie 自动填入；保存后的会话说明；续期的 6 种结果提示 |
| A12.2-11 | 舍弃 Cookie 修改？ | Cookie 页改了没保存就返回 | 对话框 | — |
| A12.2-07 | 哔哩哔哩扫码登录 | 账号列表点哔哩哔哩（电脑直接进；手机先选“二维码登陆”） | 竖屏、宽屏（二维码 140～180） | 加载、待扫码、已扫描、二维码失效、失败（加载失败、轮询中断、没取到 Cookie、核验没通过）、核验中、核验成功；第一次轮询失败弹提示 |
| A12.2-08 | 哔哩哔哩网页登录 | 手机上选“短信登陆” | 竖屏（只有 Android、iOS） | 网页、核验中（盖一层）、出错（底部红条）、正在打开二维码登录 |

电视上的账号设置（扫码登录、用手机扫码填 Cookie）在 A17.9。

## v3 的样子

**Cookie 页**（`account_cookie_editor.dart:147-254`）：标题栏“设置cookie”（`:156`，所有平台一样）。内容左右 16（窄于 360 时 12）：说明横幅（主色 5% 底、圆角 16，`Remix.information_line` 18 + 13 号说明，`:228-254`）→ 20 → 分组标题“Cookie” → 分组卡片里：多行输入框（3～7 行，14 号，最浅的表面色底、圆角 12，聚焦时主色 1.5 边，提示字是平台的“输入提示”，`:176-190`、`:15-32`）→（斗鱼的额外输入）→ 16 → “保存”按钮（`Icons.save_rounded` 18，高 48，圆角 12，`:196-214`）。保存：去掉控制字符和首尾空白后存下，底部浮动 SnackBar“Cookie 已保存在本机”（`:95-110`）；什么都不填也照存、照样这句提示。改了没保存就返回：对话框“舍弃 Cookie 修改？/ 编辑后的 Cookie 尚未保存。确定舍弃修改并离开此页面吗？”“继续编辑 / 舍弃（红字）”（`:112-145`）。

**各平台的差别**只在输入提示和说明（`*_cookie_page.dart:11-12`），见下表。

**斗鱼**（`douyu_cookie_page.dart`、`douyu_cookie_controller.dart`）：说明换成三段（第 1 步、第 2 步、7 天时效）加一个下划线链接 `https://passport.douyu.com/`（`:71-126`）；Cookie 框下面多“LTP0（用于自动续期）”“dy_did（登录所属设备）”两个单行框（带标签和提示）和描边按钮“立即续期”（`Icons.refresh`）（`:29-62`）。粘贴含 LTP0 / dy_did 的 Cookie 自动填进两个框（`controller:31-50`）；保存时 passport Cookie 不覆盖已有的登录（`:84-115`），再弹一条会话说明（有效到几时、能不能自动续期，`:120-162`），和编辑器的 SnackBar 同时出现。

**哔哩哔哩扫码**（`qr_login_page.dart`）：标题“哔哩哔哩账号登录”；说明横幅“请使用哔哩哔哩手机客户端扫描二维码登录”→ 28 → 居中最宽 440：分组卡片里白底二维码（宽 = 可用宽 − 64，限制在 140～180，内边距 12、圆角 12，`:72-90`、`bilibili_login_qr_code.dart`）→ 20 → 状态行（`qr_code_line`“请使用 哔哩哔哩 手机客户端扫码登录”，已扫描时主色底 `checkbox_circle_line`“已扫描，请在手机上确认登录”）。加载和核验是转圈 + 文字；失效、失败把二维码整个换成 `error_warning_line` 40 + 文字 +“刷新二维码 / 重试”（`:36-70`、`:183-215`）。3 秒轮询一次，连续失败退避，3 次后停（`qr_login_controller.dart:240-260`）。确认后先把 Cookie 存进设置再核验（`:286-290`），成功返回。

**哔哩哔哩网页登录**（`web_login_page.dart`）：标题栏同上，右边“二维码登录”（宽 <520 时只有 `qr_code_line` 图标）；正文是内置浏览器打开 `passport.bilibili.com/login`（iPhone 的 UA）；跳到主站时读浏览器的 Cookie、核验，成功返回；核验中盖一层转圈；出错时底部红条（`:110-145`）。

## 各平台的差别

| 平台 | v3 输入提示 | v3 说明 | 新设计 | 状态怎么判断（新） |
|---|---|---|---|---|
| 哔哩哔哩 | 没有 Cookie 页 | 扫码页说明“请使用哔哩哔哩手机客户端扫描二维码登录” | 没登录 → 扫码页；已登录点进 → 账号页（状态卡“已登录：名字”、重新核验、换 Cookie、退出）；Cookie 提示“粘贴哔哩哔哩 Cookie（需含 SESSDATA）”，保存前先核验 | 问平台 |
| 斗鱼 | 粘贴斗鱼完整 Cookie（含 dy_auth） | 三段 + passport 链接 | 说明两段 + “打开 passport.douyu.com”；“续期”一组：LTP0、dy_did、立即续期、登录后强制续期（新） | 本机算会话、到期和能否续期 |
| 虎牙 | 输入虎牙直播cookie | 登陆后,进入直播间,浏览器F12,复制…点击设置按钮即可设置虎牙直播cookie | 通用说明 +“打开虎牙网页” | 本机找账号 ID（yyuid） |
| 抖音 | 输入抖音直播cookie | 同虎牙的旧说明 | 通用说明；保存前先核验 | 问平台（昵称） |
| 快手 | 输入快手直播cookie | 同虎牙的旧说明 | 通用说明 | 只看是否保存 |
| YY | 粘贴 YY Cookie | 登录 YY 网页并进入任意直播间，在浏览器开发者工具的网络请求中复制完整 Cookie；Cookie 仅保存在本机。 | 同 v3 + 打开网页 | 只看是否保存 |
| Twitch | 粘贴 Twitch Cookie | 同上，另说明 auth-token 与 login 用于读取聊天 | 同 v3 + 打开网页 | 本机找 auth-token 和 login |
| SOOP | 粘贴 SOOP Live Cookie | 同 YY 的说明 | 同 v3 + 打开网页 | 只看是否保存 |
| 网易 CC（新） | — | — | 通用说明（升级 C-22） | “已保存，暂未用于请求” |

## v4 现在的偏差（K01.1 写的，未经对照）

已经有：状态卡、打开官网、粘贴和清空、先核验再保存、斗鱼续期组和强制续期、扫码的覆盖层和“填写 Cookie”、CC。网页登录因为没有 WebView 插件，现在是哔哩哔哩 Cookie 页加一句“暂不可用”；新设计按 v3 保留网页登录，开发时要加依赖（K01.1“留给后续”）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 一个 Cookie 页加平台差别表；状态卡、说明统一、粘贴清空、先核验再保存、页内退出；斗鱼续期组；扫码覆盖层和其他登录方式；三个选择 | 用户 2026-10-01 确认；L1～L3 按建议 A（D-003） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [Cookie 页（以虎牙为例）](page/02-Cookie-页-以虎牙为例.jpg)
- [各平台的差别](page/03-各平台的差别.jpg)
- [斗鱼](page/04-斗鱼.jpg)
- [哔哩哔哩扫码和网页登录](page/05-哔哩哔哩扫码和网页登录.jpg)
- [状态、对话框和提示](page/06-状态-对话框和提示.jpg)
- [v3 的问题](page/07-v3-的问题.jpg)
- [改了什么](page/08-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/09-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/10-各客户端.jpg)
- [需要你选的](page/11-需要你选的.jpg)
- [性能要点](page/12-性能要点.jpg)
- [拿不准的地方](page/13-拿不准的地方.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-cookie.jpg](v3-cookie.jpg)、[v4-cookie.jpg](v4-cookie.jpg)、[v4-cookie-n.jpg](v4-cookie-n.jpg) | Cookie 页（虎牙）：v3 / 新设计 / 按钮编号 |
| [v3-douyu.jpg](v3-douyu.jpg)、[v4-douyu.jpg](v4-douyu.jpg)、[v4-douyu-n.jpg](v4-douyu-n.jpg) | 斗鱼 |
| [v3-qr.jpg](v3-qr.jpg)、[v4-qr.jpg](v4-qr.jpg)、[v4-qr-n.jpg](v4-qr-n.jpg) | 哔哩哔哩扫码 |
| [v3-web.jpg](v3-web.jpg) | 哔哩哔哩网页登录（新设计同 v3） |
| [v3-sheet.jpg](v3-sheet.jpg)、[v4-sheet.jpg](v4-sheet.jpg) | 舍弃确认、保存提示、扫码各状态；新设计另有状态卡各种样子、输入出错、保存中、页内退出 |
| [v3-wide.jpg](v3-wide.jpg)、[v4-wide.jpg](v4-wide.jpg)、[v3-qr-wide.jpg](v3-qr-wide.jpg)、[v4-qr-wide.jpg](v4-qr-wide.jpg) | 1280×800 |
| [v3-land.jpg](v3-land.jpg)、[v4-land.jpg](v4-land.jpg) | 手机横屏 852×393 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 修改 | 标题写平台：“虎牙账号”等 | B1 |
| c2 | 增强 | 顶部状态卡：现在存的是什么、能不能用；哔哩哔哩、抖音有“重新核验” | B3 |
| c3 | 修改 | 说明和输入提示统一，虎牙、抖音、快手换掉旧说明 | B2 |
| c4 | 增强 | 说明里加“打开 xx 网页” | — |
| c5 | 增强 | 输入框下“粘贴”“清空”；不是 Cookie 的内容框下说明、不能保存；自动去掉“Cookie:”前缀 | B7 |
| c6 | 修改 | 没改动时保存变灰；哔哩哔哩、抖音先核验再存；保存中转圈；一次一条提示 | B4、B5 |
| c7 | 增强 | 页面里加“退出登录”；清空再保存 = 退出，先确认 | B4 |
| c8 | 保留 | 说明横幅、“Cookie”分组、多行输入、保存按钮、舍弃确认 | — |
| c9 | 修改 | 斗鱼：会话说明常驻状态卡；续期一组带标签和说明；保存后框里是实际存下的登录 Cookie | B5、B6 |
| c10 | 增强 | 斗鱼“登录后强制续期”（升级 2-1） | — |
| c11 | 修改 | 扫码：去掉重复说明；二维码 200（电脑 220）；状态盖在二维码上，位置不跳 | B8、B9 |
| c12 | 增强 | 扫码页下面“扫不了？网页登录 / 填写 Cookie” | B10 |
| c13 | 修改 | 扫码先核验后存 | B11 |
| c14 | 保留 | 网页登录页照 v3 | — |
| c15 | 增强 | 网易 CC 的 Cookie 页（升级 C-22） | — |

## 按钮的作用和用法

见对比页（编号 1～13，图 [v4-cookie-n.jpg](v4-cookie-n.jpg)、[v4-douyu-n.jpg](v4-douyu-n.jpg)、[v4-qr-n.jpg](v4-qr-n.jpg)）。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同一列，键盘弹出时输入框滚到可见处（照 v3 的 `scrollPadding`） |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 同一页，一栏最宽 720 居中；扫码页二维码 220；电脑上没有网页登录（照 v3），“扫不了？”下只有“填写 Cookie”；Ctrl+V 直接粘贴，Ctrl+S 保存（新） |
| 电视 | 不在本任务（A17.9）：pure_live_TV 用手机扫码在手机网页上填 Cookie，哔哩哔哩扫码；状态卡文字和平台差别照本页 |
| 苹果平台差异 | iOS 同 Android（有网页登录）；macOS 同电脑，Cmd+V、Cmd+S |

## 待选

- L1 已存的 Cookie 在输入框里：建议 A 照 v3 显示原文；B 默认隐藏，点“显示”才出现。
- L2 扫码页的“填写 Cookie”：建议 A 放；B 不放。
- L3 Cookie 页里的“退出登录”：建议 A 放；B 只在列表上。

## 拿不准的地方

- 哔哩哔哩网页登录要内置浏览器（`flutter_inappwebview`），v4 现在没有；没加之前“网页登录”这一项先不显示。
- Ctrl+S 保存是新加的快捷键，v3 没有；如果不想要可以去掉。
- v3 的说明横幅字色是 `onSurfaceVariant` 80%，按 kit 的颜色画，和真机可能略有差别。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-01，开发提交 `587ccc3c7`（登记表写的就是它，和 A12.1 同一个提交），合并提交 `59248e0b9`；收尾在 `a88f26dfc`“Merge U.2, U.8 and U.10 follow-ups”（2026-10-02）合并）

| 编号 | 做到 | 现在的代码（`apps/pure_live/lib/features/account/` 省略前缀） |
|---|---|---|
| c1 | ✅ | 标题 `account_editor_title`“{name}账号”（`cookie_editor.dart:404`；3.x 都是“设置cookie”） |
| c2 | ✅ | 状态卡 `AccountStatusCard`（`account_widgets.dart:20`，图标 32），文字和列表同一个 `accountStatus`（`platform_cookie_view.dart:137`）；没存时“未设置：粘贴登录后的 Cookie”；哔哩哔哩、抖音卡片右边“重新核验”（`platform_cookie_view.dart:149-152`，核验中不显示） |
| c3 | ✅ | 通用说明 `cookie_tip`、提示 `cookie_hint`（`account_platforms.dart:76-79`）；哔哩哔哩、斗鱼、Twitch、SOOP 用各自的键（`:92-93`、`:100`、`:128-129`、`:137-138`）；“仅保存在本机”挪到页底说明 |
| c4 | ✅ | 说明横幅 `AccountTipBanner`（`account_widgets.dart:99`）里“打开 xx 网页”，系统浏览器打开（`openAccountWebsite` `:166`）；斗鱼是“打开 passport.douyu.com”（`douyu_cookie_view.dart:19`） |
| c5 | ✅ | “粘贴”“清空”两个描边小按钮（`cookie_editor.dart:334-338`）；去掉“Cookie:”前缀（`account_state.dart:255`）；不像 Cookie 时框变红、说明、不能保存（`cookie_editor.dart:229-230`，`looksLikeCookie` `account_state.dart:258`） |
| c6 | ✅ | 没改动时保存变灰（`cookie_editor.dart:346`）；先核验再存（`platform_cookie_view.dart:95-124`，保存中“正在核验并保存…” `cookie_editor.dart:307`）；核验请求本身失败照存并提示“已保存，暂时无法核验账号”；一次一条提示 |
| c7 | ✅（偏差 1） | 页内“退出登录”（`cookie_editor.dart:381`），确认用和列表同一个 `confirmSignOut`（`:244`）；清空后保存按退出处理（`:225-228`） |
| c8 | ✅ | 说明横幅、“Cookie”分组、多行输入 3～7 行（`:83-84`）、48 高的保存按钮、舍弃确认“舍弃 Cookie 修改？”“继续编辑 / 舍弃”（`:274-283`，`PopScope` `:394`）；L1 A：已存的 Cookie 在框里照原文显示 |
| c9 | ✅ | 斗鱼会话说明在状态卡（`account_state.dart:211`、`:224`）；“续期”一组：LTP0、dy_did 带标签的框、“立即续期”和一句说明（`douyu_cookie_view.dart:201-255`）；粘贴 passport Cookie 只取走 LTP0 / dy_did（`:72-79`），保存后框里是实际存下的登录 Cookie（`:93-115`） |
| c10 | ✅ | “登录后强制续期”开关单独一张卡（`douyu_cookie_view.dart:257-261`，设置键 `douyuForceRenew`，`packages/live_store/lib/src/settings/settings.dart:117`，默认关） |
| c11 | ✅ | 扫码页 `BilibiliQrLoginView`（`bilibili_qr_login.dart:183`）：没有重复的顶部说明；二维码 200，宽 ≥600 时 220（`:257-260`）；六种状态 `BilibiliQrPhase`（`:17`）盖在 `live_ui` 的 `QrCodeCard` 上（`_QrCard` `:309`），失效、失败的按钮在二维码中间；下面一行 `_QrMessage`（`:349`，已扫描时主色浅底） |
| c12 | ✅ | “扫不了？”（`:274-300`）：网页登录只在 Android、iOS 且 `InAppWeb.available`（`:243-244`）；“填写 Cookie”进哔哩哔哩的 Cookie 页，返回回到扫码页（L2 A） |
| c13 | ✅ | `_complete`（`:214-240`）：确认后先核验，平台说没登录不存；核验请求失败照存，提示“已保存，暂时无法核验账号” |
| c14 | ✅ | 网页登录 `BilibiliWebLoginView`（`bilibili_web_login.dart:46`）：标题栏“二维码登录”（宽 <520 只有图标，`:140`），核验中盖一层（`:168-190`），出错底部红条（`:192-220`）；成功后 `pop(true)`（`:125`） |
| c15 | ✅ | 网易CC 走 `RoutePath.kSettingsAccount` 加 `cc`（`account_platforms.dart:117-122` 没有自己的路由），同一个 `PlatformCookieView`；状态“已保存，暂未用于请求” |

- 根因（记录）：3.x 每个平台一个 `*_cookie_page.dart`、标题都写“设置cookie”，保存不核验、什么都不填也提示“已保存”，斗鱼的会话说明是一条和保存提示同时出现的提示条，扫码页的状态把二维码整个换掉导致位置跳动。
- 偏差（记录“偏差和原因”，以现在的代码为准）：①页内退出确认当时照图写“退出虎牙？”，A07.9 收尾（`8f6a925b6`，2026-10-01）改成和列表同一个 `confirmSignOut`（3.x 文字），`confirmPageSignOut` 和 `account_sign_out_title`、`account_sign_out_message` 已删；②网页登录：设计写“v4 没有内置浏览器，先不显示”，实际 O03.1 已接入 `flutter_inappwebview`，所以手机上显示；没有内置浏览器时旧网页登录地址显示哔哩哔哩 Cookie 页加黄色提醒（`account_page.dart:39`、`platform_cookie_view.dart:140`）；③斗鱼到期时间沿用 `yyyy-MM-dd HH:mm`（设计图是示意的“10-08 21:30”）；④哔哩哔哩 Cookie 页去掉 v4 原来标题栏的“二维码登录”。
- 后来的变化：`dc5abab12`（2026-10-01）二维码深色主题的定位点、提醒卡按钮靠左；`6d90f6649` 平台名统一成“SOOP”“网易CC”；`d2ec7bbfc` 网页登录存好 Cookie 后直接关闭（A09.8 修了共用浏览器的死循环后不再用 `maybePop`）；A02.1（`914784264`）二维码卡片挪到 `live_ui` 的 `QrCodeCard`、斗鱼和 Cookie 页改用共用设置行；A02.2（`fc5bcdd46`）确认框改用 `showAppConfirmDialog`。
- 新文字：`account_status_none_hint`、`account_saving_verifying`、`account_qr_cannot_scan`、`account_qr_stopped`、`account_web_login_option`、`qr_scanned`、`qr_expired_hint`、`douyu_open_passport` 等（当时 10 条，其中 `account_sign_out_title`、`account_sign_out_message` 随收尾删掉）；改 16 条（`account_editor_title`、`account_saved_signed_in`“已保存，已登录：{name}”、`cookie_tip` 等，见记录）。没有新设置（`douyuForceRenew` 是 K01.1 的）。测试和截图只用假 Cookie（`SESSDATA=ok`、`yyuid=1234`）。

**验证**

- 自动测试：`apps/pure_live/test/features/account/account_page_test.dart` 中本任务 13 个，分组 `U.10b cookie pages`（`:334-648`）：Cookie 页从上到下的顺序和各状态、页内退出（3.x 文字）和清空保存等于退出、剪贴板粘贴和 Ctrl+S、哔哩哔哩和抖音先核验再存与重新核验、网易CC 页、斗鱼的状态卡续期组 passport Cookie 立即续期强制续期、扫码覆盖层位置不动和刷新后确认并存、平台拒绝不存（c13）、“扫不了？”、手机有内置浏览器时网页登录在前、宽屏二维码 220 和 Cookie 页 ≤720、没有内置浏览器的提醒、斗鱼会话说明的逻辑。`test/plugins_test.dart:197` 测内置浏览器落到哔哩哔哩主站时取 Cookie。
- 真机：**记录里没有 K90 结果**，也没有 `verify.md`。登记表已是“完成”，不符合 PROCESS 3.2（问题记在[子分类页](../README.md)“已知问题”）。要看的：[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条（扫码登录、杀掉重开仍登录，Keystore 解密，[K02.1](../../../K-账号和登录/K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)）、第 7 条（网页登录，F-ACC-03）、第 8 条（登录后原画，F-ACC-07），归 [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md)；另看一次虎牙 Cookie 页的粘贴、清空、舍弃确认和斗鱼续期组的键盘遮挡（`scrollPadding` `cookie_editor.dart:93`）。
- 留下的问题和去向：网易CC 的 Cookie 还不用于请求 → UPGRADES C-22（未排）；横屏手机顶栏 56 高（`cookie_editor.dart:404`、`bilibili_qr_login.dart:250`、`bilibili_web_login.dart:136` 用普通 `AppBar`）→ 建议并入 A04.1；Esc 返回 → A05.1；哔哩哔哩多账号 → [V01.2](../../../V-需求和反馈/V01-新功能提议/V01.2-哔哩哔哩多账号/README.md) 提议。
