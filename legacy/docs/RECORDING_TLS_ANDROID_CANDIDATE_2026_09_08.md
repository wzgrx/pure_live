# TLS 取消修订 Android 候选（2026-09-08）

本地日期09-08，构建记录使用UTC日期09-07。**新包构建完成，尚未安装，未发布。**

## 产物与来源

- 干净源码：`b5f39c2b29f6f756fe5ddd98e6a0e31ddf2f10b7`；元数据 `tracked_files_dirty=false`。
- 目标：Android arm64-v8a Debug，debug签名，包名 `com.mystyle.purelive`。
- 版本保持 `3.1.8+4121`，Manifest code `6121`；没有版本提升、上游合并或推送。
- APK **287,074,474 B**；SHA-256 **`016C3FC6248424459AFB78EC04603B1F0278BAE8BEDF2D0622A7A652D5EC183A`**。
- 独立保留：`local-artifacts/candidates/android-b5f39c2b/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`；复制后哈希与构建记录再次一致。
- 命令：`pwsh -NoProfile -File tool/build_local_release.ps1 -Target AndroidArm64 -Configuration Debug -SkipQuality`。
- 记录：`local-artifacts/build-records/20260907T160544871Z-build-androidarm64-debug.json`。
- 耗时411.089秒，Gradle312.7秒，16 workers；16个ELF全部LOAD对齐至少`0x4000`，APK16KB对齐、1262个Flutter资源及内容检查通过。
- 资源守卫峰值CPU70.55%、监视工作集17,116,979,200 B；记录结束活跃重型进程2，未声称全机归零。构建会话已退出0；后续只读观察仍有其他项目Gradle测试worker，未结束它或清除增量缓存。
- Firebase插件的KGP未来兼容警告保留，SDK/依赖未更新。

## 质量证据分层

包含[网络侧TLS所有权修订](RECORDING_TLS_OWNERSHIP_AUDIT_2026_09_07.md)及前批逐包刷新、完整响应暂存、尾片舍弃提示。复用该批56/56定向测试、原生四个HTTP上游停止场景和最后五文件analyze无诊断；不是本次重新执行完整测试或全部原生HTTPS/Android性能门禁。

此前c442380c候选不含TLS取消修订，保留作历史对照。手机最近有哈希核验的安装仍是80b7431c；本轮没有读取新的已安装哈希，也没有新安装证据。

## 手机边界与下一步

用户尚未确认从其他应用切换到Pure Live的窗口，本轮没有ADB、唤醒、前台输入、安装、Root/LSP/MT或代理修改。
`local-artifacts/android-b5f39c2b-native-20260907/` 已准备candidate.json及本地安装/录制helper；目录沿用本批UTC日期，仅准备并解析helper，不算设备执行。

取得明确切换窗口后重新核对型号/代号、前台、服务、进程及常亮原值，使用NoRotation包装器保留数据覆盖安装，核对首次启动前Hive字节和APK哈希。独立代理往返、原TwitCasting短录、严格完整解码及所有权清理仍待执行；保持现有用户远程设备约束。
