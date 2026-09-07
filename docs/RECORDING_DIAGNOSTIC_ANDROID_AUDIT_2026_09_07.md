# 停止诊断 Android 候选与实机（2026-09-07）

接续[源码及本机原生门禁](RECORDING_STOP_EVIDENCE_AUDIT_2026_09_07.md)。本轮有实际覆盖安装及 Picarto 短录，**整轮仍为 FAIL：自动代理收尾未通过**。独立恢复与最终清理已完成，没有手机/adbd 重启、端口/Wi-Fi/授权变更、Root/LSP 更新、卸载或清除数据。

## 构建

- 干净源码 `1aa6886f4e6f02c55b895aff57d81ece8063cd3c`，Android arm64 Debug，3.1.8+4121 / Manifest 6121。复用本批85/85定向、analyze与两个本机原生探针，不外推整库完整门禁。
- 记录 `20260907T095001315Z-build-androidarm64-debug.json`，248.667秒（Gradle216.2秒），workers16，结束活跃重型进程0。Firebase KGP未来兼容警告保留。
- APK 287,027,881 B，SHA-256 `C6E6305FC553CC15F182ADCA6BB0E6E05DBFE8C1D396C556B9EF46D60BE7B16B`。16个原生ELF LOAD≥0x4000、APK16KB对齐、1262个Flutter资源通过。
- 独立归档 `local-artifacts/candidates/android-1aa6886f/`；旧2006c044/af88a032归档哈希再次验证一致。没有升版、推送或发布；目录中历史Windows/Release文件不属于本轮构建。

## 安装与数据

型号/代号多次明确 `-s 192.168.1.2:5555` 核对为25102RKBEC/myron，在唤醒前先验身份；应用操作通过NoRotation包装器。用户提供的MT位于前台时，只明确启动本项目，不操作MT内部功能。

09:50:55–09:51:21 UTC，`adb install -r -t`成功，设备base.apk与上述SHA一致。备份主Hive161,106 B，安装前与安装后首次启动前SHA均为 `7D62749BFD1BD6DBD5EBFCBB4112D1D4559BC89856F863C413119CCD33D4D4FA`，字节一致。此证据只覆盖主Hive，不冒称逐一验证全部用户文件。首次启动后SHA变化为 `3DD44356A3C2F26AD7B4DCF66BBFD0E53E58EFE5AC24E50A623EFD74ACDED11F`，不声称启动后仍字节相同。

冷启动Total2053/Wait2059ms。首页截图已查看，四个现有关注卡片正常显示；主配置及截图留本机忽略目录 `local-artifacts/android-1aa6886f-native-20260907/`。

## Picarto实机短录

先独立验证两个代理开关开启/恢复及session对账，通过；再执行 `android_foreign_recording_smoke.ps1 -Platform picarto -RecordSeconds 20 -ExerciseStreamSelection`。

证据 `local-artifacts/diagnostics/android-recording-smoke-20260907T175408445/`：

- 实际进入HuckleberryBleu房间，播放截图可见视频，头部Picarto翻译键已正确显示。默认头像仍为空，日志含图片加载问题；该缺口未修复。只有720p30与线路1，实际切换记SKIP；远程弹幕未接入，视频画面里的聊天不是应用弹幕能力。
- TS从3,145,728增长到3,670,016 B，观察间隔14,392ms；墙钟录制26.63秒。启动观察15,993ms、停止完成观察3,720ms含UI操作/采样，不当作纯引擎耗时。
- **手机真实采集终止日志**：code=0、manualStop=true、stopRequested=true、stopElapsedMs=799、inputDrainKind=hls、inputDrainBudgetMs=20000、inputFinishRequested=true、forcedCancel=false、inputDrained=true、inputIntegrityError=false。新字段已上机，正常封装终止则无停止请求。
- MP4 8,387,211 B / 25.054秒，SHA-256 `3C10D5541A822994B2B910FD22911978B4F5C8B3EB6E96858A27F06011335F42`。主机FFmpeg对全部音视频执行 `-xerror -err_detect explode` 解码，**退出0、错误日志0 B**，记录 `decode-result.json`。
- 录制监控已取消，无FATAL/ANR，进程及本应用唤醒锁消失。本次输入健康，**没有触发Android损坏源保留分支**；该分支仍只有本机真实原生损坏对照，不把本次健康录像当作损坏分支实机PASS。

这份健康文件与旧损坏录像是不同采集，不证明旧损坏原因已被修复。长录/后台/续接/多平台仍待验。

## 自动代理恢复失败与明确清理

整轮断言仅proxyRestoredBeforeStop失败：`Proxy UI item not found within observed scrolling: 启用应用层代理`。随后停止本应用回到MT，外围清理守卫停止，没有抢回其他应用；自己的reverse已移除，两个开关的恢复仍记cleanup-pending。

实际XML显示，旧的“嵌套滚动容器歧义”已不再报错，但仍停留在设置页：`proxy-ui-5/6.xml`代理入口可见范围为[48,312][1152,486]，后续末帧为[48,312][1152,361]。浮动播放器可点击区域[390,300][1050,671]；当前工具点击节点中心(600,399)落在该区域内。**重叠拦截是由几何与源码支持的待验证解释**，不是已获取Android实际命中事件。下一步以这组真实XML建立遮挡/路由进入回归，避免继续盲点中心或反复滑动。

已告知用户后，从MT前台明确冷启动本项目，按本轮session恢复两个原开关为false；10:00:04 UTC恢复成功。session `foreign-proxy-session-d95d6ac6fea44767a5d02eb16f5cbb24/session.json`为restored，ownedReverse/reverseUncertain/uiMayHaveChanged均false。

10:01:24 UTC最后只读核验：同一型号/代号，本应用进程不存在、tcp:7897 reverse不存在、本应用唤醒锁不存在，session已恢复。包装器finally释放常亮，StayAwake=false。没有使用Root、lspctl或MT MCP修改应用。
