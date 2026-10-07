# K01 账号和登录方式

账号、网页登录、扫码、Cookie。

用户在各平台登录的方式和登录凭据的写入：哔哩哔哩扫码、哔哩哔哩网页（短信）登录、各平台粘贴 Cookie、斗鱼的 LTP0 续期凭据，以及退出。账号总览和各登录页的样子归 A12.1、A12.2。

## 范围

- 包括：
  - 平台表 `apps/pure_live/lib/features/account/account_platforms.dart`：9 个平台（哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、网易 CC、Twitch、SOOP）、各自的核验方式（`AccountCheckKind`：在线问平台、斗鱼会话、Twitch 聊天身份、虎牙 yyuid、不核验）、国内 / 海外、官网地址、旧路由、CC 只存不用（`usedByRequests: false`）。
  - 写入 `account_services.dart` 的 `AccountActions`：保存、记下哔哩哔哩 uid、退出（连同斗鱼 LTP0、DID、保存时间）、斗鱼的三种保存；页面里可替换的服务（核验、扫码接口、斗鱼续期、时钟）。
  - 状态计算 `account_state.dart`：`accountStatus`、斗鱼会话说明、粘贴文本清理（去控制字符、去 `Cookie:` 前缀）和“像不像 Cookie”的判断。
  - 扫码 `bilibili_qr_login.dart` 的 `BilibiliQrLogin`（`ChangeNotifier`）：取码、3 秒轮询、已扫码、过期、确认后先核验再存、连续失败退避和停止。
  - 网页登录 `bilibili_web_login.dart`：打开前清 WebView 里哔哩哔哩的 Cookie、跳到主站时读出 Cookie、核验后保存。
  - 斗鱼 `douyu_cookie_view.dart` 的逻辑：粘贴 passport Cookie 自动取 LTP0 和 dy_did、立即续期、“登录后强制续期”开关（设置 `douyuForceRenew`）。
- 不包括（归哪里）：
  - 页面、卡片、按钮、提示的样子 → [A12.1](../../A-界面设计/A12-账号和数据界面/A12.1-账号总览/README.md)、[A12.2](../../A-界面设计/A12-账号和数据界面/A12.2-登录和Cookie/README.md)。
  - 存 Cookie 的密钥库和加密 → J02；登录以后的有效性、失效提示、弹幕重连 → K02。
  - 平台一侧的接口：`BilibiliSite.qrCode`（`packages/live_core/lib/src/sites/bilibili/bilibili_site.dart:545`）、`qrPoll`（`:559`）、`account`（`:582`）；`DouyinSite.account`（`douyin/douyin_site.dart:743`）；`DouyuSite.renewSession`（`douyu/douyu_site.dart:499`）、`DouyuApi.sessionExpiry` / `sessionState`（`douyu_api.dart:735`、`:745`）；`HuyaApi.viewerUidFromCookie`（`huya_api.dart:1001`）；`TwitchApi.chatLogin`（`twitch_api.dart:345`）→ E01、E03。
  - WebView 本身（`flutter_inappwebview`、`shared/in_app_web.dart`）→ O03.1。

## 现状：做到哪、怎么工作的

- 用户看得到的（设置 → 平台显示与授权 → 平台账号，或列表页“需要登录”的按钮）：国内、海外两组平台，每行写当前状态（未设置、已登录：名字、登录已失效、暂时无法核验、无法在本机读取、斗鱼“到期前自动续期”或“预计某时到期”、Twitch 的聊天身份、虎牙账号 ID、CC“已保存，暂未用于请求”）；点平台进它的页面；已登录的行尾有退出（先确认）；标题栏“退出全部账号”。哔哩哔哩没登录时点它直接进扫码；扫码页“扫不了？”可以改用 Cookie 或（手机上）网页登录。Cookie 页：状态卡、说明、输入框、粘贴、清空、保存（没改动时不可点）、退出；不是 `name=value` 的文字不让存；改了没保存离开时问要不要舍弃。
- 内部怎么工作：

