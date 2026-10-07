# K02 登录状态

失效检测、重新登录、弹幕用的登录凭据、加密存储。

登录以后的事：怎么知道登录还有效（启动时、打开账号页时、看直播时）、失效了怎么告诉用户和怎么退出、Cookie 怎么交给平台适配器和弹幕连接、登录变化后打开着的直播间怎么跟上，以及登录凭据加密存储在真机上的验证（K02.1）。

## 范围

- 包括：
  - **核验和失效**：启动 1 秒后核验哔哩哔哩（`apps/pure_live/lib/app/startup.dart:85-90`、`verifyBilibiliLogin` `:116-131`）；账号列表打开时核验（`features/account/account_list_view.dart:62` 的 `_check`）；直播间里按打码昵称判断“登录可能失效”（`features/live_play/logic/room_controller.dart` 的 `nameHint` `:265-276`，阈值 `maskedChatsForExpiredLogin = 3` `:259`）。
  - **凭据交给使用方**：`StoreCookieVault`（`app/platforms.dart:52`，`cookieFor` + `cookieChanges`）→ 各平台适配器（`buildSiteRegistry` `app/platforms.dart:137-160`：哔哩哔哩带 `storedUid`、斗鱼带 `StoreDouyuLogin` 和强制续期、虎牙、抖音、快手、SOOP、YY、Twitch）；哔哩哔哩弹幕的 uid（`BilibiliApi.danmakuUid`，`bilibili_site.dart:511`、`:531`）；斗鱼取流前按需续期（`DouyuSite._renew`，`douyu_site.dart:472-491`）。
  - **登录变化后的直播间**：`room_controller.dart:281` 的 `_onLoginChanged`：哔哩哔哩的登录变了（登录、退出、续期），重新取房间详情拿新的弹幕凭据、重连弹幕，名字按新的登录显示。
  - **加密存储的真机验证**（K02.1）：Keystore 加密、杀掉重开、重装后解不开的提示。
- 不包括（归哪里）：
  - 登录方式和写入 → K01；密钥库和加密的实现 → J02（`SecretStore`、`SecretCipher`）。
  - 打码昵称的过滤、“登录看真实昵称”的引导条样子 → D02.1、A08（D-013）。
  - Twitch Cookie 被拒的平台层（`TwitchSite.cookieRefusals`，`twitch_site.dart:196`）→ E06.1 做完，提示接到直播间 → E06.2（暂停中）。
  - 各平台登录后能多拿什么（画质、受限房间）→ E 组；真机看登录后画质 → S02.6。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 启动 1 秒后，存着的哔哩哔哩 Cookie 失效（平台回 -101）时提示“登录已失效”并自动退出（同 3.x）；核验请求失败（没网等）时提示“获取用户信息失败”，Cookie 保留。
  - 账号列表每次打开都核验哔哩哔哩、抖音，状态写“已登录：名字 / 登录已失效 / 暂时无法核验”；哔哩哔哩失效同样退出并提示。
  - 看哔哩哔哩直播时：没登录，聊天列表上方提示“登录后可看到完整昵称”（游客）；存着登录但这条连接收到 3 条以上打码昵称、一个完整名字都没有，提示登录可能失效；在提示里登录（或退出）后，弹幕自动重连，名字按新的登录显示。
  - 换手机或重装后账号列表顶部提示哪些平台“无法在本机读取”，要重新填（Keystore 的密钥跟着安装走）。
- 内部怎么工作：

```text
SecretStore（J02）── cookieFor / cookieChanges ──▶ StoreCookieVault（platforms.dart:52）
   ├─▶ 平台适配器：每次请求读 cookieFor(平台)；哔哩哔哩的会话按 Cookie 重建，uid = 核验过的 uid 或设置 bilibiliUid
   ├─▶ 斗鱼：DouyuSite._renew（取流前，按保存时间判断要不要续期；强制续期开关）→ StoreDouyuLogin.saveRenewed 写回 Cookie 和时间
   └─▶ 打开着的直播间：cookieChanges.listen → _onLoginChanged（room_controller.dart:281）→ getRoomDetail 拿新 danmakuData → _syncDanmaku(force)
启动：AppStartup.start（startup.dart:70）→ 1 秒后 LegacyReloginNotice.showOnce + verifyBilibiliLogin
   verify → 记 uid；NeedsLogin（且 Cookie 期间没变）→ 提示并 signOut；其他错误 → 提示核验失败
直播间：每条聊天按昵称是否打码计数（_maskedChats、_namedChats）→ nameHint（:265）
```

