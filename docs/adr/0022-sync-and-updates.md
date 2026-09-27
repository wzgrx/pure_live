# 0022 同步、备份扩展、诊断、更新、分享口令与首启向导的实现选择

- 状态：已接受
- 日期：2026-09-28

## 背景

`spec/product.md` §13–15、§19（F-SHR-01/02、F-SYNC-01、F-DAV-01、F-BAK-01/02、F-UPD-01..03、F-NEW-08、F-NEW-11）和 `spec/modules/store.md` §7–11 规定了行为。实现时有几处规格没写具体做法，又会长期影响数据格式、依赖和隐私，需要固定下来。宪法原则 8（Cookie 加密、局域网必须配对确认、默认不上报）和原则 11（许可证）是硬约束。

## 决定

1. **WebDAV 客户端自己写。** 在 `live_net` 的 `LiveHttp` 上实现 PROPFIND（Depth 0/1）、PUT、GET、DELETE、MKCOL 和 HTTP Basic 认证，约 300 行（`apps/pure_live/lib/features/sync/webdav_client.dart`）。请求的 site id 是 `webdav`，因此跟随应用注入的 `ProxyPolicy`（ADR 0011 §3）。multistatus 只读 `href`、`resourcetype/collection`、`getcontentlength`、`getlastmodified`，用容忍任意命名空间前缀（`d:`、`D:`、`lp1:`、默认命名空间）的解析，不引入 XML 包。不支持 Digest 认证（坚果云、Nextcloud、群晖、Alist 都接受 HTTPS 上的 Basic）。
2. **WebDAV 配置暂存 meta 表。** 键 `webdav.profiles`（JSON 列表：id、name、baseUrl、username、remoteDir）和 `webdav.current`；密码只在密钥库 `webdav/<id>`。地址校验沿用 3.x 规则（store.md §6.4.12），名称不区分大小写唯一。ADR 0017 §1 说 `webdav_profiles` 表“做到时再加”；这次不改库结构（本功能不改 `packages/*`，meta 已够用）。以后加表时从这两个 meta 键迁移。配置本身暂不进备份（`V4Format` 本来就跳过 `webdavProfiles` 分区）；用户选“包含平台登录信息”时，WebDAV 密码随口令加密的 secrets 分区一起走。
3. **局域网同步沿用 3.x 协议，只做“推送”。** 端口 39888（被占用时往后试 20 个），`POST /api/remote-sync/settings`，配对码放在 `x-purelive-pairing` 头里，应答 `{code, msg, data}`，另加 `reason` 字段（`pairing` / `rejected` / `busy` / `invalid` / `origin` / `size`）区分失败原因。v4 发 version 2 包，同时接收 version 1（3.x 设备扫码后可以直接推过来）。`GET` 拉取（3.x 的“从对方接收”）返回 405，因为 v4 不能产出 3.x 格式。保护措施：
   - 配对码常数时间比较，连续错 5 次换码；每次用户做出决定后也换码，一码只用一次。
   - 同一时间只处理一个包（其余返回 409），包体上限 32 MB。
   - 带 `Origin` 头的请求（浏览器网页）直接拒绝，也不发 CORS 头。
   - 接收方先 dry run 并显示将导入的内容，确认后才写入，最长等 3 分钟，超时按拒绝处理。
   - Cookie 只能放在口令加密的 secrets 分区里；3.x 发来的明文 Cookie，会在确认框里注明。
   - 发送用直连的 `IoLiveHttp`，因为代理到不了局域网。
4. **局域网发现不做 mDNS，改用手动地址加二维码。** 3.x 用 Bonsoir 广播 `_purelive-sync._tcp`。Bonsoir 是原生插件，会增加包体和权限面，不算“便宜”。二维码内容是 `purelive://<ip>:<端口>/sync?code=<配对码>`，3.x 可以扫码发送。二维码用 `qr` 4.0.0 生成（BSD-3-Clause，纯 Dart，kevmoo 维护，2026-05 发布），自己用 `CustomPainter` 画。Android 17 的本地网络权限：清单里已经声明 `ACCESS_LOCAL_NETWORK`，运行时申请要写原生代码，现在先在页面上说明怎么去系统设置里打开。
5. **分享口令。** 编码和解码用 `live_store` 的 `ShareCode`，与 3.x 互通。分享动作在手机和桌面上都是复制到剪贴板：应用里没有系统分享插件，加 `share_plus` 要引入原生插件，留给直播间和平台层以后决定。分享接收（Android 分享到本应用）识别到口令就直接进房，因为这是用户主动分享，不再二次确认；平台不受支持时改为按主播名搜索。
6. **剪贴板识别。** 应用回到前台 1 s 后读一次剪贴板。先识别口令（整段文字或其中一个词）；看起来像链接时，再交给各平台适配器解析。识别到直播间就弹窗确认，确认后才进房。每份剪贴板内容只看一次，内存里只保存它的 SHA-256；应用自己复制出去的口令不会再提示给自己。开关存在 meta 表（`app.clipboardRecognition`，默认开，和 3.x 一样），不进设置注册表：这是这台设备上的习惯，不需要跨设备同步，也不需要改 `packages/*`。
7. **更新检查只查 GitHub Releases。** 读 `api.github.com/repos/wzgrx/pure_live/releases`（site id `github`，跟随代理），不用 3.x 的 14 个第三方镜像，因为镜像内容的完整性无法保证。筛选规则：
   - 只看主版本 ≥ 4 的标签（`v4.*`），3.x 的标签不参与。
   - 预览构建也看预发布版（`4.0.0-preview.N`），正式构建只看正式版。
   - 版本按 SemVer 优先级比较。
   - 草稿版不看。

   已安装 3.x 的更新源（根目录 `assets/version.json`、`releases.json`）不读也不改。自动检查按 `app.autoCheckUpdate` 开关，首帧后 2 s 执行，每次启动只查一次。
