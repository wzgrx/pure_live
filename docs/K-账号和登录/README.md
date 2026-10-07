# K 账号和登录

各平台账号和登录方式、登录状态、第三方认证。界面在 A12。

管用户在各直播平台上的登录：怎么登录（哔哩哔哩扫码和网页登录、各平台粘贴 Cookie、斗鱼续期）、登录了以后怎么知道还有效（启动核验、账号页核验、直播间发现登录失效）、登录凭据怎么交给平台适配器和弹幕连接，以及 3.x 的云端账号（Firebase）停用后的去向。排在设置和数据（J）之后：登录是少数用户的增强功能（更高画质、看到真实昵称、关注同步），但 Cookie 是最敏感的数据，存储和加密的规则由 J02 定、这里遵守。

## 范围

- 管什么：
  - **登录方式**（K01）：`apps/pure_live/lib/features/account/` 的逻辑部分——平台表（哪些平台有账号入口、怎么核验，`account_platforms.dart`）、状态计算（`account_state.dart`）、写入（`account_services.dart` 的 `AccountActions`）、哔哩哔哩扫码流程（`bilibili_qr_login.dart` 的 `BilibiliQrLogin`）、哔哩哔哩网页登录取 Cookie（`bilibili_web_login.dart`）、斗鱼 Cookie 和 LTP0 续期（`douyu_cookie_view.dart` 的逻辑、`DouyuSite.renewSession`）；粘贴 Cookie 的清理和判断。
  - **登录状态**（K02）：启动 1 秒后核验哔哩哔哩登录（`app/startup.dart:116`）、账号页打开时核验、直播间里根据打码昵称判断“登录可能失效”（`room_controller.dart:270-276`）、登录变化后重连弹幕拿新凭据（`room_controller.dart:281`）；Cookie 怎么交给平台和弹幕（`StoreCookieVault`，`app/platforms.dart:52`）；Cookie 和密码加密存储在真机上的验证（K02.1）。
  - **第三方认证**（K03）：3.x 的 Firebase 云端账号停用后，三个旧路由落到说明页（`features/auth/auth_page.dart`）。
- 不管什么：
  - 账号总览、Cookie 页、扫码页、网页登录页、云账号说明页长什么样 → [A12](../A-界面设计/A12-账号和数据界面/README.md)（A12.1、A12.2、A12.3）。
  - Cookie 存在哪、怎么加密、解不开怎么办 → [J02](../J-设置和数据/J02-存储和加密/README.md)（`SecretStore`、`SecretCipher`）；备份带不带账号 → J03；设备同步带不带账号 → J05。
  - 各平台怎么用 Cookie 取流、搜索、连弹幕（`packages/live_core` 的各 `*Site`、`packages/live_danmaku`）→ E、D；平台层发现 Cookie 被拒（Twitch `cookieRefusals`）→ E06.1，提示接到界面 → E06.2。
  - 哔哩哔哩打码昵称和“登录后看真实昵称”的引导 → D02.1、A08（D-013）。
  - 多账号（V01.2 提议）不在现有范围。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [K01 账号和登录方式](K01-账号和登录方式/README.md) | 平台表、扫码、网页登录、粘贴 Cookie、斗鱼续期、退出 | 界面 A12.1、A12.2；存储 J02；扫码用 E01.1 的 `BilibiliSite.qrCode/qrPoll` |
| [K02 登录状态](K02-登录状态/README.md) | 核验和失效、登录变化后的重连、Cookie 交给适配器和弹幕、加密存储的真机验证 | 存储和加密 J02；弹幕的打码昵称 D02、A08；Twitch Cookie 提示 E06.2 |
| [K03 第三方认证](K03-第三方认证/README.md) | 3.x 云端账号（Firebase）的停用和替代 | 说明页的样子 A12.3；替代方式 J03、J04、J05 |

## 现状（2026-10-07）

