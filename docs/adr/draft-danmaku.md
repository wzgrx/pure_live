# 草案：弹幕包 live_danmaku 的结构与协议选择

- 状态：草案（编号由主会话分配）
- 日期：2026-09-27

## 背景

弹幕规格（spec/modules/danmaku.md）要求连接到抽样全部在后台 isolate 完成，主线程只收批次，并留下几项待确认：isolate 的数量（§8 第 2 条）、相似度算法（第 4 条）、画面候选抽样倍率（第 5 条）、礼物的来源（第 1 条）。各平台协议还涉及 protobuf、brotli、Tars 的依赖选择。第 1 阶段没有录到任何弹幕帧（STATUS“还没做”），需要确定录制和脱敏方式。

## 决定

1. **一个 worker isolate 承载全部会话**（§8 第 2 条）。`DanmakuWorker.spawn` 启动一次，`open(room)` 每次得到新令牌；多画面同时开的 4–9 个房间共用一个 isolate。每个会话一个 isolate 会让空闲内存和启动时间随格子数增长，而解码负载（热门房间约 200 条/秒）一个 isolate 足够。
2. **凭据留在界面 isolate**。B 站 token、抖音会话 Cookie、用户 Cookie 由站点适配器维护（它们有 buvid、WBI、Cookie 保险箱的状态），worker 需要时发请求、界面 isolate 调 `DanmakuCredentials` 回复。worker 只收纯数据：`RoomDetail`、过滤设置、预算、`ProxyPolicy`。
3. **B 站认证用 protover 2（zlib）**，不用规格写的 3（brotli）。2026-09-27 实测服务端按 2 回 zlib 包；zlib 用 `dart:io` 解压，不需要 brotli 包（pub 上唯一的纯 Dart 实现 `brotli` 0.6.0 最后发布于 2023 年，SDK 约束 `<3.0.0`）。收到 protover 3 的包时跳过并计数。规格 bilibili §7.2 同步修改。
4. **protobuf 和 Tars 手写**，不引入 `protobuf` 包和 protoc 生成代码：抖音只读 PushFrame、Response、Message、ChatMessage、Common、User、RoomUserSeqMessage、GiftMessage 的十几个字段，按字段号读 varint 和长度字段即可；Tars 同理。生成代码有上百个类，协议字段变化时反而要重新生成。
5. **WebSocket 用 `dart:io`**，不用 `web_socket_channel`：握手的代理（`HttpClient.findProxy` 按 `ProxyPolicy`）、请求头、超时后强制中断握手都能直接控制，少一层依赖。
6. **相似度算法**（§8 第 4 条）：部分匹配比。短文本与长文本中每个等长窗口比较，得分 `100 × 最长公共子序列 / 长度`，取最高；62 个码点以内用位并行算法，更长用动态规划，文本截到 256 个码点。先用整段的最长公共子序列作上界排除明显不相似的文本。与 fuzzywuzzy 的 `partialRatio` 相比，它检查所有窗口而不只是匹配块对齐的窗口，所以得分不会更低（过滤只会更积极一点）；这个开关默认关闭。
7. **抽样**（§8 第 5 条）：画面候选速率 = 画面发射速率 × 1.5（房间 30 条/秒，画中画约 4.3 条/秒），按批次均匀取样；未用完的预算最多留 0.25 s，空闲后的第一批不会一下放出过多。倍率仍待用 200 条/秒样本校准。
8. **礼物**（§8 第 1 条）：斗鱼 `dgb`（有名称和数量，无价格）、B 站 `SEND_GIFT`（金瓜子按 1000 = 1 元）、抖音 `GiftMessage`（连击只在结束时出一条，1 钻 = 0.1 元）解码为 `DanmakuGift`；虎牙礼物包只有 ID 没有名称，暂不解码。批次里礼物单独一栏（`gifts`），不混进聊天列表，由应用决定显示位置。
9. **启动超时即终态**：20 s 内没有加入，发 `timeout` 并关闭连接，释放房间；手动刷新重新开会话。不在后台无限重试。
10. **弹幕样本**（ADR 0009 第 3 条的具体做法）：`fixtures/<平台>/danmaku/<情况>/frames.jsonl` + `meta.json`，由 `live_cli danmaku --record` 录制。帧先解码、脱敏、再按原协议编码（B 站重新 zlib 压缩，抖音重新 gzip），样本仍能被真实解码器读取；没有解码的消息类型清空负载、保留类型。写入前检查被替换的原值不再出现。

## 备选方案与放弃理由

- **每个会话一个 isolate**：隔离更好，但多画面时内存和启动开销成倍增长；会话之间已有令牌和房间键隔离。
- **在 worker 里再建一套站点适配器取凭据**：B 站 buvid/WBI 会话、抖音匿名 Cookie、Cookie 保险箱都要在两个 isolate 各维护一份，登录变化时容易不一致（REG-DOUYIN-017 的教训）。
- **按规格用 protover 3 并引入 brotli 包**：多一个多年未维护的依赖，只换来略小的压缩包。
- **`protobuf` 6.1.0 + 生成代码**：旧版就是这样，生成了几千行代码，而实际只读十几个字段。
- **样本只存解码后的 JSON**：测试就测不到封包、压缩和字段号，接口变化也看不出来。

## 影响

- `packages/live_danmaku` 依赖 `crypto`、`meta`、`live_core`、`live_net`，开发依赖 `fake_async`（假时钟测试）。
- `tools/live_cli` 增加 `danmaku` 命令（打印、`--pipeline` 走 worker、`--record` 录样本）。
- 规格修改：bilibili §7.2（protover 2）；斗鱼、虎牙、抖音、快手第 7 节按实测补充（见各文件）。
