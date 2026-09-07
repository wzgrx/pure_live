# TwitCasting Android 候选与原生验收（2026-09-07）

接续[源码接入与HTTP验证](TWITCASTING_ADAPTER_AUDIT_2026_09_07.md)。本批先构建及保留数据覆盖安装，再独立核对应用代理往返，随后执行播放/切档/短录/清理。实机短录失败，已定位HLS会话Cookie丢失，见下文；不将源码修复写成原生通过。保持3.1.8+4121，未发布3.2.0。

## 构建与归档

- 干净源码 `1a18f353bacb905c511a3fb0afd94ac76e7acecf`，Android arm64 Debug。复用81/81与53/53定向回归（两组有重叠）、修订范围 analyze 无诊断及生产HTTP探针1/1；本次没有重跑完整全库测试。
- 构建记录 `20260907T113143750Z-build-androidarm64-debug.json`，506.250秒，Gradle432.9秒，workers16，结束活跃重型进程0。Firebase KGP未来兼容警告仍保留，未为消除警告更新依赖。
- APK **287,047,863 B**，SHA-256 `CE018262565139AEA22AECA7D316639D3D9C18C7F1C23EC34AEF4DF1FC1F992C`，包名com.mystyle.purelive，Manifest6121（基础4121+arm64偏移2000）。16个原生库LOAD≥0x4000、APK16KB对齐、1262个Flutter资源检查通过。
- 独立归档 `local-artifacts/candidates/android-1a18f353/`，副本与构建原包SHA一致。公共产物目录中的历史Release/Windows包不是本轮新构建；旧候选归档保留。

## 设备与安装

明确 `-s 192.168.1.2:5555`，唤醒前及正文再次核对25102RKBEC/myron；其余两个transport是同机的无线别名，本轮不用默认设备选择。设备步骤经NoRotation包装器；从用户打开的MT前台只启动本项目，没有操作MT内部功能。

11:34:59–11:35:26 UTC，`adb install -r -t`成功；安装前核对本应用无活动service。主Hive备份 **149,795 B**，安装前与安装后首次启动前SHA均为 `84A1005505657575214989C31F3CBD1CD3B0DE54E3C9900D631BA115F914EACE`，字节一致；这是主Hive的证据，不扩大为逐一验证全部用户文件。首次启动后SHA正常变化为 `1605F4697373CB7F056FD0D05632FC769B423283A0D43033700E6696E62C9ED4`。

设备base.apk SHA与候选一致；冷启动Total2041/Wait2147ms，首页PNG已查看，现有关注卡片显示正常。证据 `local-artifacts/android-1a18f353-native-20260907/` 含install-home.json、配置备份、home.xml/home.png和包装器日志，全部仅留本机。安装轮次常亮已恢复。

## 原生验证

### 实机结果：FAIL

证据 `local-artifacts/diagnostics/android-recording-smoke-20260907T193740654/`，包装器退出1。公开频道 `el6_hrk`，电影ID `840592921`。目录、房间UI进入成功；HLS high → low选择已提交且状态稳定，耗时8284ms；单线路没有切线证据，远程弹幕尚未接入，均为SKIP。

**播放未验收通过。** 实际查看 `room-before-record.png` 与 `quality-switch-committed.png`，视频区域黑色；日志只证明解码器初始化，没有首帧或可听音频证据。此前即时进度将“播放通过”说得过早，已向用户明确更正；是否该直播本身为音频/黑画面仍待独立验证。

短录4次attempt均未产生正字节增长，FFmpeg返回 `-825242872`，`media=false, seconds=0, bytes=0`。首个分片401，脚本于 `android_recording_smoke.ps1:667`退出；没有可做严格解码的MP4，不计录制文件PASS，也不把它归因于旧Picarto的损坏包问题。终态 `inputIntegrityError=false`，非手动停止，未强制取消。

### 清理与状态回账

- 独立代理往返成功；实际录制轮次代理session `f5fd8407f0c44c769a96ba45967e833c`于11:41:11 UTC恢复，两开关回到原关闭状态，ownedReverse/reverseUncertain/uiMayHaveChanged均false。
- 原始失败summary保留 `monitorRemoved=false`，未重写成成功。之后仅定位本轮 `twitcasting_el6_hrk`、19:39创建的唯一卡片，确认“取消监控”，恢复“全部”筛选，保留原有其他监控并停止本应用。UI移除记录在 `monitor-cleanup/removal-result.json`；本次没有独立解析Hive证明该移除已落盘，不扩大UI证据。
- **11:55:25 UTC最终核验通过**：25102RKBEC/myron一致，Pure Live进程消失、活动唤醒锁区无本包，reverse与空基线一致，当前录制与独立往返两个精确session均restored。包装器最终StayAwake=false。记录 `local-artifacts/android-1a18f353-native-20260907/final-cleanup.json`。

