# J04 WebDAV

WebDAV 备份。

把 J03 的备份文件放到用户自己的 WebDAV 服务器（坚果云、Nextcloud、Alist、NAS）上：列目录、上传、下载恢复、删除，以及认证（Basic、Digest）和服务器配置的存储。WebDAV 页长什么样归 A12.5。

## 范围

- 包括：
  - 客户端 `apps/pure_live/lib/features/web_dav/web_dav_client.dart`：`PROPFIND`（列目录、测试连接）、`GET`、`PUT`、`DELETE`，多状态回答的解析，错误分类（账号或密码、找不到、连不上、服务器状态码）。
  - 认证 `web_dav_auth.dart`：读 `WWW-Authenticate`、Digest（RFC 7616/2617 的 MD5、MD5-sess，`qop=auth` 或不带）、自写的 MD5。
  - 服务器配置的存储：`packages/live_store/lib/src/webdav.dart`（`WebDavConfig`、`WebDavStore`；密码在密钥库 `webdav/<名字>`，当前服务器按名字记在 `meta` 的 `webdav.current`），以及页面里用到的客户端选择（`web_dav_page.dart:97` 按选中的服务器建一个，`:181-186` 测试连接每次新建）。
- 不包括（归哪里）：
  - WebDAV 页、配置对话框、帮助页的样子和交互 → [A12.5](../../A-界面设计/A12-账号和数据界面/A12.5-WebDAV/README.md)。
  - 上传和恢复的内容（备份格式、恢复预览、恢复锁）→ J03；页面上的恢复走 J03 的 `restoreWithPreview`。
  - 网络通道和代理规则（WebDAV 走 `LiveHttp`，平台键 `webdav`）→ Q01、Q02；密钥库本身 → J02。

## 现状：做到哪、怎么工作的

- 用户看得到的（设置 → 数据 → 备份与恢复 → WebDAV）：添加服务器时填名称、地址、账号、密码，可以“测试连接”；选中一个服务器后浏览目录、上传完整备份或仅关注、点文件恢复（先预览）、删除（先确认）；服务器只认 Digest 的也能连（J04.1）；应用代理打开时 WebDAV 也走代理。
- 内部怎么工作：

```text
WebDavClient(LiveHttp, WebDavConfig)（web_dav_client.dart:76）
  urlOf(path)：地址里的文件夹 + 路径，文件夹以 / 结尾
  _send(method, url)（:180）→ _exchange（:157）：
     第一次：不带账号（_Scheme.none）
     回 401 → _learn（:140）：parseAuthChallenges（web_dav_auth.dart:18）读所有 WWW-Authenticate；
        有能用的 Digest 就用 Digest（两种都给时选 Digest），否则有 Basic 用 Basic；
        401 没带 WWW-Authenticate → 用 Basic 再试一次；只给 Bearer 之类不认识的 → 不发密码
     → 重发一次（每个请求最多一次）；Digest 回 401 且 stale=true 或用的是旧 nonce → 换新 nonce 重发
     之后同一个客户端直接带上（Digest 的 nc 递增，8 位十六进制；uri 用请求行里的路径和查询）
  错误：401/403 → WebDavProblem.auth；404/409 → notFound；连不上 → network；其他 → 状态码
  list（:204）→ parseMultistatus（:240，跳过目录自身和别处的路径，不依赖命名空间前缀）
```

- 完成度：J03.1（`1b730f77e`）做了客户端和页面（只有 Basic）；J04.1（2026-10-02，`c168fdb99`）补上 Digest 和“先问服务器要什么”；A12.5（`965d41956`）按确认的设计重做了页面。**坚果云真机没试过**（F-BAK-04 记“完成”是按单元测试，真机在 S02.4 第 2 条）；真实的 Digest 服务器手边没有，只有单元测试和本机回环上的假服务器。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/web_dav/web_dav_client.dart`（310 行） | `WebDavEntry`（`:9`）、`WebDavFailure`（`:45`）、`WebDavClient`（`:76`：`urlOf`、`_target`（`:104`，Digest 签的请求目标）、签名、`_learn`（`:140`）、`_exchange`（`:157`）、`_send`（`:180`）、`list`（`:204`）、`check`（`:216`）、`write`（`:229`）、`remove`（`:233`））、`parseMultistatus`（`:240`） |
| `apps/pure_live/lib/features/web_dav/web_dav_auth.dart`（237 行） | `AuthChallenge`（`:5`）、`parseAuthChallenges`（`:18`，多行、一行多个、引号里的逗号和转义）、`DigestChallenge`（`:69`）、`digestAuthorization`（`:127`）、`randomCnonce`（`:161`）、`md5Hex`（`:179`，不为它加 `crypto` 依赖） |
| `packages/live_store/lib/src/webdav.dart`（180 行） | `WebDavConfig`（地址规则：http/https、有主机、没有用户信息、没有查询和片段）、`WebDavStore`（`all`、`current`、`add`、`update`、`remove`、`select`、`replaceAll(withPasswords:)` `:149`；`webdav.current` `:85`） |
| `apps/pure_live/lib/features/web_dav/web_dav_page.dart`（738 行）、`web_dav_config_dialog.dart`（209 行）、`web_dav_help.dart`（241 行） | 界面为主（A12.5）；逻辑相关的只有 `webDavHttpProvider`（`web_dav_page.dart:23`，测试替换）和建客户端的两处（`:97`、`:186`） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/web_dav/web_dav_auth_test.dart`（5） | MD5（RFC 1321）、Digest（RFC 7616 3.9.1）、`WWW-Authenticate` 各种写法；只认 Digest 的服务器全流程（nc 递增、uri 含 `/dav/`）；MD5-sess、`stale`、不带 qop、密码错只发两次；Basic、两种都给、不带 `WWW-Authenticate`、只给 Bearer；本机回环上的真实 HTTP 栈 |
| `apps/pure_live/test/features/web_dav/web_dav_page_test.dart`（10） | 多状态回答解析；页面：添加时测试连接、列文件、上传、恢复、子目录、删除、面包屑（假服务器只认 Basic、401 不带 `WWW-Authenticate`，走“Basic 再试一次”） |
| `packages/live_store/test/stores_test.dart` | WebDAV 密码进密钥库、地址规则 |

