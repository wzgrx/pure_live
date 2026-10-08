# E03.18 17LIVE 线路全部不通、第 2 页只给重复的一个：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E03.18]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书：登记表的 note 就是任务）

## 复现

- `patrol 17live --proxy 127.0.0.1:7897`：P1、P3 第 2 页 1 个、和第 1 页重复；P10 三个房间都选“H.264 · FLV”，网宿 `…/vod/<uid>_h264.flv` 超时、腾讯 `…/live/<uid>_h264.flv` 404。

## 先排除代理地区

- 代理出口：美国加州。同一批地址直连（国内）：网宿的原画、增强高清、高清 200 并出 FLV，`_h264` 没有数据；腾讯超时。经代理：网宿同样，腾讯 404。两条路结论一样，不是出口地区的问题。

## 根因

- 线路：`packages/live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart` 的 `qualities`（修之前 `:709-781`）把每个 CDN 的 `url264` 都列进 H.264 档，`playQualities` 在“优先 H.264”时把它排第一。现在平台把大多数房间放在网宿（`pullURLsInfo.rtmpURLs` 第一项 provider 5），网宿不出 H.264 转码，而排在后面的腾讯不出流（REG-17LIVE-002）。所以默认档两条线路都不通。
  - 实测 12 个在播房间（经代理）：网宿第一 9 个，原画都出流（codec 7），`url264` 全不出；腾讯第一 2 个，`url264` 出流（其中 29136508 的原画是 codec 12）；另 1 个两家都不出（观看 0 人，平台状态）；还有 2 个 `rtmpURLs` 是空的（适配器原来就报“没有拉流地址”）。
  - 官网播放器（`17.live` 的脚本）只用 `rtmpUrls[0]`：平常播 `webUrl`，浏览器不支持 H.265 且全局配置 `streamH265.isEnablePullTranscodeH264` 开着时才用 `url264`；配置三个区都是开的，所以转码只在腾讯上有。
- 第 2 页：`/api/v1/sections` 第 1 页之后的那一页只有 `ArchiveVideo`（照 3.x 跳过）和 `GroupCall`，`GroupCall` 的直播第 1 页的 `Latest`、`Label` 区已经有，之后游标为空。是平台的数据；应用 `room_feed.dart:479` 按 `identityKey` 去重。巡检的判定（重复超过一半就失败）没考虑这种短的最后一页。

## 改了哪些文件

- `packages/live_core/lib/src/sites/seventeenlive/seventeenlive_api.dart`：`untranscodedCdns`；`qualities` 记下第一个 CDN，网宿的 `url264` 不读，第一个是网宿时不给 H.264 档。
- `fixtures/17live/S04-live-wansu/`：新样本（经代理，`lives/29167718`，网宿第一；监护人字段本来为空，没有要脱敏的）。
- `packages/live_core/test/sites/seventeenlive_api_test.dart`、`seventeenlive_site_test.dart`：见下。
- `tools/live_cli/lib/src/patrol/checks.dart`、`tools/live_cli/test/checks_test.dart`、`docs/E-直播平台/E07-平台巡检/CHECKS.md`：短的最后一页。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试：`S04-live-wansu` 三档、原画第一；合成数据三种排列。改之前 2 个失败。
- 和 3.x 对照的 5 个（`S04-live-live` 的 H.264 地址、线路、拉流容错，site 的取流和恢复）按新规则改预期：H.264 去掉网宿的地址，用 `_served` 写明 E03.18。
- `seventeenlive_*` 87 个通过；`tools/live_cli` 加 2 个（短的最后一页全是重复算正常；和第 1 页一样大的仍失败），全部 62 个通过。

## 巡检复测

- `patrol 17live --proxy 127.0.0.1:7897`：正常 11、失败 0、没测到 1（P13）、不支持 1。P1、P3 第 2 页 1 个重复（最后一页，写进说明）；P9 网宿房间 3 档、腾讯房间 4 档；P10 网宿房间“原画 · FLV”2 条 1 条出 FLV（腾讯 404），腾讯房间“H.264 · FLV”1 条出 FLV。

## 真机上要看的

- K90 经代理：17LIVE 热门里随便进几个房间，默认档有画面（网宿房间是“原画 · FLV”，腾讯房间是“H.264 · FLV”）。

## K90 复查（2026-10-08，提交 `9126ec299`，经代理）

- 17LIVE 热门第一个房间“原画 · FLV”有画面 ✓；第二个房间“H.264 · FLV”（腾讯）有画面 ✓。第一次进第二个房间时黑屏约 9 秒没有转圈（日志是 mpv 缓冲停顿），再进一次是“正在进入直播间”→“正在连接直播流”→约 3 秒出画面，没有复现；代理的带宽有限，先记下。

结论：通过。
