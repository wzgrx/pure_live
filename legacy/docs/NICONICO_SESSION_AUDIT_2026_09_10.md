# niconico 会话与媒体 Cookie 审计（2026-09-10）

## 基线与范围

基线 79f7320a，接续[元数据审计](NICONICO_METADATA_AUDIT_2026_09_10.md)。原有 niconico 仅提供节目元数据和短期 WebSocket 地址；本批实现原生 Dart 会话所有权与媒体 Cookie 合同，不将短期地址当作长期可播放源。

## 实施合同

- [NiconicoSession](../lib/core/site/niconico/niconico_session.dart)：验证已观察入口与可观看状态，复用现有动态 WebSocket 代理配置、独立握手客户端；同时收到合法 seat 与 stream 才完成启动。
- 发送 startWatching/getAkashic，commentable=false；seat 间隔驱动单一 keepSeat 定时器，ping 响应 pong/keepSeat。更新间隔替换原定时器，启动/静默有总期限。连接失败、错误、断线、取消和退出立即隔离后续发布，不隐式拿旧 token 无限重连。
- 同一调用者 token 可管理多个独立消费者；关闭一个会话不取消调用者或其他会话。done 提供终态，close 有界等待资源清理；超时记录 cleanupSucceeded=false，而不是宣称关闭成功。
- [NiconicoStream](../lib/core/site/niconico/niconico_stream.dart)：保留实际六个质量标签，不称六条视频清晰度；主列表此前实际只有三档视频。每份 stream 更新原子替换完整 Cookie 集并使旧 grant 本地失效，退出清空所有当前 Cookie。
- Cookie 域/路径/同名顺序与 Expires 使用既有 HLS cookie 算法；保留同名不同路径、HTTP-date 到期和 Secure 条件，并收紧到明确媒体 origin。参考 [RFC 6265](https://datatracker.ietf.org/doc/html/rfc6265#section-5.4) 的路径选择及顺序；不是浏览器通用 Cookie jar。
- 将[原有 cookie 实现](../lib/core/common/hls_session_cookies.dart)原样移到 core/common，录制旧路径保留 export。算法与既有 origin 隔离不变，避免核心平台层反向依赖 recorder 或重复实现另一套 cookie 算法。
- [流夹具](../test/fixtures/niconico/stream.json)保留实际 13 个 Cookie 的路径、同名分组及 nullable expires 类型，替换全部值/媒体标识，固定一个未来日期；到期回归另使用注入时钟。

## 验证过程

首轮夹具复制使用动态 spread，Dart 将空花括号判为不确定 map/set；修订为显式 Map 类型。该已失败轮次另发现 FakeAsync 会话关闭等待；核对进程归属后只终止该自有测试客户端及后代，保留失败记录，未停止其他 Java/构建任务。

最小诊断表明握手、seat/stream 和 ready 已完成，等待发生于 SDK stream cancellation 的跨 zone Future 收尾。测试时保留虚拟时钟，并显式让根 zone 完成取消；未通过延长生产超时来隐藏问题。第二轮遗漏更新监听器的取消等待，产生一次测试超时与后续 guard 连锁失败，记录仍为失败；随后统一处理该等待。

最终会话 **24/24**、七文件严格分析通过，记录 `20260910T015850454Z-niconico-session-final.json`：279.89 秒（含其他 Java 作业排队），CPU 峰值 17.39%、工作集峰值 7,025,504,256 B，收尾活动重任务 0。同生产输入复用流解析 28 项、元数据 48 项、既有 Cookie 8 项及录制 loopback Cookie 兼容 3 项，合计 111 个不同的定向用例分批通过。记录目录为 `local-artifacts/build-records/`；root-futures 轮的 24+3 已通过，但整体记录因测试 null-aware element 提示仍为 failed，未将其整体标成绿色。该测试语法提示修订后重跑最终 24 项及严格分析。初始失败/诊断证据均在 `local-artifacts/niconico-session-20260910/`，不计为通过。

## 生产协议探针（本机 Flutter 测试进程）

[探针](../tool/probes/niconico_session_probe_test.dart)默认跳过；显式启用 PURELIVE_NICONICO_SESSION_PROBE 和当前 PURELIVE_NICONICO_PROGRAM 后，经本机 Clash 7897 使用生产 API/Session。验证主列表、低档视频/独立音频列表及其声明的 AES-128 普通媒体密钥，并跨过一次服务器指定的 seat 间隔后再取主列表。限制响应时间/体积，不获取媒体分片、登录或发评论，不把列表和密钥请求等同媒体解码。

初版探针把首个 EXT-X-KEY 一律当作 AES-128，三个列表都 HTTP 200 后断言失败，未完成保活验收；关闭/清理通过。复验观察到 NONE 与 AES-128 并存，按 [RFC 8216](https://datatracker.ietf.org/doc/html/rfc8216#section-4.3.2.4) 单独处理 NONE，并增加两项探针回归，未删除密钥或保活验证。02:05:18 UTC 的生产复验 3/3（两项探针回归、一次真实会话）通过：主列表 1,115 B、视频 4,987 B、音频 4,275 B、普通 AES-128 密钥 16 B、保活后主列表 1,115 B，五次请求均 200 且按 URI 选择 Cookie。seat 间隔 30 秒，keepSeat 发送 2 次、pong 1 次；最终 sessionClosed/cleanupSucceeded 均 true、保留 Cookie 为 0。没有下载媒体分片或解码，密钥缓冲读取后清零。探针严格分析通过，终态记录 `20260910T020705740Z-niconico-session-production-keys.json`；这与七文件严格分析共同覆盖本批八个 Dart 文件。

每次请求根据实际 URI 选 Cookie，不把 Cookie 放进外部进程命令行或共享 Dio。只报告请求类型/状态/长度/是否带 Cookie，最后关闭自身 Session/HttpClient，恢复独立测试客户端和代理 provider；清理失败保留失败终态。

## 剩余完整范围

尚未把会话所有权接入播放器与录制控制器，HLS relay 仍需接收按请求选择/更新的 Cookie；还要完成媒体解码、严格短录/续期、质量与音频选项、目录/平台注册/迁移，以及 Android/Windows 原生 UI 和长时验收。

仍为 19 直播站点加 IPTV、8 组参考平台未注册、历史 42 组验收未闭环。本批未操作手机、构建、安装、改版本、发布或同步上游。现有 Android 152cf151 / Windows 2fb471d3 候选保持，3.2.0 完整目标继续。
