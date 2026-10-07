# G01.4 Steam 选清晰度实际仍是自适应：用档位限定 HLS 变体

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：2026-10-07 docs v2 核对：E 组（UPGRADES 27-7 写“完成”不对）、G 组复核属实（各档都是同一个主列表，`steambroadcast_site.dart:440-448`）。已批准升级 27-7（[specs/UPGRADES.md](../../../specs/UPGRADES.md)）随本任务改成“部分完成”
- 相关：Steam 适配器 [E03.14](../../../E-直播平台/E03-海外平台/E03.14-Steam直播/README.md)；播放核心 [G01.1](../G01.1-播放核心/README.md)（取流管线、本地中继）；niconico 的同类做法（`packages/live_media/lib/src/inputs/recipes.dart:22-50`，3.x 的 `HlsMasterSelection`）；决定 D-001、D-017
- 任务书：[brief.md](brief.md)

## 目标

Steam 直播间的清晰度菜单里有“自适应 HLS”和每个变体（`1080p60`、`720p`、`480p`……，27-7）。现在选哪一档播的都是同一个主列表，播放器（mpv）照旧自己挑变体，所以选“480p”省不了流量、选“1080p60”也不保证清楚——菜单只是名字。

做完以后：选具体档位时只播那一个变体（和它的音轨），换档立即换画质；“自适应 HLS”照旧让播放器挑；复制直链、投屏仍给主列表地址（外部播放器自己挑）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 清晰度 | 只有“自适应 HLS”一档 | `SteamBroadcastApi.quality`（`packages/live_core/lib/src/sites/steambroadcast/steambroadcast_api.dart:434-440`）+ 每个变体一档，数据是 `SteamBroadcastVariant`（`:49-113`，`id`、宽高、`BANDWIDTH`、帧率、编码） | 不变 |
| 选了一个变体 | — | `resolvePlayUrlsRaw`（`steambroadcast_site.dart:466-471`）→ `_resolution`（`:440-448`）：**一律返回主列表**作为唯一线路，只带上变体的编码和 `appliedQualityData`；注释说“a variant's quality plays it restricted to the variant (M7)”（`:438-439`、`steambroadcast_api.dart:1024-1028`），但播放层没有任何地方用 `SteamBroadcastVariant.selectIn`（`steambroadcast_api.dart:82`，全仓库只有测试调用） | 播放时把主列表改写成只剩这个变体 |
| 播放层怎么走 | — | `MediaRoute.of`（`packages/live_media/lib/src/source.dart:111-127`）：HLS 只有在有令牌传递策略（`queryPolicy`）或租期切断连接时走本地中继，其余 `direct`，mpv 直接拿主列表；中继本来就支持改写主列表（`HlsRelayRecipe.master`，`relay/hls_relay.dart:36-38`），niconico 用它限定变体（`inputs/recipes.dart:37-48`） | Steam 的变体档走中继、用 `master` 改写 |
| 测试 | — | `packages/live_core/test/sites/steambroadcast_site_test.dart:774` 只测到“选择器能在主列表里找到变体”（`selectIn` → `/3500000/video.m3u8`），没测播放层用不用 | 加播放层的测试 |

## 方案

- c1 `live_core`：加一个小接口 `HlsVariantSelector`（例如放在 `lib/src/hls_master.dart`：`HlsMasterSelection selectIn(String text, {required Uri source})`），`SteamBroadcastVariant` 实现它（方法已经有了）。`LivePlayUrlResolution` 加可选的 `sourceVariantSelectors`（按线路地址，和现有的 `sourceQueryPolicies` 一样的形状，只加不改）；Steam 的 `_resolution` 对变体档填上。
- c2 `live_media`：`PlaybackPlan` 加 `variantSelectorFor(source)`（照 `queryPolicyFor`，`source.dart:204`）；`MediaRoute.of` 多一个参数，HLS 有选择器时走 `hlsRelay`；`MediaOpener.open`（`input.dart:112-160`）把它放进 `HlsRelayRecipe(master: (source, text) => selector.selectIn(text, source: source).rewrite(source, text))`（照 niconico）。主列表刷新（CDN 换主机）时选择器按 `id` 和最近的 `BANDWIDTH` 重新找（`selectIn` 已经这样写），找不到就报错让会话换线路或回退自适应。
- c3 复制直链、投屏（`StreamUse.copy`、`StreamUse.cast`）照旧给主列表地址，不受影响（它们不走 `MediaOpener`）。
- c4 文档：UPGRADES 27-7 已改成“部分完成”并指向本任务；完成后改回“完成（G01.4）”。
- 不改：清晰度列表和名字；“自适应 HLS”；录制（`packages/live_record` 录 Steam 时是否限定变体另看，见“留下的问题”）。

## 验证

- 自动测试：`packages/live_media/test/relay_test.dart` 加中继用例（假的 Steam 主列表，选 720p 后中继给 mpv 的主列表只有一个变体和它的音轨）；`plan_test.dart` 的路由加“HLS + 选择器 → hlsRelay”；`steambroadcast_site_test.dart:774` 加断言 `resolution.variantSelectorFor(...)` 是那个变体。
- 真机：有代理时 K90 上 Steam 直播间换档（任务书“真机验证”）；做之前“未开始”。

## 留下的问题

- 录制 Steam 时选了变体是否也只录那一路，没有核对（`packages/live_record` 的取流），写进记录；需要时另开 H 组任务。
- 走中继比直连多一层本地转发（CPU 很少），自适应档不受影响。
