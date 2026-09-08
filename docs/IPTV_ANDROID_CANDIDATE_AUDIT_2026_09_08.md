# IPTV 三批修复累计 Android 候选（2026-09-08）

## 当前候选

干净源码 `b68c81d1052be4fcdfd2ac810203943c7ce2f0d3` 重新完成完整质量门禁、Android arm64 Debug构建及APK内容/签名/归档核验。包含 [UA与间隔](IPTV_SETTINGS_DIALOG_AUDIT_2026_09_08.md)、[网络导入](IPTV_NETWORK_DIALOG_AUDIT_2026_09_08.md)、[EPG选择](IPTV_EPG_SELECTION_AUDIT_2026_09_08.md) 三批IPTV修订，并保留之前FLV停止/坏源保留和克拉克拉目录修复。

**未安装手机、未发布，版本仍3.1.8+4121。** 最新Android验收输入为b68c81d1；96673538保留历史副本。Windows GUI候选仍f3de664a，未由本次Android构建更新。

## 质量与构建

- Flutter3.47.0固定SDK入口、PowerShell7.6.5，依赖锁定解析，未升级依赖。
- **2129/2129测试、42/42公共接口、全量analyze一次407.6秒无问题**。质量记录 `20260908T060901920Z-quality-full.json`：827.779秒，峰值CPU53.74%、14,720,958,464 B，结束检测活跃重型进程1。该计数不是本任务仍在执行的判定；实际质量/父构建会话已取得终态。
- 仓库审计4306个跟踪文件，0错误、2个既有提示，不据此推导全部运行行为无缺陷。固定原生依赖预取通过，未更新Root、模块或手机组件。
- 构建记录 `20260908T061745858Z-build-androidarm64-debug.json`：1364.946秒含质量阶段，Gradle451.1秒，workers16。峰值CPU66.26%、15,259,979,776 B，构建结束活跃重型进程0。
- daemon/增量缓存保留；本轮日志FROM-CACHE=0、UP-TO-DATE=0、configuration cache未复用，配置启用不是命中证据。Firebase未来KGP兼容性警告保留，不借机升级依赖。

## 产物与校验

| 项目 | 实测 |
| --- | --- |
| 包名 | com.mystyle.purelive |
| 版本 | 3.1.8；基础build4121，arm64偏移2000，Manifest6121 |
| ABI/原生库 | 唯一arm64-v8a，16个ELF全部LOAD至少0x4000；APK 16KB对齐通过 |
| Flutter资源 | 1262项，版本、关键原生库、翻译及资源完整性门禁通过 |
| 大小 | 288,144,953 B |
| SHA-256 | `BC11C39F25E2391408581B9FB5B8903861FA4C8D9CD7DBCDCFE186E94785E91A` |
| 证书SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

新包与先前96673538归档Debug包签名一致；没有读取手机当前证书，因此不把历史证书一致当作覆盖安装已经核验。归档前后SHA一致，旧包哈希保持。实际打包的中英文萌星目录/能力说明及五个IPTV新键逐值对照冻结源码，公开TLS测试私钥未打包。

不可变归档：`local-artifacts/candidates/android-b68c81d1/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。同目录保留构建元数据、质量/构建记录和archive-verification。通用3.1.8-4121目录中的Windows/Release文件仍为旧独立产物，不算本轮多平台构建。

归档记录 `20260908T061929202Z-android-candidate-archive-b68c81d1.json`：52.953秒，峰值CPU9.47%、13,948,080,128 B，结束检测活跃重型进程1；本轮归档进程及其finally监控清理已结束，未对其他进程执行终止或重启。

## 原生待验

既有16组累计场景保留，新增UA/间隔、网络导入、EPG来源选择3组，**19组候选专项全部待验**。该清单与历史42个未闭环大项有重叠，不做简单相加或换算总进度。

实机前仍核对当前窗口、设备测试包装器/共享约束、明确serial与25102RKBEC/myron、当前包/证书。覆盖安装保留用户数据，场景采用独立测试来源并恢复设置。无当前窗口确认时继续源码或独立Windows工作，不将历史ADB连接当作当前前台许可。

本批无ADB、MT、Root/LSP、手机重启/adbd重启、网络切换、清数据、安装或发布。历史台账62行仍20PASS、32RUN、10NR；IPTV真实初始化/下载/解析/管理、长录、性能、多平台及完整3.2.0仍待完成。

证据：`local-artifacts/iptv-android-candidate-20260908/`，含完整pipeline、签名输出、源冻结、19组native-handoff、哈希索引及终态checkpoint。
