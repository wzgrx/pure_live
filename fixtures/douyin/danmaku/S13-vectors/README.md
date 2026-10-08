# S13 弹幕向量（合成）

录制样本 `S13-live` 的负载都是未压缩的 `pb`，也没有 `createTime`、坏帧、别的房间、2^63 以上的编号等情况，这里用合成的帧补上，所以没有 `meta.json`。

- `frames.jsonl` 和 `expected.json` 都由 `../legacy_expected.dart`（经 `../legacy_expected.sh` 运行）写出：每一行是一帧收到的数据，`vector` 是它所属的向量名；同一个向量的帧依次交给同一个 3.x `DouyinDanmaku` 实例，`args` 是这个实例的房间参数。
- 帧用 3.x 生成的 protobuf 类构造，字段的形状照 `S13-live`；需要畸形或少见编码的向量（截断、坏 gzip、同一字段两次、字段用了别的 wire type、`needAck` 只有高位）用原始字节拼。用户、头像、编号都是合成的（昵称和编号取自 `S13-live` 里已经合成过的值）。
- 25 个向量。其中 4 个是新代码有意与 3.x 不同的（一条坏消息之后的消息、超出时间范围的消息、2^63 以上的编号），对照测试先断言 3.x 的输出确实如此，再断言新代码的输出，见 docs/D-弹幕/D01-平台弹幕协议/D01.5-抖音弹幕。
- 对照测试：`packages/live_danmaku/test/sites/douyin_test.dart`。
