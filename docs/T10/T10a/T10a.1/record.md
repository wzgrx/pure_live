# T10a.1 页面：账号与登录

- 日期：2026-10-01
- 目录：`apps/pure_live/lib/features/account/`（路由 `kSettingsAccount`、`kBiliBiliQRLogin`、`kBiliBiliWebLogin`、`kHuyaCookie`、`kDouyuAccountCookie`、`kDouyinCookie`、`kDouyuCookie`、`kTwitchCookie`、`kYyCookie`、`kSoop`、`kKuaishouCookie`，类名 `AccountPage`）、`apps/pure_live/lib/features/auth/`（路由 `kSignIn`、`kMine`、`kUserManage`，类名 `AuthPage`）；类名和构造参数不变，路由表没改
- v3 来源：标签 `v3.2.11` 的 `lib/modules/account/`（31 个文件，约 2400 行：账号列表、8 个 Cookie 页、哔哩哔哩扫码和网页登录、`account_cookie_editor.dart`）、`lib/common/services/settings/bilibili_account_service.dart`（启动时核验哔哩哔哩账号）、`lib/modules/auth/`（13 个文件，约 3400 行，Firebase 云端账号）
- 用到的模块：T02a.1（`BilibiliSite.qrCode`、`qrPoll`、`account`）、T02a.2（`DouyuApi` 会话函数、`DouyuSite.renewSession`）、T02a.4（`DouyinSite.account`）、T02a.3/M4.08（`HuyaApi.viewerUidFromCookie`、`TwitchApi.chatLogin`）、T09b.1（`store.secrets` 加密 Cookie、`SecretRefs.douyuLtp0/douyuDid`、设置 `bilibiliUid`、`douyuCookieSavedAt`、`douyuForceRenew`）、T01a.1（设置卡片、`PlatformLogo`、`QrCodeWidget`）、T07a.1（provider、`AppNavigator`、`i18n`）

## 做法

| 文件 | 内容 |
|---|---|
| `account_page.dart` | 路由入口：扫码路由给 `BilibiliQrLoginView`；`kSettingsAccount` 不带参数是账号列表，带平台 id（字符串）是该平台的 Cookie 页；其余 Cookie 路由按 `accountPlatformForRoute` 分到 `PlatformCookieView`，斗鱼给 `DouyuCookieView`；`kDouyuCookie` 照 v3 仍是抖音页的旧别名；`kBiliBiliWebLogin` 是哔哩哔哩 Cookie 页加“网页登录暂不可用”的说明 |
| `account_platforms.dart` | 平台表：id、Cookie 路由、核验方式、国内/海外、提示文字、官网地址、Cookie 是否已被请求使用（CC 只存不用） |
| `account_state.dart` | 状态计算（纯函数）：`accountStatus`（未设置、核验中、已登录 + 名字、已失效、核验失败、无法解密，以及斗鱼、Twitch、虎牙的本地判断）、斗鱼会话说明 `douyuSummary`（照 v3 `_sessionSummary`）、粘贴文本清理 `cleanPastedCookie`（去控制字符、去 `Cookie:` 前缀）、`looksLikeCookie` |
| `account_services.dart` | 页面内 provider（测试替换）：`accountVerifierProvider`（哔哩哔哩 `account`、抖音 `account`）、`bilibiliQrApiProvider`、`douyuRenewerProvider`、`accountClockProvider`；`AccountActions`：所有写入都走 `LiveStore`（`secrets.setCookie/writeAll/clearCookies`、`bilibiliUid`、`douyuCookieSavedAt`） |
| `account_list_view.dart` | 账号列表 |
| `cookie_editor.dart` | 通用 Cookie 编辑页（v3 `AccountCookieEditorPage`） |
| `platform_cookie_view.dart` | 单个平台的 Cookie 页（虎牙、抖音、快手、YY、CC、Twitch、SOOP、哔哩哔哩） |
| `douyu_cookie_view.dart` | 斗鱼 Cookie 页：页面 Cookie + LTP0 + dy_did、立即续期、“登录后强制续期”开关 |
| `bilibili_qr_login.dart` | 扫码流程 `BilibiliQrLogin`（`ChangeNotifier`，对应 v3 `BiliBiliQRLoginController`）和页面 |
| `account_widgets.dart` | 状态卡、说明横幅（带“打开官网”）、确认框 |
| `auth/auth_page.dart` | 云端账号的三个路由：说明 Firebase 云端账号已停用，引到 WebDAV、设备同步、备份与恢复和平台账号 |

翻译：`zh.json`、`en.json` 各加 49 个键（41 个 `account_*`、8 个 `auth_*`），放在原有的 `account_verifying` 前后，按字母序；v3 的 Cookie 页、斗鱼、扫码、退出相关的键照用。

