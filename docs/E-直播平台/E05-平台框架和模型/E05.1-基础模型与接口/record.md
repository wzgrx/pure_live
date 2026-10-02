# E05.1 基础模型与接口

- 日期：2026-09-28
- 目标包：`packages/live_core`（纯 Dart，依赖 `live_net`、`meta`）
- 参考仓库核对：pure_live_TV `9fb40418`

## 对照

| v3 文件 | 行数 | 重构后 |
|---|---|---|
| `common/models/live_room.dart` | 912 | `live_room.dart`（直播间、回看）、`audience.dart`（人数口径、平台能力表、排序键） |
| `common/models/live_area.dart`、`model/live_category.dart`、`model/live_anchor_item.dart`、`model/live_play_quality.dart` | 142 | `live_area.dart` |
| `common/models/live_message.dart` | 200 | `live_message.dart` |
| `core/interface/live_site.dart`、`live_search.dart`、`live_directory.dart`、`live_quality_discovery.dart`、`live_input_recipe.dart` | 519 | `live_site.dart`、`input_recipe.dart` |
| `core/interface/live_danmaku.dart`、`core/danmaku/empty_danmaku.dart` | 97 | `live_danmaku.dart` |
| `core/common/hls_source_query_policy.dart` | 85 | `hls_source_query_policy.dart` |
| `core/utils/live_quality_label.dart` | 150 | `quality_label.dart` |
| `core/common/convert_helper.dart` | 6 | `convert.dart` |
| — | — | `site_error.dart`：类型化错误，来自归档 v4 |

## 审查发现的 v3 问题

| # | 问题 | 位置 | 根因 | 处理 |
|---|---|---|---|---|
| 1 | 直播间按“平台+房间号”判断相等、计算哈希，但这两个字段可以修改。房间放进 Set 或 Map 之后被改，就再也找不到 | `live_room.dart:251-273,540-544` | 模型全是可变字段 | 模型不可变；平台和房间号在创建时规范化 |
| 2 | 模型依赖播放器的音量存储、网络层的请求头规则，还有界面的文案键 | `live_room.dart:1-2,551-557,634-640` | 分层混乱 | 音量存储移到播放和存储模块（G、J02.1），文案键移到界面层 |
| 3 | 同一个状态存了三份：`status`、`liveStatus`、`isRecord`。构造函数里 `status` 默认 false，所以适配器只要忘了设状态，房间就成了“未开播” | `live_room.dart:283-292,317-355` | 状态没有唯一来源 | 只保留 `liveStatus`（null 表示“这次响应没说”）；`status` 和 `isRecord` 写 JSON 时从它推出 |
| 4 | `copyWith` 清不掉字段，“回到直播”只能先复制再改字段 | `live_room.dart:891-897` | 可空字段用 null 表示“不改” | 回看信息单独成值对象 `CatchUp`，用 `withoutInterval()` 去掉播放区间 |
| 5 | `toJson` 不写 `link`，但 `fromJson` 会读，备份里丢了房间链接 | `live_room.dart:559-597` | 遗漏 | 加上 `link`（3.x 读得懂这个字段） |
| 6 | 弹幕颜色只认 4、6、8 位十六进制：蓝色 `0x0000FF`、深灰 `0x0A0A0A` 这类 1–3、5、7 位的值和负数都变成白色 | `live_message.dart:128-150` | 按字符串长度解析 | 改用位运算。pure_live_TV 也修了（补足 6 位后取最后 6 位），效果相同 |
| 7 | 平台接口的 `id` 和 `name` 是可变字段；方法名拼错（`getCategores`、`getPlayQualites`）；`getRoomDetail` 多带一个没用的 `platform` 参数，默认实现返回的房间号是空的 | `core/interface/live_site.dart:195-270` | — | 改为 getter；修正方法名；去掉多余参数；默认实现用传入的房间号 |
| 8 | 接口依赖 dio 的 `CancelToken`，取消时抛 dio 的异常 | `live_search.dart`、`live_quality_discovery.dart`、`live_directory.dart` | 模型层依赖具体的 HTTP 库 | 改用 `live_net` 的 `CancelToken`，取消时抛 `TransportFailure(cancelled)` |
| 9 | 出错时适配器返回一个“看起来像未开播”的房间，或者一句中文。临时出错会被当成下播，录制因此停止 | 各适配器（诊断报告） | 错误没有类型 | 引入 `SiteError`：NotFound、NeedsLogin、RateLimited、RiskControl、RegionBlocked、StreamUnavailable、UnsupportedLink、ApiChanged、NetworkFailure。各平台在 E 改用 |
| 10 | `LivePlayQuality.withPlaybackUnconfirmed(bool)` 用位置布尔参数，调用处看不出含义 | `model/live_play_quality.dart:26` | — | 改为命名参数 `unconfirmed:` |

