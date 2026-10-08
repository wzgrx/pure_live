# J 设置和数据

设置、存储和加密、备份恢复、WebDAV、设备同步、3.x 数据迁移。界面在 A11、A12。

管用户的数据本身：每个设置的键名、默认值、范围和存在哪里，关注、历史、分组、屏蔽、Cookie 和密码怎么存、怎么加密，备份文件的格式、WebDAV 和局域网设备同步怎么传，以及覆盖安装 3.x 后怎么把旧数据接过来。排在直播间、弹幕、播放、录制、浏览之后：那几组是用户每天直接用的功能，这一组是它们的地基；但**数据出错（丢关注、丢设置）是这个项目最严重的事故**，所以本组的 J06.1（3.x 数据迁移的真机验证）是第一档。

## 范围

- 管什么：
  - **设置项**（J01）：`packages/live_store/lib/src/settings/` 的注册表（`Settings`，218 个设置，键名就是 3.x 的 Hive 键）、`SettingsStore` 的读写和监听、坏值的修复；设置在应用里**在哪里生效**（谁读它）；设置页的目录 `apps/pure_live/lib/features/settings/settings_catalog.dart` 里“这一行改的是哪几个设置”的对应关系；设置项逐条核对（J01.2）。
  - **存储和加密**（J02）：`packages/live_store` 整个包——一个 SQLite 文件 `pure_live.db`（drift，后台 isolate）里的关注、历史、关注分区、分组、屏蔽、设置、密钥、WebDAV、内部记录、3.x 其他模块的原值；Cookie 和密码的加密（`SecretStore` + 应用的 `SecretCipher`：Android Keystore、Windows DPAPI，`apps/pure_live/lib/platform/secret_cipher.dart`）；数据目录（`apps/pure_live/lib/app/data_root.dart`）；多个桌面窗口共用一个库时的同步（`LiveStore.syncExternal`）。
  - **备份恢复**（J03）：备份格式（3.x 的分区布局，`backupVersion: 4`）和 `BackupService`；应用一侧加的分区（搜索记录、网络电视列表、多画面上次的画面，`apps/pure_live/lib/shared/backup/`）；恢复前预览的比较逻辑（`previewRestore`）；备份文件的命名、默认目录、写文件的方式；同步到电视（`features/backup/tv_sync.dart` 的文档和发送）。
  - **WebDAV**（J04）：`features/web_dav/web_dav_client.dart`（PROPFIND、GET、PUT、DELETE，走应用的 `LiveHttp`）和 `web_dav_auth.dart`（Basic、Digest）；服务器配置的存储（`live_store` 的 `WebDavStore`，密码在密钥库）。
  - **设备同步**（J05）：`features/remote_receiver/` 的协议、服务、局域网发现（`remote_sync_protocol.dart`、`remote_sync_service.dart`、`mdns_peers.dart`），和 3.x 的线上格式互通。
  - **3.x 数据迁移**（J06）：`packages/live_store/lib/src/legacy/`（直读 Hive 文件、转换、合并、账本、身份迁移）和应用一侧的调用（`app/bootstrap.dart`、`app/iptv_legacy.dart`、`app/fonts.dart` 的 `legacyFontRoots`、`app/startup.dart` 的 `LegacyReloginNotice`）；覆盖安装后的真机核对。
- 不管什么：
  - 这些东西长什么样、怎么点：设置总览和各设置页 → [A11](../A-界面设计/A11-设置界面/README.md)；账号、备份、WebDAV、设备同步、日志页 → [A12](../A-界面设计/A12-账号和数据界面/README.md)；设置里的弹幕页 → A08.5、A08.6；录制设置页 → A10.2；电视设置面板 → A17.9。
  - 设置“生效”的具体行为归用到它的组：弹幕设置怎么画 → D05；播放、画质、硬解 → G；录制设置 → H03；刷新率策略 → R02；代理规则 → Q02；屏幕常亮、权限 → O。J 只管键、默认值、范围、存储，以及“确实有人读它”。
  - 登录、Cookie 的取得和核验 → [K](../K-账号和登录/README.md)（K 用 J02 的 `SecretStore` 存）；网络电视库的表和 3.x 网络电视库的读取逻辑 → [L01](../L-网络电视和点播/L01-网络电视/README.md)（`app/iptv_library.dart`、`app/iptv_legacy.dart` 的转换规则），J06 只核对迁移结果。
  - 覆盖安装本身（签名、版本号、包能不能装上）→ [S04.1](../S-质量和验证/S04-覆盖安装验证/README.md)、Y01；J06.1 和 S04.1 同一次做。

## 子分类怎么分