Cookie 改动后立即生效：适配器经应用的 `StoreCookieVault` 读 `secrets.cookieFor`，`cookieChanges` 让哔哩哔哩等重建会话。页面监听 `secrets.cookieChanges` 刷新显示。

## 与 v3 的功能对照

| v3 | v4 | 说明 |
|---|---|---|
| 账号列表：哔哩哔哩、虎牙、YY、抖音、快手、Twitch、SOOP、斗鱼，平台图标、状态文字、已登录时退出按钮 | 有 | 分“国内平台”“海外平台”两组；加 CC（C-22 的入口）；状态见“界面改进”2 |
| 点已登录的平台 = 退出确认框；点未登录的进 Cookie 页/登录 | 改 | 点平台都进它的页面（查看、修改、核验），退出用行尾按钮（有确认框）；见“界面改进”3 |
| 哔哩哔哩：已登录显示用户名，核验中显示“正在核验账号…” | 有 | |
| 哔哩哔哩账号服务：启动 1 秒后核验 Cookie，`-101` 时提示“登录已失效”并退出，记下 uid | 部分 | 打开账号列表时核验（同样的提示和退出、记下 uid）；应用启动时的核验没做（属于 `lib/app`，见“留给后续”） |
| 抖音：显示昵称，取不到时“已登录” | 有 | 失效的 Cookie 显示“登录已失效”（v3 把错误数据当账号信息，T02a.4 问题 16） |
| 斗鱼：按会话状态显示（未设置、有效、过期可续期、需重新粘贴） | 有 | |
| 退出确认框（“确定退出“{name}”账号吗？”），同时只处理一个 | 有 | |
| Cookie 页：说明横幅、多行输入、保存（规范化、提示“Cookie 已保存在本机”）、改了没保存离开时确认舍弃 | 有 | 额外输入（斗鱼 LTP0/dy_did）也算未保存；见“界面改进”4 |
| 虎牙、抖音、快手、YY、Twitch、SOOP 各自的 Cookie 页（提示文字不同） | 有 | 同一个页面按平台表配置；虎牙、抖音、快手的旧说明换成通用说明（见“界面改进”8） |
| 斗鱼：粘贴 passport Cookie 自动填 LTP0/dy_did；passport Cookie 不覆盖已存的登录；保存后提示会话状态和到期时间；“立即续期”及各种失败提示；passport 链接 | 有 | |
| 斗鱼“登录后强制续期”开关（UPGRADES 2-1） | 新增 | 见“已批准的升级” |
| 哔哩哔哩扫码登录：加载、待扫码、已扫码、核验中、成功、过期（刷新二维码）、失败（重试）；3 秒轮询，连续失败退避、3 次后停止，第一次失败提示；确认后核验 Cookie，成功返回 | 有 | 过期和已扫码改成盖在二维码上；见“界面改进”6 |
| 哔哩哔哩网页登录（内置浏览器打开 passport 登录页，跳到主站时读 WebView 的 Cookie 并核验；标题栏“二维码登录”） | 部分 | 应用里没有 WebView 插件（flutter_inappwebview），这个路由改成哔哩哔哩 Cookie 页加说明，标题栏仍有“二维码登录”；见“留给后续” |
| 退出哔哩哔哩时清 WebView 的 Cookie | 没有 | 没有 WebView |
| 云端账号（Firebase）：邮箱/GitHub 登录注册、找回密码、“我的”（预览云端配置、上传、下载覆盖本机、退出）、管理员的用户管理（上传权限、升降管理员、删除用户）、登录后本机没有关注时自动下载云端配置 | 不做 | T07a.1 已去掉 Firebase（T07a.1 问题 10，PLAN 第 5 节的 GMS 问题）；三个路由显示停用说明和替代方式（WebDAV、设备同步、备份与恢复）；见“留给后续” |

v3 其他打开本页的地方：设置的平台设置页（`platform_settings_page.dart:56`）、列表页“需要登录”状态的“前往登录”（`base_page_view.dart:212`）都进 `kSettingsAccount`，路由不变；备份页的云端账号块进 `kMine`/`kSignIn`，现在落到停用说明页。`AppNavigator.toBiliBiliLogin`（T07a.1）在手机上让用户选“短信登录”或“二维码登录”，前者进 `kBiliBiliWebLogin`，现在是 Cookie 页（见“留给后续”）。

## v3 问题及处理

