# 录制源策略元数据接线审计（2026-09-09）

实现提交 `a82f6d37f732224e93cd9c700ce9038c0230555e`。

## 范围

基线 `11c5d5926eaf0c07559aacad030988ed09b55065`。继续 [HLS 单源策略](HLS_SOURCE_QUERY_POLICY_AUDIT_2026_09_09.md)，将策略作为类型化、不可变的逐 URL 元数据，经平台解析、录制画质/线路选择及实际控制器/管理器/服务传入已有 relay。

这是新增平台所需的应用能力接线，不把普通 HLS 不继承 query 的正确行为归为 Bug。没有同步上游，也没有注册 TTing 或把单个接口样本视为完整媒体支持。

## 源码链与保持的行为

1. `LivePlayUrlResolution.withSourcePolicies` 一起复制、规范化 URL 列表和策略映射，要求每个键属于结果列表且精确匹配策略源 URI；旧签名/其他源/缺失 URL 均报错。映射及列表不可修改，错误不打印签名。原 const 构造器保持可用，默认策略为空，不从 token 字样猜平台能力。
2. 正常与 recovery 扩展统一使用 `normalized()`，保留 `appliedQualityData`、`qualityUnconfirmed` 和源策略，而不是重新构造时只复制 URL/画质字段。
3. `StreamResolverService` 按实际筛选后的选中 URL 查策略，传入 `ResolvedRecordStream`。普通解析、逐线路 cursor、重试换 CDN、续租更新 URL 均使用各次响应的精确 URL，不使用旧列表位置或画质标签查 token。
4. `RecorderController._runTask` 的本次 resolved 对象（含有效预取结果）把策略传给 `FFmpegManager.start`，再到 `FFmpegService.start`、`FFmpegHlsInputRelay.startForArguments`。relay 继续做最终源绑定核验并由现有 FFmpeg 会话持有/关闭。
5. 管理器增加注入服务的 `forTesting` 构造器；生产单例仍获取原 `FFmpegService.to`，初始化去重、错误后的再初始化、事件转发逻辑不变。两个显式测试 manager 实现补齐新增可选参数。

没有改动录制重试次数、画质确认语义、线路优先级、暂停/停止、缓存目录保护、输出汇总或原生停止排空逻辑；新增策略对象不写入 task JSON。这不声称原有持久化 URL 或日志已经完成全面凭据审查。

## 验证与夹具修订

新增元数据文件 9 项：输入不可变/规范化、错配策略、正常/recovery 的新签名与画质确认、旧 URL 不隐式启用、未注册平台仍被拦截、真实 FFmpegManager 到注入服务的参数传递、普通与 cursor 两种录制筛选/轮换/续租、真实命令构造与 loopback HLS 请求链。另在原录制生命周期文件增加 1 项：实际控制器的两个 native 尝试分别收到精确匹配其 URL 的策略，旧策略不匹配新尝试。

首次 `20260908T235653662Z-record-source-query-green.json`：**96 项通过，1 个测试文件加载失败**。新文件的替身错误继承只有私有构造器的 FFmpegService，8 项未运行；更正为实现其接口并提供未使用成员的 noSuchMethod，生产代码未因此修改。该失败不是产品红测，也不是 96/97 全部用例通过。原日志、文件副本及输入哈希独立保留。383.206 秒含资源排队，CPU 峰值 15.92%、Working Set 11,606,663,168 B、结束活跃重型进程 0。

第二次 `20260909T000340189Z-record-source-query-green.json`：**101 通过 / 3 失败**，331.352 秒。三个新录制场景使用未注册的 fixture 平台名，在进入注入站点前被原 `Sites.isSupported` 检查拦截；没有移除生产检查或临时注册平台。改用既有已注册键并注入完全本地的站点替身，同时增加未注册平台明确失败的对照。它不证明 Bilibili 线上接口支持该策略，没有发出 Bilibili 请求；生产接线仍未改动。

最终 `20260909T001744937Z-record-source-query-green.json`：八文件 **105/105**，八份改动 Dart 文件 `analyze --fatal-infos` **No issues found**，测试/分析与最终 runner 均退出 0。757.392 秒含资源排队与分析，CPU 峰值 63.54%、Working Set 13,016,985,600 B；结束守卫仍观察到 2 个活跃重型进程，没有以此终止进程或重启工具。

运行范围为元数据、录制解析、租约生命周期、输出生命周期、用户意图、HLS 源策略、HLS relay、平台录制合同八文件；原始证据在忽略目录 `local-artifacts/record-source-query-20260909/`。提交前逐项核对 green-source.json 的八个 SHA-256 与当前文件一致。没有把测试文件加载失败、未注册夹具错误当作产品修复，也未跳过原有失败断言。

### 原生证据边界

控制器测试使用注入的 FFmpegManager，真实 manager 测试使用注入的 FFmpegService，HTTP 链路实际启动本机 relay/源服务器。实际 FFmpegService 到 relay 的参数传递由源码核对与分析覆盖；**未启动 FFmpeg 解码/封装、未生成录制成品、未连接生产 TTing 媒体，也没有实机 PASS**。没有用源请求 200 代替声音、画面、文件完整性或恢复能力。

## 剩余、发布与回滚

- 主播放器仍会把 resolution 拆成 URL 列表，需把策略沿初次播放、恢复结果、提交快照和切源事务完整传递，再为真实 native source 管理 relay；保持远端源身份与本地播放 URI 的对应。
- 多画面默认解析和换档还直接调用 getPlayUrls，需接入统一结果和每格源生命周期。音频服务绑定现有 UnifiedPlayer，接线应随该源所有权，不加到未使用的旧音频 helper。
- 完成上述接线后继续 TTing 严格 API/状态/身份、设置迁移、双语文案、收藏分享、平台注册及媒体/录制验证。录制接线完成不代表平台注册完成。
- 无手机、ADB/MT、Root/LSP、构建、安装或发布操作。版本仍 3.1.8+4121，Android bee143e2、Windows f3de664a 候选保持。17 直播站点 + IPTV、10 组参考平台未注册、历史 42 个宏观未闭环项均未减记；稳定 3.2.0 仍按完整目标验收后交付。
- 回滚本批时一起反向还原公共结果类型、录制调用方及测试签名，避免留下消费新字段的半条链；没有数据库迁移或设备数据回滚。
