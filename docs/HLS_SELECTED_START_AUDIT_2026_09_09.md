# 已准入 HLS 缓存的原生起点衔接（2026-09-09）

起点 `ae92681f`，承接 [原生起点控制实验](HLS_NATIVE_START_BOUNDARY_AUDIT_2026_09_09.md)。该实验已用固定 FFmpegKit 和 payload 哈希证明默认选片会丢失已可用的音频前缀；共同停止边界另待处理。本批接入生产的显式预取路径，默认预取仍关闭。

## 设计与兼容边界

- 原生参数先于第一次 HTTP GET 固定，而整批预取准入发生在 GET 期间。不给所有输入添加 `-live_start_index 0`，也不引入一次没有 native 消费者的伪发布或重复网络预读。
- 只有显式开启预取、且调用方没有指定 `live_start_index` / `prefer_x_start` 时，relay 为该 native 输入启用 `prefer_x_start=1`；随后仅真正选中的缓存媒体清单添加 `EXT-X-START:TIME-OFFSET=0,PRECISE=NO`。零偏移选择首个完整分片，不平移源 PTS，不合成缺失媒体。
- 自动模式对未准入原路径中的源站 START 指示进行中和，避免刚启用的 native 提示支持意外改变之前忽略该提示的选片行为。原有多变体/不支持标签/DVR 输入仍不接受我们的零起点指示。显式调用参数保持优先，原 START 提示也保持，调用者的原生选择继续生效。
- 该转换只改变本地提供给 native 的清单指示，不放宽原始快照准入；例如源站包含尚不支持的 START 标签时仍拒绝预取。媒体下载、Cookie/查询策略、整批取消和缓存上限不变。
- 起点提示在 scheduler 的实际发布文本中生成，进入最后已发布快照；冻结、ENDLIST 和重复读取保留同一个文本，不在停止时重新计算起点或发布未提供媒体。

## 来源与影响面

分类沿用上一轮原生因果对照的 `integration-conflict`：native 默认直播选片机制与维护分支“已缓存前缀应交付”的录制需求存在组合差异，不宣称 FFmpeg 播放默认值本身是缺陷。冻结上游与原生 payload 对照沿用前一篇审计，不合并上游。改动仅涉及 recorder relay、清单发布与其探针；播放器、UI、持久化、手动停止和来源代次均未改动。回滚可整体撤回本批起点桥接，保留原有显式预取默认关闭。

## 验证计划与记录

新增七个确定性组合：自动选中、关闭预取、未准入源提示、显式 prefer=1/0、显式 live_start_index，以及显式索引覆盖选中输入。覆盖参数向量、本地 START 内容、零准入/零下载、冻结和关闭回收。旧实现两项自动模式红测失败，其余十项通过。

原生控制在保留此前四种机制对照的基础上，增加实际选中提示、未准入源提示自动回退、显式调用方提示三个场景；基线用显式 prefer=0 固定原生原先默认机制，生产自动模式独立核对。七场均已通过，详见下表。

本批不操作手机/Root/LSP、不重录线上直播、不构建或发布。宏观 42 项与全平台 3.2.0 完整验收门禁保持。

## 已完成定向检查

- 红测：`20260909T154805662Z-hls-selected-start-red.json`，10 PASS / 2 FAIL；两处均为旧实现缺少自动起点参数。
- 修复：`20260909T155302486Z-hls-selected-start-fixed.json`，六文件 98/98 PASS，七个改动 Dart 文件严格分析 PASS。耗时 165.434 秒（含互斥等待），CPU 峰值 17.77%，内存峰值 8,455,426,048 B，结束活跃重型进程 0。
- 执行输入：`local-artifacts/hls-selected-start-20260909/fixed-source-hashes.json`；原生阶段逐项复核同一源码哈希，不以另一个候选二进制代替本次源码。

## 原生与文件证据

源码提交：`db0ad486c999e3706c76018270c60de15d9b1d72`。固定夹具、FFmpegKit DLL、CLI ffprobe/ffmpeg 哈希均沿用前一篇审计，脚本执行前逐项验证。

证据根：`local-artifacts/hls-selected-start-20260909/controls/start-1788969402078758`。文件测试 3/3 PASS（两项统计 + 一项含七场的 native 控制），其余三个 opt-in 探针未运行；不是七项全功能验收。

| 场景 | 实际首 V/A 序号 | V/A 包数 | A−V 首 PTS 秒 | 缓存 feed |
| --- | --- | --- | --- | --- |
| equal-default | 0 / 0 | 180 / 282 | −0.021033 | 2 |
| shared-unequal-default | 1 / 1 | 120 / 281 | −0.015689 | 2 |
| distinct-unequal-default | 1000 / 2001 | 180 / 281 | 1.984311 | 2 |
| distinct-unequal-zero | 1000 / 2000 | 180 / 375 | −0.021033 | 2 |
| distinct-selected-hint | 1000 / 2000 | 180 / 375 | −0.021033 | 2 |
| distinct-unselected-hint | 1000 / 2001 | 180 / 281 | 1.984311 | 0 |
| distinct-explicit-hint | 1000 / 2000 | 180 / 375 | −0.021033 | 0 |

- 所有场景 native code=0、manual stop、drained=true、forcedCancel=false、tailDiscarded=false、coverageIncomplete=false、integrityError=false；关闭后 feeds/entries/bytes 均为 0。原生日志仍有 I/O、重复 moov 或 pthread_join ESRCH 文本，保留原始日志，不宣称零告警。
- 自动已准入路径与显式零索引的各轨统计完全相同；未准入自动路径与基线统计完全相同。源站提示加显式 prefer=1 仍由调用方控制，零缓存准入但恢复首片。
- `retained-decode/summary.json`：七份 TS 全文件严格解码 exit=0、stderr=0；逐包 SHA-256 对比确认 selected=zero、unselected=default、explicit=zero，两轨均一致。默认音频为零起点音频去掉前 94 包的精确后缀；原视频 payload 不变；共用序号默认视频少 60 包的历史对照仍成立。
- 原生记录 `20260909T155716235Z-hls-selected-start-native.json`：79.343 秒，CPU 峰值 9.24%，内存峰值 9,295,683,584 B，结束活跃重型进程 0。
- 解码记录 `20260909T155801771Z-hls-selected-start-retained-decode.json`：20.480 秒，CPU 峰值 5.54%，内存峰值 8,919,121,920 B，结束活跃重型进程 0；输入 SHA 保存在 `retained-decode/input-hashes.json`。

## 剩余边界

本批只解决已准入缓存的初始选片，不对齐源站本来不同的 PDT 起始，不补造缺失媒体。零起点样本音频末 PTS 仍比视频晚 1.990967 秒，共同停止边界仍待设计；真实直播此前的后续刷新 sequence-gap 和长录制验收仍待处理。未重跑真实直播或放宽时长门槛。默认预取保持 false，当前手机/Windows 候选尚未包含此源码；版本、Root、LSP、MT APK 与发布状态均未变更。