| # | 问题 | 位置 | 处理 |
|---|---|---|---|
| 1 | 只要存了 Cookie 就显示“已登录”（虎牙、YY、快手、Twitch、SOOP），粘贴错的内容也一样 | `account_page.dart:51-150` | 能本地判断的平台给出具体状态（Twitch 的聊天身份、虎牙的 yyuid）；不是 `name=value` 形式的文本不保存 |
| 2 | 点已登录的平台直接弹退出确认，想看或改 Cookie 只能先退出 | `account_page.dart` 各 `onTap` | 点平台进它的页面，退出用行尾按钮 |
| 3 | 斗鱼：清空输入框再保存不会退出——没有新登录时保留旧的，还提示“已填入 LTP0” | `douyu_cookie_controller.dart:105` | 输入框都空时保存 = 退出（先确认）；其余规则照旧 |
| 4 | 斗鱼：粘贴 passport Cookie 保存后，输入框里留着 passport Cookie，看上去像已经换掉了登录 | `douyu_cookie_controller.dart:95-102` + `account_cookie_editor.dart:105` | 保存后输入框显示实际存下的登录 Cookie（没有就清空） |
| 5 | 斗鱼：每次保存都把保存时间设成现在，Cookie 没变也会把推算的 7 天到期时间往后推 | `douyu_cookie_controller.dart:117-118` | 只在 Cookie 变了时更新 |
| 6 | 斗鱼：退出只清 Cookie，LTP0、dy_did 留在本机 | `account_page.dart:163-170` | 退出时一并清除，保存时间归零 |
| 7 | 哔哩哔哩扫码：核验前先把 Cookie 存进设置，核验失败（网络）时 Cookie 留着、页面却显示失败 | `qr_login_controller.dart:286-290` | 先核验：平台说没登录就不存；核验请求失败时照样存（passport 刚发的），提示“获取用户信息失败” |
| 8 | Cookie 只认原样粘贴；带 `Cookie:` 前缀的整行请求头只有斗鱼页能处理 | `cookie_value.dart`、`douyu_cookie_controller.dart:69` | 所有平台去掉前缀 |
| 9 | 换设备或重装后 Cookie 解不开时（v4 新情况，T09b.1），页面看不出来 | — | 列表顶部提示哪些平台要重新填写，平台状态显示“无法在本机读取”，退出可以删掉这条 |

## 界面改进

（2026-10-01 用户授权：界面、布局、操作和视觉反馈可以改进；数据都在 `live_store`，3.x 的 Cookie、LTP0、dy_did、`bilibiliUid`、`douyuCookieSavedAt` 由 T09b.1 原样导入，键名没改。）

1. **分组**：列表分“国内平台”“海外平台”，顶部一段说明（登录有什么用、Cookie 只加密存在本机）。
2. **状态更具体**：哔哩哔哩、抖音显示“已登录：名字”或“登录已失效”或“暂时无法核验”；斗鱼显示“到期前自动续期”或“预计某时到期”；Twitch 显示聊天身份或“缺少 auth-token/login，聊天以游客身份连接”；虎牙显示账号 ID 或“没找到 yyuid”；CC 显示“已保存，暂未用于请求”；颜色区分正常、提醒、失效。
3. **操作**：点平台进它的页面；退出用行尾按钮；标题栏菜单“退出全部账号”（确认后清除所有 Cookie 和斗鱼续期凭据）。
4. **Cookie 页**：顶部状态卡（当前存的是什么状态，哔哩哔哩/抖音可点“重新核验”）；“粘贴”（读剪贴板）和“清空输入”按钮；没改动时保存按钮不可点；保存中按钮转圈；不是 Cookie 的文本在输入框下报错；已存时有“退出登录”按钮；底部说明 Cookie 只存在本机、备份时只有选择包含账号才写入。
5. **先核验再保存**：哔哩哔哩、抖音的 Cookie 保存前先问平台，平台说没登录就不存并提示；暂时问不到就照存并标“暂时无法核验”。
6. **扫码**：已扫码时二维码上盖一个勾，过期时盖“刷新二维码”按钮（v3 把二维码整个换成错误文字）；二维码稍大（160～220）；标题栏加“填写 Cookie”，可以改为手动粘贴。
7. **打开官网**：每个平台的说明横幅里有“打开 xx 网页”，用系统浏览器打开登录页。
8. **说明文字**：虎牙、抖音、快手的旧说明（“登陆后,进入直播间,浏览器F12…点击设置按钮”）换成通用说明（`cookie_tip`，统一原则“说明文字”）；哔哩哔哩加了自己的说明。
9. **斗鱼**：会话说明从只在保存时弹提示，变成页面上常驻的状态卡；“立即续期”和“登录后强制续期”放在“续期”一组，带说明。
10. **云端账号路由**：不再是空白或报错，说明停用原因和替代方式。

## 已批准的升级（docs/specs/UPGRADES.md）

