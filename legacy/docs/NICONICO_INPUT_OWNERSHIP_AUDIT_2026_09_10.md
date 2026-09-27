# niconico 会话与私有 HLS 输入所有权（2026-09-10）

## 范围与来源

接续[明确选流双轨短录](HLS_MASTER_SELECTION_AUDIT_2026_09_10.md)，把探针中临时拼接的 seat、master 预读、中继和关闭关系移入生产 `NiconicoHlsInput`。这是尚未完成的 niconico 应用接入工作，不记为现有已注册平台的上游问题；本轮没有合并上游、构建应用或操作手机。

## 行为与所有权

- 每个输入独占一份 seat、当前 grant 和私有中继。播放/录制分别创建；不在全局缓存中持有会话。明确分辨率必须唯一匹配，保留关联音频；显式 `resolution: null` 仍走原 ABR，不声称旧 ABR 缺轨已经修复。
- 父取消在打开前登记；内部取消传入 seat 和 master 预读。已取消时不创建 seat；异步返回的 seat/relay 先收归本对象再检查取消，迟到创建也被关闭并等待清理。关闭不依赖播放器继续请求数据。
- 退出先关闭已经取得的资源，同时等待创建终态，再关闭迟到资源。复查发现并修订了“早期 seat 清理阻塞时延迟关闭迟到 relay”的顺序问题，现两者立即开始清理、共同等待结束。
- 同根 grant 更新即时撤销旧 Cookie；请求回调读取实际当前 grant。根变化或远端会话结束自动关闭整份输入，要求消费者重新解析；不把新会话 Cookie 注入旧 master 缓存。
- `finish` 只请求录制中继排空，保留 seat 供已发布媒体收尾；最终 `close` 释放 Cookie、签名根地址和 seat/relay 引用，只保留脱敏计数。失败清理通过 `done` 和 `close` 报告，不标作成功。
- master 预读复用生产 `CancellableHttpConnections`、`HlsUpstreamClient` 和 `HlsBodyReader`：连接归属、取消、当前 URI Cookie、5 秒空闲/20 秒完整响应预算、4 MiB/严格 UTF-8。非 200 或根跳转不用于选流；退出等待读取/连接清理，不遗弃迟到请求。
- `NiconicoSession` 增加每实例代理入口，默认保持原路由。输入使用明确传入的路由，不为某个消费者修改全局 WebSocket 代理。
- 真实官方节目 `lv351173514` 暴露先前合同遗漏：其页面给出 `/wsapi/v2/watch/…`，用户节目为 `/unama/wsapi/v2/watch/…`。元数据和 seat 两处均保留这两种精确路径，继续限定原 host、wss、数字 ID；不把任意路径纳入。增加官方入口与四个邻近非法形态回归。

## 确定性验证

- 新增输入所有权 23 项、HTTP master 读取 8 项、每实例代理 2 项，联合既有会话/授权/选流/运行时 Cookie/捕获合同共 **125/125** 通过；六文件严格分析通过。
- 包含关闭幂等、预取消、迟到 seat/读取/bind、两阶段关闭交错、同根刷新、三个阶段的根变化、远端断开、启动/关闭失败、独立输入、父取消、歧义画质，以及实际生产 relay 的本地端口创建/释放。
- HTTP 用真实 loopback 验证状态码、超限、无效 UTF-8、跳转及 headers/body 阶段取消；不是只用完成的 Future 模拟网络。
- 首轮 119 项测试通过但分析有 3 个告警，保留失败记录 `20260910T032630324Z-niconico-input-owner-initial.json`。修订后记录 `20260910T032857117Z-niconico-input-owner-late-cleanup.json`：72.30 秒、CPU 峰值 9.37%、工作集峰值 6267953152 B、结束活动重型进程 0；六份源文件哈希核对一致。
- 官方入口阶段联合 **179/179**、八文件严格分析通过；记录 `20260910T033617429Z-niconico-input-owner-official-path.json`：121.17 秒、CPU 峰值 49.77%、工作集峰值 6413025280 B。八份源文件哈希一致。结束全机重型计数为 1，随后的守卫发现 `java#27984`（Gradle 9.7.1 daemon）并排队；本轮没有启动或终止 Gradle，保留此原始计数，不写成 0。
- 码率区分补齐后最终 **183/183**、八文件严格分析通过：`20260910T034236713Z-niconico-input-owner-bitrate-selector.json`，82.18 秒、CPU 峰值 10.60%、工作集峰值 7844073472 B、结束活动重型进程 0。与另行通过的 12 项连接/TLS 回归分列，不累加重复运行次数。

