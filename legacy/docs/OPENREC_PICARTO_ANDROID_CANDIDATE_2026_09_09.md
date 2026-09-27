# OPENREC、Picarto 与平台名称修订累计 Android 候选（2026-09-09）

## 当前验收输入

干净源码 **`bee143e21664e8222b8edabab6aa5ea7d5a87850`** 已完成完整门禁、Android arm64 Debug
构建及独立签名、资源、归档核验。相对 [1d318bba 候选](HUAJIAO_ANDROID_CANDIDATE_2026_09_08.md)新增：

- [OPENREC API](OPENREC_API_AUDIT_2026_09_09.md)及[应用接入](OPENREC_APPLICATION_INTEGRATION_AUDIT_2026_09_09.md)：`37bdd9c9` / `70a78805`；
- [Picarto 响应作用域与总时限](PICARTO_RESPONSE_LIFECYCLE_AUDIT_2026_09_09.md)：`cd1e3126`；
- [OPENREC 双语平台注册名称补项](OPENREC_PLATFORM_LABEL_AUDIT_2026_09_09.md)：`bee143e2`。

**Android 最新已核验候选为 bee143e2，未安装、未发布；版本仍为 3.1.8+4121。**
旧 1d318bba APK 独立归档保留，Windows 候选仍为 f3de664a。源码为 17 个直播站点 + IPTV，
10 组参考平台尚未注册；候选成功不改变各平台完整能力及原生验收状态。

## 门禁与构建证据

| 阶段 | 实际结果 |
| --- | --- |
| 完整静态分析 | No issues found，1037.5 秒，一次调用 |
| Flutter 完整测试 | **2492/2492**，12 并发，测试资源实际构建 |
| 公共接口门禁 | **42/42**，覆盖 9 个既有平台 |
| 仓库审计 | 4366 个跟踪文件，0 错误、2 项既有提示 |
| Android arm64 Debug | 成功；assembleDebug 1655.7 秒，16 workers |
| 独立签名、资源及归档 | 成功；父构建会话 72730、归档会话 50172 均取得退出 0 |

先前 `42ae9fae` 的完整测试为 2491 通过、1 失败，原因是双语资源缺少 `site_openrec`。
该失败记录完整保留；本次使用修订后的新输入，不把旧失败记录提升为成功。
并发控制台没有逐条显示所有测试标题；本次完整无过滤测试集通过，`sites_test.dart` 中无跳过的
双语名称合同及新增品牌断言均保留。没有为补一个控制台标题再次重跑测试。

42 个公共接口用例来自 `tool/interface_probe.py`，覆盖 Bilibili、斗鱼、虎牙、抖音、快手、CC、
Twitch、SOOP、YY；不涵盖新增的 8 个直播适配器或 IPTV，也不等于 Dart 注册适配器、
媒体完整解码、短录封装或设备验收。范围清单保存在本批 `interface-gate-scope.json`。
OPENREC 的既有注册适配器探针仍为 DIRECT 目录 200 但无可选卡片、Clash 目录 403，
整条播放/录制流程及原生验收保持待验，不以本次 42/42 掩盖该缺口。

| 重型记录 | 耗时 | 峰值 CPU / 工作集 | 收尾活跃重型进程 |
| --- | --- | --- | --- |
| `20260908T194953840Z-quality-full.json` | 2288.177 秒 | 51.55% / 10,595,631,104 B | 0 |
| `20260908T202024943Z-build-androidarm64-debug.json` | 4100.904 秒 | 72.08% / 14,545,051,648 B | 1 |
| `20260908T203731080Z-android-candidate-archive-bee143e2.json` | 836.334 秒，含排队 | 17.94% / 11,431,788,544 B | 0 |

构建 pipeline 耗时已包含完整质量阶段，两者不重复相加。统计是资源守卫观测范围，
不是 App 性能结果；构建收尾的 1 个活跃进程不据此推断归属或泄漏。归档等待其他工作区任务
释放资源，没有终止其他进程、重启守护进程、清除增量缓存、升级依赖或同步上游。
保留既有 Firebase auth/core KGP 与 apksigner Java native-access 未来兼容提示，当前阶段均成功。
缓存配置启用且增量目录存在，但日志未证明 FROM-CACHE、UP-TO-DATE 或配置缓存复用。

## APK、签名与资源

| 项目 | 核验结果 |
| --- | --- |
| 包名 / 版本 | `com.mystyle.purelive` / 3.1.8；基础 build 4121，arm64 偏移 2000，Manifest code 6121 |
| ABI / 对齐 | 唯一 arm64-v8a；16 个 ELF 的 LOAD 至少 0x4000，APK 16 KB 对齐通过 |
| Flutter 资源 | 1262 项，205,376,780 B；关键资源及原生库内容门禁通过 |
| APK 大小 | **288,245,662 B** |
| SHA-256 | `9CEBE4F06D993A2F3FCB51794D8438054A988D5007160EB5B88B9C9F6F04469F` |
| 证书 SHA-256 | `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9` |

apksigner 验证为一个 Android Debug 签名者、v2 通过，与归档 1d318bba 同证书。
整个 zh/en JSON 与源码逐值匹配，包含新增 `site_openrec`、OPENREC 说明以及既有 IPTV/平台文案；
公开 localhost TLS 测试密钥未进入 APK。19 个冻结源码、测试、翻译和依赖输入在构建及归档后
哈希均未变化，元数据确认输入提交及干净工作树。没有重读手机当前安装证书。

归档：`local-artifacts/candidates/android-bee143e2/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。
同目录包含 BUILD_METADATA、quality-record、build-record 和 archive-verification。
通用 `local-artifacts/3.1.8-4121/` 内的 Release、Windows 等旧文件不是本次构建输出。

## 原生验收与下一步

本批 `native-handoff-plan.json` 已绑定实际 APK、SHA、源码和归档记录：32 个继承场景加 6 个
OPENREC / Picarto 场景，共 **38 组，全部 not-run**，ID 无重复。它们与历史 42 个未闭环大项
重叠，不相加作为全目标剩余数；历史账本仍为 20 PASS / 32 RUN / 10 NR，无原生 PASS 增量。

手机切换窗口仍待确认。[既有备份与 schema 7 演练](ANDROID_SCHEMA7_BACKUP_REHEARSAL_2026_09_08.md)
是历史证据；覆盖安装前重新核对显式设备序列号、25102RKBEC / myron、前台及当前播放/录制状态、
安装证书与一致数据备份。仅降级 APK 不构成 schema 7 到 6 的数据回滚。
确认窗口后保留数据覆盖安装并分批验收；Android 不可达时按既定范围转 Windows。

本批没有 ADB、手机输入、MT、lspctl、Root/LSP/模块或设备网络设置操作。
没有卸载、清数据、重启手机/adbd、撤销授权或执行 kill-server。
剩余平台、双端功能/布局/性能、文档整理及全平台稳定 3.2.0 发布继续，未将此候选当作全目标完成。

本批证据根目录：`local-artifacts/openrec-label-android-candidate-20260909/`。
