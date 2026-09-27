# IPTV 数据链路累计 Android 候选（2026-09-08）

后续验收输入已更新为[花椒与响应收尾累计候选 1d318bba](HUAJIAO_ANDROID_CANDIDATE_2026_09_08.md)，包含本页全部数据修订；本页 c97a61aa 归档保留。两者均未在该构建阶段安装手机，不借后续构建补写原生 PASS。

## 当前输入

干净源码 `c97a61aa5fbc9f6eb92a2ecff5c5b0011d990982` 完成完整质量门禁、Android arm64 Debug 构建，以及独立签名/资源/归档核验。相对 [b68c81d1 候选](IPTV_ANDROID_CANDIDATE_AUDIT_2026_09_08.md)新增六批：

- [初始化失败与离页保护](IPTV_INITIALIZATION_AUDIT_2026_09_08.md)；
- [EPG 导入事务与网络](EPG_IMPORT_TRANSACTION_AUDIT_2026_09_08.md)；
- [EPG 来源身份与 schema 7 迁移](EPG_SOURCE_IDENTITY_AUDIT_2026_09_08.md)；
- [自动映射保留与回滚](IPTV_MAPPING_TRANSACTION_AUDIT_2026_09_08.md)；
- [播放列表覆盖导入与缓存引用](IPTV_REPLACEMENT_AUDIT_2026_09_08.md)；
- [M3U 解析、损坏输入及升级身份](M3U_PARSER_AUDIT_2026_09_08.md)。

最新 Android 验收输入更新为 **c97a61aa**，旧 b68c81d1 独立归档保留。**未安装手机、未发布，版本仍 3.1.8+4121**。Windows GUI 候选仍 f3de664a，没有随本次 Android 构建更新。

## 完整门禁与构建

- 固定 Flutter 3.47.0 / Dart 3.13 入口，PowerShell 7.6.5；没有升级依赖或同步上游。
- **2313/2313 Flutter 测试、42/42 公共接口探针、全量 analyze 570.9 秒无问题**。这是现有门禁范围，不等于十五个平台所有能力和原生场景均通过。
- 质量记录 `local-artifacts/build-records/20260908T115646015Z-quality-full.json`：1334.448 秒（含排队），峰值 CPU 59.37%、工作集 45,083,799,552 B，结束活跃重型进程 0。仓库审计 4320 个跟踪文件、0 错误、2 项既有提示。
- 构建记录 `local-artifacts/build-records/20260908T121543110Z-build-androidarm64-debug.json`：整条 pipeline 2452.945 秒，**已含上述质量阶段**，不重复相加。Gradle assembleDebug 1043.0 秒，16 workers；构建阶段监控峰值 CPU 79.23%、15,660,261,376 B，结束计数 1。父会话 39222 已取得退出 0；残留计数不代表该构建仍运行，也未据此终止其他进程。
- 增量目录存在、daemon/cache/VFS 配置保留；日志记录未证明 configuration cache 重用，不宣称缓存命中。Firebase 两个插件仍有未来 KGP 迁移提示，当前构建通过；固定依赖未借机更新。
- 固定原生依赖预取通过；FFmpeg hook 缺少远端 SHA 的核验仍为跳过，不升级成远端哈希通过。

## APK 与不可变归档

| 项目 | 实测 |
|---|---|
| 包名 | com.mystyle.purelive |
| 版本 | 3.1.8；基础 build 4121，arm64 偏移 2000，Manifest code 6121 |
| ABI / 对齐 | 唯一 arm64-v8a；16 个 ELF 的 LOAD 至少 0x4000，APK 16 KB 对齐通过 |
| Flutter 资源 | 1262 项；关键资源/版本清单和原生库完整性通过 |
| 大小 | 288,174,752 B |
| SHA-256 | `92A37A9C67EC38FD6863FADF36143AC83576AF1C2680BF3D50B775AF31F2BE19` |
| 签名证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

独立 apksigner 核验新包与旧 b68c81d1 包通过，证书一致；**本轮未读取手机当前证书**，所以不把两份本地 APK 同签名当作覆盖安装已通过。打包的完整 zh/en 文案逐值对照当前源码；公开 TLS 测试密钥未进入 APK。归档前后 SHA 一致，旧包哈希保持。

归档路径：`local-artifacts/candidates/android-c97a61aa/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。同目录保留 BUILD_METADATA、quality-record、build-record 和 archive-verification。通用 `3.1.8-4121` 目录内的其他 Windows/Release 文件是历史独立产物，不算本次全平台输出。

归档记录 `local-artifacts/build-records/20260908T122252828Z-android-candidate-archive-c97a61aa.json`：399.811 秒含等待，峰值 CPU 10.31%、14,466,002,944 B，结束活跃重型进程 0；归档会话 50688 退出 0。没有重启或终止其他 Java/Gradle 进程。

## 待原生验收与数据库前置条件

原有 19 组候选场景保留，新增上述六批的数据/交互场景，**25 组全部待验**。`native-handoff-plan.json` 记录逐组动作、预期、所需证据和清理要求；该数字与历史 42 个待闭环大项重叠，不相加为总剩余量。

本候选包含 schema 7 迁移代码，**实际手机迁移尚未执行**。覆盖安装前：

1. 明确当前 Pure Live 前台窗口，按共享设备约束，显式 Serial 并只读核对 25102RKBEC / myron；再检查当前包版本、证书、前台和录制状态。
2. 先保存一致数据库备份及原 APK/数据清单并验证完整性。活动 WAL 写入期间只复制 SQLite 主文件不是一致备份；优先可用的 SQLite online backup，否则仅在约定测试窗口使 Pure Live 停止写入后取得完整快照。
3. 保留数据覆盖安装；不卸载、不清数据。不以旧 schema 6 APK 直接降级 schema 7 数据，回退需匹配的升级前快照。
4. 使用独立测试来源/频道，记录收藏、设置和引用的前后状态；恢复本轮改动，保留无关用户变更。

本轮没有任何 ADB/手机输入、MT APK MCP、lspctl、Root/LSP 或网络设置操作；不重启手机/adbd、不切 Wi-Fi、不改 ADB 端口/授权、不执行 kill-server 或模块更新。未获得当前前台测试窗口时，继续源码与剩余参考平台合同核验，不重复构建同一个候选。

[历史大项矩阵](ACCEPTANCE_MATRIX_3_1_0.md)仍为 **62 项：20 PASS / 32 RUN / 10 NR**，无原生 PASS 增量。十二组参考平台未注册、完整功能/模式/性能验收及文档/全平台稳定 3.2.0 目标继续。

证据根目录 `local-artifacts/iptv-data-android-candidate-20260908/`：完整 pipeline 与签名日志、归档脚本、25 组原生计划、20 个累计变化源码/测试的冻结校验、哈希索引和终态 checkpoint。
