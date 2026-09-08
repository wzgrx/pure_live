# 累计 Android 候选与完整门禁（2026-09-08）

## 结论与范围

干净提交 `3a7716b06dc6cacc94d3b2ad2fa5c557070b1447` 已完成全量质量门禁和 Android arm64 Debug 构建、签名/内容核验及独立归档。版本保持 **3.1.8+4121**；没有安装、ADB/MT/Root/LSP 操作、Windows 新构建、上游合并或发布。

本候选替代此前 Android `58546f51` 的累计源码范围，纳入目录刷新事务、映客应用注册、克拉克拉底层 API、YY 外部打开、CC 分类分页与总目录/官方入口。克拉克拉仍未应用注册；官方专题网页入口不等于原生赛事播放能力。Windows 最新 Debug 仍为 `f3de664a`，其运行结果不外推到本 APK。

## 门禁失败与修订过程

保留全部失败日志，不以最终通过覆盖原始证据。

1. **已公开的 TLS 测试夹具被密钥扫描拦截**：`5bb89b0c` 首次门禁停止于仓库审计，尚未运行 Flutter analyze/test/build。该密钥是已有 loopback TLS 测试材料，不是发布签名密钥；检查两份自签证书、公钥匹配、SAN 和隔离信任上下文。`bea97d1b` 仅允许精确路径 `test/fixtures/tls/localhost-key.pem` 与 SHA-256 `b55b3743dda7dd512713f6efa4850d3a729486e9e2bff8cb4302738c192a5af8` 同时匹配时记录明确警告。改字节、移动路径、追加密钥/令牌及其他秘密依然报错；6/6 回归通过。没有目录级或 PEM 通配豁免。
2. **CC 接口探针存在误报成功路径**：源码检查发现旧探针会把迁移后的 HTML 当作分类成功。取消本任务拥有的第二次流程，保留取消记录；未终止其他任务。`cdc7742c` 将用例明确命名为 `cc.category_rooms`，核对独立 CC 分类 API 两个偏移、游戏身份、房间 ID 和列表结构，5/5 mock 回归通过。它不验证大神总目录或浏览器渲染。
3. **录制注册表测试预期过时**：第三次全量 analyze 无问题，测试 1942 通过、1 失败。预期列表遗漏已注册 TwitCasting、猫耳和映客。`3a7716b0` 补齐三项并将测试命名收窄为“声明录制详情解析能力”；没有修改生产录制逻辑，也不把类型断言描述为每站真实录制成功。
4. **最终完整重跑通过**：未使用 SkipQuality；同一干净提交完成以下全部阶段。

原始记录位于 `local-artifacts/candidate-build-20260908/`：`pipeline.log`、`retry-pipeline.log`、`cancelled-retry.json`、`final-pipeline.log`、`recording-contract-pipeline.log`、`tls-fixture-review.json`。两个失败门禁为 `20260908T002045306Z-quality-full.json` 与 `20260908T003512538Z-quality-full.json`。

同目录 `validation-source.json` 绑定候选源码、10 个门禁修订/夹具输入与 24 个日志、构建和归档证据摘要；已逐项重新核对哈希。本文及三个验收/调度入口共 183 个本地文档链接检查通过，文档更新不触发重复应用构建。

## 最终验证

| 层级 | 结果与边界 |
| --- | --- |
| 工具回归 | 新增 Python 审计 6/6、CC 探针 5/5；既有包装器回归使用假 ADB，不接触手机 |
| 仓库审计 | 4277 个已跟踪文件、2206 文本文件，0 错误、2 警告（空 catch 清单、精确公开 TLS 夹具） |
| 全量 analyze | 1 次，106.0 秒，无诊断 |
| 全量 Flutter 测试 | **1943/1943 通过**，日志 3 分 13 秒，concurrency=12 |
| 公开接口探针 | **42/42 通过**；包括 CC 两页分类房间，不包括新总目录原生加载/浏览器接管 |
| Android 构建 | arm64 Debug 成功；assembleDebug 257.5 秒，整个流程含质量门与资源排队 924.651 秒 |
| APK 内容 | 唯一 arm64 ABI，16 个 ELF，全部 LOAD 至少 `0x4000`，ZIP 16 KB 对齐及 Flutter 资源门禁通过 |
| 独立归档 | 新旧 APK 签名验证成功、证书相同；归档复制后 SHA 再核对，旧候选哈希未变；测试 TLS 文件未进入 APK |
| 原生/发布 | **未安装、未原生验收、未发布** |

全量质量记录 `local-artifacts/build-records/20260908T004453496Z-quality-full.json`：482.331 秒，峰值 CPU 83.29%、工作集 19,158,384,640 B；结束时观察到 2 个其他重型进程，因此后续构建遵循资源守卫排队。构建记录 `20260908T005156558Z-build-androidarm64-debug.json`：峰值 CPU 82.76%、工作集 19,552,178,176 B、结束后活跃重型进程 0。统计来自主机重型进程采样，不全部归因于单个 Pure Live 子进程。

构建保留了 Flutter 关于 firebase_auth/firebase_core 使用 KGP 的未来兼容警告，以及 apksigner 所用 Java 的 native-access 警告；当前退出成功，没有因此升级依赖或模块。缓存保持启用，但本次摘要没有观察到 FROM-CACHE/UP-TO-DATE，也未报告 configuration cache 复用，不声称缓存命中。

## 候选身份

- 路径：`P:\pure_live\local-artifacts\candidates\android-3a7716b0\PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`
- 包名：`com.mystyle.purelive`；基础 build `4121`，arm64 偏移 `2000`，Manifest versionCode **6121**。
- 大小：**287,151,530 B**。
- SHA-256：`AE3777EF827B4C5F987686B1F85A27DF45E8BE5FF7CDD94B6EB6A89B921B6CF3`。
- Debug 证书 SHA-256：`1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`；v2 签名验证成功。不是正式签名发布包。
- 同目录保存 BUILD_METADATA、build-record、quality-record、archive-verification；归档任务记录为 `20260908T005249620Z-android-candidate-archive-3a7716b0.json`，41.252 秒、结束活跃重型进程 0。
- 与旧 `58546f51` 候选证书相同，只证明两个本地候选一致；安装前仍需核对手机实际已安装包的签名和版本，保留数据覆盖安装。

## 下一步与剩余范围

`local-artifacts/candidate-build-20260908/native-handoff-plan.json` 绑定当前候选，8 组均为 not-run：CC 总目录、分页、刷新、旧收藏、官方入口，映客注册，YY 外部打开及播放/录制冒烟。前台测试窗口仍待明确；开始设备轮次前重新核对显式 serial、25102RKBEC/myron、当前前台与录制状态，并使用共享租约包装器。不重启或更改连接，不卸载或清数据，不更新模块。

本次新增的是源码完整门禁与候选证据，没有新增原生 PASS。当前 14 个直播站点 + IPTV、13 组参考平台未注册；历史 42 个未闭环宏观验收项不等于 42 个 Bug，也不是全部剩余任务。双端完整交互、代理、长时播放/录制及新增平台验收继续；3.2.0 仍等待完整验收后再构建发布。
