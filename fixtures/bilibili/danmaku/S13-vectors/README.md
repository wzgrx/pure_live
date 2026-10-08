# S13 弹幕向量（合成）

录制样本 `S13-live` 里没有醒目留言、`p_is_ack`、登录后的完整昵称，也没有畸形帧，这里用合成的 WebSocket 消息补上，所以没有 `meta.json`。

- `frames.jsonl` 和 `expected.json` 都由 `../legacy_expected.dart` 写出：每一行是一条收到的消息，`vector` 是它所属的向量名；同一个向量的消息依次交给同一个 3.x `BiliBiliDanmaku` 实例。
- 消息的形状照 `S13-live` 的 `DANMU_MSG`；醒目留言照 `fixtures/bilibili/S06-live` 里 `super_chat_info.message_list[0]` 的字段，用户、头像、`token` 是合成的。
- 没有 brotli（protover 3）的向量：3.x 的 brotli 包在 Dart 3 上装不上，新代码也不再请求 brotli（见 docs/D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕）。M5.F（B-3）改回 protover 3 后，brotli 向量放在 `../S13-brotli-vectors`，这里不变。
- 对照测试：`packages/live_danmaku/test/sites/bilibili_test.dart`。
