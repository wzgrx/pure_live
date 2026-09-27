# HLS 保留清单发布与缓存原生读取（2026-09-09）

起点 `fdc34216`，代码 `16593295bf7a7337061f9d272f984c246455844c`。承接[保留元数据](HLS_RETAINED_WINDOW_AUDIT_2026_09_09.md)与[预取池](HLS_PREFETCH_POOL_AUDIT_2026_09_09.md)。

## 结论与边界

本批完成保留清单的渲染，并首次把 **HlsRetainedWindow → HlsPrefetchPool → 本地 HTTP 读取租约 → 独立原生 ffprobe** 接在同一个受控验证中。测试源站在缓存完成后关闭，原生消费者仍读到与直连参考相同的逐包时间戳、大小、标志和轨道归属。

这不是实际录制接线完成：`FFmpegHlsInputRelay` 尚未导入新池/渲染器，没有自动轮询选中媒体清单、动态公平调度、消费进度淘汰或真实 TTing 回测。本批是新录制路径的功能开发，不把开发中的语法/分析失败记作生产 Bug 红测。当前宏观仍 **20 PASS / 32 RUN / 10 NOT RUN，42 项未闭环**。没有设备操作、APK 构建、版本变化、上游合并或发布。

## 清单合同

新增 `lib/recorder/services/hls_retained_manifest.dart`：

- 保持首个保留分片的媒体序号、不连续序号；已解析的 BYTERANGE 输出绝对偏移，避免前缀淘汰改变取字节位置。
- 先恢复初始化段自己的密钥状态，再输出 MAP，再恢复媒体密钥；处理密钥轮换、多个 KEYFORMAT 和 NONE。URI 映射覆盖密钥、MAP、媒体，原始快照不变。
- 首个保留分片可补出原已推导的 PDT 锚点；后续保留显式锚点，不跨不连续点凭空推导。此处是清单元数据渲染，不重写媒体 PTS/DTS。
- `throughSequence` 只允许现有连续前缀，未发布末段时暂不输出源站 ENDLIST；`finish` 可冻结指定前缀。调用方仍须先证明该前缀资源可用，并承担发布期间的缓存所有权；渲染器本身不检查下载就绪。
- 输出按 UTF-8 字节计费，默认及硬上限 8 MiB；映射 URI 必须为无凭据、无片段的 HTTP(S)，长度有界。异常不返回部分清单；映射回调自身若有注册副作用，仍应由调用方负责事务清理。
- MAP 消失、反向/过大不连续展开、未知密钥属性和非法未加引号属性显式失败，避免静默套用旧初始化段或改变属性含义。

`hls_retained_window.dart` 同时保留版本、INDEPENDENT-SEGMENTS 和 PLAYLIST-TYPE 合同：刷新不能切换后两者，版本不下降；未知 MAP 属性进入 unhandledTags，阻止丢属性后发布；VOD 超容量不裁掉内容且保持合并原子性。

渲染最低版本 6，保留更高来源版本；有界输出省略 EVENT/VOD 声明，终态仍由 ENDLIST 表示。非 I-frame MAP 的版本要求、AES 初始化 IV 及 EVENT/VOD 更新限制依据 [RFC 8216 §4.3.2.5、§4.3.3.5、§7](https://datatracker.ietf.org/doc/html/rfc8216)。首次 rfc-editor 请求 429，随后以 IETF Datatracker 原文复核；未用第三方解释替代规范。

## 验证

四个变更 Dart 文件格式化与 `dart analyze --fatal-infos` 通过。

**70/70 定向测试**：新渲染器 9 项 + 原窗口 38 项 + 预取池 15 项 + spool 5 项 + body reader 3 项。覆盖前缀淘汰/范围、密钥/MAP 顺序、PDT/断点、部分终态、EVENT/VOD、URI 映射和预算、未知属性及异常合同；新文件不替代平台 UI/录制验收。

**1/1 独立原生探针**：`tool/probes/hls_retained_publication_probe_test.dart`。

1. 重用已固定哈希的 60 秒 H.264/AAC 分轨 fMP4 夹具，各轨保留最后三个分片。
2. 直连参考由原文件的 MAP、EXTINF/URI 原文独立截取，不调用新渲染器。视频序号 27–29，音频 28–30；两轨各自比较，不把不同尾段窗口当作完整 A/V 同步证明。
3. 预取两个初始化段、六个媒体段，共 **8 条目、623,258 B**，所有 ticket.ready 为 true 后关闭 HTTP 源站与其客户端。
4. 原生 ffprobe 通过新渲染清单，从池的读取租约取回所有八个资源。视频 **180 包**，音频 **189 包**；与各轨直连参考逐包相等（仅忽略容器字节位置 pos），stderr 为空、退出码 0。
5. 源站请求计数关闭后维持 **18**，原生缓存读取不回源。关闭池后条目和计费字节均为 0。

独立工具 `D:\Soft\ffmpeg\bin\ffprobe.exe` SHA-256：`02A6801CE4AA4B84706771C511C6802AFF5EFD2FE15EE305F9303E74413ECEF6`。这次没有运行应用 FFmpegKit 录制会话、连续慢源控制、加密媒体解码或 Android/Windows UI；不据此宣称完整录制 PASS。Flutter 原生 hook 仍提示远端缺少 SHA，本机 ffprobe 的独立固定哈希检查并不替该远端包背书。

## 证据与失败记录

根：`local-artifacts/hls-retained-publication-20260909/`，原生输出 `controls/publication-1788952282720044/`，包含两份输出清单、两轨 direct/cached 逐包 JSON、四份 stderr 和 evidence.json；check.ps1、阶段日志、四源码哈希及 artifact-index.json 在根目录。

| build-records 记录 | 结果 | 含排队秒数 | 峰值 CPU % | 峰值工作集 B | 结束活跃重型进程 |
| --- | --- | ---: | ---: | ---: | ---: |
| 20260909T110722043Z-hls-retained-publication-first.json | 新探针使用错误的参数 spread 语法，format 失败；改为 joinAll 列表 | 12.467479 | 5.90 | 11269169152 | 0 |
| 20260909T110831033Z-hls-retained-publication-syntax-fixed.json | 闭包后的 cascade 被解析到 String，analyze 失败；调整配置顺序 | 41.3078098 | 13.08 | 12054478848 | 0 |
| 20260909T111126075Z-hls-retained-publication-checked.json | format / analyze / 70 定向 / 1 原生通过 | 128.0458828 | 72.24 | 14325014528 | 0 |

三次均使用资源守卫，等待上一真实会话结束后才改源码或重跑；未重启其他重型进程。

## 下一步，不缩减原目标

1. 将真正选中的视频/音频清单接到共同录制来源代次，独立于 native 消费速度刷新；补齐池 loader 的 HTTP 状态、Content-Range、压缩长度、敏感头/查询策略与每请求取消。
2. 明确清单发布引用、下载/读取租约、消费后淘汰的统一所有权。现有池 8 条目/6 并发是全局边界，不为每个轨道另开一池掩盖资源翻倍；遇双轨持续慢交付需用时序证据重新确定有界预算/公平性。
3. 保持未知/LL-HLS 标签合同显式，不把 PART、SERVER-CONTROL、SKIP 等静默丢掉；常规旧路径仍保留现有行为。
4. 生产接线后重跑原 12 秒交付/6 秒窗口控制，检查持续连续序号、首输出延迟、停止排空、资源归零及包时间线，再复测真实 TTing 和设备候选。
5. 九个平台组、完整 Android/Windows 验收、说明书与全平台 3.2.0 发布继续保留，未被本批基础验证替代。
