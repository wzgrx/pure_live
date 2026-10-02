# Q01.2 Brotli 解码

- 日期：2026-09-29
- 目标包：`packages/live_net`（纯 Dart，没有新依赖）
- 依据：RFC 7932；参考实现 google/brotli 1.2.0（本机 `libbrotlicommon`、`libbrotlidec` 和 Debian 的 `python3-brotli` 1.2.0），官方测试集取自 google/brotli `d5d3f459`
- 用途：
  - 猫耳弹幕的帧是 Brotli（[E02.4](../../../E-直播平台/E02-其他国内平台/E02.4-猫耳FM/record.md) 末尾“升级落地（E06 平台层升级）”）；
  - 哔哩哔哩弹幕 protover 3 是 Brotli，[D01.2](../../../D-弹幕/D01-平台弹幕协议/D01.2-哔哩哔哩弹幕/record.md) 因为没有解码器退回了 protover 2（zlib）。
- 为什么自己写：pub 上的 `brotli` 0.6.0 要求 SDK `<3.0.0`，Dart 3.13 装不上；SDK 和工作区里都没有 Brotli 解码。

## 接口

```dart
Uint8List brotliDecode(List<int> data, {int? maxOutput})
```

- `data` 必须正好是一个完整的 Brotli 流。
- 坏数据一律抛 `FormatException`（消息以 `Invalid Brotli stream:` 开头），包括：
  - 截断；
  - 流结束后还有多余字节（同 Python `brotli.decompress`；C 的一次性接口 `BrotliDecoderDecompress` 会忽略多余字节）；
  - “大窗口”扩展（窗口位 `0010001`，不属于 RFC 7932）；
  - RFC 写着“should be rejected”的情况，按参考解码器的做法处理，见下面“检查”。
- `maxOutput`：解压结果超过这个字节数就抛 `FormatException`（消息含 `limit of N bytes`）。
  - 在元块头读出长度时就判断，不等解完这个元块，也不先分配内存。所以几百字节的“解压炸弹”（本来能解出 1 GiB）在第一个元块头就被拒绝，内存不超过 `maxOutput` 左右。
  - 为 null 时不限制。来自网络的数据应当设上：猫耳帧头里有解压后的长度，可以直接传；哔哩哔哩沿用 D01.2 的 16 MiB 上限。
  - 负数是 `ArgumentError`。
- 在 `live_net.dart` 里导出。`brotli_tables.dart`、`brotli_dictionary.dart` 是内部文件，不导出。

**不做流式接口**：猫耳的一帧、哔哩哔哩的一个 protover 3 包，各自都是一个完整的流，一次解完即可。以后真有分块到达的场景，先拼起来再解；那时再考虑增量接口。

## 做法

| 文件 | 内容 |
|---|---|
| `lib/src/codec/brotli.dart` | 解码器：位读取、前缀码、上下文模型、块切换、距离、字典引用、元块 |
| `lib/src/codec/brotli_tables.dart` | RFC 的固定表：上下文查找表 Lut0～2（第 7.1 节）、字典的 NDBITS 和各长度的起点（第 8 节）、121 种变换（附录 B）及其应用 |
| `lib/src/codec/brotli_dictionary.dart` | 静态字典，生成的文件（见下节） |

- **位读取**：64 位整数作缓冲，每次补 32 位（`ByteData.getUint32`），最多存 63 位，保持非负。输入末尾之后补零；用到了补的零，就在下一次补位或流结束时报“截断”。所以不会越界读，也不会在截断的数据上空转。
- **前缀码**：两级查表，一级 8 位，最长码 15 位，建表方法同参考实现。每组码表按参考实现的上界（字母表大小 + 376）一次分配，按实际大小紧挨着放。简单码（1～4 个符号，含树形选择位）和复杂码（HSKIP、16/17 重复码、跨码长的重复累加）都按 RFC 第 3 节。
- **窗口**：输出本身就是窗口（整段输出在一块缓冲里），不用环形缓冲。可回溯的最大距离是 `min(已输出字节数, 2^WBITS - 16)`，超过它就是字典引用，所以窗口位不同，同一段数据的解释也不同（测试覆盖了 10～24 全部窗口）。
- **距离**：最近 4 个距离的环，初值 16、15、11、4，跨元块保留。距离码 0（包括插入复制码 0～127 隐含的 0）和字典引用不进环，其余都进环。短距离码算出 0 或负数就拒绝。
- **字典引用**：长度只能是 4～24，变换号只能是 0～120；变换后的长度先算出来，超过元块剩余长度就拒绝，然后直接写进输出。
- **上下文**：四种模式（LSB6、MSB6、UTF8、Signed）合成一张 2048 项的查找表，每个字面量只查两次表。距离的上下文按复制长度 2、3、4、更长。
- **块切换**：三类（字面量、插入复制、距离）各自的类型码和计数码。只有一种类型时计数从 2^24 起，用完就拒绝（同参考实现）。