```text
保存（platform_cookie_view.dart:94 _save）
  cleanPastedCookie（account_state.dart:255）→ 在线核验的平台（哔哩哔哩、抖音）先问平台：
     accountVerifierProvider（account_services.dart:29）→ BilibiliSite.account / DouyinSite.account
     平台说没登录（NeedsLogin）→ 不存，提示 account_cookie_rejected；问不到 → 照存，标“暂时无法核验”
  → AccountActions.save（:101）→ store.secrets.setCookie（J02，加密）；哔哩哔哩换了 Cookie 先把 bilibiliUid 清 0，核验后再记（:110）
  → secrets.cookieChanges → 平台适配器（StoreCookieVault）和打开着的直播间（K02）立即用新的
扫码（bilibili_qr_login.dart:43 BilibiliQrLogin）
  qrCode → waiting → 每 3 秒 qrPoll（失败退避 2～4 倍，连续 3 次失败停，:52）→ scanned（码上盖勾）→ confirmed：
  _complete：先核验，平台说没登录不存；存 Cookie 和 uid → done；expired → 盖“刷新二维码”
网页登录（bilibili_web_login.dart:54）
  打开前清 www / passport / m.bilibili.com 的 WebView Cookie（:67-77）→ 用户在 passport 页登录 → 跳到主站（isBilibiliHome :25）
  → 读三个域的 Cookie 拼成请求头（cookieHeader :32）→ 没有 SESSDATA 报错；核验规则同扫码 → 存 → 返回
斗鱼（douyu_cookie_view.dart）：粘贴 passport Cookie 自动填 LTP0 / dy_did，不覆盖已存的登录；saveDouyu 只在 Cookie 变了时更新保存时间（account_services.dart:138）；
  立即续期（:121）→ douyuRenewerProvider → DouyuSite.renewSession；“登录后强制续期”写设置 douyuForceRenew，取流时 DouyuSite 读（douyu_site.dart:459）
退出（account_services.dart:116）：删 Cookie；斗鱼一并删 LTP0、DID、保存时间；哔哩哔哩 uid 清 0
```

