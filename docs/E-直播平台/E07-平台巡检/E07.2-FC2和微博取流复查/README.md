# E07.2 用巡检复查：FC2 分片要带 l_ortkn 会话 Cookie、微博媒体要带 Referer 和 UA

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台（先巡检确认，再修）
- 来源：上游对照 [W01.3](../../../W-上游借鉴/W01-定期对照/W01.3-2026-10-08上游对照/README.md)：上游 pure_live `14d965326`（“FFmpeg 中继携带 l_ortkn 会话 Cookie —— 修复分片 403”）、`960bcf7e3`（“房间声明媒体播放请求头 —— 修复建连后无数据”），都是 2026-10-06
- 相关：巡检工具 [E07.1](../E07.1-平台巡检工具/README.md)；FC2 [E03.13](../../E03-海外平台/E03.13-FC2LIVE/README.md)、微博 [E02.8](../../E02-其他国内平台/E02.8-微博直播/README.md)

## 目标

上游 2026-10-06 报了两处取流问题，4.x 的写法和上游修之前一样，但 4.x 这两个平台验证时是好的（微博 2026-09-28 实测媒体不需要请求头）。平台可能变了，也可能只是上游那边的节点。用巡检工具在真实接口上确认；确认有问题的照上游的思路修。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 上游的修法 |
|---|---|---|---|
| FC2 媒体请求 | UA、Origin、Referer（3.x 的 HLS 中继） | 同：`packages/live_core/lib/src/sites/fc2live/fc2live_api.dart:258-264`（`mediaHeaders`）、`fc2live_control.dart:137-138`；`l_ortkn` 只在控制连接的握手里（`fc2live_api.dart:188-193`） | 录制的 FFmpeg 输入加 `Cookie: l_ortkn=<orz>`（分片不带就 403） |
| 微博媒体请求 | 不带（3.x 的 `PlaybackHeaderResolver` 没有微博分支） | 同：`packages/live_core/lib/src/sites/weibo/weibo_api.dart:112-117`（`mediaHeaders` 为空，注释写了 2026-09-28 的实测）、`:491-516`（线路不带请求头） | 线路带 `Referer: https://weibo.com/l/wblive/` 和完整桌面 UA |

## 方案

- c1 巡检确认：FC2 找两个在播频道，取流后不带和带 `l_ortkn` 各请求一次变体列表和前三个分片；微博找两个在播房间，不带请求头、只带 UA、带 Referer 和 UA 各连一次 FLV，看 10 秒内有没有数据。结果写进 `record.md`。
- c2 修（只修确认有问题的）：FC2 的媒体请求头加 `cookie: l_ortkn=<orz>`（播放和录制都走 `mediaHeaders`，控制连接已经有 `orz`）；微博的 `mediaHeaders` 改成 Referer 加完整 UA，注释更新实测日期。先写改之前会失败的测试（请求头断言）。

## 验证

- 巡检：两项的结果写进记录；修了的再跑一遍通过。
- 真机（K90）：修了的平台进一个直播间看 2 分钟、录 1 分钟，播放和录制都正常。

## 留下的问题

- 都确认没问题的话，本任务改“完成”，在记录里写“上游的情况 4.x 没有复现”。