### 检查

以下情况都抛 `FormatException`，每一项都有专门构造的坏流（`crafted.bin` 里的 `bad/*`），参考解码器同样拒绝：

- 窗口位是大窗口标记；
- 元块长度多出一个全零的高位半字节；元数据长度多出一个全零的高位字节；元数据的保留位不是 0；
- 未压缩元块或元数据前、最后一个元块后的填充位不是 0；流结束后还有字节；
- 简单码的符号超出字母表、符号重复；
- 复杂码的码长码不完整或超额（只有一个码长符号时除外）；码长不完整或超额；重复码超出字母表；
- 上下文图的零游程超出图的大小；
- 字面量插入、复制、字典词超出元块剩余长度；
- 字典引用的长度不在 4～24、变换号不小于 121；
- 短距离码算出的距离不大于 0；
- 截断。

## 静态字典

- 来源：RFC 7932 附录 A 的十六进制，122,784 字节。
- 生成：`python3 tools/brotli/gen_dictionary.py --rfc rfc7932.txt --check-lib`（不带 `--rfc` 时从 www.rfc-editor.org 下载）。
  - 脚本先核对 RFC 写明的长度和 CRC-32（`0x5136cb04`）；
  - 带 `--check-lib` 时再和本机 `libbrotlicommon` 的 `BrotliGetDictionary()` 逐字节比较；
  - 最后写出 `brotli_dictionary.dart`：Base64 分成 112 个字符一行，首次使用时解码（约 1 毫秒）。
- 校验：
  - RFC 附录 A、`libbrotlicommon` 1.2.0、google/brotli 的 `c/common/dictionary.bin` 三者一致；
  - SHA-256 `20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70`，测试核对它和 RFC 的长度、CRC-32。
- 上下文查找表和变换表也是用脚本从 RFC 文本提取的：
  - 测试核对 RFC 给出的 CRC-32（Lut0 `0x8e91efb7`、Lut1 `0xd01a32f4`、Lut2 `0x0dd7a0d6`，变换表按附录 B 的写法 648 字节、`0x3d965f81`）；
  - 另外把 121 种变换作用在字典的全部 13,504 个词上，按词长和 `libbrotlicommon` 的 `BrotliTransformDictionaryWord` 比 SHA-256。

## 测试

`packages/live_net/test/brotli_test.dart`，18 个用例，连续跑 3 次全部通过，单独跑约 7 秒。`lib/src/codec/` 三个文件的行覆盖率 100%。

测试向量在 `test/data/brotli/`，共 1.4 MB，由 `tools/brotli/gen_test_vectors.py` 生成：

- 参考实现只用来生成向量，不是仓库的依赖；
- 每组是一个 `.bin`（所有流首尾相接）加一个 `.json`（名字、位置、期望结果：输出长度和 SHA-256，或 `error`）；
- 期望结果全部来自参考解码器。

| 组 | 数量 | 内容 |
|---|---|---|
| `official` | 41 | google/brotli `tests/testdata`（MIT）里的 `.compressed` 文件：`empty.compressed.00～17`、`x.compressed.00～03` 这些手工构造的边界流，`mapsdatazrh`、`alice29` 等。只留了一部分控制大小，去掉了 `asyoulik`、`lcet10`、`plrabn12`、`empty.compressed.18` |
| `reference` | 236 | 参考编码器压缩：<br>- 13 种输入 × 质量 0～11：空、单字节、英文、中文 Markdown、猫耳弹幕 JSON、随机字节、重复、1 MiB 零、32 位整数信号、UTF-16、远距离重复；<br>- 两种输入 × 窗口 10～24 × 质量 5 和 11；<br>- 文本和字体模式；块大小 16、18、24；<br>- 两个超过 16 MiB 的流，其中的远距离重复一个正好在最大窗口（2^24 − 16）以内、一个正好在窗口外 |
| `crafted` | 254 | 生成脚本里的小编码器写的流：237 个合法流、17 个坏流。合法流的输出先和脚本自己的格式模型比对，再交参考解码器确认。覆盖参考编码器从不写出的部分：<br>- LSB6、MSB6 上下文模式和多棵树；<br>- 简单码 1～4 个符号和树形选择位，复杂码的 HSKIP 0/2/3、16/17 重复、只有一个码长符号（RFC 的 256 个 8 位码的例子）、长到 15 位的码（二级表）；<br>- 上下文图的游程和 move-to-front；三类块切换的三种类型码写法；<br>- 16 个短距离码、直接距离码、NPOSTFIX 0～3 × NDIRECT；<br>- 121 种变换每种一个流；开头就用初始距离引用字典的流；<br>- 元数据块（含最后一个元块是元数据）、未压缩元块、10～24 每种窗口 |
| `mutations.json` | 2447 | 从上面的小流派生：截断、翻转 1～3 位、末尾多加字节、把窗口位换成 18 种写法（含大窗口标记）。参考解码器拒绝其中 1867 个、接受 580 个。本解码器对每一个的结论（拒绝，或输出的长度和 SHA-256）都和参考解码器一致 |
| `transforms.json` | 21 | 每种词长的全部字典词 × 121 种变换的 SHA-256（libbrotlicommon） |

