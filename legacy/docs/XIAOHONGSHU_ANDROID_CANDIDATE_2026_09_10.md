# 小红书累计 Android 候选与当前升级前置核验（2026-09-10）

**Android arm64 Debug 构建、独立归档、签名/资源核验以及当前只读数据备份完成；未安装、未发布。** 前一轮分享代码与真实接口取证属于 progress，本轮推进实际产物和保留数据升级前置条件，不将它们计作手机运行 PASS。

## 候选与源码

- 干净源码 **`d4adcb7702f61e7e49fc4329188c7e2b7989dbb3`**，元数据 `tracked_files_dirty=false`。相对[fb106ed6 候选](HLS_ANDROID_CANDIDATE_2026_09_10.md)，15 个生产/资源文件有累计差异。
- 主要包括[小红书应用接入](XIAOHONGSHU_APPLICATION_INTEGRATION_AUDIT_2026_09_10.md)及[短链、动态/旧分享路径修订](XIAOHONGSHU_SHARE_LINK_AUDIT_2026_09_10.md)，目录迁移为 12，保持隐藏选择。源码中的战旗底层增量仍未注册，不计为可用站点入口。
- 版本保持 **3.1.8+4121**，非 3.2.0 稳定版。命令 `tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`，16 workers、增量缓存保留。
- 本次复用逐批定向证据，没有执行或声称当前累计提交已通过完整发布门禁。关联最近 320 项应用回归及末次 31 项复验、214 项分享回归及末次 82 项复验、严格分析，以及[两轮真实控制器录制](XIAOHONGSHU_CONTROLLER_NATIVE_AUDIT_2026_09_10.md)。Windows 原生测试不替代 Android 实机结果。

## 产物核验

| 项目 | 结果 |
| --- | --- |
| 包名 | com.mystyle.purelive |
| versionName / 基础 build / ABI 偏移 / Manifest code | 3.1.8 / 4121 / 2000 / 6121 |
| ABI 与 ELF | 唯一 arm64-v8a，16 个原生库，全部 LOAD 对齐至少 0x4000 |
| APK 对齐与资源 | 16 KB 对齐通过；1,262 项 Flutter 资源，205,955,596 B |
| APK 大小 | 288,486,345 B |
| APK SHA-256 | `0D23C15D8F81A86F8FEDA0D15F7DA0B1C0A731B78213D2C1323AB5DBE5C822D4` |
| 签名 | apksigner 验证通过，单一 Android Debug 签名者、v2 通过 |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

