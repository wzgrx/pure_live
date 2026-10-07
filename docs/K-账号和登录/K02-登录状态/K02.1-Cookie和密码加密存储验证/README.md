# K02.1 Cookie 和密码加密存储在真机上验证

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证
- 来源：J02.1 记录（`SecretCipher` 的平台实现由 I01.1 接上，真机没看）；功能清点 F-AND-05（Cookie 加密存储，[inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 2 节）；[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 4 节第 6 条“重开后仍是登录状态（Keystore 解密正常）”
- 旧编号：T10b.1
- 相关：J02（`SecretStore`、`platform/secret_cipher.dart`）、K01.1（账号页）、A12.1（“无法在本机读取”的提示）、J06.1（迁移时 Cookie 也走同一个加密）、S02.6 第 3 阶段（网页登录、登录后画质，最好同一次上机）；决定 D-019；任务书 [brief.md](brief.md)

## 目标

在 K90（HyperOS，Android 17）上用测试包确认：

1. Cookie、斗鱼续期凭据、WebDAV 密码在库里是密文，库文件、日志里找不到明文；
2. 杀掉应用再打开，账号仍是登录状态（Keystore 解密正常），弹幕按登录显示完整昵称；
3. 换了安装（卸载重装后带回旧库，模拟换手机或重装）时，解不开的 Cookie 当作未登录，账号页顶部和对应行有提示，退出能清掉，重新登录正常；
4. 记录 Keystore 有没有出错（为 J02 的“保存失败没有提示”判断优先级）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在 | 要做到 |
|---|---|---|---|
| Cookie 存储 | 明文存在 Hive box 里（`lib/common/services/settings/cookie_settings_controller.dart:10-35`） | `secrets` 表，AES-256-GCM，密钥在 Android Keystore（别名 `pure_live.secrets.v1`，`AppChannelsPlugin.kt:147-187`；Dart `platform/secret_cipher.dart:20`） | 真机上确认是密文、能解开 |
| WebDAV 密码 | 明文，当前配置还另存一份（`web_dav_controller.dart:17-26`、`:62-65`） | 密钥库 `webdav/<名字>`，`webdav_profiles` 表没有密码列（`packages/live_store/lib/src/webdav.dart:89-97`） | 同上 |
| 换设备或重装 | 明文，跟着数据走 | 解不开的进 `unreadable`（`secrets.dart:55-70`），账号页提示“{names}的 Cookie 无法在本机读取（换了设备或重装后会这样），请重新填写。”，行状态“无法在本机读取已保存的 Cookie，请重新填写” | 真机上看到这两句，退出能清掉 |
| 日志 | 3.x 的日志可能带请求头 | 应用日志按名字遮掉 Cookie、`Authorization`、配对码等（`app/app_log.dart:103-120`） | 打开本地日志后日志文件里没有 Cookie 的值 |

## 方案

- c1 准备：K90 上装 debug 测试包，清数据；用维护者自己的测试账号扫码登录哔哩哔哩；粘贴假的 YY、斗鱼（含 LTP0、dy_did）Cookie；加一个假的 WebDAV 服务器（带密码）；打开“本地日志”。
- c2 查密文：用 `run-as` 读出 `files/pure_live.db`（和 `-wal`、`-journal`），看 `secrets` 表是二进制、`settings` 和 `webdav_profiles` 里没有 Cookie 和密码，全文件搜明文找不到；日志目录同样。
- c3 杀掉重开：账号页仍是“已登录：名字”，进一个哔哩哔哩直播间看到完整昵称。
- c4 模拟换安装：备份库文件 → 卸载测试包（Keystore 里的密钥随之删除）→ 重新安装 → 把库放回去 → 打开：看提示、退出、重新登录。
- c5 结论写进 `record.md`；发现问题开任务（保存失败没提示的问题已知，在 J02 子分类页）。

## 验证

- 本任务就是验证：照任务书的真机步骤做，结果写进本文件夹新建的 `verify.md`（照 `templates/verify.md`，步骤从任务书抄），截图放 `verify/`，Cookie 和账号名要遮住。
- 自动测试：已有（`packages/live_store/test/stores_test.dart` 的“Cookie 加密和换设备读不出”、`account_page_test.dart:317` 的提示），不新增。

## 留下的问题

- 保存时 Keystore 出错没有提示、扫码会停在“核验中”（J02、K01 的已知问题）：本任务记录 K90 上有没有出错，再决定开不开任务。
- 退出哔哩哔哩不清 WebView 的 Cookie（K01 的已知问题）：c4 之后顺带看一眼网页搜索打开哔哩哔哩是不是还登录着。
