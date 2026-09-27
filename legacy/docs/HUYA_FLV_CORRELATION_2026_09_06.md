# 虎牙同会话收包、FLV 时间戳与缓冲关联

## 基线与目的

本地起点 `d6d4123cd83ffaf14903d74a23bf800087adc8d4`。上一轮两处生产修复已推送；本轮不合并上游、不连接手机、不改生产缓冲或线路默认值。目标是进一步定位已测到的缓冲耗尽，而非以更多延迟或重连作为解释。

## 观测方法与边界

- `tool/probes/flv_observation_relay.py`：只绑定随机 loopback 端口，只接受一次 `/observe.flv` 请求；一条上游 HTTP 会话原样转发给同一个 libmpv。
- 分开记录 `readWaitMs`（等待上游 read1）与 `writeWaitMs`（向播放器写入），与 native 时间线共用 monotonic 起点。
- 只读解析 FLV tag 边界、AVC/AAC 媒体 DTS、AVC 有符号 CTS；不把配置头当帧，不把正常 32 位回绕当倒退，不猜未知增强编码布局。检查 PreviousTagSize，记录解析错误但不修改/截断转发字节。
- 时间戳历史上限 700，跳变事件 64，IO 事件 128；chunk 为 64 KiB，FLV 单 tag 长度来自有界 24 位字段。无媒体文件、签名地址、账号或请求头日志。
- 上游请求和本地写入都有 15 秒超时；关闭 listener/thread，等已接管的 handler 退出；不停止其他项目的进程。将 native 主动 stop 前的停止意图传给 relay，区分测试收尾和运行中错误。
- **该方法改变了 TLS/HTTP 客户端和本地转发路径**，所以不把它当成 direct-mpv 等效证明；但同一个样本内部的收包、时间戳和 native 缓冲来自同一条流，而非两条独立连接拼接出的因果关系。

协议核对：[VSO FLV/AVC CTS 定义](https://veovera.org/docs/enhanced/enhanced-rtmp-v2.html)，仅使用传统 AVC/AAC 分支。

## 确定性验证

`python -W error::ResourceWarning -m unittest discover -s tool/probes -p test_flv_observation_relay.py -v`：7/7，1.058 秒。

覆盖每一种字节拆分位置、负 CTS、DTS 回绕、配置头与增强编码排除、时间戳跳变/倒退、有界历史、坏长度、字节级转发一致、UA 中逗号保留、只接管一次连接、handler/listener 释放。初次夹具未关闭预期的 HTTPError，已补显式 close，最终无该 ResourceWarning。

本轮只有诊断代码，不重复上一轮 1101 项生产回归或全量 analyze；Dart 探针编译、Python 用例和实网测试分别记账。

## TX 同会话结果

记录 `20260905T192116524Z-quality-focused.json`，原始脱敏数据 `local-artifacts/huya-correlated-tx.log`。

- 房间 660000，TX、请求码率 10000，网页令牌故意为空，原生 WUP。单连接 330.125 秒主动结束，读取 101,985,117 B，34,005 tags，解析错误 0、EOF 0。
- native 在 44.142–46.209 秒缓冲暂停；暂停开始时前向字节 0、cache-duration 0、underrun=true。
- 同一输入在 43.324–45.650 秒附近等待 read1 2326 ms；该次向 native 写入等待 0 ms，全样本最长写入等待仅 3 ms。
- 视频最大相邻 DTS 差 33 ms、音频 78 ms，无超过 500 ms 的 DTS 跳变或倒退。native 最大轮询间隔 415 ms，不足以解释约两秒时钟停顿。
- 因而该次停顿的直接证据指向**HTTP 媒体供给到达间歇**，不是本地转发写入回压或源 DTS 跳变。不仅凭这一端的 read1 时长断言哪一段网络/CDN负责；调用调度、TLS 与网络接收仍属于其观测边界。
- 呈现丢帧计数 2、解码丢帧 0；无 Flutter 纹理、硬解或真实音频设备，不作为全部观看体验通过。
- 早期 relay 收尾记录 `ConnectionResetError`：native 已主动 stop，且观测期 EOF=0，handler 已结束。之后增加显式停止意图归因，不把测试关闭读端冒充运行中上游断流。

## AL 对照结果与排除项

记录 `20260905T192822939Z-quality-focused.json`，原始脱敏数据 `local-artifacts/huya-correlated-al.log`。相同房间、请求码率、原生凭据和默认缓存，串行换 AL 观测 330.083 秒。

- 1 次上游连接，128,788,131 B、33,993 tags，EOF=0、解析错误=0、正常主动停止、handler 结束。
- 103.185–103.590 秒发生约 405 ms 缓冲暂停。同一输入 101.899–103.342 秒等待 read1 1443 ms，最大 native 写入等待仅 2 ms。
- 视频最大 DTS 差 18 ms、音频 34 ms，无异常跳变；最大轮询间隔/时钟进度间隔均 426 ms。两次 cachePauseSamples 是一个暂停区间内的采样，不是两次卡顿。
- 该样本比 TX 样本短暂停顿更少，但 AL 仍未达到零停顿。网络条件随时刻变化，两个顺序样本不支持永久硬编码某个 CDN，更不支持宣称用户网络或整个虎牙服务器有统一故障。
- 另一次只读网页元数据检查发现，样本中的 PC/Web/Mobile PriorityRate 数值一致；没有证据用“改用 PC 优先级字段”作为本轮修复。只输出 CDN/优先级，未保存房间签名材料。
- 两次探针结束后的活跃重型进程归零由各自记录核对；AL 阶段资源峰值为验证工具工作集 14,178,594,816 B、CPU 48.34%，不充当客户端占用。

## 下一步与发布门禁

1. 这次定位到同会话媒体供给到达间歇，同时排除了对应样本的 DTS 跳变、本地写入回压和自动换播放器。继续评估有界的抗抖与 CDN 健康策略，并把额外延迟作为明确代价；不以线程数、关闭缓冲 UI、固定周期换源处理此证据。
2. 任何缓冲/线路默认值修改需要故障输入回放、当前原生链路对照与首播等待度量。上一轮六秒方案已失败，不因为这轮定位更清楚就重新默认启用它。
3. 当前新增的是可重复定位基础设施与实证，不是宣告客户端彻底修复。3.2.0 发布门禁保持未完成；此次不构建或发布 APK，不修改生产版本号。
