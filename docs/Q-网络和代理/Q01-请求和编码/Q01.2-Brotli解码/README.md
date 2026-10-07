# Q01.2 Brotli 解码（猫耳弹幕、哔哩哔哩 protover 3）

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能
- 来源：E02.4 猫耳 FM 的弹幕帧是 Brotli、D01.2 哔哩哔哩弹幕的 protover 3 是 Brotli，而 pub 上的 `brotli` 0.6.0 要求 SDK <3.0.0、Dart 3.13 装不上，SDK 和工作区里都没有 Brotli 解码；在网络包里自己写一个
- 旧编号：M1.1、T03a.2
- 相关：前一块 [Q01.1](../Q01.1-网络/README.md)；用它的 D01.2（哔哩哔哩，UPGRADES 附录 B-3）、猫耳弹幕（D01）；依据 RFC 7932，参考实现 google/brotli 1.2.0；记录 [record.md](record.md)

## 目标

- 应用能解 Brotli：猫耳弹幕能收、哔哩哔哩弹幕能用和网页一样的 protover 3（压缩率更高）。
- 解码器和参考实现逐字节一致；坏数据只抛 `FormatException`，不卡死、不越界、不被“解压炸弹”拖垮内存。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 结果 |
|---|---|---|---|
| Brotli | 没有；哔哩哔哩弹幕用 protover 2（zlib），猫耳弹幕没有 | `packages/live_net/lib/src/codec/brotli.dart:25` 的 `brotliDecode(data, maxOutput:)`，在 `live_net.dart` 导出 | 新增 |
| 哔哩哔哩弹幕 | protover 2 | `packages/live_danmaku/lib/src/sites/bilibili.dart:327`（`protocolVersion = 3`）、`:452`（op 5 的 protover 3 包，`maxOutput` 用剩余的 16 MiB 额度） | 改回 protover 3（B-3，D01.2） |
| 猫耳弹幕 | 没有 | `packages/live_danmaku/lib/src/sites/missevan.dart:255`（帧首字节 1 表示 Brotli，后 3 字节是解压长度，作 `maxOutput`） | 新增（E02.4、D01） |

## 结果

- 改动（提交 `a2b5c0610`，2026-09-29，“feat(live_net): pure-Dart Brotli decoder (M1.1)”）：
  - c1 解码器 `codec/brotli.dart`（759 行）：64 位位缓冲、两级前缀码表（一级 8 位、最长 15 位）、输出即窗口、最近 4 个距离的环、字典引用和 121 种变换、四种上下文模式合成一张 2048 项的表、三类块切换。
  - c2 表 `codec/brotli_tables.dart`（303）和静态字典 `codec/brotli_dictionary.dart`（1474，生成；`tools/brotli/gen_dictionary.py` 从 RFC 附录 A 提取，核对长度、CRC-32 和本机 `libbrotlicommon`，SHA-256 `20e42eb1…5c70`）。
  - c3 检查：大窗口标记、多余的零半字节和零字节、保留位、填充位、流后多余字节、码表超额或不完整、各种越过元块剩余长度、距离不大于 0、截断——都抛 `FormatException`（消息以 `Invalid Brotli stream:` 开头）；`maxOutput` 在读到元块长度时就判断。
  - c4 测试向量生成脚本 `tools/brotli/gen_test_vectors.py`（参考实现只用来生成，不是仓库依赖），向量 1.4 MB 在 `packages/live_net/test/data/brotli/`。
- 偏差：只做一次性接口，不做流式（猫耳一帧、哔哩哔哩一个包各自是完整的流）。
- 测试：`packages/live_net/test/brotli_test.dart`，记录写 18 个用例（按 `test(` 计 16 个，部分用例按向量组循环），`lib/src/codec/` 行覆盖率 100%：官方 41 个流、参考编码器 236 个、自造 254 个（17 个坏流）与参考解码器逐个一致；2447 个变异流的结论一致；75,117 个截断前缀全部 `FormatException`；随机字节和随机翻转；1 GiB 的解压炸弹在 1 秒内拒绝；猫耳 10 个真实帧。
- 性能：1 MiB 英文文本 AOT 约 6～7 毫秒（C 参考实现约 2 毫秒），弹幕帧在微秒级（记录“性能”）。

## 验证

- 自动测试：`cd packages/live_net && dart test test/brotli_test.dart`（约 7 秒）。
- 真机：没有单独的 verify.md。哔哩哔哩弹幕（protover 3）在 K90 冒烟（S02.2）里正常显示；猫耳弹幕没有 K90 记录（D 组的说明已列为“完成但没有真机结果”的平台之一）。

## 留下的问题

- 只有一次性接口、整个输出放在内存里、不支持大窗口和共享字典（都不属于 RFC 7932 或用不到）：不做。
- HTTP 响应的 `content-encoding: br` 不会自动解（`IoLiveHttp` 只开 gzip、deflate）：现在没有平台请求 `br`，见 [Q01 已知问题](../README.md#已知问题和限制)。