- 完成度：核验和失效、弹幕重连在 K01.1、I01.2、D02.1（B06 c1）里做完，有单元测试；**加密存储从没在真机上验证**（F-AND-05 → K02.1）；登录后的画质没在真机看（F-ACC-07 → S02.6）。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/app/startup.dart` | `bilibiliCheckDelay = 1 秒`（`:25`）；`LegacyReloginNotice`（`:30`，迁移时 Keystore 失败的一次性提示）；`AppStartup.start` 里的计时（`:85-90`）；`verifyBilibiliLogin`（`:116`） |
| `apps/pure_live/lib/app/platforms.dart` | `StoreCookieVault`（`:52`）、`StoreDouyuLogin`（`:68`：`longTermKey`、`deviceId`、`savedAt`、`saveRenewed` `:88`）、`buildSiteRegistry`（`:137` 起，哪些平台拿到 Cookie） |
| `packages/live_net/lib/src/cookies.dart` | `CookieVault` 接口（`:6`：`cookieFor`、`changes`）、`MemoryCookieVault`（测试） |
| `apps/pure_live/lib/features/account/account_list_view.dart` | `_check`（`:62`，打开列表时核验；失效时退出并提示） |
| `apps/pure_live/lib/features/live_play/logic/room_controller.dart` | `ChatNameHint`（`:67`）、`maskedChatsForExpiredLogin`（`:259`）、`nameHint`（`:265`）、`_signedIn`（`:276`）、`_onLoginChanged`（`:281`）、订阅 `cookieChanges`（`:309`） |
| `packages/live_core/lib/src/sites/bilibili/bilibili_site.dart` | `_login`（`:78`，读 Cookie 并清理）、弹幕 uid（`:511`、`:531`、`:540`） |
| `packages/live_core/lib/src/sites/douyu/douyu_site.dart` | 构造参数 `forceRenewal`（`:76`）、`_renew`（`:472`）、`renewSession`（`:499`） |
| `packages/live_core/lib/src/sites/twitch/twitch_site.dart` | `cookieRefusals`（`:196`，E06.1）、`_chat`（`:209`，聊天身份） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/account/account_page_test.dart` | 哔哩哔哩失效时退出并提示（`:310`）；解不开的 Cookie 的提示和删除（`:317`） |
| `apps/pure_live/test/features/live_play/live_play_controller_test.dart` | 游客的提示（`:253`）；已登录时 3 条打码、没有完整名字提示登录失效（`:270`）；其他平台、其他登录不提示不重连（`:296`） |
| `packages/live_store/test/stores_test.dart` | Cookie 加密、换设备读不出 |

## 3.x 基线

- `git show v3.2.11:lib/common/services/settings/bilibili_account_service.dart`：启动后 1 秒（`initialLoadDelay` `:18`、`:52`）`loadUserInfo`，-101 时 `logout`（`:107`、`:152-173`），退出时清掉 WebView 的全部 Cookie（`:200`）；记下 uid 给弹幕用。
- Cookie 明文存在设置 box 里（`cookie_settings_controller.dart:10-35`）；没有加密，所以也没有“解不开”的情况。
- 斗鱼续期：`lib/modules/account/douyu/douyu_cookie_controller.dart` 和平台层；3.x 没有“登录后强制续期”。
- 必须保留：启动核验的时机和失效时的退出；`bilibiliUid` 的含义（弹幕 uid 的后备）。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| Keystore 加密、杀掉重开仍登录、重装后解不开的提示都没在真机上看过 | `platform/secret_cipher.dart:20`；`account_state.dart` 的 `unreadable` 状态 | 不知道 K90（HyperOS）上 Keystore 是否正常；也没人见过“无法在本机读取”的样子 | [K02.1](K02.1-Cookie和密码加密存储验证/README.md) |
| 保存时 Keystore 出错没有提示 | J02 已知问题 | 少见机型 | K02.1 先确认 K90 上不出错；之后小任务 |
| 只核验哔哩哔哩和抖音；其他平台的 Cookie 失效没有任何提示，直到用户发现画质变低或搜不到 | `account_platforms.dart` 的 `check` | 斗鱼按保存时间推算到期；虎牙、快手、YY、SOOP 无从判断 | 照 3.x；Twitch 的被拒提示 → E06.2 |
| 直播间“登录可能失效”的判断只看打码昵称个数（3 条打码且没有完整名字） | `room_controller.dart:259-276` | 弹幕很少的房间可能一直不提示；平台改打码规则会误报 | 照 D02.1 的设计；有反馈再调阈值 |

## 相关决定和规范

- D-013（打码昵称不还原，做登录引导）、D-018、D-019；J02 的加密规则；不把真实 Cookie 写进仓库。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account/ test/features/live_play/`；`cd packages/live_store && dart test test/stores_test.dart`。
- 真机：[CHECKLIST](../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条（扫码登录，杀掉重开仍登录）→ K02.1；第 8 条（登录后原画）→ S02.6。

## 路线

1. **K02.1**（第二档，小）：真机验证加密存储和三种状态（正常、杀掉重开、重装后解不开），顺带看保存失败。
2. E06.2 的“Twitch”阶段：Cookie 被拒时直播间提示一次。
3. 以后：其他平台的失效检测（例如虎牙、快手请求时回登录错误时提示）要先有平台层的错误分类，进 V01 提议或 E 组任务。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [K 账号和登录](../README.md)。

- 代码：`features/account/`、`packages/live_danmaku`
- 进度：`░░░░░░░░░░░░░░░░░░░░` 0%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| K02.1 | Cookie 和密码加密存储在真机上验证 | 验证 | 未开始 | — | — | [设计或说明](K02.1-Cookie和密码加密存储验证/README.md) |

## 还没完成的

- **K02.1 Cookie 和密码加密存储在真机上验证**（未开始，第二档，规模 小）

<!-- docs:生成结束 -->