## 真实链路

原六秒探针已改为直接调用生产 `NiconicoHlsInput.open`，删除探针自己的 master HTTP 和 seat→relay 清理拼接。完成下述新实现实录复验，不沿用旧输入的成功记录作为新实现证明。

本轮前三份外部失败保留：

1. `20260910T033003871Z-niconico-input-owner-production.json`：12 项连接/TLS 定向通过，外部样本在 session 阶段失败。随后 UTC 03:31:17 读取原 `lv351357212` 官方页面得到 ENDED/canWatch=false。原探针未记录具体 failure kind，保留原记录，不追写推断；没有本次成功实录。
2. `20260910T033245358Z-niconico-input-owner-fresh-program.json`：新节目在 watch 阶段 schema 失败；补充脱敏错误类别与状态后定位到上述官方 WebSocket 路径。UTC 03:33:03 官方页面仍 ON_AIR/canWatch=true，无登录/地区门槛。随后修订精确路径合同，而不是换一个绕开此缺口的样本。
3. `20260910T033811979Z-niconico-input-owner-official-production.json`：入口修订后 watch 已 onAir/allowed，但 720p 输入仍 schema 失败。随后 `20260910T034007210Z-niconico-input-owner-shape-diagnostic.json` 只读协议诊断到达 master、seat 清理通过；当前官方源实际提供 800×450/1080800 和两份 512×288/412800、201600，并没有 720p。该诊断的通过只表示取得结构，不表示录制成功。

此真实样本还要求区分同分辨率码率：输入现在可同时指定 `resolution` 与精确 `bandwidth`，不以第一个相同尺寸变体代替用户选择。新增三档选择/关联音频回归，结构来自上述响应，夹具中的媒体路径为合成值；单独码率而无分辨率在创建 seat 前失败。800×450 关联 192 Kbps 音频，两份 512×288 关联 96 Kbps 音频，均保留各自 master 分组。

### 实际提供的 800×450 档位通过

UTC 03:43:18，`lv351173514` 通过生产输入 owner、Clash 7897 和桌面 FFmpeg 取得六秒成品；没有修改源内容、移除音轨或放宽捕获合同。`20260910T034325736Z-niconico-input-owner-observed-quality.json` **1/1 通过**，43.77 秒、CPU 峰值 9.32%、工作集峰值 7449845760 B、结束活动重型进程 0；八份源文件与最终 183 项定向输入哈希相同。

| 项目 | 结果 |
| --- | --- |
| 视频 | H.264 800×450；180 包，覆盖 6.000 秒 |
| 音频 | AAC；281 包，覆盖 5.994666 秒 |
| A/V | 公共覆盖 5.984 秒；首差 +16 ms，尾差 +10.666 ms |
| 完整性 | 双轨无已知内部空档、DTS 回退或缺失时长；完整严格解码通过 |
| 成品 | 819558 B；容器 6.010667 秒 |
| 清理 | seat/relay 共同清理通过；Cookie 0、中继资源 0 |

预取实际 feed=2，初始 Cookie 13。短录未跨过 30 秒 seat 周期，keepSeat=0；不把它记为新的长时保活或跨窗口验收。FFmpeg/ffprobe 哈希复核与上一轮相同，仍是桌面原生工具而非应用 FFmpegKit。成品及脱敏报告在忽略目录 `local-artifacts/niconico-input-owner-20260910/20260910T034241862Z-production/`，失败记录与 `evidence.json` 一并保留。

成品 SHA-256：`3E1B022E2E23BE53AA5431BF20EE9BFED5F9A1B35800E46A7D3C557B7B419AA0`。

## 尚未完成与下一步

当前生产输入仍由探针调用，尚未穿过 `LivePlayUrlResolution`、播放器状态/恢复事务、`FFmpegRecordSession` 的实际应用边界。下一步实现带取消的输入工厂及其状态传递，再接通 niconico 适配器；不使用伪媒体 URL、短期 bootstrap URL 或全局会话缓存来绕开现有 URL-only 接口。

平台注册、目录/搜索/分享、实际播放器/应用 FFmpegKit、Android/Windows GUI、跨窗口和长时录制继续待验。完整范围保持 19 直播站点 + IPTV、8 组未注册、历史 42 组未闭环；现有候选不含本批实现，版本保持 3.1.8+4121，未发布 3.2.0。
