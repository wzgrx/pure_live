# T09d.2 WebDAV Digest 认证

- 日期：2026-10-02
- 任务：[T09d.2/README.md](README.md)
- 改动：`features/web_dav/web_dav_auth.dart`（新：读 `WWW-Authenticate`、Digest 计算、MD5）、`features/web_dav/web_dav_client.dart`（按服务器的要求选认证方式）；测试 `test/features/web_dav/web_dav_auth_test.dart`（新）

## 逐条对照

| 编号 | 做到 | 说明 |
|---|---|---|
| c1 Digest 认证 | ✅ | MD5、MD5-sess；`qop=auth` 或不带 qop（RFC 2069 的写法）；带回 opaque 和服务器写的 algorithm；同一个 nonce 的 nc 递增，写成 8 位十六进制；`uri` 用请求行里的路径和查询（含地址里的文件夹，如 `/dav/`）。只给 SHA-256 或只给 `auth-int` 的 Digest 不支持（v3 也不支持），当作不认识的方式 |
| c2 照 v3 选方式 | ✅ | 第一次请求不带账号；401 时读 `WWW-Authenticate`（多行、一行多个、引号里的逗号都能读），有能用的 Digest 就用 Digest，否则有 Basic 用 Basic，重发一次；同一个客户端之后直接带上 |
| c3 nonce 过期 | ✅ | Digest 回 401 时：`stale=true` 或用的是旧 nonce（nc > 1）就用新 nonce 重发；每个请求最多重发一次。密码错：Digest 两个请求、Basic 两个请求后报“账号或密码错误”，之后每次一个请求 |
| c4 没有 `WWW-Authenticate` | ✅ | 用 Basic 再试一次（v4 原来能连的照旧能连）；只给 Bearer 等不认识的方式时不发密码，报“账号或密码错误” |

和 v3 的差别（README 已写）：v3 的 Digest `uri` 用相对地址根的路径、`nc=1`、MD5-sess 算法写错、opaque 不加引号；这里按 RFC 写。v3 回 401 没有 `WWW-Authenticate` 时直接报错，这里再用 Basic 试一次（选择 2 的 A）。

## 根因

T09c.1 用自己的客户端（走应用的 `LiveHttp`，代理才生效）换掉 webdav_client 时只写了 Basic：每个请求先带 Basic（原 `web_dav_client.dart:86-88`、`:98`），不读 `WWW-Authenticate`，只认 Digest 的服务器账号密码对也报“账号或密码错误”。

## v3 → v4

webdav_client 1.2.2 的 `lib/src/webdav_dio.dart:75-134`（选方式、重发）→ `web_dav_client.dart` 的 `_sign`、`_learn`、`_send`；`lib/src/auth.dart:81-180`（Digest）→ `web_dav_auth.dart` 的 `parseAuthChallenges`、`DigestChallenge`、`digestAuthorization`。MD5 自己写（`md5Hex`，RFC 1321 的例子测过），应用不为它加 `crypto` 依赖。

## 设置

没有新设置；3.x 的 WebDAV 配置（地址、账号、密码、选中的服务器）键名和含义不变。

## 测试

新增 5 个（`web_dav_auth_test.dart`）：

1. MD5 和 RFC 1321 的例子一致；Digest 回答和 RFC 7616 3.9.1 的 MD5 例子一致（两行、SHA-256 那行不用）；一行多个方式、转义引号、大小写。
2. 只认 Digest 的服务器：测试连接、上传、列目录、下载都成功；只有第一个请求不带账号、被 401，之后 nc 从 00000001 到 00000004；`uri` 是 `/dav/backup%201.txt`。
3. MD5-sess：nonce 过期带 `stale=true`、不带 `stale` 都重发成功；不带 qop 的服务器能用；Digest 密码错只发两个请求。
4. Basic 服务器（坚果云等的回法）用 Basic；Basic 和 Digest 都给用 Digest；401 不带 `WWW-Authenticate` 用 Basic；只给 Bearer 不发密码；Basic 密码错第二次只发一个请求。
5. 真的 HTTP 栈（`IoLiveHttp` + 本机回环端口上的服务器）：两行 `WWW-Authenticate` 能读到，用 Digest 连上。

改之前 2、3、5 会失败（原来每个请求都带 Basic，Digest 服务器回 401）。原有的 9 个 WebDAV 页面测试没改，照旧通过（它的假服务器只认 Basic、401 不带 `WWW-Authenticate`，走 c4）。`apps/pure_live` 全部测试通过。

## 没验证的

- K90：TASKS 第 5 节 5.5 第 2 条（坚果云测试连接、上传、恢复）——确认坚果云照旧能用，且每个客户端只多一次 401。
- 真实的 Digest 服务器手边没有，只有单元测试。

## 合并时注意

- 只动了 `features/web_dav/` 的两个文件和新测试，不和别的任务冲突。
- 走 http 代理（不是隧道）访问 http 地址时，请求行是完整地址，`uri` 仍写路径；常见服务器（Apache、nginx）接受。