| 子分类 | 管什么 | 和其他子分类、其他组的关系 |
|---|---|---|
| [J01 设置](J01-设置/README.md) | 设置注册表、读写、默认值和范围、生效位置、设置页目录和设置的对应、逐条核对 | 设置页的样子 A11；各设置生效的行为在 D、G、H、O、Q、R；存储引擎在 J02 |
| [J02 存储和加密](J02-存储和加密/README.md) | `live_store` 的库、表、各仓库类、密钥加密、数据目录、多窗口同步 | J01、J03、J04、J06 都建在它上面；Cookie 的使用方 K；Keystore 的原生通道在 O（`AppChannelsPlugin.kt`） |
| [J03 备份恢复](J03-备份恢复/README.md) | 备份格式、导出和恢复、预览、文件、同步到电视 | 界面 A12.4；WebDAV（J04）和设备同步（J05）传的就是这个格式 |
| [J04 WebDAV](J04-WebDAV/README.md) | WebDAV 客户端、认证、服务器配置的存储 | 界面 A12.5；上传下载的内容是 J03 的备份 |
| [J05 设备同步](J05-设备同步/README.md) | 局域网同步协议、服务、发现、配对码 | 界面 A12.6；Android 17 本地网络权限 O04；扫码 O03（`shared/qr_scan.dart`） |
| [J06 3.x 数据迁移](J06-3.x数据迁移/README.md) | 覆盖安装后自动导入 3.x 的数据，以及真机核对 | 迁移代码在 J02 的 `legacy/`；网络电视库 L01；覆盖安装 S04.1 |

## 现状（2026-10-07）

- **做到哪**：登记的 6 个任务里 4 个“完成”（J01.1 设置、J02.1 存储和迁移、J03.1 备份与 WebDAV、J04.1 WebDAV Digest 认证），2 个未开始（J06.1 3.x 数据迁移的真机验证，第一档；J01.2 设置项逐条核对，第二档）。J05 没有登记任务：设备同步的逻辑在 I08.1、I01.3（发现）、A12.6（拆出“先取再应用”）里做完。
- **真机**：这一组几乎没有 K90 结果。4 个“完成”的任务都是 2026-10-01～02 合并时按“单元测试 + 构建通过”记的；按功能清点（[inventory/FEATURES.md](../inventory/FEATURES.md) 第 1、12 节）：F-APP-01（3.x 设置导入）、F-APP-02（3.x 网络电视库导入）“没验证”→ J06.1、S04.1；F-BAK-03（`Download/PureLive` 免权限写入）、F-BAK-05（设备同步）、F-BAK-06（扫码）“没验证”→ S02.4；F-BAK-04（WebDAV）“完成”但坚果云实测在 S02.4 第 2 条；F-AND-05（Cookie 加密存储）→ K02.1。
- **和 3.x 比**：
  - 少了：3.x 的 Firebase 云端账号和云端配置（不做，A12.3、F-ACC-08）；3.x 备份页的日志管理移到了设置 → 数据 → 日志管理（I01.3）。
  - 多了：存储从一个 Hive box 换成 SQLite（按行写、有事务、后台 isolate）；Cookie 和 WebDAV 密码加密；恢复前预览、文件里没有的部分保持不变（3.x 会重置成默认）；完整备份带上搜索记录、网络电视列表和多画面上次的画面（3.x 读这种文件时忽略多出来的分区）；WebDAV 走应用代理、测试连接、Digest；设备同步要配对码、接收前预览；设置搜索和“恢复本页默认”；迁移只读 3.x 的文件（不复制、不加锁、不改不删）。
- **主要的代码**：`packages/live_store`（纯 Dart，`lib/` 约 4600 行，46 个测试）；应用一侧 `features/settings/`（14 个文件约 8300 行，界面为主）、`features/backup/`、`features/web_dav/`、`features/remote_receiver/`、`shared/backup/`、`app/bootstrap.dart`、`app/data_root.dart`、`app/iptv_legacy.dart`、`platform/secret_cipher.dart`。细到文件的在各子分类的代码地图。

## 当前重点和顺序

1. **第一档：J06.1 3.x 数据迁移的真机验证**（和 S04.1 同一次做）。4.0.0 已经发给用户覆盖安装 3.x，迁移只有用造出来的 Hive 文件做的单元测试（`packages/live_store/test/migration_test.dart`），没有一次用真实的 3.x 数据跑过；出错就是用户丢关注和设置。验证方式不能碰用户手机上的 3.x（D-019），任务书写了两条路：模拟器上装 3.2.11 造数据再覆盖安装 4.x（真正的覆盖路径），以及 K90 上的测试包读入从模拟器拿到的 3.x 文件（真机 Keystore）。
2. **第二档：J01.2 设置项逐条核对**。读取检查（清点第 15 节）已经做完，剩下默认值、范围、生效位置三项逐条对照 3.x；V03.3 的初比是 172 个里 106 个字面值一样、64 个要展开 3.x 的常量。
3. **顺带（不单独开任务）**：S02.4 第 1～3 条（备份目录、坚果云、设备同步和扫码）做完后，J03.1、J04.1 的真机结果写回记录；K02.1 验证 Keystore 时顺带看 WebDAV 密码。
4. 以后：设备同步被拒本地网络权限时的提示文字（见 J05 已知问题，等 O04.1 真机确认）；3.x 存下的京东、酷狗、百度占位值迁移时没清、迁移报告看不到 → [J06.2](J06-3.x数据迁移/J06.2-3.x迁移报告在正式版里看得到/README.md)（2026-10-07 登记）。

