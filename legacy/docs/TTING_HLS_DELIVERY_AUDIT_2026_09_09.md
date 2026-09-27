# TTing HLS 交付时序与短窗口取证（2026-09-09）

后续[滚动 HLS 控制](HLS_ROLLING_DELIVERY_AUDIT_2026_09_09.md)已复现 10/15 秒预算分界，并证明能启动、输出 PTS 连续仍可能遗漏输入时段；下文保留真实取证结论。

基线 `9611a946`；诊断实现与真实采集源码 `2c8df1c02c70490fb78226146af2d6b71d19db38`；最终非 HTTP 引用脱敏补充 `707793ab81784cf3910ce3959ad6710eb2257f1e`。承接[逐包/CMAF 对照](TTING_CMAF_TIMELINE_AUDIT_2026_09_09.md)，本批增加观测能力并完成一次真实取证，**没有修改录制时间戳、整段暂存策略、重试、代理配置或超时值**。

## 1. 可选诊断的边界

`FFmpegManager.start(hlsDiagnostics: ...)` 经 FFmpegService 把同一个 HlsRelayDiagnostics 传给 relay，在原生 execute 之前接入，避免 startAck 后挂观察器漏掉首请求。默认 null，不采集、不写盘。只读快照由调用探针决定保存；本批仅 opt-in 探针开启。

- 使用同一个单调时钟关联请求、最终上游响应头、首个 body chunk、body 读完、local response.close 和 handler 结束；probe 的输出采样和原生事件也记录该时钟。时间不是墙钟 UTC，响应头阶段包含连接/代理/可能的重定向，不拆成单独 CDN 耗时。
- receivedBytes 是 relay 读到的内容字节；bodyCompleteMs 不等于原生消费完成。deliveredMs 只表示本地响应关闭完成，原生可能已超时离开，尤其禁止用它证明视频已录入。
- 只保留匿名资源 ID、状态码、数量、固定状态标签，以及重写后的清单摘要。每个实例默认前 512 请求，硬上限 1024；每清单最多 64 分片、32 子引用，省略数量显式输出。摘要没有 URL、请求头、Cookie、标题、异常文本或媒体。
- master 记录 audio/variant 等角色，媒体清单记录 sequence、duration、明确带时区的 PDT 及有限前向推算；跨 discontinuity 后没有新锚点则留空，不做反向推算，不声称完整实现 LL-HLS PART/SKIP/字节范围诊断。停止后缓存 ENDLIST 明确标记 cached-stop/previous-stop。
- 非 HTTP 原样保留的输入引用不会被误认为匿名本地 ID；诊断解析异常只保留 parseFailed 固定标记，不影响原传输。快照为脱离内部状态的 JSON 数据。relay 关闭仍释放资源/暂存文件，诊断对象保留有界终态供所属探针保存。

