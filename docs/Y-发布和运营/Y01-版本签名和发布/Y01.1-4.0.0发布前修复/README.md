# Y01.1 4.0.0 发布前修复

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：发布
- 来源：2026-10-02 凌晨 4.0.0（Android）发布前的审查：逐个看 release 构建、3.x 导入、播放会话、权限、外部意图、启动链和录制的边界情况，只管 Android。
- 旧编号：T16a.1
- 相关：Y01.2（紧接着的发布）；J06（3.x 导入，第 2、8 条）；G02（播放会话，第 3、9 条）；O04（权限，第 4、5 条）；O03（外部意图，第 6 条）；I01（启动，第 7 条）；记录 [record.md](record.md)

## 目标

发布前把审查发现的、会让 4.0.0 正式包在用户手上出问题的 9 处修掉，每处一个提交、每处有改之前会失败的测试（新函数的除外），并做一次 release 构建确认原生改动和资源压缩都没问题。

## 3.x 和现状

| 条 | 问题（根因） | 3.x | 修之前的 4.x | 修之后 |
|---|---|---|---|---|
| 1 | release 资源压缩删掉了 audio_service 的媒体按钮图标（只在 Dart 里按名字引用），Android 13 起媒体通知和前台服务起不来 | `res/raw/keep.xml` 保留这三个 | 只保留 `ic_stat_playback` | `keep.xml` 加回 `audio_service_pause`、`play_arrow`、`stop` |
| 2 | 3.x 导入：`LegacyMigration.merge` 先写设置、再加密 Cookie，AndroidKeyStore 坏的机器上抛异常，关注等永远导不进来 | Cookie 明文，没有这个问题 | 中途退出、账本不记、每次启动重来 | 先写不需要加密的，加密单独 `try/catch`，跳过的登录信息启动后提示一次“部分平台需要重新登录” |
| 3 | `PlaybackSession.dispose()` 时引擎还在创建，创建好的引擎没人释放（原生播放器和纹理泄漏） | — | 快速进出直播间泄漏 | `dispose` 等正在创建的引擎并释放它 |
| 4 | Android 17 本地网络权限：投屏搜索和局域网直播源没申请 `ACCESS_LOCAL_NETWORK` | 只有代理和设备同步申请 | 同 3.x，用户只看到“搜索失败” | 投屏、局域网 IPTV、多画面打开前先申请，被拒时说明原因 |
| 5 | 两个插件用同一个权限请求码 `20261001`，结果被错发 | — | 通知和本地网络互相答错 | 本地网络改 `20261003`，测试扫描所有请求码不重复 |
| 6 | 导出的 `MainActivity` 收到任意 `route` 就打开，别的应用能直接打开设置、备份、WebDAV | — | 任意页面 | 只允许 `/search`、`/record_mannager`，Dart 和 Kotlin 两边都挡 |
| 7 | 启动链没有兜底：`LiveStore.open` 抛异常时停在系统启动画面 | — | 卡在启动画面 | 错误页“纯粹直播没能启动”，原因、重试、导出日志 |
| 8 | 3.x 默认目录（应用私有存储）里的录像升级后用户进不去 | 录到 `<app_flutter>/PURE_LIVE/RECORDS` | 默认录到外部私有目录，旧录像留在原处 | 第一次启动把成品录像移到新的默认目录（只做一次，分段和未完成的不移） |
| 9 | 两次 `stop` 重叠留下的空闲定时器 45 秒后把正在播放的引擎释放掉 | — | 换线、切房间时偶发黑屏 | 定时器只由最新的一次 `stop` 设，触发前再确认 |

## 结果

- 提交：每条一个，最后一个是 `c5bc87666`（2026-10-02 08:16，“fix(android): keep audio_service's media button icons in release builds”，第 1 条）；第 1、5、6 条的原生改动之后在 `e975d3915` 上做了 release 构建。改动的文件和逐条的根因、测试见 [record.md](record.md)。
- 新翻译键：`legacy_import_relogin`（第 2 条）、`local_network_denied_cast`、`local_network_denied_stream`（第 4 条）、`launch_failed_*` 6 个（第 7 条），中英文都有。
- 新文件：`apps/pure_live/lib/app/launch_failure.dart`（第 7 条）。
- 偏差：第 8 条导入的 3.x 录制任务里的“上次文件”路径（`lastOutputPath`）没改，录制中心点这个任务的“打开文件夹”仍指向旧的私有目录（记录“已知不足”）。
- 测试数量：`apps/pure_live` 729 个全部通过（开始前 721 个）；`packages/live_player` 34 个、`packages/live_store` 44 个通过。改之前会失败的：第 1、2、3、4、5、6、9 条的测试；第 7、8 条是新函数，没法先跑出失败。

## 验证

- 自动测试：`test/platform/system_surfaces_test.dart`（图标都在 `keep.xml`、请求码不重复）、`packages/live_store/test/migration_test.dart`（加密不可用时其余照样导入、跳过一次）、`test/services_test.dart`、`packages/live_player/test/session_test.dart`（创建中被释放、重叠的 stop）、`test/features/live_play/live_play_more_test.dart`、`live_play_more_page_test.dart`（本地网络）、`test/intake_test.dart`（外部意图）、`test/launch_failure_test.dart`（启动失败）、`test/features/recorder/recorder_centre_test.dart`（3.x 录像搬家）。
- release 构建：`flutter build apk --release --split-per-abi --target-platform android-arm64`（110.3 MB），`lintVitalAnalyzeRelease` 无问题；`aapt2 dump resources` 看到三个 audio_service 图标和 `ic_stat_playback` 都在、文件大小和原图一致。
- 真机：记录里写明第 4～8 条**没在真机上试**（Android 17 以下不弹本地网络权限、没在手机上 `am start`、没制造启动失败、没在真机上搬录像）。登记表是“完成”，这几条的真机部分属于发布后的验证：本地网络权限 → O04.1；3.x 导入和录像搬家 → J06.1、S04.1。

## 留下的问题

- 第 8 条：导入的 3.x 录制任务的 `lastOutputPath` 仍指向旧目录 → 没有任务管；需要维护者决定是否在 J06.1 里一起处理。
- 第 2、8 条只在造的数据上测过，真实 3.x 数据的覆盖安装 → S04.1、J06.1（第一档）。
- 状态登记为“完成”但第 4～8 条没有真机结果，和 PROCESS 第 3.2 节“完成必须有真机结果”不完全相符；建议在 S02.5 或 S02.6 的清单里补“外部意图只开两个页面”“启动失败页”两项（`am start` 和制造只读数据目录都能在 K90 上用测试包做）。