用例：

- 表：字典、查找表、变换表的 CRC-32 和 SHA-256；全部字典词的全部变换；摘要函数自检（测试自带 SHA-256，因为 live_net 不依赖 `crypto`）。
- 与参考解码器一致：三组流逐个核对；两个超过 16 MiB 的流；特性覆盖清单。
- 接口：
  - 最小的空流、普通 `List<int>` 输入；
  - `maxOutput` 等于长度时通过、少一字节时拒绝，负数报参数错误；
  - 解压炸弹：64 个 13 字节的元块，每个解出 16 MiB 零，共 1 GiB 放在 1 KB 以内。先用同样结构的 3 MiB 版本确认它是合法流；带 `maxOutput` 时在 1 秒内拒绝；
  - 大窗口标记。
- 坏数据（各在独立 isolate 里跑，外面套 2 分钟超时，防止卡死时拖住测试进程；每个输入单独计时，都要在 1 秒内）：
  - `mutations.json` 的 2447 个与参考解码器逐个一致，本机最慢的一个约 12 毫秒；
  - 截断：输出不超过 1 MiB 的合法流，1 KiB 以内的取全部前缀，更长的随机取 50 个，共 75,117 个，全部是 `FormatException`，最慢的一个约 90 毫秒；
  - 随机字节 4000 个，大流随机翻转 1～3 位 1500 个（`maxOutput` 4 MiB）：只有正常输出或 `FormatException`，没有其他异常，最慢的一个约 7 毫秒。
- 真实数据：`fixtures/missevan/danmaku/S06-live` 的 10 个下行 Brotli 帧：
  - 按帧头的长度作 `maxOutput` 解开，长度相符；
  - 都是 JSON 对象，第一帧是 `{"type":"user","event":"connect","user":{"user_id":0}}`。
  - 这批帧都是未压缩元块，Brotli 的压缩路径由上面的向量覆盖。

重新生成向量（需要 `python3-brotli` 或虚拟环境里的 `pip install brotli`，以及 `libbrotlicommon`）：

```bash
git clone --depth 1 https://github.com/google/brotli.git /tmp/brotli
python3 tools/brotli/gen_test_vectors.py --official /tmp/brotli/tests/testdata
```

脚本用固定的随机种子，同一版本的参考实现生成的文件相同。

## 性能

没有放进门禁，基准脚本在会话临时目录里。1 MiB 英文文本（Canterbury 语料 alice29、asyoulik、lcet10、plrabn12 拼接后取前 1 MiB），Intel Core Ultra 9 275HX，WSL2，Dart 3.13.4：

| 质量 | 压缩后 | JIT（`dart run`，预热后中位数） | AOT（`dart compile exe`，中位数） | C 参考实现（Python 调用） |
|---|---|---|---|---|
| 1 | 415,064 | 9.8 ms | 6.9 ms | 2.5 ms |
| 5 | 355,272 | 9.0 ms | 7.3 ms | 1.9 ms |
| 9 | 347,080 | 8.6 ms | 6.1 ms | 1.8 ms |
| 11 | 320,585 | 9.5 ms | 6.6 ms | 2.1 ms |

JIT 第一次（未预热）72 ms。弹幕帧通常只有几百字节到几 KB，解一帧在微秒级。

## 限制

- 只有一次性接口，没有流式接口（理由见“接口”）。
- 不支持“大窗口”扩展和共享字典（两者都不属于 RFC 7932）。只解码，不压缩。
- 整个输出放在内存里（它同时是窗口），内存约等于输出大小；容量翻倍增长，最后按实际长度复制一份返回。
- 前缀码表按元块头声明的数量分配。恶意的元块头最多让一个元块分配约 2.6 MiB 的表，这个元块结束或出错后就释放，不会累积。
- 不设 `maxOutput` 时不限制输出。

## 留给其他模块

| 模块 | 内容 |
|---|---|
| D01 猫耳 | 帧首字节 1 表示 Brotli，后 3 字节是小端的解压长度：`brotliDecode(帧[4:], maxOutput: 长度)`。接上后把 `audience.dart` 里猫耳的 `onlineAvailability` 改成 `roomRealtime`（E02.4 已记） |
| D01.2 哔哩哔哩 | 可以改回 protover 3：op 5 的 protover 3 包用 `brotliDecode`，`maxOutput` 用剩余的 16 MiB 额度。要不要改（压缩率更高，但 S13 的录制和向量都是 protover 2），在那一步决定，并补 protover 3 的样本 |
