# 2026-09-04 平台传输与 K90 Pro 实机审计

## 范围

- 以当前维护仓库 `master` 为唯一代码基线，本轮没有拉取或合并上游。
- 审查 Twitch、SOOP Live、YY Live 的列表、房间、播放、弹幕与录制链路，同时复核通用 WebSocket 失活恢复。
- Android 实机为 K90 Pro（网络 ADB）；所有设备动作通过共享 A→B→C 轮转器执行，Pure Live 只占用 C 轮。

## 根因与修复

### Twitch 匿名 GraphQL 完整性

Twitch 的匿名网页链路对两个端点使用不同的设备身份头：`/integrity` 引导请求使用 `X-Device-Id`，携带 `Client-Integrity` 的 GraphQL 请求使用 `Device-Id`。旧实现把同一个头复用于两个端点，令已经取得的完整性令牌在 GraphQL 阶段被拒绝。

当前实现把设备身份、Cookie `auth-token`、令牌缓存和一次有界重试绑定为同一会话；浏览器回退也使用相同头部约定，并拒绝把仍含完整性错误的 GraphQL envelope 当作成功。

### SOOP 弹幕节点

SOOP 房间 API 返回的聊天端口是明文协议端口，WSS 需要使用相邻的官方安全端口。旧实现直接把明文端口拼进 `wss://`，在部分房间表现为列表和视频正常、弹幕连接失败。现在统一校验端口范围、优先使用 `CHDOMAIN`，缺失时从 `CHIP` 推导安全域名，并只解码完整的 `SVC_CHATMESG` 帧。

### YY H5 协议

YY 的 H5 匿名弹幕链路要求保留 WebSocket Upgrade 请求头大小写，并依次完成匿名登录、AP 登录和频道加入。通用 WebSocket 客户端会规范化头名，旧流程也缺少完整的房间加入状态机。现在增加独立的大小写保持通道、10 字节小端包头编解码、房间身份核验、拼包/截断保护和可重连生命周期。

### 通用 WebSocket 失活

连接成功但长期没有任何入站数据时，旧客户端可能永久保留半开连接。现在用可配置的入站空闲门限关闭失活传输，按候选端点继续重连；收到心跳或业务帧会刷新活动时间，正常关闭诊断保留 close code/reason。

## K90 Pro 自动化修复

K90 Pro 按用户设置在 10 分钟后锁屏且没有密码。无线 ADB 的单次 UIAutomator 读取偶尔很慢，旧测试只在取得 C 轮时唤醒一次，长流程后会把 `com.android.systemui` 锁屏层误判成 Pure Live 页面。

- C 轮包装器现在以 `try/finally` 开启供电时常亮，并在结束、失败或异常后恢复原有锁屏策略。
- UI 冒烟在每次观察和状态触控前再次执行唤醒与 keyguard 复核。
- 设备 UI 图补录当前 3.1.8 设置页的网络代理短滑距离与卡片坐标。
- 国外平台测试使用临时 `127.0.0.1:7897` ADB reverse，同时启用应用层和播放器代理；结束后复核两个开关均关闭并移除 reverse。
- 首页模式和平台标签都改为“点击后复核 selected 状态”的有界操作；平台标签只读取总数不少于 9 的 TabBar，排除顶部状态栏和底部导航栏。
- 录制计时不再包含为了查看录制中心而产生的额外导航时间；运行态用私有 TS 文件真实增长作为机器门禁，停止后再验证录制中心与最终 MP4。

## 验证证据

- `flutter analyze`：0 issue，记录 `local-artifacts/build-records/20260904T095135254Z-quality-focused.json`。
- Flutter 完整测试：724/724，通过记录 `local-artifacts/build-records/20260904T094911784Z-quality-full.json`。
- 新增协议与连接定向测试：32/32，通过记录 `local-artifacts/build-records/20260904T093225274Z-quality-focused.json`。
- 公开接口探测：42/42，通过记录 `local-artifacts/diagnostics/interface-probe-20260904T094206498Z.txt`。探针对独立 TLS EOF 使用新连接有界重试，不把一次 CDN 断连误报成长期接口失效。
- Android SOOP 完整录制：弹幕、三档画质、线路、文件增长、停止状态、MP4 音视频流和清理全部通过，见 `local-artifacts/diagnostics/android-recording-smoke-20260904T122658151/summary.json`。
- Android YY 完整录制：画质、线路、文件增长、停止状态、MP4 音视频流和清理全部通过；房间当时没有真实聊天，因此以协议握手 ready 为弹幕门禁，见 `local-artifacts/diagnostics/android-recording-smoke-20260904T124922219/summary.json`。
- Android Twitch 完整录制：列表、真实房间、弹幕、`1080P60（原画）` 等画质、线路、MP4 音视频流和清理均取得实机证据，见 `local-artifacts/diagnostics/android-recording-smoke-20260904T111321371/summary.json`；当次唯一失败项是旧测试正则没有识别“分辨率在前、原画在括号内”的标签，当前正则已修正。
- 代理最终状态：应用层代理关闭、播放器代理关闭、`tcp:7897` reverse 已移除，见 `local-artifacts/diagnostics/android-proxy-disabled-20260904T165023484/summary.json`。

## 发布状态

本文件记录开发分支验证，不代表新版本已经构建或发布。Android/Windows 正式产物仍须从同一冻结提交串行构建，并完成各自产物核验与安装回归。
