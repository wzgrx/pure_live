# 花椒与响应收尾累计 Android 候选（2026-09-08）

后续[升级前备份与本地演练](ANDROID_SCHEMA7_BACKUP_REHEARSAL_2026_09_08.md)已补手机身份、实际安装证书、一致关键状态快照及真实 schema 6 副本的生产迁移证据。仍未安装或原生验收；下文“未读取手机证书/无 ADB”保留为本构建阶段记录。

## 当前验收输入

干净提交 **`1d318bbab4e1ec00f6b13d2fd68254cd67198cf6`** 已完成完整质量门禁、
Android arm64 Debug 构建与独立签名/资源/归档核验。相对
[c97a61aa 数据候选](IPTV_DATA_ANDROID_CANDIDATE_2026_09_08.md)新增：

- [花椒公开 API](HUAJIAO_API_AUDIT_2026_09_08.md)，实现 `9106e379`；
- [五平台响应作用域与收尾](PLATFORM_RESPONSE_LIFECYCLE_AUDIT_2026_09_08.md)，实现 `a482e576`；
- [花椒应用入口、UID 身份和独立目录游标](HUAJIAO_APPLICATION_INTEGRATION_AUDIT_2026_09_08.md)，实现 `08a8d19c`。

Android 最新候选更新为 **1d318bba**，旧 c97a61aa 独立归档保留。
**未安装手机、未发布；版本仍 3.1.8+4121。** Windows GUI 候选仍 f3de664a，未随本批更新。
源码仍为 16 个直播站点 + IPTV，11 组参考平台未注册；候选构建不改变各平台能力和原生验收状态。

## 完整检查和构建

| 阶段 | 结果 | 记录 |
| --- | --- | --- |
| 全量静态分析 | No issues found，855.7 秒 | `pipeline.log` |
| Flutter 完整测试 | **2418/2418**，12 并发，测试资源实际构建 | `pipeline.log` |
| 公共接口探针 | **42/42** | `pipeline.log` |
| 仓库审计 | 4339 个跟踪文件，0 错误、2 项既有提示 | `20260908T142708273Z-full.json` |
| Android arm64 Debug | 成功，Gradle assembleDebug 632.3 秒，16 workers | `20260908T150540156Z-build-androidarm64-debug.json` |
| 签名/资源/归档 | 成功，旧包与新包同证书、归档前后哈希相同 | `20260908T150840765Z-android-candidate-archive-1d318bba.json` |

所有重型步骤经资源守卫串行运行；依赖按锁文件解析，没有升级依赖、同步上游、清理增量缓存或终止其他任务。
2418 项是本次完整执行总数，不是上一轮 287 项定向测试的重复计数；42 个公共接口探针也不覆盖
全部 16 个站点的所有功能。花椒另有上一轮真实注册适配器探针，但仍不是媒体解码或原生验收。

质量记录 `local-artifacts/build-records/20260908T145327112Z-quality-full.json`：1575.140 秒，
峰值 CPU 71.09%、工作集 15,663,677,440 B；构建 pipeline 2307.146 秒，**已包含该质量阶段，
两者不重复相加**。构建阶段峰值 CPU 68.09%、工作集 29,931,532,288 B。
归档记录 98.520 秒，峰值 CPU 29.41%、工作集 25,047,371,776 B。
三个阶段结束活跃重型进程计数均为 0，父构建与归档会话均已取得退出 0。
资源统计是守卫观测范围，不是 App 原生性能测试。

两项仓库提示为已审查的公开 localhost TLS 测试密钥和 30 处空 catch 清单；不把文件扫描当作
全仓语义审查。构建保留 Firebase auth/core 的未来 Kotlin Gradle Plugin 兼容提示；签名工具保留
Java native-access 未来兼容提示，当前验证均成功。缓存配置保留且构建前存在增量目录；日志未证明
configuration cache 重用或 FROM-CACHE 命中，不宣称本次缓存命中。

