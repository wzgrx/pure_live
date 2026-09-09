# TTing 与 HLS 保留累计 Android 候选（2026-09-10）

**构建、内容/签名/资源和独立归档核验完成；未安装、未发布。** 上轮真实控制器的两次启动/停止/自动合并已通过，属于 progress；本轮把累计源码落到Android产物，不以Windows原生结果替代Android运行验收。

## 来源和范围

- 干净源码 `fb106ed6e51293c27ef8e2ac10b2422bba04867d`，元数据 `tracked_files_dirty=false`。
- 相对[上一Android候选bee143e2](OPENREC_PICARTO_ANDROID_CANDIDATE_2026_09_09.md)，包含[TTing应用接入](TTING_APPLICATION_INTEGRATION_AUDIT_2026_09_09.md)、HLS清单/输入保留与停止排空、源完整性警告及[实际录制入口启用](HLS_CONTROLLER_PREFETCH_AUDIT_2026_09_10.md)。当前18个直播站点+IPTV，9组参考平台未接入。
- 应用录制控制器显式开启受准入限制的HLS预取，底层普通FFmpeg默认仍false；FLV与离线合并不进入HLS缓存。此处描述打包源码，不宣称已经在手机验证运行。
- Android arm64 Debug，版本仍3.1.8+4121，不改正式版本。命令 `tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`，16 workers，串行并保留增量缓存。

## 产物核验

| 项目 | 结果 |
| --- | --- |
| 包名 | com.mystyle.purelive |
| versionName / 基础build / ABI偏移 / Manifest code | 3.1.8 / 4121 / 2000 / 6121 |
| ABI / 原生库 | 唯一arm64-v8a，16库，全部ELF LOAD至少0x4000；APK 16 KB对齐通过 |
| Flutter资源 | 1262项、205,889,233 B；关键资源与原生库完整性通过 |
| APK大小 | 288,457,197 B |
| SHA256 | `5ABE2D149AB2CDF340404F0C67E23586F483365A8A28FC2E5439C6B7B3081359` |
| 签名 | apksigner验证通过，单一Android Debug签名者、v2通过 |
| 证书SHA256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`，与同SHA旧归档的已核验证书一致；未读取手机安装证书 |

归档 `local-artifacts/candidates/android-fb106ed6/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`；同目录含 `BUILD_METADATA.json`、`build-record.json`、`signature.log`、`archive-verification.json`、`native-handoff-plan.json`。源输出与归档SHA一致，旧bee143e2独立APK保持原SHA和288,245,662 B。通用版本目录中的旧Release/Windows文件不是本次产物。

包内zh/en完整JSON与当前源码逐值一致，版本清单一致，localhost TLS测试私钥/测试目录未打包。签名校验保留现有Java native-access警告，构建保留Firebase auth/core KGP未来兼容警告；当前阶段退出0，没有为警告升级依赖。

## 验证与资源分层

本次使用`-SkipQuality`，**没有重跑或声称通过当前提交完整发布门禁**。复用此前逐批定向证据，直接关联最近103/103控制器/相邻回归与四文件严格分析、TTing完整实录合同1/1及真实控制器两轮原生1/1；原生探针的初始编译和lint失败仍留账，最终只做静态修订的范围见原审计。旧bee143e2完整门禁不外推为当前54个生产/资源文件累计差异已过全量回归。

| 阶段 | 资源记录 | 秒 | 峰值CPU | 峰值工作集B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| Android Debug | 20260909T180625448Z-build-androidarm64-debug.json | 75.542 | 58.08% | 8259579904 | 0 |
| 签名/资源/归档 | 20260909T180754073Z-android-archive-fb106ed6.json | 8.275 | 0.06% | 7150202880 | 0 |

Gradle阶段65.4秒。缓存策略启用且增量目录存在，工具日志未证明FROM-CACHE/UP-TO-DATE或配置缓存复用，不以较短耗时单独推导缓存命中率。一次构建前检查把旧摘要中APK大小前缀误并入预期SHA，检查即失败、尚未启动构建；随后从旧归档JSON读取并验证64位SHA，与实际文件一致后才执行本轮构建。旧APK未发生变化。

## 原生交接和剩余

新交接计划绑定本候选源码/APK/SHA，继承38组待验场景并新增TTing目录质量、完整父片录制、用户停止重启、缺片提示、多任务资源及非选中HLS/FLV回归六组，**44组全部not-run，ID唯一**。这些场景与宏观42组有重叠，不相加作为总缺陷/工时。

下一步先核对当前设备身份、前台测试窗口、同签名升级条件及一致数据备份，按共享设备包装器与现行远程约束执行后续安装/原生验收。尚未获得本候选的Android运行证据，既有schema6→7离线演练不是当前设备数据备份。手机重启/adbd、Wi-Fi/端口、Root/LSP/模块、卸载清数据均不作为测试手段。

本轮无ADB/MT或任何手机状态变更。Windows候选仍f3de664a；当前Android候选fb106ed6尚未安装。历史20 PASS/32 RUN/10 NR保持，全平台3.2.0质量、运行、构建和发布目标继续；本包不是稳定版交付。