[HLS RFC 8216 §4.3.3.2/§6.3.2](https://www.rfc-editor.org/rfc/rfc8216.html#section-6.3.2)说明不同 rendition 的相同 sequence 不保证同一媒体位置。因此以下音视频比较使用清单中的 PDT，不直接相减两路 sequence。PDT 推算是观测辅助，未用于改写输入或同步算法。

## 2. 本地验证

六个新增定向场景：master 角色/两路时间范围关联、分片未收齐时保持未发布、请求与清单容量上限、缺失/异常 PDT 与 discontinuity、停止中的半段接收、非 HTTP 引用脱敏。相邻 relay/连接取消/query policy/暂存配额/输入排空/终态测试共同通过。

原生 CMAF 对照复用上一批逐份校验过哈希的有限 24 秒夹具，经实际 Manager → Service → relay → FFmpegKit，验证首请求确实被记录。三个场景分别为 30、30、25 个请求，全部终态、零省略：

| 场景 | 诊断观测 | 原生包数 video/audio | 首 PTS 差 |
|---|---|---|---|
| aligned | audio 13 段、video 12 段；请求头最大 13 ms | 720 / 1126 | 0.021033 秒 |
| aligned-delivery-delay | video 清单响应头延迟 2504 ms，仍为 12 段 | 720 / 1126 | 0.021033 秒 |
| video-window-ten-seconds-later | video sequence=5、7 段，audio sequence=0 | 420 / 1126 | 10.021033 秒 |

自然 ENDLIST 继续按直播 unexpectedEof 处理；未修改生产 EOF 语义。最后一次仅加强非 HTTP 诊断引用筛选并增加测试，未重跑真实网络或改变此前有效 HTTP 原生对照输入。

## 3. 一次真实采集：0/1，零录制文件

取证使用已注册 TTingSite/生产源解析/720 选择、Clash 7897、原生 Windows FFmpegKit，与此前探针一致。保留原 100 次一秒采样上限及 30 媒体秒/两段目标，不降低门槛。07:52—07:54 UTC 所选房间为 52406。

结果：100.401 秒采样范围内 bytes、segments、recordedSeconds 全为 0，只有 startAck，没有 started。手动停止耗时约 2.022 秒，原生总年龄 102.410 秒，code=-1482175736、inputDrained=true、inputTailDiscarded=true、forcedCancel=false。手动停止产生的 complete 事件不等于成功采集；探针在 native-stop 的 started 断言失败，未进行合并/解码。

诊断保留全部 **27 请求、零省略**。上游实际返回的响应均为 200/206；最后的两个 local 410 来自停止退休资源，其中一个已收到上游 206 的部分 body。未把 local 410 归因于上游访问失效。

### 两路时间范围与首次实际请求

- 首次 audio 清单：4 × 1.984 秒，共 7.936 秒，第一段 PDT 07:52:52.119Z；首次 video 清单：3 × 2 秒，共 6 秒，第一段 PDT 07:52:58.167Z。
- 首次实际请求 audio 是 ID f，PDT **07:52:58.071Z**；它与首次已提供 video 窗口第一段仅差 **0.096 秒**，并非最初就缺少十秒对齐机会。
- native 实际下载两个 audio 分片及初始化资源后再次请求 video 清单。更新后的第一段 ID 17 为 **07:53:12.167Z**，比首次请求 audio 晚 **14.096 秒**。这是请求顺序/滚动窗口的观测，不把相邻两个网络实验视为同一份原始 TS 的逐包证明。

### 视频完整交付慢于窗口，且晚于 probe 的本地读取预算

下面是实际请求到的完整视频分片；每个 EXTINF 都为 2 秒。body 耗时包括 relay 读取及暂存，不是隔离测出的纯网络带宽。

| 匿名 ID | 字节数 | 响应头等待 ms | 首 body 至读完 ms | 请求至 local close ms |
|---|---:|---:|---:|---:|
| 17 | 583199 | 1982 | 8793 | 10778 |
| 1h | 565488 | 2406 | 15137 | 17544 |
| 1r | 531867 | 2350 | 13281 | 15632 |
| 21 | 551801 | 2095 | 8155 | 10251 |
| 2b | 516351 | 1970 | 10061 | 12032 |

这些完整交付均超过 6 秒 video 清单窗口。五次相应的下一次清单请求分别在分片请求后 **10151、10149、10146、10140、10143 ms** 开始，且都先于该分片 local close；日志同时记录读取失败与 skipping expired segments。

**本探针显式 rwTimeout=10；应用录制默认是 15 秒，真实 UI 会读取保存的设置值。** command builder 把该值转换为微秒级 -rw_timeout；relay 在完整收齐前保持媒体响应未发布。观测与“本地读取预算先耗尽，原生转去刷新，而后台整段收集才完成”的机制高度一致。它同时暴露当前 720 交付吞吐跟不上媒体时间，单纯增加等待也不证明稳定实时录制。尚未单独隔离 CDN、Clash 节点、网络抖动或暂存开销，不把慢速全部归因于任一方。

## 4. 门禁和保留证据

| build-records 记录 | 结果 | 总耗时 / 峰值 CPU / WS |
|---|---|---|
| 20260909T074602958Z-hls-bounded-diagnostics.json | 首轮 47/47、2 个真实/离线 opt-in 跳过；6 文件严格分析通过 | 134.249 秒 / 28% / 11709452288 B |
| 20260909T075053901Z-hls-bounded-diagnostics.json | 47 定向 + 1 原生测试（三场景）=48/48；7 文件严格分析通过 | 165.293 秒 / 11.9% / 11265331200 B |
| 20260909T075440753Z-tting-hls-timeline-capture.json | 真实短录 0/1，1 个离线 opt-in 跳过；诊断已保留 | 176.077 秒 / 30.97% / 11403673600 B |
| 20260909T075918147Z-hls-bounded-diagnostics.json | 最终 48/48 定向（含六个新增），2 个 opt-in 跳过；末次修改 2 文件严格分析通过 | 171.509 秒 / 30.76% / 11416576000 B |

四次退出时活跃重型进程均为 0；串行使用 build_resource_guard，未在运行中编辑源码。运行脚本、源码哈希、复用夹具、原生 runtime 哈希核对、controls 与真实 native 输出均在忽略目录 `local-artifacts/hls-diagnostics-20260909/`。

真实原件：`native/TTing 录制 1788940366273493/hls-timeline.json`，14325 B，SHA-256 `97F6C5BF0776440957632A51EDE5809EA7FFE0B64A30C9408C28816F781C6542`。同目录保留 capture-samples.json、failure.json、requested-segments-summary.json；根目录 native-artifact-index.json 索引哈希。真实日志扫描 raw HTTP URL=0、token 赋值=0，结构化 timeline 也为零 URL；不是对所有未来输入作绝对隐私保证。

## 5. 后续修复入口，不把诊断等同于修复

下一批先以本地受控滚动 CMAF 重现“2 秒分片/6 秒窗口、连续慢 body、整段发布、10/15 秒读预算”，同时覆盖同吞吐但短暂响应头时延的对照。核对首个失效状态、原生放弃/relay 后台完成的交叉时序，再设计读取预算与输入排空的协调；保留停止、整段完整性、存储上限、签名代次和用户设置不变量。若对不同清晰度做吞吐对比，单独标注实际选择，不把降低到 480 的成功当作 720 修复。

此前原始 TS 的 10.18 秒晚起点证据仍成立；本轮零产物取证没有证明旧 TS 的完整唯一根因，更没有完成 TTing 实时录制/同步验收。全目标继续：18 直播站点 + IPTV、9 组未注册、42 个宏观大项未闭环不变，版本 3.1.8+4121。没有手机/Root/LSP 操作、候选重建、版本递增、发布或上游合并。
