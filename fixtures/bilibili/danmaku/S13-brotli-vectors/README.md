# S13 brotli 向量（合成）

protover 3（Brotli）的合成向量，M5.F（附录 B-3）补上：录制样本 `S13-protover3` 里的包都是服务端正常压缩的，这里补上分帧的各种组合和坏流，所以没有 `meta.json`。

- `frames.jsonl` 和 `expected.json` 都由 `../legacy_expected.dart` 写出，格式同 `S13-vectors`：每一行是一条收到的消息，`vector` 是它所属的向量名；同一个向量的消息依次交给同一个 3.x `BiliBiliDanmaku` 实例。
- Brotli 流用未压缩的元块写成（`_brotliStream`，RFC 7932 第 9.2 节，最简单的合法编码），参考解码器（Python `brotli` 1.2.0）能解开每一个合法的流、拒绝坏流。
- 3.x 用的 `package:brotli` 0.6.0 在 Dart 3 上装不上，生成器换成 live_net 的 `brotliDecode`（M1.1）。合法的流两者解出同样的字节；坏流 `brotli-corrupt` 上 0.6.0 会卡死（见 docs/D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕），这里记下的是 M1.1 的判定（抛错、这条消息剩下的部分丢掉）。
- 对照测试：`packages/live_danmaku/test/sites/bilibili_test.dart`。
