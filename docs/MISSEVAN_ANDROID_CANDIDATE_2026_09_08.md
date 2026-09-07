# 猫耳与分类收藏 Android 候选（2026-09-08）

**构建及内容核验完成；尚未安装，未发布。**

## 来源与产物

- 干净源码 `7aaecb8e80d6ad8116512a6207fa15b6f0ffe90b`，`tracked_files_dirty=false`。
- Android arm64-v8a Debug、debug 签名，包名 `com.mystyle.purelive`；版本仍 `3.1.8+4121`，Manifest code `6121`。
- 大小 **287,112,756 B**；SHA-256 **`47674FEA4D3A2923194A0DE49E032A8F6F3CF98398A84DE2D14EC68707872CB4`**。
- 独立归档 `local-artifacts/candidates/android-7aaecb8e/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`，同目录保留 BUILD_METADATA 与构建资源记录。复制后 SHA 再次一致。
- 命令 `tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`。
- 记录 `local-artifacts/build-records/20260907T182135897Z-build-androidarm64-debug.json`，耗时 297.849 秒，Gradle 247.8 秒，16 workers。
- 16 个原生 ELF LOAD 对齐至少 `0x4000`、APK 16 KB 对齐与内容门禁通过；1262 个 Flutter 资源、资源总大小 202,439,126 B。
- 峰值 CPU 66.65%、监视工作集 15,102,492,672 B；结束活跃重型进程数 0。保留增量缓存；Firebase KGP 未来兼容警告仍在，未为该警告升级依赖。

## 验证分层

本包包含 [猫耳应用接入](MISSEVAN_APPLICATION_INTEGRATION_AUDIT_2026_09_08.md)、[分类收藏身份](FAVORITE_AREA_IDENTITY_AUDIT_2026_09_08.md)及此前 TLS 所有权等修订。
构建复用本批 201/201 定向、19 文件 analyze、公开 API 1/1 与 Windows HLS/FLV 原生短录各 1/1、MP4 全段严格解码证据；没有把 `-SkipQuality` 描述成重跑完整质量门禁，也不把 Windows 原生结果外推为 Android 播放/录制通过。

旧 `android-b5f39c2b` 候选已保留并再次核对原 SHA，未被覆盖。手机最近有哈希核验的安装仍为历史 `80b7431c`，本轮没有重新读取设备安装状态。

## 下一步与边界

本轮没有 ADB、MT、Root、LSP、唤醒、切换前台或安装。手机切换窗口尚未确认；现存 `android-b5f39c2b-native-20260907` helper 仍绑定旧包，后续使用本候选前要更新其显式候选参数并核对。

获得切换窗口后，重新核对 `25102RKBEC / myron`、前台与服务，按 NoRotation 包装器和指定 serial 执行备份、保留数据覆盖安装及首次启动前 Hive/安装包哈希对照，再复验原 TwitCasting 录制与新增猫耳。无重启、adbd 重启、调试撤销、Wi-Fi/端口修改、卸载/清数据或模块更新。
完整 UI、长时租约、代理/relay 与其他平台缺口继续保留；本候选不是 3.2.0 稳定发布。