- **做到哪**：登记的 2 个任务里 K01.1（账号与登录，`e5ae55fbf`）“完成”，K02.1（Cookie 和密码加密存储在真机上验证）未开始（第二档）；K03 没有任务（云端账号不做，F-ACC-08）。之后的相关任务：O03.1 接上 WebView，哔哩哔哩网页（短信）登录做出来了（`bilibili_web_login.dart`）；I01.2 把哔哩哔哩启动核验放进 `app/startup.dart`；A12.1～A12.3 按确认的设计重做了页面。
- **真机**：几乎没有 K90 结果。清点第 12 节：F-ACC-01、02、04、05、06 “完成”（按单元测试和记录），F-ACC-03（网页登录）、F-ACC-07（登录后取流的高画质）“没验证”→ S02.6；F-AND-05（Cookie 加密存储）→ K02.1。S02.3 记录写明“账号页没在真机上看”。
- **和 3.x 比**：
  - 一样：账号列表的平台（哔哩哔哩、斗鱼、虎牙、抖音、快手、YY、Twitch、SOOP）、扫码流程和轮询、斗鱼 LTP0 续期、各 Cookie 页、启动核验哔哩哔哩、退出确认。
  - 多了：CC 的 Cookie 入口（UPGRADES C-22，存下但还没用于请求）；状态更具体（哔哩哔哩、抖音显示名字或“登录已失效”，Twitch 显示聊天身份，虎牙显示账号 ID）；保存前先核验（平台说没登录就不存）；“退出全部账号”；粘贴时去掉 `Cookie:` 前缀；斗鱼“登录后强制续期”开关（UPGRADES 2-1）；Cookie 加密存储。
  - 少了：Firebase 云端账号（不做）；哔哩哔哩退出时不清 WebView 里的 Cookie（改成打开网页登录时清，见 K01 已知问题）。
- **主要的代码**：`apps/pure_live/lib/features/account/`（11 个文件约 2600 行，界面和逻辑各半）、`features/auth/auth_page.dart`（119 行）、`app/startup.dart`（启动核验）、`app/platforms.dart`（Cookie 交给适配器）；平台一侧在 `packages/live_core/lib/src/sites/` 的哔哩哔哩、抖音、斗鱼、虎牙、Twitch。

## 当前重点和顺序

1. **第二档：K02.1**（小）：K90 上验证 Cookie 和 WebDAV 密码确实是加密存的、杀掉重开还在、测试包重装后解不开时账号页的提示；顺带看保存时 Keystore 出错有没有提示（J02 已知问题）。最好和 [S02.6](../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段（网页登录、登录后画质）同一次上机。
2. 之后根据 K02.1 和 S02.6 的结果决定：保存失败的提示、网页登录的问题。
3. 第三档、待维护者决定：C-17（快手登录后的直播搜索）、C-22（CC 登录后加入弹幕）都要用户提供登录 Cookie 才能验证（V03.3“需要维护者决定”）；V01.2（哔哩哔哩多账号）是提议，先出方案。

## 风险和注意

- **Cookie 是最敏感的数据**：仓库里（代码、测试、样本、文档、截图）不能出现真实 Cookie、账号、uid；测试用合成值（`SESSDATA=fake` 这类）；日志里只记结构不记值（`LoggingHttp` 的失败摘要不含 Cookie）；截图遮住 Cookie 输入框。
- **平台风控**：核验和续期会请求平台的账号接口；不要在测试里访问真实平台（D-017）；真机上频繁核验可能触发风控（哔哩哔哩 -352、斗鱼验证码），验证时控制次数。
- **平台改登录方式**：哔哩哔哩扫码接口、网页登录跳转的地址、斗鱼的 passport Cookie 字段都可能变；改动以平台适配器为准（E01.1、E01.2），这里只用它们的接口。
- **规则**：3.x 的键名不变（`bilibiliUid`、`douyuCookieSavedAt`、`douyuForceRenew`，Cookie 从 3.x 的 `<平台>Cookie` 迁到密钥库，D-018）；打码昵称不还原（D-013）；真机只用测试包（D-019），登录用维护者自己的测试账号。

## 相关

- 规范：[specs/UPGRADES.md](../specs/UPGRADES.md) 2-1、C-17、C-22；清点 [inventory/FEATURES.md](../inventory/FEATURES.md) 第 12 节（F-ACC-01～08）、第 2 节 F-AND-05。
- 决定：D-013（打码昵称）、D-017、D-018、D-019。
- 其他组：A12（界面）、J02（加密存储）、E01、E03（平台的账号接口）、D02（打码昵称）、E06.2（Twitch Cookie 提示）、O03.1（WebView）、S02.6（网页登录和登录后画质的真机）、V01.2（多账号提议）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`██████████░░░░░░░░░░` 50%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [K01 账号和登录方式](K01-账号和登录方式/README.md) | 账号、网页登录、扫码、Cookie。 | `████████████████████` 100% | 1 / 1 |
| [K02 登录状态](K02-登录状态/README.md) | 失效检测、重新登录、弹幕用的登录凭据、加密存储。 | `░░░░░░░░░░░░░░░░░░░░` 0% | 0 / 2 |
| [K03 第三方认证](K03-第三方认证/README.md) | 第三方认证和云账号。 | — | 0 / 0 |

## 还没完成的（2）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [K02.1](K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md) Cookie 和密码加密存储在真机上验证 | 未开始 | 第二档 | — |
| [K02.2](K02-登录状态/K02.2-加密存储失败时提示/README.md) 加密存储失败时提示；扫码登录出错不再卡在“核验中”；退出哔哩哔哩时清网页 Cookie | 未开始 | 第二档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
