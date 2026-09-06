# 累计候选验收与主页横屏导航溢出（2026-09-07）

## 本轮范围与质量证据

基线 **`f867f799db0c9ed34bf92b6f1b5d99ff10ee9796`**，干净工作树，包含此前 WebDAV 表单、已保存选择、上传和文件操作互斥四批改动。本轮没有同步上游，也没有发布 3.2.0。

- 完整回归 **1283/1283 + 42/42 接口探针**，analyze 无诊断（406.2 秒）。`20260906T202900712Z-quality-full.json`，798.858 秒。
- Windows x64 Debug 成功：`20260906T203428098Z-build-windowsx64-debug.json`，全流程 1147.64 秒、编译 154.6 秒。原 CMP0175/MSB8028 警告仍存在，没有通过清空增量缓存隐藏。
- 初始 ADB 仅有 offline transport，故先构建 Windows；构建完成复查出现在线 `192.168.1.2:5555`（25102RKBEC / myron），按用户要求转到 Android。Windows 新候选尚未启动做 GUI 补证。
- Android arm64 Debug 成功：`20260906T204056106Z-build-androidarm64-debug.json`，282.307 秒、Gradle 257.3 秒；复用同一源码已经通过的完整门禁，以 SkipQuality 避免重复。包名 `com.mystyle.purelive`，开发版本仍 `3.1.8+4121`，实际安装包 code 6121。Firebase KGP 的未来兼容提示保留，未将 Debug 当正式签名发布包。
- 完整质量记录的结束活跃重型进程为 **1**；Windows、Android 构建记录均为 **0**，分别保留，不混用阶段资源结果。

## 产物身份和保留

| 产物 | 字节 | SHA-256 |
| --- | ---: | --- |
| Windows Debug ZIP | 141252773 | `0FA4651E8F7175FF6B7E337670DDF080D6DED7DC280D53DCB083B4F844EDC6D0` |
| Windows Debug kernel_blob.bin | 172423400 | `B9DB8E501D906CB7D7A213C8A6280F6A59A5CDBE1E6B69CDD0A366075D5574F4` |
| Android arm64 Debug APK | 286971424 | `9AD4A907070D4D09AAFF41E8F72E9464ABBC1876C24D93DCE9AE73DC22972240` |

Windows Debug 的 Dart 代码身份不单凭 runner EXE 判断。上述新产物位于 `local-artifacts/3.1.8-4121/`；该目录中旧 portable ZIP、setup.exe 和 Release APK 的存在不表示它们属于本轮构建。

旧 Windows `b5ab680d` ZIP/元数据保存在 `local-artifacts/candidates/windows-b5ab680d-debug/`，前后哈希一致；旧 Android `9c20ad11` APK/元数据保存在 `local-artifacts/candidates/android-9c20ad11-debug/`，APK SHA-256 `118E0ACC5CFFF3B91EA25D627859D9B623590F2D7A372CAAF968AF78E0E1B8DF`，同样通过复制前后校验。

## Android 实机结果：发现待修复问题

通过本任务 NoRotation 包装器操作本包，保留唤醒/常亮恢复与前台守卫。安装前先停止 Pure Live、备份其 Hive 配置文件；`adb install -r -t` 成功，安装前后的配置字节完全一致，没有卸载或清除应用数据。

首次截图守卫因查询 `dumpsys window windows` 未得到当前焦点字段而停止，尚未发出点击；改用实际返回焦点字段的 `dumpsys window` 后，活动与窗口焦点均核对为 Pure Live，再重新截图。这是辅助脚本的兼容问题，不计为应用启动失败。

实际界面保持设备原来的横屏状态：截图 **2608×1200**，设备物理规格 **1200×2608 / 480 dpi**，系统字体倍率 **1.0**。首页左侧导航底部显示溢出条。对应本包日志明确记录：

> A RenderFlex overflowed by 168 pixels on the bottom.

定位为 `lib/modules/home/tablet_view.dart:87` 的 NavigationRail，而非 WebDAV 页面。底部目标被截断，当前结果为 **FAIL，尚未修复**。证据为 `local-artifacts/webdav-cumulative-native-20260907/android-home.png`、同名 XML、`android-overflow.log` 和安装核验 JSON；原始配置副本含用户数据，只留本地忽略目录，不加入 Git 或发送到服务。

## 初步源码定位和下一步

- HomePage 在宽度大于 680 时使用 HomeTabletView；手机横屏也进入该分支，不只是平板或 Windows。
- NavigationRail 的 leading 放置菜单、多画面、工具箱、搜索和录制入口，随后还有启用的目的地；没有可滚动或高度适配设置，短高度容纳不下这些内容。
- 只读核对冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`，同样的 NavigationRail、groupAlignment 和 leading 结构没有滚动配置，因此该根因暂归 **upstream-existing**。不声称这是远端最新版本。
- 固定 Flutter 3.47.0 的本地 SDK 已支持 NavigationRail.scrollable 与 leadingAtTop。后续先增加真实 HomeTabletView 短高度/大字体回归，再设计让工具入口与目的地均可访问的滚动布局；不能只裁切内容或仅让剩余目的地挤进极小视口。
- 完成源码修复后重新构建对应候选，先复验本例，再继续累计 WebDAV 的原生表单/存储选择/传输补证。现有完整测试并没有覆盖这个实际横屏组合，不能作为界面全通过的证据。

## 收尾与剩余范围

本包已停止，设备包装器恢复原有常亮策略，没有操作其他应用。第一次停止后的“进程不存在”负断言保留了 pidof 的预期退出码 1，被包装器误记为失败；随后单独复核进程确实不存在、ADB 在线并正常结束，证据 `android-cleanup-verified.log`。

原先准备的 Windows loopback WebDAV 服务只做过自身预检，UI 请求日志为空，没有用户上传、恢复或删除；服务进程按确切脚本身份停止。Windows 没有新 AppData，未启动 GUI。用户安卓配置没有导入测试备份或替换为测试目录。

WebDAV 原生补证、主页溢出修复以及其余全平台/长时矩阵继续。新 APK、ZIP 的存在不等于 3.2.0 已验收或发布。
