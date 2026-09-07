# 累计候选门禁与原生交接（2026-09-07）

本阶段停止扩展辅助页源码小批次，固定累计应用源码 `182374945f093642e82fb24a2bb56ce6f3533d4a`，先完整门禁，再 Android arm64 Debug 与保留数据覆盖安装；目标仍是全范围验收后才发布 3.2.0。旧 `67612cc9` APK 已复制至本地候选归档并核对原 SHA-256，不覆盖回滚副本。

## 首次完整门禁

- `20260907T014542936Z-quality-full.json`：**1520/1522 测试通过**，analyze 无诊断（86.3 秒），全流程 288.356 秒，结束活跃重型进程 0。测试失败后接口探针没有执行。
- 两项失败均在 `video_processor_lifecycle_test.dart`，取消活跃转封装及原生失败后立即检查 `.partial` 文件不存在；实际当时仍存在。该文件与录制业务代码不在本阶段播放器/工具箱改动范围。
- 构建入口按门禁停止，`20260907T014543093Z-build-androidarm64-debug.json` 为 failed，outputs 为空；没有启动本次 Gradle 编译、生成或安装新 APK。旧产物留存不等于这次构建通过。

## 测试时序诊断与修訂

原测试所有场景共用 30 ms 注入期限，但使用真实临时目录 I/O。转封装超时合同允许在原生执行未结束时先返回失败，持有目录/任务直到原生结束再异步清理；所以非超时用例受额外期限干扰时，返回 false 不代表清理已结束。此前 `9c20ad11` 已对部分超时测试及 teardown 使用所有权释放等待，两个上述场景仍遗漏。

不改源码的独立运行 **8/8 通过**：`20260907T014829498Z-quality-focused.json`，78.787 秒，结束活跃重型进程 0。该结果说明失败依赖调度条件，不作为全量失败已解决的替代证据。

本次仅修订测试：普通取消、成功和失败场景使用原有生产期限，按显式 native started/finish 信号推进；只有三个专测超时的用例设置 30 ms，原 300 ms 防逃逸断言保留。取消/失败的文件断言之前等待既有、最多 2 秒的真实任务所有权释放；源片保留、部分文件删除和互斥释放断言全部保留，没有用固定睡眠代替状态。移除进度测试覆盖 service 实例导致的多余控制器创建。没有改动录制业务超时、清理或数据规则。

修订后独立 **8/8 通过**：`20260907T015041827Z-quality-focused.json`，78.364 秒，结束活跃重型进程 0。日志 `local-artifacts/cumulative-finalization-fixture-fixed-20260907.log`。接下来需在干净提交重新完成全量门禁，成功后才继续编译；此处尚未写成累计门禁通过。

## 设备状态与待执行

只读核对 `-s 192.168.1.2:5555` 返回 `25102RKBEC / myron / Android 17`；devices 有多个指向同一手机的 transport，后续仍指定该编号。forward 列表存在 `tcp:18787 → tcp:8787`，尚未在本阶段执行 MCP initialize/tools/list，因此不声称 MT 接口或具体会员能力已重新验证。

本阶段尚未唤醒/安装/点击/旋转手机，没有改 Root/LSP、ADB 端口、Wi-Fi 或调试授权。准备的本地 Android 帮助脚本只做了语法检查，使用前要按实际新候选 SHA 更新元数据断言。下一轮应先读 `local-artifacts/cumulative-candidate-work-state.json` 与已启动会话的结果，避免重复构建。

真实平台、DLNA 接收器、Android/Windows 原生流程和长时验收继续，历史账本 42 个未闭环大项不变。

## 最终累计质量与 Android 候选

测试修订提交 `af88a032f53e389ea4260ae916f53ea73f53f393` 上重新执行完整门禁及构建；工作树干净，应用源码与 `18237494` 相同。

- **1522/1522 单元/Widget、42/42 公开接口探针通过**。analyze 无诊断，79.0 秒；记录 `20260907T015733844Z-quality-full.json`，323.969 秒，结束活跃重型进程 0。前文失败保持历史，不再作为当前门禁状态。
- Android arm64 Debug 构建成功，`20260907T020239405Z-build-androidarm64-debug.json`。含完整质量的总流程 628.651 秒，Gradle 275.3 秒，结束活跃重型进程 0；16 workers，16 个原生库、ELF 最小 LOAD 对齐 `0x4000` 和 APK 16 KB 对齐校验通过。
- 版本仍 **3.1.8+4121 / Manifest code 6121**，包 `com.mystyle.purelive`，不是正式 3.2.0 发布包。原 Firebase KGP 未来兼容警告保留，没有因警告更新依赖。
- APK **286,998,845 B**，SHA-256 **EFD5A76AE8B4A8823B95FC50087EEBC5999690C7E796E39F9A41FFFF82C130E8**；路径 `local-artifacts/3.1.8-4121/PureLive-3.1.8-4121-android-arm64-v8a-debug.apk`。BUILD_METADATA 核对目标、源码 SHA 和 tracked_files_dirty=false。Windows 文件仍为历史产物，本次没有新 Windows 构建。

## Android 原生安装与首页横屏补证

明确 `-s 192.168.1.2:5555` 再核对型号/代号后，经 `run_android_device_test_turn.ps1 -NoRotation -Serial ...` 执行两个有界轮次。

1. 只停止 Pure Live，备份主 Hive 文件，`install -r -t` 覆盖安装。安装前后 app_settings.hive **268,399 B 逐字节一致**；设备 base.apk SHA 与上述候选完全相同。随后启动并抓取竖屏、横屏首页。
2. 重新启动本应用并横屏，依据本次 UIAutomator 树定位左侧唯一竖向 ScrollView，在该范围向上滑动；滚动前后截图及 XML 均保留。滚动后“关注／热门／分区”三个目的地矩形均完整位于可视范围，主页卡片仍显示，无可见溢出条纹。本轮 PID 3712 的 flutter:E / AndroidRuntime:E 采样为空；这不是长时稳定性结论。
3. 第一次本地语义检查把上方“录制中心”工具快捷键误称为底部导航项；图像复核发现命名错误后，使用已录制的 XML 对真实三项导航分别验证完整矩形，修订 result.json，不伪称点击或打开了录制中心。本轮仅滚动导航，没有进入播放、历史或工具箱。
4. 两轮均恢复 `accelerometer_rotation=1 / user_rotation=0`，停止 Pure Live，包装器释放临时常亮；cleanup.json 与包装器退出码均成功。没有重启手机/adbd、改 Wi-Fi、修改 ADB 端口、撤销授权、更新 Root/LSP 或调用 MT。

证据目录 `local-artifacts/cumulative-native-af88a032-20260907/`：安装/哈希记录、portrait/landscape PNG/XML、rail-scroll/before/after PNG/XML、语义验证、日志及清理结果。原配置备份只保留本地忽略目录。此证据补足此前 `67612cc9` 因前台变化中止的首页横屏子场景，不把 A1-01 或整套 UI 直接改为 PASS。

**下一步**：复用已安装 `af88a032`，集中验证累计历史/公共刷新、WebDAV、工具箱输入与直链、播放器菜单选择/取消；再推进播放器组合、平台录制与性能工作组。没有新源码变化时复用该包与完整门禁，不按微步骤重编译。实际 DLNA 接收器和 Windows 原生增量仍待完成；历史大项仍 42 个未闭环。没有版本递增、推送、发布或全目标完成声明。