## APK 与独立归档

| 项目 | 实测 |
| --- | --- |
| 包名 | `com.mystyle.purelive` |
| 版本 | 3.1.8；基础 build 4121，arm64 偏移 2000，Manifest code 6121 |
| ABI / 对齐 | 唯一 arm64-v8a；16 个 ELF 的 LOAD 至少 0x4000，APK 16 KB 对齐通过 |
| Flutter 资源 | 1262 项；资源总字节 205,281,383；关键原生库和版本资源通过 |
| APK 大小 | **288,202,501 B** |
| SHA-256 | `BB016E197F698E487EF8238818BB52A041A0CAB99AB5A7F8A7DA630FC313B26E` |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

独立 apksigner 验证为一个 Android Debug 签名者、v2 通过，与归档 c97a61aa 证书一致。
**没有读取手机当前安装证书**，所以这不是覆盖安装已成功的证据。整个 zh/en JSON 与源码逐值相同，
花椒四键、克拉克拉萌星文案和 IPTV 修订文案均存在；公开 TLS 测试密钥未进入 APK。
37 个累计相关源码/测试/翻译/依赖输入的冻结哈希保持不变；构建元数据确认输入提交和干净工作树。

归档路径：`local-artifacts/candidates/android-1d318bba/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。
同目录保存 BUILD_METADATA、quality-record、build-record 和 archive-verification。
通用 `local-artifacts/3.1.8-4121/` 中的 Windows、Release 等文件是历史独立产物，不算本次输出。

## 原生验收交接与剩余

`local-artifacts/huajiao-android-candidate-20260908/native-handoff-plan.json` 保留原有 25 组场景，
新增花椒设置、游标/布局、UID 分享收藏、HLS/FLV 实播与完整短录、生命周期、能力含义及五平台
原生响应清理 7 组，合计 **32 组待验**。每组记录动作、预期、证据和清理约束；这些与历史 42 个
未闭环大项重叠，不相加为整个目标剩余数。

新计划的 APK、SHA、源码和 archive-verification 均绑定 1d318bba；继承计划中曾残留的旧 b68c81d1
归档引用已在新计划纠正，原始历史证据未覆写。新增场景保持 not-run，没有从测试或构建自动提升为 PASS。

下一轮按以下前置顺序进入实机，而不是重复构建同一源码：

1. 只读核对显式设备 `-s`、型号 `25102RKBEC`/代号 `myron`、当前前台及 Pure Live 播放/录制状态；
   连接失败按用户要求先读 devices/mdns、再尝试备用端口，不改设备网络配置。
2. 在共享设备测试窗口核对当前包、版本、签名与数据清单，取得并验证一致数据库备份。
   schema 7 升级前，活动 WAL 写入时只复制 SQLite 主文件不算一致备份；使用可用的 online backup，
   或仅在约定窗口让 Pure Live 停止写入后保存完整快照。
3. 保留数据覆盖安装，核对安装后源码产物、迁移关系、用户收藏/设置，再分批执行计划。
   若回退 schema 6，必须配套升级前数据快照，不把仅降级 APK 当作数据回滚。
4. Android 不可达时转到 Windows 本地验证；国外平台继续使用用户指定的 Clash 路由条件，
   直连探针结果不代替应用代理路径验收。

本轮没有 ADB、手机输入、MT MCP、lspctl、Root/LSP/模块、重启或网络设置操作。
不卸载或清数据、不重启手机/adbd、不切 Wi-Fi、不改 ADB 端口/授权、不执行 kill-server。
历史账本仍 **20 PASS / 32 RUN / 10 NR**，无原生 PASS 增量；全部功能、剩余参考平台、双端性能、
文档整理和全平台稳定 3.2.0 发布仍继续，不据本候选宣称全目标完成。

本批证据根目录：`local-artifacts/huajiao-android-candidate-20260908/`。