## 风险和注意

- **丢数据**：任何改动 `live_store` 表结构、`legacy/` 转换规则、备份格式的任务，都要有“3.x 数据 / 3.x 备份读进来还是原样”的测试（`migration_test.dart`、`backup_test.dart` 的写法），并在任务书里写清回退办法。迁移按 `路径|大小|修改时间` 记账（`meta` 的 `legacy.importedSources`），改了转换规则不会对已经导入过的用户重跑，需要重跑时要另写一次性的修复。
- **3.x 的设置键名和含义不变（D-018）**：新设置只加不改，写清默认值；3.x 读 v4 的备份（回退用）靠的就是键名不变、分区不变。改默认值也算改含义，要先在 J01.2 的表里写明依据。
- **不碰用户的 3.x**（D-019）：真机验证只用测试包 `com.mystyle.purelive.v4dev`，不读、不复制、不导出用户手机上正式包 `com.mystyle.purelive` 的数据（手机有 root 也不行），也不动 Windows 上 `D:\Soft\PureLive`、`D:\Soft\pure_live`。需要 3.x 数据时在模拟器上自己造。
- **密钥**：Keystore 的密钥跟着安装走（卸载重装、换设备都解不开），解不开的 Cookie 当作未登录并在账号页提示；备份默认不带账号（同 3.x），设备同步带不带由用户勾选。仓库里不能出现真实 Cookie、账号、WebDAV 地址（样本要脱敏）。
- **局域网**：设备同步、同步到电视走明文 HTTP，靠配对码和对方确认；Android 17 要“本地网络”权限（O04）。
- **备份往返**：v4 写 `backupVersion: 4`，3.x 读到大于 3 的版本按最新兼容导入；v4 自己加的分区（`search`、`iptvLibrary`、`multiview`）3.x 忽略。新加分区时保持这个性质。

## 相关

- 规范：[specs/ENGINEERING.md](../specs/ENGINEERING.md)（包的依赖方向：`live_store` 只依赖 `live_core`）；[specs/UPGRADES.md](../specs/UPGRADES.md)（J02.1 涉及 22 条：受限直播、优先 H.264、Twitch 语言、斗鱼续期、YouTube 全部聊天、房间身份、按主播关注、画质命名等）；清点 [inventory/FEATURES.md](../inventory/FEATURES.md) 第 1、12、15 节。
- 决定：D-001（3.x 是基线）、D-006（签名，覆盖安装的前提）、D-018（设置键名不变）、D-019（不碰 3.x）。
- 其他组：A11、A12（界面）；K（账号，用 J02 的密钥库）；L01（网络电视库和它的迁移）；O04（本地网络权限）；Q02（代理，WebDAV 走应用代理）；S02.4、S04.1（真机）；Y01（发布和覆盖安装）。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 进度和子分类

`███████████████████░` 93%

| 子分类 | 范围 | 进度 | 完成 / 全部 |
|---|---|---|---:|
| [J01 设置](J01-设置/README.md) | 设置项、设置搜索、设置项核对。 | `████████████████████` 100% | 3 / 3 |
| [J02 存储和加密](J02-存储和加密/README.md) | 数据库、设置存储、Cookie 和密码加密。 | `████████████████████` 100% | 1 / 1 |
| [J03 备份恢复](J03-备份恢复/README.md) | 备份和恢复。 | `████████████████████` 100% | 1 / 1 |
| [J04 WebDAV](J04-WebDAV/README.md) | WebDAV 备份。 | `████████████████████` 100% | 1 / 1 |
| [J05 设备同步](J05-设备同步/README.md) | 局域网设备同步。 | `██████████████████░░` 90% | 0 / 1 |
| [J06 3.x 数据迁移](J06-3.x数据迁移/README.md) | 覆盖安装 3.x 后自动导入关注、历史、设置、账号。 | `██████████████░░░░░░` 70% | 0 / 2 |

## 还没完成的（3）

| 任务 | 状态 | 档位 | 阶段 |
|---|---|---|---|
| [J06.1](J06-3.x数据迁移/J06.1-3.x数据迁移的真机验证/README.md) 3.x 数据迁移的真机验证（覆盖安装时用真实数据核对） | 开发中 | 第一档 | 2/3：下一阶段“逐项核对关注、历史、设置、账号” |
| [J06.2](J06-3.x数据迁移/J06.2-3.x迁移报告在正式版里看得到/README.md) 3.x 迁移报告在正式版里看得到，清掉京东、酷狗、百度的占位名 | 待真机 | 第二档 | 2/2 |
| [J05.1](J05-设备同步/J05.1-同步前勾选内容/README.md) 同步前勾选内容：设备同步发送、接收前选同步哪几类（接 V01.6） | 待真机 | 第三档 | — |

决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。

<!-- docs:生成结束 -->