8. **SHA-256 的来源和校验方式。** 校验值按以下顺序取：
   1. GitHub API 给每个文件的 `digest` 字段（`sha256:…`）。
   2. 发布说明里与文件名同一行的 64 位十六进制串。
   3. `SHA256SUMS` 类文件里的对应行。

   应用内不下载也不安装：Android 安装 APK 需要 `REQUEST_INSTALL_PACKAGES` 和 FileProvider。版本页按平台和 ABI 排列下载链接，交给浏览器下载，并提供“校验下载的文件”：用 file_picker 选文件，流式计算 SHA-256 后比对。其中 ABI 从 `Platform.version` 读取，不需要插件。哈希用 `crypto` 3.0.7（BSD-3-Clause，dart-lang，锁文件里本来就有）。
9. **版本号不用插件读取。** 版本号写在 `lib/app/version.dart` 的常量里，`test/version_test.dart` 与 `pubspec.yaml` 对照，不加 `package_info_plus`。发版改版本号时两处一起改，测试会检查。
10. **本地滚动日志自己写，不用 talker。** 日志写在 `<应用支持目录>/logs/app.log`，另外最多保留 2 个旧文件，每个 256 KB，总量不超过 768 KB。每一行写入前都经过 `LogScrubber` 清理，去掉以下内容：
    - `Cookie`、`Authorization`、配对码等请求头的值；
    - URL 里的用户信息和整个查询串（签名流地址的签名就在查询串里）；
    - 名称看起来敏感的键值对；
    - 48 个字符以上的不透明串。

    写入是同步追加：日志量很小，出错时这样不会丢最后几行。
11. **诊断包是一个 JSON 文件，不打 zip。** 内容包括：应用版本；运行时能拿到的设备信息（系统、版本、CPU 核数、语言、屏幕，不含主机名）；全部设置的当前值，并标出哪些被改过；数据计数；最近 3000 行日志（再清理一遍）。不打 zip，就不用加 `archive` 依赖，用户和开发者也能直接打开看。密钥不在设置里，所以不会被带进去。
12. **崩溃处理只在本机。** `FlutterError.onError` 和 `PlatformDispatcher.onError` 都写进日志，并留下 `crash.pending` 标记。“崩溃报告”开关（meta `app.crashReports`，默认关）只决定下次启动时要不要提示“导出诊断包”，不设任何远程上报端点。以后如果要接远程上报，另写一份 ADR。
13. **首启向导只出现一次。** 向导只在两个条件同时满足时出现：meta `app.firstRunDone` 未设置，并且没有任何关注。显示前先写标记，所以无论用户怎么操作都不会再出现。向导提供从文件、WebDAV 或局域网导入（局域网直接进入接收页），也可以跳过。以下启动任务由 `StartupTasks`（main 里包在 `PureLiveApp` 外面）在首帧之后发起，此时路由的导航器已经存在（REG-STORE-014）：向导、崩溃提示、更新检查、剪贴板监听。
14. **所有恢复走同一个确认流程。** 本地文件、WebDAV、局域网和向导都调用 `confirmAndRestore`：先 plan（dry run），再显示确认框（可以选完整恢复或仅关注，加密的账号信息可以填口令），最后一次事务写入。口令不对时，其余内容照常导入并提示（store.md §7.3）。导出和上传可以选“包含平台登录信息”，这时必须设置至少 6 位的口令。

## 备选方案与放弃理由

- `webdav_client` 1.2.2：2024-05 以后没有更新，依赖 dio 和 xml；3.x 用过，但它的调试日志会打印认证头。
- `xml` 包：根目录的覆盖锁在 7.0.1，最新版 7.1.0 是 2026-09-27 当天发布的；这里只需要解析 multistatus 这一种文档，引入完整的 XML 解析器不划算。
- mDNS（Bonsoir）和 UDP 广播发现：需要原生插件，Android 上还要 MulticastLock；手动地址加二维码已经能完成配对，发现功能以后可以单独加。
- `qr_flutter` 4.1.0：2023 年以后没有更新。
- 第三方 GitHub 镜像：无法保证内容完整；只有 SHA-256 与 API 来自同一来源时，校验才有意义。
- `package_info_plus`：多一个原生插件，只是为了读一个构建时就确定的常量。
- talker_flutter：功能远超需要（界面、Dio 拦截器），而且脱敏规则仍然得自己写。
- zip 诊断包：要加 `archive` 依赖，用户也要先解压才能看内容。
- 把剪贴板开关和崩溃报告开关放进设置注册表：注册表的设置会进备份并跨设备同步，这两项是本机偏好；放进去还要改 `live_store`。

## 影响

- 新增依赖：`qr` 4.0.0（BSD-3-Clause）、`crypto` 3.0.7（BSD-3-Clause，之前已是间接依赖）。
- 直播间页调用 `shareRoom(context, ref, detail)`（`lib/features/share/share_room.dart`）分享口令。
- 待办：
  - 系统分享面板（share_plus 或原生 `ACTION_SEND`）。
  - `ACCESS_LOCAL_NETWORK` 的运行时申请。
  - 局域网自动发现。
  - `webdav_profiles` 表和 WebDAV 配置进入备份。
  - 应用内下载并安装 APK。
  - 远程崩溃上报（需要另写 ADR，默认关）。
  - 搜索页识别分享口令，需要搜索功能调用 `ShareTextRecognizer.findShareCode`。
