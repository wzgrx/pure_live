# 0010 live_core 的领域模型与错误类型

- 状态：已接受
- 日期：2026-09-27

## 背景

诊断的跨模块结论（[DIAGNOSIS.md](../rewrite/DIAGNOSIS.md)）指出三个根本问题：

- 数据不自描述：请求头、租期、线路身份、画质确认都在旁路。
- 错误没有类型：平台层返回“状态未知”的房间来掩盖失败，界面只能拿到中文句子。
- 同一个量在不同口径间混用：热度、在线、累计互相顶替。

5 个平台规格（`spec/sites/*.md`）和录制样本给出了 v4 需要的字段和错误。第 4 阶段实现适配器之前，先把它们共用的类型定下来。

## 决定

`live_core` 是纯 Dart 包，下列类型都是不可变值，放在 `packages/live_core/lib/src/`：

1. **身份**：`RoomRef`（平台 + 房间号，规范化后比较）。短号、别名、分享链接由适配器解析成规范房间号，一个房间只有一个 `RoomRef`（B 站短号 6 → 7734200）。
2. **状态**：`LiveState` 只有三个值：`live`、`offline`、`replay`（轮播或回放）。拿不到状态就是错误，不存在“未知”状态。
3. **人数**：`Audience` 分三个口径：`online`（在线）、`popularity`（热度）、`cumulative`（累计）。每个口径可以为空，互不顶替；界面按有值的口径显示对应的说法。
4. **列表**：`RoomCard`（卡片需要的字段）和 `RoomDetail`（卡片加头像、简介、公告、原站链接和弹幕参数）。分页结果是 `Page<T>`，下一页用不透明的 `PageCursor`，没有游标就是最后一页；是否结束由适配器按平台规则判断，不靠条数。
5. **取流**：
   - `Quality` 的 `id` 是平台的不透明请求码（斗鱼 rate、B 站 qn），`rank` 用来排序。
   - `StreamLine` 自带播放所需的全部数据：地址、格式、请求头、线路身份（CDN 码）、请求的画质、服务端确认的画质（可空，表示未确认）、编码和租期。
   - `Lease` 记录续期时刻 `refreshAt`、到期时刻 `expiresAt`，以及到期是否断开已建立的连接 `cutsConnection`：斗鱼为 true，走拼接续流；虎牙为 false，只预取。
   - `StreamSet` 是一次取流的结果。
6. **错误**：`SiteError` 是 sealed 类，适配器只抛它的子类，界面和恢复策略按类型处理：
   - `NotFound`：房间或主播不存在。
   - `NeedsLogin`：需要登录。
   - `RateLimited`：限流，可带建议的等待时间。
   - `RiskControl`：风控，包括签名被拒、验证码、过期 Cookie。
   - `RegionBlocked`：地区限制。
   - `StreamUnavailable`：在播但没有可用视频流。
   - `UnsupportedLink`：认不出的链接。
   - `ApiChanged`：响应形态和规格不符，带原始片段的摘要。
   - `NetworkFailure`：网络层失败，可重试。
7. **能力接口**按能力拆分，平台只实现自己支持的部分：`LiveSite`（身份和能力）、`CatalogSource`、`SearchSource`、`RoomSource`、`StreamSource`、`LinkResolver`。弹幕接口放在 `live_danmaku`，不进 `live_core`。

## 修订（2026-09-27，四个平台解析器完成后）

- **顺序**：`Page.items` 和 `StreamSet.lines` 按平台规格规定的顺序排列：规格没有要求重排时保持平台顺序，要求重排时照规格（例如 B 站列表按热度，线路按规则排序）。
- **`StreamUnavailable`** 的含义扩为“现在没有可播放的流”：未开播、轮播或回放没有流、在播但没有视频流。界面结合房间状态显示原因。
- **未知的开播状态**抛 `ApiChanged`，不当作未开播（规则 2）。
- **封禁或锁定的房间**（B 站 `lock_status`）暂不建模。有样本后再决定，是加一个状态，还是映射成错误。
- **短号和别名**不进 `RoomDetail`：适配器比较输入的 `RoomRef` 和 `detail.ref`，自行记录对应关系。

## 备选方案与放弃理由

- **沿用旧版 `LiveRoom`**：一个类同时承担卡片、详情、收藏、历史和 IPTV，有 40 多个可空字段，还有 `status` 和 `liveStatus` 两套状态。
- **错误用字符串或错误码**：界面只能按文字匹配，文案一改就坏，恢复策略也无法区分“该重试”和“不该重试”。
- **租期由播放层从 URL 的 `expire` 参数推断**：参数名因平台和 CDN 而异，虎牙的凭据到期又不会断开连接。只有适配器知道租期的真实含义。

## 影响

- 适配器测试拿录制样本（`fixtures/`）驱动 v4 适配器，把结果和旧版期望值比较；规格判定旧版有错的字段，在测试里写明差异。
- 旧应用接入 v4 适配器（3.3.x）时，由一层转换把 `RoomDetail` 等映射回 `LiveRoom`。
