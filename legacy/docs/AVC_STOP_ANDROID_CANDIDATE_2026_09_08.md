# AVC 停止修复累计 Android 候选（2026-09-08）

## 结论与源码

干净提交 `966735384aa3224f217fa14eb4e72769a6edafac` 已完成一次完整质量门禁及 Android arm64 Debug 构建、内容/签名/归档核验。包含 [AVC 停止边界修复](FLV_AVC_STOP_BOUNDARY_AUDIT_2026_09_08.md) `1abbff9a`、[坏源保留保护](KILAKILA_NATIVE_TAIL_AUDIT_2026_09_08.md) `26de4378` 及先前萌星目录修复。旧 ae5232b2 保留为历史输入，新 Android 候选以本报告为准。

**未安装、未操作手机、未发布。** 版本保持 3.1.8+4121；候选通过不是原生/UI/长录验收通过。Windows GUI 候选仍 f3de664a，未因本次 Android 构建而更新。

## 完整验证

- Flutter 3.47.0 / Dart 3.13 固定入口，锁文件未改变；2098/2098 Flutter 测试、42/42 公共接口通过，全量 analyze 一次、233.3 秒无问题。
- 质量记录 `20260908T042959828Z-quality-full.json`，572.715 秒；峰值 CPU 44.01%、13,039,648,768 B，结束活跃重型进程 0。
- 仓库检查 4301 个跟踪文件、0 错误、2 个既有提示（已审阅公开 TLS 测试私钥和空 catch 清单）；不是对全部运行行为无缺陷的证明。
- 本轮原生依赖预取及 Windows FFmpeg hook 均报告 SHA 校验通过；没有升级 SDK、插件或原生库。

首次由调用者误选 Windows PowerShell 5.1，在解析无 BOM 中文脚本时失败，未进入 Flutter analyze/测试或 Gradle。保留失败质量记录 `20260908T041939717Z-quality-full.json`、构建记录 `20260908T041939991Z-build-androidarm64-debug.json` 与原日志。同一源码在实际工作环境 PowerShell 7.6.5 解析、平台合同检查通过后重跑；未通过编辑测试、删中文或跳过门禁掩盖错误。

## 构建与产物

- 构建记录 `20260908T043750521Z-build-androidarm64-debug.json`：1042.431 秒含前置质量阶段，Gradle 413.2 秒；workers=16。峰值 CPU 75.48%、14,141,349,888 B，结束活跃重型进程 0。
- 保留增量缓存与 daemon；本轮日志 `FROM-CACHE=0 / UP-TO-DATE=0`、configuration cache 未复用，不把配置启用计作命中。Firebase 的未来 KGP 兼容性警告保留，没有借机升级依赖。
- 包名 `com.mystyle.purelive`，versionName=3.1.8，基础 build=4121，arm64 偏移2000，Manifest versionCode=6121。
- 唯一 ABI arm64-v8a、16 个原生 ELF 的 LOAD 对齐至少 0x4000；APK 对齐、1262 项 Flutter 资源、版本/翻译与关键原生库完整性门禁通过。实际中英文萌星名称与能力说明逐值核对，测试 TLS 私钥未打包。
- 大小 **288,139,348 B**；SHA-256 **`45D2D8C2386F4F86CAC83917472960D1725599FB5F03AA6852E039D331E0D84E`**。
- 签名校验通过，证书 SHA-256 `1e832295a696cf8210bca063e458bad0be12dfa64939d3362ff11b8f237ff7b9`，与先前 ae5232b2 归档 Debug 包一致；未读取手机当前证书，因此不将历史同签名当作已验证当前覆盖安装条件。
- 归档位置：`local-artifacts/candidates/android-96673538/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。复制后哈希复核，旧包哈希仍正确，未覆盖历史候选。
- 归档记录 `20260908T043901867Z-android-candidate-archive-96673538.json`：30.849 秒，峰值 CPU 65.2%、13,615,296,512 B，结束活跃重型进程 0。

通用 `local-artifacts/3.1.8-4121/` 中其他平台文件属于历史独立构建，目录列表不是本轮全平台构建成功。请使用上述不可变候选路径和对应元数据。

## 后续验收

保留既有15组累计 Android 原生场景，新增本候选 AVC 正常/待画面/停滞/EOF 及源保留验证，共16组待验。Windows 已通过的原生固定输入和真实双协议短录继续作为定位证据，不替代 Android 原生 FFmpeg 或界面验收。设备操作前仍按当前窗口、共享 purelive 租约、显式 serial、25102RKBEC/myron 和当前签名核验执行；覆盖安装保留数据，不重启、不清数据、不修改网络/Root/LSP。

历史矩阵仍为62项：20 PASS、32 RUN、10 NR，即42个未闭环大项；12组参考平台尚未注册。上述16组是候选专项，不与42项简单相加或当作剩余 Bug 数。全平台/长录/性能和正式3.2.0条件继续，未提前宣称完成。

本机证据目录：`local-artifacts/avc-stop-android-candidate-20260908/`，保留首次失败、重跑日志、签名结果、源冻结、16组 native-handoff、校验索引及终态 checkpoint。
