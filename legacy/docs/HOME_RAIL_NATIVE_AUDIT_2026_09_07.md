# 累计候选验收与主页横屏导航溢出（2026-09-07）

## 后续源码修复：整条导航独立滚动

以文档提交 `350e9833` 为基线，保留下面 `f867f799` 的原生失败证据；本节是随后进行的源码修复，不代表旧 APK 已修好。

- 固定 SDK 的 NavigationRail 默认 `leadingAtTop: true`、`scrollable: false`。仅打开 scrollable 只会滚动目的地，工具列仍占固定高度。本次同时设置 `leadingAtTop: false`，菜单、多画面、链接解析、搜索、录制和目的地一起滚动；不裁掉入口或缩小文字。
- `groupAlignment: -1` 将整组从顶部排列。高窗口也采用同一顺序，原来目的地靠下的空白分隔不再保留，这是明确的布局变化；目的地 ID、选中映射、回调路由及用户配置均保持原语义。
- 在轨道外使用 `PrimaryScrollController.none`，隔离 Android 默认继承的正文滚动控制器，避免两份滚动位置附着到同一个控制器。
- 为链接解析、搜索和录制按钮补齐既有翻译键 tooltip，支持图标语义与鼠标悬停提示；没有新增或改动翻译资源。

### 红测和测试范围

初始两个真实 HomeTabletView 短高度红测在旧源码上分别产生 **120 px / 68 px RenderFlex 溢出**，记录 `20260906T210749234Z-quality-focused.json`。初版尚未加载中文资源、没有设备系统安全边距，因此这组数字与原生的 168 px 不作等值比较；证明的是相同固定高度结构失效。此前格式预检查失败发生在测试执行前，记录 `20260906T205709649Z-quality-focused.json`，不计为红测。

最终测试加载真实中文资源、临时 Hive 和真实 HomeTabletView；路由目的页使用轻量占位页，只验证入口路由契约，不冒充目标功能页验收。扩展测试最初因 GetMaterialApp 的路由表未注册根页而失败，修正为显式 `/` 根路由，并在每次打开时断言真实 HomeTabletView 已挂载。这属于测试夹具修正，不计应用回归。

| 场景 | 断言 |
| --- | --- |
| 869×400、900×260、1200×1000，各 1× / 2× 文字 | 无溢出；滚动至分区并点击得到真实索引 2，再回到菜单打开设置入口 |
| 排序、未知 ID、单一目的地和当前选择隐藏 | 真实索引映射保留；隐藏选择为 null |
| 空目的地 | 显示空态，菜单仍可打开，正文不错误显示 |
| 可选录制/多画面 | 显隐遵守原配置，多画面动态切换后布局仍有效 |
| 链接解析、搜索、录制、多画面 | 图标滚动后可命中，进入对应命名路由 |
| Android 正文与轨道 | 正文控制器只有一个 position；两侧滚动位置互不变化 |
| Windows 鼠标滚轮、短窗口拉高 | 最后目的地可访问；拉高后菜单和最后目的地均可命中 |

16 项中间回归已通过（`20260906T212035383Z-quality-focused.json`，67.604 秒，结束活跃重型进程 0）；随后补充多画面路由用例。最终 **25/25 通过（17 项导航 Widget + 8 项应用设置回归）**，**analyze 无诊断，执行一次、224.7 秒**。记录 `20260906T212759737Z-quality-focused.json`，全流程 342.524 秒、结束活跃重型进程 0；日志 `local-artifacts/home-rail-final-20260907.log`。记录中的源码基线是 `350e9833`，验证对象包含本批尚未提交的 Dart 差异；不是下面旧候选的完整门禁。重型任务按共享守卫排队，未终止其他工作区的 Java 构建。

### 原生复验与回滚边界

本修复尚未重新打包或上机，下面旧候选的原生结果仍为 FAIL。下一阶段构建包含本修复的候选，核验源码/包哈希，保留设备配置后复验横屏截图、底部目的地、返回菜单和页面入口，再继续累计 WebDAV 原生补证。Windows Widget 鼠标测试不等同 Windows GUI 验收。

回滚范围为本批 `tablet_view.dart` 和新增的 `home_tablet_view_test.dart`；没有存储迁移。旧 `f867f799` 构建已保留哈希，回退时仍须保留其已知横屏缺陷标记。开发版本仍为 3.1.8+4121，3.2.0 全平台验收和发布继续等待实际完成。

## 本轮范围与质量证据

> 后续候选准备补记：`11264976` 之后重新发现 ADB，设备同时通过两个 IPv4 端口和一个 mDNS transport 在线，均报告 myron / 25102RKBEC。不是三部不同手机。旧设备包装器既没有 Serial 参数，也未将 `PURELIVE_ADB_SERIAL` 传给首次唤醒，因此自动选择歧义时提前失败；其 finally 还会尝试清理未成功获取的旧环境目标。这是本地测试基础设施缺陷，不是应用离线或首页回归。
>
> 包装器现接受 `-Serial`（默认取进程环境），编码传参、清理绑定实际成功的唤醒结果。**7/7 离线夹具通过**，覆盖参数优先级、自动选择、唤醒失败、正文失败、正文更改编号以及输入按数据传递；首轮 5 个红测均失败。日志 `home-rail-wrapper-red/green/final-20260907.log` 位于本地忽略目录，最终耗时 24.715 秒，静态构建策略检查通过。明确指定 `192.168.1.2:5555` 的实际包装器预检随后通过、常亮清理通过，证据 `home-rail-device-preflight-fixed-20260907.log`；尚未安装新候选或点击应用。旧 `f867f799` APK 和元数据已复制到 `local-artifacts/candidates/android-f867f799-debug/` 并核对复制前后哈希一致，为后续构建保留回退证据。

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
