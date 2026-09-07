# TwitCasting Cookie 修复候选 Android 复验（2026-09-07）

接续[首段401与源码修复审计](TWITCASTING_ANDROID_NATIVE_AUDIT_2026_09_07.md)。本轮完成80b7431c构建、保留数据覆盖安装、实际短录及严格解码；**首段401已在本场景解除，但文件解码失败，整体原生录制验收仍为FAIL。** 未提升版本、未发布3.2.0。

## 候选与安装

- 源码 `80b7431c0771ff502bb6e9966b2540dc94d7ba2b`，干净Android arm64 Debug；复用上一批57/57定向测试、修订范围analyze无诊断及生产转发HTTP探针1/1，不冒充全库门禁。
- 构建记录 `20260907T123735885Z-build-androidarm64-debug.json`：566.839秒，Gradle465.0秒，workers16，结束活跃重型进程0。APK **287,054,981 B**，SHA-256 `D965095AC696FC98D000E89542835F98C8A0C30DA0DF54EF4089D19571762E8D`。3.1.8+4121、Manifest6121、16个ELF LOAD≥0x4000、APK16KB及1262资源检查通过。Firebase KGP未来兼容警告未通过擅自更新依赖消除。
- 归档 `local-artifacts/candidates/android-80b7431c/`，源包与副本哈希一致。公共目录其他平台/Release产物为历史文件；Windows仍是2d8e4e0c。
- 12:38:34–12:39:24 UTC，明确 `-s 192.168.1.2:5555`，唤醒前与正文分别验证25102RKBEC/myron。从MT前台仅启动本项目，安装前本包无活动service，`install -r -t`成功，设备APK哈希一致。
- 主Hive **84,400 B**，安装前与安装后首次启动前均为 `4DE2C4493372B8BBC397A6B8E696F56B866685130B0ABE97FBA63F52A8A7E747`；备份保留。本次证明主Hive在覆盖安装时字节一致，不扩写为逐一验证全部用户文件。首次启动后SHA `649BA462FBB7C0087284D87C57539EBDC99B678AB799CE7BD8EF6B6186AFFFFA`。
- 冷启动Total2079/Wait2085ms；已查看首页PNG，5张现有关注卡片正常。安装及后续测试均经NoRotation包装器，没有重启手机/adbd、卸载、清数据、修改Wi-Fi/调试授权/ADB端口或Root/LSP/模块。

## 原生过程与有限通过项

`local-artifacts/diagnostics/android-recording-smoke-20260907T204208131/`，20:42:08–20:46:15本地时间，公开频道 `el6_jil_` / JIL@EL6💎。

- 独立代理开启/恢复先通过，再开始短录代理事务。目录/房间与三档HLS可操作；high→low状态提交并稳定，7872ms。单线路及未接入的远端弹幕为SKIP；此次未熄屏，后台各项为SKIP，不采用旧布尔assertions中的条件true冒充覆盖。
- `room-before-record.png`仍是黑色视频区；`room-recording.png`已实际显示虚拟主播画面，且为low选择状态。这证明本场景low最终出现画面，**不证明high首次起播、首帧耗时、持续音频或所有播放器模式通过**。
- 请求录制30秒，实际墙钟39.019秒；两次增长采样524,288→1,048,576 B，采样门禁耗时28.971秒。完成MP4 **2,253,538 B**，容器时长19.733333秒，H.264 1920×1080、声明30/1、AAC48kHz双声道。录制选high，独立于播放器low，不是错误继承了播放器档位。
- MP4 SHA-256 `EE19EB612ED73B67C48C91E3854999C16572D01F4E06DF1C8B7CCE7599E7D2D7`。原生脚本返回0、metadata/清理门禁通过；这层检查不等于严格内容解码通过。
- 本轮预检XML明确“立即启动录制”enabled/clickable=true，“停止录制/取消监控”均false；日志没有预检停止/取消旧监控动作，之后取消的是本轮新建任务。证据 `preflight-ownership-observation.json`。

## 严格解码：FAIL

本机FFmpeg对完整文件同时映射视频与音频，以 `-xerror -err_detect explode`严格解码到空输出，返回 **-1094995529**，错误日志 **647 B**：H.264宏块89,44处bytestream -5 / Invalid data。不得以成功remux、文件非空或ffprobe有音视频轨道覆盖此失败。

原生日志：录制session1返回0、media=true，但 `manualStop=true, stopElapsedMs=6056, inputDrainBudgetMs=6000, forcedCancel=true, inputDrained=false, inputIntegrityError=false`；合并session2返回0。当前显式损坏标志没有覆盖本次内容损坏，原TS已经不在录后文件列表；MP4与全部诊断仍保留。

进一步只读本地包时间线/解码诊断：

- 视频232包、音频348包；MP4样本时长异常项分别在视频3.966秒附近延展4.033秒、9.966秒附近延展8.033秒；对应音频为4.010667/8.021秒。容器duration会把这些时长计入，故19.733秒不等同连续正常内容。
- “DTS差减前包duration”的gap列表为空，只因为MP4样本duration由时间差描述；**不据此宣布不存在丢包/时间跳变**。是否上游直播、实时窗口跳段或本地转发/停止行为造成，需要源侧与确定性对照。
- verbose严格解码在约19.2秒附近出现首个H.264错误；3秒处单帧严格提取成功，已查看为实际1920×1080主播画面。支持“存在正常前段且错误位于尾部附近”，但没有精确到损坏包来源的因果证据。
- `forcedCancel`与尾部错误同时出现，尚不等同证实取消是唯一根因；此前Picarto存在强制取消却完整解码健康的对照。禁止仅增加超时或降低校验来消除红项。

严格解码记录 `20260907T124741033Z-twitcasting-android-recording-decode.json`为failed；包检查记录 `20260907T125157440Z-twitcasting-packet-timeline.json`为succeeded，后者只代表诊断执行成功。两个任务均受资源守卫保护，结束活跃重型进程0；外部Java忙时排队，未停止它。

## 清理核验

当前录制session精确为 `9873a15d69cf4910b5918b90f54de044`，独立往返session在本轮root的proxy-roundtrip中，二者均restored。**12:47:25 UTC**再次只读核对：型号/代号一致，原两个代理开关关闭、reverse与空基线一致，本包进程和活动唤醒锁消失，脚本报告本轮监控已移除。包装器最终StayAwake=false。没有独立解析Hive证明监控取消已落盘，不扩大UI证据。

本轮安装/包装器/最终清理证据根为 `local-artifacts/android-80b7431c-native-20260907/`；录像与诊断保留在上述smoke目录，全为本机忽略产物。

## 下一步（尚未实现）

1. 优先用本机生产FFmpegManager和确定性HLS/fMP4源复现慢速分块传输、在途停止、短实时窗口跳段；同时核对4秒/8秒样本延展及尾包错误。先复现再改relay/drain，避免反复占用手机。
2. 检查强制取消但未标记损坏的attempt在合并/删源时的完整性判定；保留不确定来源不是宣称所有强制取消都损坏，更不是用只修保留策略替代修复输入/停止根因。
3. 后续实机前修订测试器的旧监控保护：当前 `android_recording_smoke.ps1`预检仍包含停止/取消已存在监控的分支；本轮禁用状态证明未触发，但它不应在未来房间碰撞时删除用户任务。修订要连同失败finally中的force-stop所有权一起测试，不能只在预检throw后又停止用户已有录制。本轮没有继续执行第二轮设备输入来碰这个边界。
4. 首帧/首次high播放、长录/后台、直播会话更新和全平台验收继续；全目标、全库正式门禁、全平台3.2.0发布均未完成。
