# K01.1 账号与登录

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（模块重构：账号页和云端账号路由）
- 来源：模块重构计划 M13.8（3.x 的 `lib/modules/account/`、`lib/modules/auth/` 按 4.x 的结构重写）；用户 2026-10-01 授权界面、布局、操作和视觉反馈可以改进，数据都在 `live_store`、3.x 的键名不变
- 旧编号：M13.8、T10a.1
- 相关：依赖 E01.1（哔哩哔哩扫码和账号接口）、E01.2（斗鱼会话和续期）、E01.4（抖音账号）、E01.3、E03.2（虎牙 yyuid、Twitch 聊天身份）、J02.1（`SecretStore`）；之后的 O03.1（WebView → 网页登录）、I01.2（启动核验）、A12.1～A12.3（按确认的设计重做页面）、K02.1（真机验证加密存储）；决定 D-018；记录 [record.md](record.md)

## 目标

3.x 的账号列表、8 个 Cookie 页、哔哩哔哩扫码和网页登录、云端账号的三个路由在 4.x 里都有去处；登录凭据全部经 `live_store` 加密保存，改了立即被平台适配器用上；状态比 3.x 说得更准（不再“存了 Cookie 就算已登录”）；修掉 3.x 账号页的 9 个问题。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| 状态 | 存了 Cookie 就“已登录”，粘贴错也一样（`modules/account/account_page.dart:51-150`） | 能本地判断的给具体状态（`features/account/account_state.dart:115`）；哔哩哔哩、抖音问平台 | 完成 |
| 点平台 | 已登录的直接弹退出，想看 Cookie 要先退出 | 点平台进它的页面，退出用行尾按钮（`account_list_view.dart:97`、`:116`） | 完成 |
| 保存 | 原样存；哔哩哔哩扫码先存再核验，网络失败时留着 Cookie 却显示失败（`qr_login_controller.dart:286-290`） | 先核验，平台说没登录不存（`platform_cookie_view.dart:94`、`bilibili_qr_login.dart` 的 `_complete`） | 完成 |
| 斗鱼 | 清空保存不退出（`douyu_cookie_controller.dart:105`）；每次保存重设保存时间（`:117-118`）；退出不清 LTP0、DID（`account_page.dart:163-170`） | 清空保存 = 退出；只在 Cookie 变了时更新时间；退出一并清（`account_services.dart:116`、`:138`） | 完成 |
| 网页登录 | WebView 打开 passport，跳到主站时读 Cookie（`web_login_controller.dart:176`） | 当时没有 WebView，路由显示 Cookie 页加说明；O03.1 之后 `bilibili_web_login.dart` 照 3.x 做出来 | 完成；真机没看 |
| 云端账号 | Firebase：登录、上传下载配置、管理员管理用户（`lib/modules/auth/`，13 个文件） | 三个路由显示停用说明，引到 WebDAV、设备同步、备份和平台账号（`features/auth/auth_page.dart`） | 不做（F-ACC-08） |
| CC | 没有入口 | 列表里有 CC，存下但写明“暂未用于请求” | UPGRADES C-22 的入口完成 |

## 结果

- 提交：`e5ae55fbf`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)“做法”“与 v3 的功能对照”）：
  - c1 平台表和路由分发：一个通用 Cookie 页按平台表配置，代替 3.x 每个平台一个页面；斗鱼单独一页；`kDouyuCookie` 照 3.x 仍是抖音页的旧别名。
  - c2 状态：哔哩哔哩、抖音“已登录：名字 / 登录已失效 / 暂时无法核验”；斗鱼按会话（未设置、有效、过期可续期、需要重新粘贴）；Twitch 显示聊天身份；虎牙显示 yyuid；CC 已保存暂未使用；解不开的 Cookie 在列表顶部提示。
  - c3 写入：`AccountActions` 全部经 `LiveStore`；`cookieChanges` 让适配器立即用新 Cookie。
  - c4 扫码：`BilibiliQrLogin`（对应 3.x 的 `BiliBiliQRLoginController`）：3 秒轮询、连续失败退避、3 次后停止、已扫码和过期盖在二维码上、确认后先核验再存。
  - c5 斗鱼：passport Cookie 自动填 LTP0 和 dy_did、不覆盖已存的登录、立即续期、“登录后强制续期”开关（UPGRADES 2-1，`douyuForceRenew`）。
  - c6 云端账号三个路由的停用说明。
  - c7 修了 9 个 3.x 问题（record“v3 问题及处理”）。
  - 翻译 zh、en 各加 49 个键（41 个 `account_*`、8 个 `auth_*`）。
- 偏差和后来做的：网页登录当时没有 WebView → O03.1 做出来；启动时核验哔哩哔哩当时只在打开账号页时做 → I01.2 放进 `app/startup.dart:116`；`AppNavigator.toBiliBiliLogin` 的“短信登录”选项现在进的是真的网页登录（有 WebView 时）。
- 测试：当时 11 个（`account_page_test.dart`）；A12 重做后现在是 `test/features/account/account_page_test.dart` 22 个。

## 验证

- 自动测试：`cd apps/pure_live && flutter test test/features/account/`。
- 真机：**没有 K90 结果**（S02.3 记录写明“账号页没在真机上看”）。扫码登录后杀掉重开仍登录（Keystore 解密）→ [K02.1](../../K02-登录状态/K02.1-Cookie和密码加密存储验证/README.md)；网页登录、登录后原画 → [S02.6](../../../S-质量和验证/S02-真机验证/S02.6-K90补验/README.md) 第 3 阶段。登记表按当时“构建通过 + 单元测试”记成“完成”。

## 留下的问题

- 真机：见上。
- 退出哔哩哔哩时不清 WebView 里的 Cookie（3.x 清）→ K01 子分类页“已知问题”，建议小改动。
- C-17（快手登录后搜索）、C-22（CC 登录后加入弹幕）→ 未排，等维护者决定是否提供登录 Cookie。
- 云端账号要不要用别的方式恢复（自建服务、只用 WebDAV）→ 不做（用户已决定，A12.3）；有新想法进 V01。
- CHZZK、AcFun 等不读 Cookie 的平台没有入口 → 适配器接上 `CookieVault` 时在平台表加一行。