- 完成度：K01.1（2026-10-01，`e5ae55fbf`）做完账号列表、各 Cookie 页、扫码、斗鱼；O03.1 加了 WebView 后网页登录做出来（3.x 有）；A12.1～A12.2 按确认的设计重做了页面（例如“扫不了？”的入口、宽屏）。清点：F-ACC-01、02、04、05“完成”，F-ACC-03（网页登录）“没验证”→ S02.6。**账号页整体没在 K90 上看过**（S02.3 记录）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/account/account_page.dart`（50 行） | 路由分发：扫码、网页登录（有 WebView 时）、按路由或参数找平台、斗鱼单独的页、其余 `PlatformCookieView`；`kDouyuCookie` 照 3.x 是抖音页的旧别名 |
| `.../account_platforms.dart`（160 行） | `AccountCheckKind`（`:7`）、`AccountPlatform`（`:25`）、`accountPlatforms`（`:87`，9 个平台和顺序）、`accountPlatformOf`（`:144`）、`accountPlatformForRoute`（`:154`） |
| `.../account_services.dart`（159 行） | `AccountIdentity`、`AccountVerifier`（`:8-13`）、`BilibiliQrApi`（`:16`）、`DouyuRenewer`（`:26`）；provider：`accountVerifierProvider`（`:29`）、`bilibiliQrApiProvider`（`:39`）、`douyuRenewerProvider`（`:44`）、`accountClockProvider`（`:50`）、`accountActionsProvider`（`:53`）；`AccountActions`（`:71`：`cookieOf`、`unreadable`、`snapshot`、`save` `:101`、`rememberBilibiliUid` `:110`、`signOut` `:116`、`douyuLogin`、`saveDouyu` `:138`、`saveDouyuPair` `:151`、`saveDouyuRenewed` `:155`） |
| `.../account_state.dart`（261 行） | `AccountTone`、`AccountStatus`、`AccountCheck` 一族（核验中、已核验、被拒、失败）、`AccountSnapshot`（`:92`）、`accountCheckFailure`（`:87`）、`accountStatus`（`:115`）、`accountStored`（`:187`）、斗鱼 `douyuSessionState`（`:211`）和 `douyuSummary`（`:224`）、`cleanPastedCookie`（`:255`）、`looksLikeCookie`（`:258`）、`pastedCookieField`（`:261`） |
| `.../bilibili_qr_login.dart`（395 行） | `BilibiliQrPhase`（`:17`）、`BilibiliQrLogin`（`:43`：取码、轮询、退避、`_complete`、失败）；`BilibiliQrLoginView`（`:183`，界面） |
| `.../bilibili_web_login.dart`（230 行） | `bilibiliPassportLogin`（`:16`）、`bilibiliLoginUserAgent`（`:20`，iPhone UA）、`isBilibiliHome`（`:25`）、`cookieHeader`（`:32`）、`BilibiliWebLoginView`（`:46`：清 Cookie `:67`、`_page` `:79`、`_complete` `:105`） |
| `.../cookie_editor.dart`（427 行）、`platform_cookie_view.dart`（167 行）、`douyu_cookie_view.dart`（305 行）、`account_list_view.dart`（224 行）、`account_widgets.dart`（205 行） | 界面为主（A12.1、A12.2）；逻辑相关：`PlatformCookieView._save`（`platform_cookie_view.dart:94`，先核验再存）、`CookieEditor._save`（`cookie_editor.dart:220`，空 = 退出、不像 Cookie 报错）、`DouyuCookieView._renewNow`（`douyu_cookie_view.dart:121`）、`AccountListView._check`（`account_list_view.dart:62`，打开列表时核验，失效时退出并提示） |
| `apps/pure_live/lib/app/platforms.dart` | `StoreCookieVault`（`:52`）、`StoreDouyuLogin`（`:68`）：把这里写的东西交给平台适配器 |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/account/account_page_test.dart`（22） | 列表两组和每个平台的状态（`:209`）；点平台进页、哔哩哔哩没登录直接扫码（`:279`）；退出确认（`:294`）；哔哩哔哩失效时退出并提示（`:310`）；解不开的 Cookie（`:317`）；Cookie 页顺序、退出、清空保存 = 退出（`:335`、`:391`）；粘贴和 Ctrl+S（`:411`）；先核验再存（`:435`）；CC（`:464`）；斗鱼续期组、passport Cookie、立即续期、强制续期（`:474`）；扫码的状态、被拒不存、“扫不了？”、手机先网页登录（`:535`～`:600`）；没有 WebView 时网页登录路由的说明（`:624`）；斗鱼说明（`:631`）；云账号三个路由（`:651`）；平台名字（`:703`） |

## 3.x 基线