独立归档：`local-artifacts/candidates/android-d4adcb77/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。同目录含 BUILD_METADATA、build-record、signature、archive-verification、native-handoff-plan 和脱敏 preflight-comparison。源输出与归档 SHA 相同；旧 fb106ed6 的 288,457,197 B APK 保持原 SHA。通用版本目录中的旧 Release/Windows 文件不是本次产物。

包内 zh/en 完整 JSON 和版本清单与源码逐值一致，测试 TLS 私钥/测试 TLS 目录未打入 APK；关键原生库与 Flutter 资源通过项目门禁。保留 KGP 将来兼容警告及 apksigner Java native-access 警告，没有为此升级依赖或降低门禁。

## 当前安装包和数据备份

本轮明确使用 `-s 192.168.1.2:5555`，先确认 `25102RKBEC / myron`，然后只读检查自己的包、进程、服务和数据。实际安装仍为 **80b7431c**，3.1.8 / 6121，lastUpdateTime 为 2026-09-07 20:39:14。

当前安装 APK 的设备端 SHA 为 `D965095AC696FC98D000E89542835F98C8A0C30DA0DF54EF4089D19571762E8D`，与[已验签备份](ANDROID_SCHEMA7_BACKUP_REHEARSAL_2026_09_08.md)的本地实际 APK 字节 SHA 相同；候选证书与该备份证书相同。本轮没有重新下载或重新验签相同旧 APK，也没有只凭版本号推定证书。

复用已审查的只读 `exec-out run-as tar` 过程，在三次确认 Pure Live 无进程/服务的观察之间取得两份新快照：

- 每份 **10,824,192 B**，253 个成员、227 个文件；路径、大小、mtime、模式及文件 SHA 逐项一致。
- 两份完整 tar 的 SHA 均为 `0e2d97bf03abeabdea1f5abcc43422783b60ddfd57c0e7691e0aaaa3b6d6cdb5`，且与上次完整纳入范围的清单和 tar 一致。
- 只在本机独立解压副本检查 SQLite；**9 个数据库 integrity_check 均 ok、外键违反数均 0**。手机 IPTV DB 仍是 schema 6，没有执行手机迁移。
- 覆盖设置、IPTV 缓存与数据库、应用文件及包含 WAL/SHM 的状态目录。录制媒体保留手机原位、Debug 运行资源/旧下载 APK/可重建缓存不在状态 tar 内；这不是整机或整个应用文件系统镜像。私有原始数据仅保存本机忽略目录，不上传、不写入 Git。

当前迁移探针、database.dart、生成数据库代码、频道身份函数、pubspec 和 lock 的六份 SHA 也与上次演练输入一致。因此复用既有 schema 6→7 本机迁移 **1/1** 证据，不重复运行不变的迁移测试。此复用只覆盖相同数据库输入与迁移代码，不把它扩展成 Android 安装、当前所有设置迁移或全功能运行通过。

新证据根 `local-artifacts/xiaohongshu-android-candidate-20260910/`；`preflight/` 保存两份新 tar、成员哈希、数据库核验与三次静止观察，`preflight-comparison.json` 保存上述比较。最后于约 **2026-09-09T20:29:51Z** 再读型号、Pure Live 进程与 DB/Hive 哈希，核心数据仍一致且本包无进程。

初始前台为 `com.bilibili.app.in`，最后窗口观察为 `tv.danmaku.bili`、屏幕 Awake；中途前台变化不是本任务操作。最后 activities 没有匹配的 resumed 项，另读 window 才取得当前焦点，没有据空结果推断手机空闲。本轮已询问 Pure Live 前台测试窗口；在确认前保持只读，不唤醒、安装、force-stop 或输入。

## 资源与交接

| 阶段 | build-records 记录 | 秒 | 峰值 CPU / 工作集 B | 结束活跃重型进程 |
| --- | --- | ---: | --- | ---: |
| Android Debug | 20260909T202610480Z-build-androidarm64-debug.json | 224.832 | 74.36% / 9,882,234,880 | 1 |
| 签名/资源/独立归档 | 20260909T202819217Z-android-archive-d4adcb77.json | 17.870 | 6.20% / 10,034,540,544 | 0 |

Gradle 阶段 197.8 秒；缓存配置启用且增量目录存在，但日志没有 FROM-CACHE/UP-TO-DATE/配置缓存复用证据。构建后计数 1 是采样值，后续归档按守卫等待活跃 Java，未结束其他进程；归档结束为 0，不凭耗时或单次计数推导性能回归/泄漏。

交接计划按旧数组实际 **44** 项继承，新增小红书目录迁移、分享/搜索、下播身份、原生线路播放、录制重启、错误恢复及可见布局/生命周期 **7** 项，合计 **51 项全部 not-run、ID 唯一**。旧计划的 inherited/added 历史字段与累计数组计数不一致，本次以真实数组计数重建，不据旧字段漏掉已有场景。51 项与宏观验收矩阵重叠，不与 42 组相加计算缺陷或工期。

下一次安装前重新核对设备、前台、APK/数据是否变化；状态变化时取得新一致快照。只通过共享设备包装器、显式 Serial 和 NoRotation 执行保留数据同签名覆盖安装；不卸载/清数据，不重启手机/adbd、不改网络/端口/授权、不更新 Root/LSP/模块。APK 回退不等于数据库回滚，schema 6 回退需匹配备份。

当前 **19 个直播站点 + IPTV，8 组参考平台未注册；宏观仍 20 PASS / 32 RUN / 10 NR，42 组未闭环**。Windows 候选仍 2fb471d3。本轮不追加 Windows 构建或提前发布 3.2.0，后续继续原目标的双端全功能与平台扩展验收。
