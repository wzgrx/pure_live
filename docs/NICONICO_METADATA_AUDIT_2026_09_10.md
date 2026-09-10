# niconico 元数据与会话入口审计（2026-09-10）

## 基线与范围

基线 `0251ee25`。工作区、站点目录、测试及现有平台审计中没有 niconico 适配器；本批新增原生 Dart 的 watch-page 元数据与会话 bootstrap，而不是再包装桌面外部程序。

固定 [biliup niconico](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/niconico.rs)依赖外部 Streamlink 判定和下载。该调用路径并非 Android 已具备的能力，子进程失败也不应直接等同下播。另读取 [Streamlink nicolive](https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/nicolive.py) 当前源码理解会话消息；未执行下载的源码、安装外部工具或合并上游。后者 HEAD 查询被 GitHub API 限流，未取得提交号，因此仅按本机文件 SHA-256 与取证时间固定证据，不声称冻结了远端提交。首次误用 niconico.py 路径返回 404，随后使用实际 nicolive.py；404 不作为插件不存在的证据。

## 当前外部证据

niconico 请求均显式经本机 Clash 7897；未改变应用/系统代理，未提供用户账号或 Cookie、未登录、发评论或操作手机。

| 请求/阶段 | 观察 | 证明范围 |
| --- | --- | --- |
| 官网首页 | HTTP 200，SSR 包含目录卡片与 DAT-csr-data | 可发现公开节目；本批未实现完整目录/分页 |
| 官方频道 watch | HTTP 200，ON_AIR、canWatch=false、地区限制=true、无 socket | 明确地区门槛，不是下播 |
| 用户直播 watch | HTTP 200，ON_AIR、canWatch=true、无需登录、无地区限制、返回 socket | 匿名节目会话入口有效 |
| 预告 watch | HTTP 200，RELEASED、地区限制=true | 预告状态与访问门槛分列 |
| 已结束 watch | HTTP 200，ENDED、canWatch=false、无 socket | 已结束状态，不代表回放权限或回放成功 |
| 用户节目 WebSocket | serverTime → seat → stream；keepIntervalSec=30、protocol=hls、13 个 Cookie | 取得初始会话响应，尚未长期持有/续期 |
| HLS 主列表 | HTTP 200、1,115 B、3 个 variant：1280×720、854×480、512×288，独立音频组 | 只验证主列表声明，未读取媒体分片/密钥或解码 |

WebSocket 探针使用有界期限/消息大小；只请求观看能力且 commentable=false，最终关闭输出并 dispose。主列表请求发生在 socket 关闭后，仍返回 200，**不以此推断长期播放无需心跳**。13 个 Cookie 具有相同名称但不同 playlists、segments/video、segments/audio、keys 路径，下一阶段要按请求域和路径选择；不可压成一个覆盖所有资源的简单键值表。

原始页面、四份嵌入 JSON、会话消息、主列表、响应头、源码及 `evidence.json` 哈希清单在 `local-artifacts/niconico-contract-20260910/`。会话与媒体凭据只留忽略目录，公开夹具替换为合成数据。

## 实施

- [NiconicoWatch](../lib/core/site/niconico/niconico_watch.dart)：严格解析唯一 script#embedded-data/data-props，先校验节目 ID，再保留 RELEASED/ON_AIR/ENDED 和独立访问条件。未知结构、身份冲突、HTTP 失败不冒充下播。
- 公共 lv 节目 ID 是一次广播身份，既不同于 broadcaster，也不同于 socket 路径中的内部数字 ID。watchCount 仅保留平台累计值，不称同时在线人数。
- 仅允许 onAir 且明确 canWatch=true、无登录或地区门槛时发布短期 wss bootstrap。核验已观察主机/路径、排除凭据主机/端口/碎片/重复 query，使用页面 frontendId。未观察的新 socket 主机保持待核验，不泛化接受任意地址。
- [NiconicoApi](../lib/core/site/niconico/niconico_api.dart)：共享 Dio/代理路由、固定 HTTPS watch 路径、不自动跟随重定向；2 MiB 严格 UTF-8 正文和 20 秒总期限，独立取消作用域，收尾不取消调用者 token。
- [四份夹具](../test/fixtures/niconico/README.md)与[确定性测试](../test/niconico_api_test.dart)：保留原始字段类型/状态与门槛，替换节目 ID、标题、主播、socket 路径与令牌；登录场景和损坏边界是合成变体。
- [生产 HTTP 探针](../tool/probes/niconico_metadata_probe_test.dart)默认跳过。显式设置 PURELIVE_NICONICO_METADATA_PROBE=1、PURELIVE_NICONICO_PROGRAM 为当前公开节目 ID、可选 PURELIVE_NICONICO_OUTPUT，按资源守卫执行；临时独立 Dio 经 Clash，finally 恢复共享客户端并关闭自身，不建立 socket 或读取媒体。

## 验证

定向共 **53/53 通过**：48 项确定性测试、4 份完整捕获 HTML 回放、1 项真实生产 Dio HTTP。生产探针 01:21:00 UTC 返回 HTTP 200、节目身份匹配、onAir/allowed，存在已观察主机会话入口。五文件严格分析无问题。终态记录 `local-artifacts/build-records/20260910T012220811Z-niconico-metadata-initial.json`：200.64 秒（含等待已有 Java 工作），CPU 峰值 73.98%、工作集峰值 9,082,294,272 B，收尾活动重任务 0；未终止其他进程。没有重复构建或全量回归。

## 下一阶段及完整目标

1. 实现有所有权的 WebSocket session：独立播放器/录制消费者、seat 间隔与 ping、期限/取消、连接退出、错误和断线事件；复用现有代理策略。
2. 解析 stream 质量矩阵与按域/路径的 Cookie jar，处理同名不同路径、有效期和会话更新；按需传递到媒体/密钥请求，隔离其他站点。
3. 验证主/子列表、音视频与密钥请求、实际解码/严格短录及续期，再接入 LiveSite、导航、分享收藏、能力说明和迁移。
4. Android/Windows UI、播放与录制往返/清理、长时及全平台交付门禁继续；本批不替代这些阶段。

仍为 19 个直播站点加 IPTV，8 组参考平台未注册，历史 42 组验收未闭环。本批没有安装、切手机前台、改数据/Root/LSP、构建、改版本或发布，候选 Android 152cf151 / Windows 2fb471d3 不变，3.2.0 目标保持。回滚仅移除本批新增的未注册代码/测试/记录，无迁移。