### 根因复现与源码修复边界

11:56:46 UTC对同一公开频道/电影、同一初始化段和媒体段进行匿名HTTP对照：

| 资源 | 不带Cookie | 带播放列表签发Cookie |
| --- | --- | --- |
| init.2.mp4 | 401 / 13 B | 200 / 1,095 B |
| media.1658.mp4 | 401 / 13 B | 200 / 1,054,092 B |

Cookie为CDN在公开播放列表响应签发的host-only、`/tc.livehls/v1/streams/840592921/hls/`路径会话，不是登录账号凭据；对照JSON只留名称/属性，不保存值。原生IJK日志亦可见Set-Cookie及后续Cookie头，但不足以单独证明可见播放。匿名原始日志仍仅留本地，未提交。

来源分类 **fork-regression**：维护分支 `e35247d03849e12e0b5aedf1079c64e56fdb056f`新增TLS HLS转发器时，没有消费上游Set-Cookie，也未向后续初始化/密钥/媒体请求传递会话。TwitCasting接入暴露了既有转发缺口；本轮没有新上游合并。第一个错误状态是成功获取播放列表后丢弃会话，而不是FFmpeg最终退出。

修订采用单relay、仅内存、限额的会话存储；原始调用方Cookie/Authorization仅原origin发送，重定向逐跳处理响应Cookie并重算作用域，最多5跳且拒绝HTTPS降级。Cookie遵循路径大小写/目录边界、Max-Age优先、过期/删除；对Domain进一步收窄到签发origin，不支持跨origin共享。每个relay最多64条、总16Ki字符、单条4Ki字符，极端Max-Age最多一年；关闭时清空。没有浏览器/账号Cookie读取、全局持久化、依赖升级或TLS校验降级。路径/期限依据[RFC 6265](https://httpwg.org/specs/rfc6265.html)；这是受限媒体会话存储，不是完整浏览器Cookie实现。

录制HLS为直接影响面；播放器本身、FLV输入、UI/弹幕/画中画和配置迁移未改。最初本地回归在旧实现稳定得到200预期/401实际，之后再改生产代码。定向门禁和生产转发HTTP补证见下一节；手机仍安装旧1a18f353，修复候选构建/覆盖安装及完整实机复验尚待执行。回滚点为1a18f353，回退本批relay与新增会话存储文件即可，保留数据不动。

## 源码验证

- **57/57定向回归通过**：HLS转发14、会话存储8、TwitCasting适配32、录制代理路由3。覆盖首段401复现、初始化/媒体会话、重定向旋转与跨origin凭据隔离、并发relay隔离/关闭、重定向上限、路径大小写与边界、期限/删除、异常Cookie、数量/大小上限，以及旧的Range、停止冻结、在途请求、资源回收与FLV代理合同。
- **修订范围Dart analyze：No issues found。** 范围为两个生产文件、两个测试文件与生产探针；没有全库重新验收或新构建。
- **真实生产转发探针1/1通过**：12:24:02 UTC，目录新选公开频道 `el6_jil_`、电影840596017；原 `el6_hrk`已下播，原探针明确因live=false失败，日志保留，没有复用旧电影URL。新请求使用实际生产relay、正常HTTPS校验与本地Clash；初始化段200 / 1,095 B，媒体段200 / 527,411 B，Cookie计数1、关闭后0，未向本地读取端返回Set-Cookie，也未保存Cookie值。
- 本次生产探针属于HTTP层，不是FFmpeg录制文件或Android播放PASS。实机失败项继续保留。

门禁记录分层保存，未将失败流水线改写成全绿：最初local_ci因格式检查提前退出；精确红测 `20260907T120203432Z-hls-cookie-red.json`实际复现401。首次绿测发现Dart非法Cookie抛HttpException，生产代码已处理；另有日志测试夹具初始化及其onInit签名问题，夹具修正后57/57通过。`20260907T121556532Z-hls-cookie-green.json`的测试全绿，但分析因仅测试生命周期/探针路径标注5警告退出；说明测试用途后最终分析无诊断，复用同业务源码57项证据。

`20260907T122036088Z-hls-cookie-finish.json`完成最终分析、随后原频道下播使HTTP阶段失败；只刷新公开目录并重跑外部探针，`20260907T122407743Z-hls-cookie-production-relay.json`成功。以上重型任务结束活跃重型进程均0，守卫与监控均释放；没有并行构建，也没有停止其他项目Java进程。完整日志与脱敏HTTP结果位于 `local-artifacts/hls-cookie-20260907/`。

## 边界

本轮不重启手机/adbd、不切换Wi-Fi/ADB端口/授权，不更新Root/LSP/模块，不卸载或清数据；没有使用Root、lspctl或MT MCP改包。当前Windows候选仍为2d8e4e0c，未包含TwitCasting。长录/后台/错误恢复、多平台/全功能及正式全平台门禁继续。