## 3.x 基线

- `git show v3.2.11:lib/modules/web_dav/`：`web_dav_page.dart`（779 行）、`web_dav_controller.dart`（432 行）、`webdav_service.dart`（31 行，`:17` 用 webdav_client 自带的 Dio，不走应用代理）、`webdav_config.dart`、`web_dav_help.dart`（坚果云教程，7 张截图 `assets/webdav/*.png`）；配置存在 `lib/common/services/settings/web_dav_controller.dart`（122 行，明文密码，当前配置另存整份 JSON `:62-65`）。
- 认证在依赖包 webdav_client 1.2.2：第一次不带账号，401 时按 `WWW-Authenticate` 选 Digest 或 Basic（`webdav_dio.dart:91-134`），Digest 计算 `auth.dart:81-180`（有几处不合 RFC：`uri`、`nc`、MD5-sess、opaque 引号，4.x 不照搬，见 J04.1 README）。
- 必须保留：3.x 的 WebDAV 配置（地址、账号、密码、选中的服务器）键名和含义（由 J02.1 导入：`webDavConfigs`、`currentWebDavConfig`）；坚果云、Nextcloud、Alist 用 Basic 照旧能连。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 坚果云测试连接、上传、恢复没在 K90 上做过 | — | 单元测试的假服务器模拟了坚果云的回法；真服务器的细节（例如 PROPFIND 的深度、编码）没核对 | [S02.4](../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 第 2 条（CHECKLIST 第 5 节第 2 条） |
| 没有真的 Digest 服务器测过 | `web_dav_auth.dart` | 只靠 RFC 例子和本机假服务器 | 有用户反馈再说；不开任务 |
| 只支持 MD5 / MD5-sess 的 Digest，不支持 SHA-256、`auth-int` | `web_dav_auth.dart:69` | 只给这两种的服务器报“账号或密码错误”（3.x 也不支持） | 不做 |
| 每个客户端第一次请求多一次 401 往返 | `web_dav_client.dart:157` | 打开页面、换服务器、测试连接各多一次请求 | 照 3.x（J04.1 选择 1 的 A），不做 |
| 走 http 代理（不是隧道）访问 http 地址时，请求行是完整地址，Digest 的 `uri` 仍写路径 | `web_dav_client.dart:104` | 常见服务器接受；个别严格检查的会拒绝 | 不做（J04.1 记录“合并时注意”） |
| 帮助页没有 3.x 的截图 | `web_dav_help.dart` | 只有文字步骤 | 不做（J03.1） |

## 相关决定和规范

- D-018（3.x 的 WebDAV 配置键名不变）；J04.1 的两个选择按建议 A（先不带账号；401 没有 `WWW-Authenticate` 时 Basic 再试一次）。
- 不把真实的 WebDAV 地址、账号写进仓库：测试用 `https://dav.example.com/dav/`、`user@example.com`。

## 测试和验证

- 自动测试：`cd apps/pure_live && flutter test test/features/web_dav/`。
- 真机：坚果云（维护者自己的账号，不进仓库）→ S02.4 第 2 条：测试连接、上传完整备份、从服务器恢复；看坚果云每个客户端是否只多一次 401（`adb logcat` 里应用日志的失败摘要不含查询串和密码）。

## 路线

1. S02.4 第 2 条做完后，结果写回 J04.1 README 的“验证”。
2. 以后：WebDAV 定时备份（3.x 没有，见清点“统计”一节末尾“v3 没有的”）如果要做，先进 V01 提议。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [J 设置和数据](../README.md)。

- 代码：`features/web_dav/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| J04.1 | WebDAV Digest 认证 | 功能 | 完成 | 2026-10-02 | c168fdb99 | [设计或说明](J04.1-WebDAVDigest认证/README.md)、[记录](J04.1-WebDAVDigest认证/record.md) |

<!-- docs:生成结束 -->
