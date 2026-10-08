# G01.4 Steam 选清晰度实际仍是自适应：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[G01.4]` 提交）
- 设计或说明：[README.md](README.md)、[brief.md](brief.md)

## 复现（经代理 127.0.0.1:7897）

- `live_cli probe steambroadcast 76561199845912453 --quality 480p`：清晰度 `auto 1080p60 720p 480p 360p`，选 480p 解析出 1 条线路，就是 `…/master.m3u8`（1543 字节，HLS 主列表，里面 4 个变体都在）。播放层拿到它走 `direct`，mpv 自己挑变体。

## 根因

- `packages/live_core/lib/src/sites/steambroadcast/steambroadcast_site.dart:440-448`（改之前的 `_resolution`）：每一档都只返回主列表这一条线路，变体只用来填编码和 `appliedQualityData`；`SteamBroadcastVariant.selectIn` 只有测试调用。
- 播放层没有地方能接“这条线路要限定哪个变体”：`LivePlayUrlResolution` 只有 `sourceQueryPolicies`，`MediaRoute.of`（`packages/live_media/lib/src/source.dart:111-127`）对没有令牌策略、没有切断租期的 HLS 一律 `direct`。

## 改了哪些文件

- `packages/live_core/lib/src/hls_master.dart`：新接口 `HlsVariantSelector`（`selectIn(text, source:)` 返回 `HlsMasterSelection`）。
- `packages/live_core/lib/src/live_site.dart`：`LivePlayUrlResolution` 加 `sourceVariantSelectors`（按线路地址，默认空）；`lines(...)` 加可选参数 `sourceVariantSelectors`，键必须是线路地址（否则 `FormatException`）；`normalized()` 去重后保留。其他构造函数一律为空，旧调用不变。
- `packages/live_core/lib/src/sites/steambroadcast/`：`SteamBroadcastVariant implements HlsVariantSelector`；`_resolution` 对变体档给主列表线路填上这个变体，“自适应 HLS”不填。恢复时（重新取的主列表，CDN 主机可能变）照旧按档位 id 在新回答里找变体，找到就带新的选择器；新回答没有这一档时照旧回到自适应并报 `appliedQualityData = auto`（E03.14 的既有行为，界面会显示实际档位）。
- `packages/live_media/lib/src/source.dart`：`PlaybackPlan.variantSelectors` 和 `variantSelectorFor(source)`（照 `queryPolicyFor`）；`MediaRoute.of(…, variantSelector:)`：HLS 有选择器时走 `hlsRelay`。
- `packages/live_media/lib/src/input.dart`：`MediaOpener.open(…, variantSelector:)`，中继的 `HlsRelayRecipe(master: (source, text) => selector.selectIn(text, source: source).rewrite(source, text))`（照 niconico），可以和 `queryPolicy` 同时有。主列表里找不到这个变体时中继回 502，播放器当打开失败，会话按现有规则换线路或报错，不会悄悄播别的档。
- `packages/live_player/lib/src/session.dart`：打开线路时多传一个参数 `variantSelector: plan.variantSelectorFor(source)`（和 `queryPolicy` 并列，只这一行；换清晰度流程没动）。
- `docs/specs/UPGRADES.md`：27-7 改回“完成（G01.4）”，状态统计同步。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试（改之前编译不过：新参数和字段不存在；`session_test` 的新用例在去掉 `session.dart` 那一行时单独失败：引擎拿到的是 `steam.example` 而不是本机中继）：
  - `packages/live_core/test/live_site_test.dart`：选择器必须是线路地址、去重后保留、其他构造函数为空。
  - `packages/live_core/test/sites/steambroadcast_site_test.dart`：变体档的解析结果带这个变体做选择器，自适应档没有；恢复后仍是 720p 的选择器；新主列表没有那一档时没有选择器。
  - `packages/live_media/test/plan_test.dart`：HLS + 选择器 → `hlsRelay`，没有 → `direct`，FLV 不受影响；`variantSelectorFor`。
  - `packages/live_media/test/relay_test.dart`：本机回环放 `S09-master-live` 的主列表，经 `MediaOpener` 按 720p 打开：中继给出的主列表只剩 1280x720 一个变体和 1 条音轨；换 CDN 主机的同一份主列表仍选中 720p；没有 720p 的主列表回 502；没有选择器时照旧 `direct`。
  - `packages/live_player/test/session_test.dart`：带选择器的线路经中继打开。
- 结果：`live_core` 3664 个、`live_media` 49 个、`live_player` 56 个全部通过；`apps/pure_live` 984 个全部通过；`dart analyze --fatal-infos` 无问题。

## 巡检

- 改之后用临时程序（放在 `tools/live_cli/bin/` 下，用完删掉）对 76561199845912453 每一档走一遍“解析 → `PlaybackPlan` → `MediaOpener`（经代理）→ 读中继给引擎的主列表”：
  - 自适应 HLS：`direct`（引擎直接拿整份主列表）。
  - 1080p60、720p、480p、360p：`hlsRelay`，中继的主列表各只有 1 个变体（分别是 1920x1080、1280x720、854x480、640x360）和 1 条音轨；经中继取那个变体的媒体列表 200、28 个分片。
- `live_cli patrol steambroadcast --proxy 127.0.0.1:7897`：P6～P12 正常（P9 各档都在、P10 自适应档的线路能读）。P1、P3 失败：“第 2 页和第 1 页重复 9 个”——平台的分页这时回了几乎同一页（03:36 那次巡检还是“重复 0 个”），和本任务无关（没有改列表代码），见“留下的问题”。

## 复制直链、投屏、录制

- 复制直链、投屏用解析结果的地址（`resolution.urls`），不经过 `MediaOpener`，仍是 `master.m3u8`。
- 录制（`packages/live_record/lib/src/resolver.dart:421` 起）只带 `sourceQueryPolicies`，没有读 `sourceVariantSelectors`：录 Steam 时仍把整份主列表交给 FFmpeg，FFmpeg 默认挑最高的一路，选的档位对录制不起作用。本任务按范围不改，需要的话另开 H 组任务（录制输入照播放这样走中继，或者直接录选中的变体地址加音轨）。

## 留下的问题

- 录制不按档位，见上。
- Steam 推荐和分区第 2 页和第 1 页几乎一样（巡检 P1、P3，2026-10-08 04:2x 连续两次）：平台分页的问题，建议在 E03 组开任务查 `ajaxgetbroadcasts` 的分页参数。

## 真机上要看的

- K90 开代理进一个在播的 Steam 直播间，按 brief 的“真机验证”四步：选 480p 画面变糊、调试信息约 854×480；换 1080p60（有的话）变清楚、60 帧；换回“自适应 HLS”恢复自选；菜单 → 获取直链仍是 `master.m3u8`。

## K90 复查（2026-10-08，提交 `9126ec299`，经代理）

- Steam 直播间画质菜单：自适应 HLS、720p、480p、360p。选 480p 后日志 `VideoOutput.Resize … width: 854, height: 480` ✓（选中的变体真的用上了）。
- 经这个代理带宽不够，自适应和 720p 下反复缓冲、恢复两次后一度“播放已中断 · 平台没有给出可播放的直播流”，点重试又在连接；换回“自适应 HLS”、1080p60、获取直链没法在这个网络下看。
- 还剩：网络好的时候看换回自适应、获取直链仍是 `master.m3u8`。
