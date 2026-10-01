# F.4b WebDAV Digest 认证

- 状态：完成（2026-10-02，[记录](../records/F.4b.md)）
- 档位：可以以后；规模：小
- 功能点：F-BAK-04（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/features/web_dav/web_dav_client.dart`
- 依赖：U.11b（WebDAV 界面）合并后
- 来源：M13.10“留给后续”、M13.18 任务说明第 4 项
- 评审页：按授权直接开发（把 v3 的认证方式补回来；两处选择按建议 A 做）
- 记录：[records/F.4b.md](../records/F.4b.md)

## v3 的行为（`~/ref/v3ref`，v3.2.11；认证在依赖包 webdav_client 1.2.2 里）

| 行为 | 位置 |
|---|---|
| 建客户端时只给用户名和密码，不定认证方式（`NoAuth`） | `modules/web_dav/webdav_service.dart:17`；包 `lib/src/client.dart:220-227` |
| 每个请求按当前方式带 `authorization`；第一次什么都不带 | 包 `lib/src/webdav_dio.dart:75-79` |
| 回 401 时看 `WWW-Authenticate`：含 `digest` 用 Digest，否则含 `basic` 用 Basic，都没有就报错；换好后重发，之后同一个客户端一直用这个方式 | 包 `webdav_dio.dart:91-134` |
| Digest 时再回 401 且 `stale=true`：取新 nonce 重发；别的 401 报错 | 包 `webdav_dio.dart:113-122` |
| Digest 计算：MD5、MD5-sess，`qop=auth`（或不带 qop），带 opaque | 包 `lib/src/auth.dart:81-148`、`:165-180` |

v3 的 Digest 有几处不合 RFC（v4 不照搬）：`uri` 用的是相对地址根的路径（`webdav_dio.dart:76` 传进 `auth.dart:82`），地址带文件夹（如坚果云的 `/dav/`）时和请求行对不上，会被检查 uri 的服务器拒绝；`nc=1` 不是 8 位十六进制；MD5-sess 用了 nc 而不是 nonce（`auth.dart:116`）；opaque 没加引号（`auth.dart:102`）。

## v4 现在

- `WebDavClient` 每个请求都先带 Basic（`features/web_dav/web_dav_client.dart:86-88`、`:98`），不读 `WWW-Authenticate`；401、403 一律算“账号或密码错误”（`:107-111`）。
- 客户端按选中的服务器建一个（`web_dav_page.dart:97`），配置对话框的“测试”每次新建一个（`:182`）。

## 差别和根因

| 编号 | 差别 | 根因 |
|---|---|---|
| P1 | 只认 Digest 的服务器（部分 NAS、Apache/nginx 的 Digest 目录）账号密码对也报“账号或密码错误” | M13.10 用自己的客户端换掉 webdav_client 时只写了 Basic（`web_dav_client.dart:86-88`），列为“留给后续” |
| P2 | 不看服务器要什么，先把密码（Base64）发出去；Digest 服务器走 http 时密码明文经过网络 | 同上，没有 v3 的“先问再选”（`:98` 每个请求都加） |

## 要做的改动

| 编号 | 类型 | 内容 | 对应 |
|---|---|---|---|
| c1 | 补上 | Digest 认证（RFC 7616/2617）：MD5、MD5-sess；`qop=auth` 或不带 qop；带回 opaque、algorithm；同一个 nonce 的 nc 递增（8 位十六进制）；`uri` 用实际请求的路径（含地址里的文件夹） | P1、v3 包 `auth.dart` |
| c2 | 补上 | 照 v3 选方式：第一次请求不带账号，回 401 时按 `WWW-Authenticate` 选（两种都给时用 Digest），重发一次；同一个客户端之后直接带上 | P2、v3 包 `webdav_dio.dart:91-134` |
| c3 | 补上 | Digest 回 401 且 `stale=true`（或用的是旧 nonce）时用新 nonce 重发一次；每个请求最多重发一次，密码错时照旧报“账号或密码错误” | v3 包 `webdav_dio.dart:113-122` |
| c4 | 保留 | 401 不带 `WWW-Authenticate` 时用 Basic 再试一次（v4 现在能连的服务器照旧能连）；只给了不支持的方式（如 SHA-256 Digest、Bearer）时不发密码，直接报“账号或密码错误” | 选择 2 |

没有界面改动，不加设置，不加翻译。

## 需要选的

| 编号 | A（建议，按 A 做） | B |
|---|---|---|
| 1 第一次请求带不带密码 | 照 v3 先不带，按服务器的要求选；每个客户端多一次 401 往返（页面打开或换服务器时一次，测试连接时一次） | 照 v4 现在先带 Basic，401 要 Digest 时再换；少一次往返，但 Digest 服务器也会先收到 Base64 的密码 |
| 2 401 没有 `WWW-Authenticate` | 用 Basic 再试一次（v4 现在能连的照旧能连） | 照 v3 直接报错 |

## 测试和验证

- 单元测试（`apps/pure_live/test/features/web_dav/web_dav_auth_test.dart`，本地假服务器，地址 `https://dav.example.com/dav/`、账号 `user@example.com`）：
  - Digest 计算和 RFC 7616 3.9.1 的 MD5 例子一致；MD5 用 RFC 1321 的例子；`WWW-Authenticate` 多个方式、引号里的逗号、多行都能读。
  - 只认 Digest 的服务器：测试连接、列目录、上传、下载都成功；只有第一个请求被 401，之后直接带 Digest，nc 递增，uri 含 `/dav/`。
  - nonce 过期（`stale=true`）重发成功；密码错只发两次就报“账号或密码错误”。
  - Basic 服务器（坚果云的回法）用 Basic；两种都给用 Digest；不带 `WWW-Authenticate` 用 Basic；只给 Bearer 不发密码。
  - 用真的 HTTP 栈（`IoLiveHttp` + 本机回环端口）连一个 Digest 服务器，两行 `WWW-Authenticate` 能读到。
- 原有的 WebDAV 页面测试（假服务器只认 Basic、不带 `WWW-Authenticate`）不改，照旧通过。
- K90：TASKS 第 5 节 5.5 第 2 条（坚果云测试连接、上传、恢复）。手边没有 Digest 服务器，Digest 只有单元测试。

## 风险和性能

- 没有常驻任务；每个客户端多一次 401 往返。
- 3.x 的 WebDAV 配置（地址、账号、密码、选中的服务器）键名和含义不变。
- 坚果云、Nextcloud、Alist 回 401 都带 `WWW-Authenticate: Basic`，走 Basic，和 v3 一样。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
| 2026-10-02 | 写功能对比 |
| 2026-10-02 | 开发完成（先不带账号，按 `WWW-Authenticate` 选 Basic 或 Digest），待 K90 验证 |