## 保留的 v3 行为

- **JSON 格式逐字段兼容 3.x**，3.x 数据的迁移（J02.1）和备份导入都依赖这一点：
  - 键名不变；
  - `liveStatus` 存枚举**序号**，顺序是 live、offline、replay、unknown、banned，不能变；
  - `audienceMetricType` 存名字；
  - 没有 `liveStatus` 时，由旧的 `status` 推出；
  - `isRecord: true` 表示回放；
  - 虎牙把热度误存为在线人数的旧记录，读取时迁回热度；
  - `watching` 默认 `'0'`，这个值不算测量结果。
- **稀疏合并**：刷新结果里没带的字段保留旧值；标签只在本地；IPTV 的请求头以播放列表为准；平台和房间号不同的房间不合并。
- **人数口径**：
  - 热度、在线、累计三者分开，保留各平台的能力表和注释；
  - “优先显示在线人数”模式下，排序分三档：有明确在线数、在线数待定、只有原生数值；
  - 数值相同时按房间标识排序，刷新时卡片不乱跳；
  - 哔哩哔哩详情接口偶尔返回热度 `1` 时，保留列表里的热度。
- **画质标签**：各平台代码转成中文；原本就是中文的标签不动；依次退回到分辨率、原始标签、码率、编号。
- **取流**：
  - 去掉空白和重复的地址，保持平台给的线路顺序；
  - 平台确认了实际画质就用确认的，否则按请求的画质，并标为“未确认”；
  - HLS 查询策略只对它创建时对应的那个地址生效。
- **可选能力接口全部保留**：
  - 画质确认、逐条线路解析、恢复时重新取地址、签名地址的续期时间；
  - 关注卡片的轻量刷新、录制前的严格详情；
  - 可取消的搜索、按关键词分页、画质探测和它的生命周期；
  - 原生分页和游标分页、目录说明。
  
  调用方式和 v3 一样，通过基类上的扩展方法统一调用。

## 行为上的有意变化

- **构造直播间时不再默认“未开播”**：没给状态就是“未知”（显示为待定）。v3 的默认 `status=false` 是问题 3 的来源。E 的各平台会显式给出状态。
- **回放并入 `liveStatus`**：v3 里“直播中 + isRecord”在显示上已经是回放，现在直接存为回放。之后的刷新只要明确给出状态，就以刷新结果为准。
- **JSON 多写一个 `link` 字段**。

## 放到其他模块的部分

| v3 内容 | 去向 |
|---|---|
| `core/common/binary_writer.dart`、`core/common/utils/list_util.dart` | D01 弹幕（只有弹幕协议用） |
| `pkg/tars`、`core/tars` | E 虎牙 |
| 直播间的音量读写（`LiveRoomVolumeManager`） | G 播放、J02.1 存储 |
| `audienceMetricI18nKey` | 界面层（M13） |
| `common/models` 下的应用级模型：字体、版本、B 站用户信息、刷新率 | 对应页面的模块 |

## 上游核对

- pure_live_TV 的模型改用了 freezed，`AudienceMetricType` 的顺序也变了（`unknown` 在前，还加了 `watching`），和 3.x 的 JSON 不兼容。v4 以 3.x 的格式为准，电视端并入时用同一个模型。
- pure_live_TV 另外有按弹幕类型取颜色的表（`LiveMessageColor.fromType`），留到 D01 评估。

## 测试

81 个用例，连续跑 3 次全部通过：

| 测试文件 | 内容 |
|---|---|
| `live_room_test.dart` | 移植 v3 三个测试文件的 26 个用例（人数口径、状态、出错时退回待定），按新模型调整了构造方式。另加 3.x JSON 的逐字段往返、回看字段、宽松类型读取、状态枚举顺序、身份规范化和集合去重 |
| `models_test.dart` | 分区的 JSON 和身份（含猫耳命名空间）、弹幕颜色（覆盖 v3 出错的几类值）、醒目留言的相等性、画质标签（移植 v3 的 3 个用例并补充）、`asT`、类型化错误 |
| `live_site_test.dart` | 取流的清理和画质确认、恢复时重新取地址、查询策略的校验、无地址的输入、可取消的搜索、画质探测的生命周期、基类的默认实现、空弹幕 |
| `hls_source_query_policy_test.dart` | 原样移植 v3 的测试 |