- `git show v3.2.11:lib/modules/account/`（31 个文件约 2300 行）：`account_page.dart`（列表；点已登录的平台直接弹退出，`:51-150` 存了 Cookie 就显示“已登录”）、`bilibili/qr_login_controller.dart`（3 秒轮询 `:42`，先存 Cookie 再核验 `:286-290`）、`bilibili/web_login_controller.dart`（WebView 读 Cookie `:176`）、`douyu/douyu_cookie_controller.dart`（清空保存不退出 `:105`、每次保存都重设保存时间 `:117-118`）、`widgets/account_cookie_editor.dart`（通用 Cookie 编辑页）、各平台的 Cookie 页。
- 启动核验：`lib/common/services/settings/bilibili_account_service.dart`（启动 1 秒后 `loadUserInfo` `:52`，失效时退出；退出时 `_clearBrowserCookies` 清掉 WebView 的全部 Cookie `:200`）。
- 必须保留：平台和入口路由（列表页、设置页、“前往登录”都进 `kSettingsAccount`）；3.x 的键 `bilibiliUid`、`douyuCookieSavedAt`；扫码的节奏和失败处理；斗鱼 passport Cookie 不覆盖已存的登录；退出确认的文字。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 账号页、扫码、网页登录、斗鱼续期都没在 K90 上看过 | — | 真机上的扫码轮询、WebView 跳转、键盘遮挡（`cookie_editor.dart` 的 `scrollPadding`）不知道 | 扫码和杀掉重开 → K02.1；网页登录、登录后原画 → [S02.6](../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段 |
| 退出哔哩哔哩时不清 WebView 里的哔哩哔哩 Cookie（3.x 清全部，`bilibili_account_service.dart:200`）；4.x 改成打开网页登录时才清（`bilibili_web_login.dart:67-77`） | `account_services.dart:116-123` | 退出后，应用内的网页（网页搜索打开的哔哩哔哩页面，`shared/in_app_web.dart`）可能仍是登录状态 | 建议小改动：`signOut(bilibili)` 时也清 WebView 的哔哩哔哩 Cookie（WebView 可用时）；没有任务，S02.6 网页登录时顺带确认 |
| 保存 Cookie 时 Keystore 出错没有提示，扫码登录会停在“核验中” | `account_services.dart:101-107`；`cookie_editor.dart:234-239`；`bilibili_qr_login.dart:136-159` | 少见机型才会出错；出错时用户不知道为什么 | 见 J02 已知问题；K02.1 先确认 K90 上不出错 |
| CC 的 Cookie 只存不用 | `account_platforms.dart:117-122` | 用户填了也没效果（页面写明“暂未用于请求”） | UPGRADES C-22，未排：要用户的登录 Cookie 才能验证“登录后加入弹幕”（V03.3 需要维护者决定） |
| 快手登录后的“直播”搜索没做 | — | 有 Cookie 也只能搜到游客能搜的 | UPGRADES C-17，未排（同上） |
| CHZZK、AcFun 等适配器不读 Cookie 的平台没有入口 | `account_platforms.dart:82-87` | 照 3.x | 哪个平台的适配器接上 `CookieVault` 就加一行 |

## 相关决定和规范

- D-013（打码昵称不还原，做登录引导）、D-017（测试不访问真实平台）、D-018（键名不变）、D-019。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：2-1（斗鱼强制续期，完成）、C-17、C-22（部分完成）。
- 不把真实 Cookie、账号写进仓库（[specs/ENGINEERING.md](../../specs/ENGINEERING.md)、PROCESS 第 14 节）。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account/`（内存库 `LiveStore.memory()`，核验、扫码、续期、时钟都用页面 provider 替换，不访问平台）。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条（扫码、杀掉重开仍登录）→ K02.1；第 7 条（网页登录）、第 8 条（登录后原画）→ S02.6。用维护者自己的测试账号，截图遮住 Cookie。

## 路线

1. K02.1 + S02.6 第 3 阶段：真机走一遍扫码、网页登录、Cookie 页、斗鱼续期。
2. 根据结果开小任务：退出时清 WebView 的哔哩哔哩 Cookie、保存失败的提示。
3. C-17、C-22：维护者决定是否提供登录 Cookie 来做（做的话开到 E 组）。
4. V01.2 哔哩哔哩多账号（提议，参考 pure_live_TV `6ba16c55`）：用户确认后在本组登记实现任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [K 账号和登录](../README.md)。

- 代码：`features/account/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| K01.1 | 账号与登录 | 功能 | 完成 | 2026-10-01 | e5ae55fbf | [设计或说明](K01.1-账号与登录/README.md)、[记录](K01.1-账号与登录/record.md) |

<!-- docs:生成结束 -->