| 编号 | 本页 |
|---|---|
| 2-1 斗鱼“登录后强制续期” | 完成：斗鱼 Cookie 页的开关，读写设置 `douyuForceRenew`（T09b.1，默认关），适配器每次取流时读取（T07a.1 已接上），带说明 |
| C-17 快手：配置 Cookie 后加“直播”搜索 | 入口已有（快手 Cookie 页，存进 `secrets`，`KuaishouSite` 已读取）；余下：有登录 Cookie 后验证快手直播搜索接口，再在平台层加搜索（T02.D2），搜索页的能力表跟着改 |
| C-22 网易 CC：登录后加入弹幕 | 入口完成：账号列表有 CC（`kSettingsAccount` + `cc`），Cookie 存进 `secrets`，状态写明“暂未用于请求”；余下：`CcSite`/CC 弹幕接上 `CookieVault`，用登录 Cookie 验证“登录后加入”（T06a），通过后把平台表里 CC 的 `usedByRequests` 改成 true |

## 留给后续

| 内容 | 去向 |
|---|---|
| 哔哩哔哩网页登录（短信）：需要应用加 `flutter_inappwebview`（Twitch 的 WebView 传输也要，见 T07a.1、T07f.1 记录），之后在 `kBiliBiliWebLogin` 照 v3 做：打开 `passport.bilibili.com/login`（iPhone UA），跳到主站时取 Cookie，核验后保存；退出哔哩哔哩时清 WebView 的 Cookie | 协调者加依赖后本目录补上 |
| `AppNavigator.toBiliBiliLogin` 在手机上给“短信登录”选项，现在进的是 Cookie 页；在 WebView 接上之前建议去掉这个选项或改名“填写 Cookie” | 协调者（`lib/routes/app_navigator.dart`） |
| 应用启动时核验哔哩哔哩 Cookie（v3 `BiliBiliAccountService` 启动 1 秒后核验，失效时提示并退出，记 uid）：现在只在打开账号页时做；可以把 `accountVerifierProvider` + `AccountActions` 的同一套逻辑放到启动后台 | 协调者（`lib/app/bootstrap.dart`） |
| 云端账号（Firebase）没有重做：要不要恢复云端同步、用什么替代（例如自建服务、只用 WebDAV），需要用户决定；3.x 云端上的配置现在只能经旧版下载后导出备份再导入 | 用户决定 |
| CHZZK、AcFun 等适配器不读 Cookie 的平台没有入口；以后哪个平台的适配器接上 `CookieVault`，在 `account_platforms.dart` 加一行即可 | 各平台 |
| 设置页里通往本页的入口（v3 平台设置页的“三方认证”）、列表页“需要登录”状态的按钮 | M13 设置页、各列表页 |

## 测试

`apps/pure_live/test/pages/account/account_page_test.dart`，11 个（加速流程，只测主要路径；内存库 `LiveStore.memory()`，核验、扫码、续期、时钟用页面 provider 替换）：

| 用例 | 内容 |
|---|---|
| 列表状态 | 哔哩哔哩核验后显示名字并记 uid、抖音失效、Twitch 聊天身份、虎牙 yyuid、CC 暂未使用、SOOP 已保存、未设置；退出按钮只给已登录的 |
| 哔哩哔哩失效 | 打开列表时 `-101`（NeedsLogin）：提示并退出（v3） |
| 退出 | 取消不删；确认后删除并提示；“退出全部账号”清掉所有 Cookie 和斗鱼 LTP0 |
| Cookie 页 | 非 Cookie 文本报错不存；带 `Cookie:` 前缀的整行存成规范形式、状态显示 yyuid；改了未保存返回时确认舍弃 |
| 粘贴按钮 | 读剪贴板；剪贴板空时不改 |
| 先核验再保存 | 网页登录路由的说明；哔哩哔哩失效 Cookie 不存、有效的存下并记 uid；抖音暂时无法核验照存并标出；清空保存 = 确认后退出 |
| CC 入口 | 列表点 CC 进 `kSettingsAccount` + `cc` 的 Cookie 页并保存 |
| 斗鱼 | passport Cookie 自动填 LTP0/dy_did、不覆盖登录、保存时间不变；立即续期调用续期并存下新 Cookie 和时间；强制续期开关写设置；退出清除 Cookie、LTP0 和保存时间 |
| 扫码 | 待扫码、已扫码、过期、刷新出新二维码、确认后核验、存 Cookie 和 uid、提示、返回列表显示已登录 |
| 斗鱼说明（单元） | 游客、过期、过期可续期；粘贴清理和 Cookie 形式判断 |
| 云端账号 | 停用说明、点 WebDAV 进对应路由 |
