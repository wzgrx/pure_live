# HLS 按短轨结束的原生边界控制（2026-09-10）

起点 `72d40565` / 生产 `40a2bf8c`；探针提交 `a46bcceaecc8312de9bb75b5197f5e8969a817ae`。承接 [起点](HLS_SELECTED_START_AUDIT_2026_09_09.md) 与 [刷新周期](HLS_RELOAD_CADENCE_AUDIT_2026_09_10.md)。本轮仅评价原生候选策略，生产录制和合并命令保持原样。

## 问题与控制

首片保全后，固定 3 个视频 / 4 个音频完整分片仍有约 2 秒音轨尾差。[FFmpeg 输出选项文档](https://ffmpeg.org/ffmpeg.html#Advanced-options)描述 shortest 以最短输出流的结束限制输出，可能引入缓冲，默认缓冲时长 10 秒；这不是仅在用户点击停止时触发的规则。因此同时检验尾差改善、内容裁减和任务退出时刻，不只观察文件结束时间接近。

同一固定 CMAF、真实 FFmpegManager、生产显式预取、独立 A/V 序号与已验证首片提示，依次比较：

1. 视频3/音频4、两份 LIVE 清单，保留全部输出。
2. 同样输入，实验参数 `-shortest -shortest_buf_duration 10`。
3. 视频4/音频3、只有音轨源清单 ENDLIST，保留全部输出。
4. 同样的音轨先结束输入，实验 shortest。

视频清单始终 LIVE、固定内容不继续追加；每场四秒观察窗口，仍运行时才发手动停止。本实验没有模拟长期增长的视频。探针在 startAck 留存所属会话/relay 和命令，仅落盘布尔/数值参数，支持观察提前自然完成。媒体源与原生参数变化仅限探针，夹具、应用策略和用户数据保持原样。

## 假设失败与最终结果

首轮 `20260909T165318446Z-hls-shortest-boundary-first.json`，证据 `controls/shortest-1788972762925751`：四场都完成，但“音轨已结束 + shortest 会在手动停止前自然完成”的断言失败，实际 stopIssued=true。该阶段 **2 PASS / 1 FAIL**、五个 opt-in 未运行，严格分析尚未执行。这是候选假设被反证，不是生产缺陷红测。

修订探针以明确验证实际观察到的截尾及手动停止行为，并收紧固定夹具包数；没有修订生产代码。最终 `20260909T165945246Z-hls-shortest-boundary-observed.json`：**3/3 PASS**（两统计、一项含四场原生控制），五个其它 opt-in 未运行；两个改动 Dart 文件严格分析 PASS。证据 `controls/shortest-1788973152810447`，两轮逐轨包数一致：

| 控制 | 视频包 | 视频首/末 PTS（秒） | 音频包 | 音频首/末 PTS（秒） |
| --- | ---: | --- | ---: | --- |
| long-audio-preserved | 180 | 1.421033 / 7.387700 | 375 | 1.400000 / 9.378667 |
| long-audio-shortest | 180 | 1.421033 / 7.387700 | 282 | 1.400000 / 7.394667 |
| ended-audio-preserved | 240 | 1.421033 / 9.387700 | 282 | 1.400000 / 7.394667 |
| ended-audio-shortest | 179 | 1.421033 / 7.354367 | 282 | 1.400000 / 7.394667 |

末包 PTS 差不是两轨结束时刻或完整唇音同步指标，须另计包时长与编码重排。第一组 shortest 的末包 PTS 差约 6.967 ms，代价是减少 93 个音频包；第二组减少 61 个视频包，约两秒有效视频。

四场 stopIssued/manualStop=true、native code0、drained=true、forcedCancel=false、inputTailDiscarded=false、coverage=false、integrity=false；关闭后池 entries/bytes=0。上述输入排空/覆盖标记描述输入交付，不等于输出编码包完整。保留日志仍含 I/O、重复 moov 和 pthread_join ESRCH 信息，没有记为“原生日志零警告”。

音轨先结束 + shortest 的时间线进一步显示：音轨 ENDLIST 在 44 ms 已交付给 native，视频仍 LIVE；视频 1000–1003 四段均完整交付（最后一段 107 ms），4002 ms 才发停止，4134 ms 提供停止视频清单，4136 ms 完成。因此不是 relay 隐藏音轨结束，也不是源视频缺片。当前证据只支持四秒观察窗内任务未自然完成；不推断所有 HLS/native 版本都如此。

## 独立文件核对与资源

四份最终 TS 全文件严格解码均 exit0、stderr0，逐包 payload SHA-256 对比证明：

- long-audio-shortest 的视频 180 包与保留版完全相同；音频 282 包是保留版 375 包的精确前缀，丢掉的是尾部 93 包。
- ended-audio-shortest 的音频 282 包与保留版完全相同；视频 179 包是保留版 240 包的精确前缀，丢掉的是尾部 61 包。

工具/输入哈希与完整证据保存在 `local-artifacts/hls-shortest-boundary-20260910` 的 `observed-source-hashes.json`、`retained-decode/input-hashes.json`、`retained-decode/summary.json`。固定夹具、FFmpegKit DLL 与 ffprobe/ffmpeg 均按已有固定 SHA 核对。包数取自最终文件，不以原生进度行 frame 值替代。

| 阶段 | 资源记录 | 秒 | 采样峰值 CPU | 采样工作集字节 | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 假设反证 | 20260909T165318446Z-hls-shortest-boundary-first.json | 75.021 | 18.59% | 5070229504 | 0 |
| 最终控制 + 严格分析 | 20260909T165945246Z-hls-shortest-boundary-observed.json | 46.006 | 8.60% | 5230342144 | 0 |
| 保留文件解码 + payload | 20260909T170029379Z-hls-shortest-boundary-retained-decode.json | 5.804 | 0% | 3969302528 | 0 |

最后一行是短阶段采样值，不代表解码未消耗 CPU。首次生成解码脚本的 JavaScript 调用存在字符串语法错误，在执行 shell 前失败；修订调用后仅执行上述一次解码，没有遗留任务。

## 决策、剩余验收与回滚

不采用全局 `-shortest` 作为直播录制修复。它确实接近输出尾边界，却裁减已取得的有效内容，且本次仍等待手动停止。由此确认的是候选策略的取舍，不是一个已修复生产 Bug；现有共同 A/V 停止边界仍未闭环。

下一步明确“原始内容完整保留”与“对齐导出副本”的独立合同：停止后计算两轨包结束边界、报告单轨尾部长度，不用静默裁剪或仅改验收时长掩盖源差异。若生成对齐副本，保留原件并以独立文件验证，不改变活动期持续录制语义。随后再做包含已验证起点/覆盖/周期修订的有界真实录制，不反复重录旧输入直到偶然通过。

回滚只需撤回探针提交 `a46bccea`。默认预取仍关闭；无手机、MT、Root/LSP、线上直播重录、版本、构建或发布。宏观仍 20 PASS / 32 RUN / 10 NOT RUN，42 组未闭环，全平台 3.2.0 交付门禁保持。
