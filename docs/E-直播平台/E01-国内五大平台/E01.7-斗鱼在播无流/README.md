# E01.7 斗鱼在播但没有流：streamStatus 为 0 时报“没有画面”

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：[E01.6](../E01.6-国内五大平台巡检和修复/record.md) 第 1 轮巡检（2026-10-08）：斗鱼 9263298 显示在播，`getH5PlayV1` 答 `streamStatus: 0`，唯一的线路 404。决定（维护者委托）：`streamStatus` 为 0 时报 `StreamUnavailable`，不把 404 的地址交给播放器去重试。
- 相关：[E01.2](../E01.2-斗鱼/README.md)（斗鱼平台）；[E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)、[CHECKS.md](../../E07-平台巡检/CHECKS.md)（P9）
- 记录：[record.md](record.md)

## 目标

进一个“在播但主播没在推流”的斗鱼房间，画面上直接说明没有可播放的流（“平台显示在播，但没有给出可播放的地址”，可以重试或换房间），而不是播放器连一个 404 的地址、转圈后报播放失败。

## 3.x 和现状

| 方面 | 3.x | 修之前（文件:行） | 要做到 |
|---|---|---|---|
| `streamStatus` | 不读 | 不读：元数据（`rate=-1`）照样给出画质和 CDN（`douyu_site.dart:274-276`、`douyu_api.dart` 的 `qualities`），取流给出地址，CDN 回 404 | 元数据 `streamStatus` 为 0 时 `StreamUnavailable` |

## 结果

- c1 `packages/live_core/lib/src/sites/douyu/douyu_api.dart` 的 `qualities`（只用于元数据回答）：`streamStatus` 是 0（数字或字符串）时抛 `StreamUnavailable('getH5PlayV1: streamStatus 0 (no stream pushed)')`；没有这个字段（旧回答、合成数据）不变。进房（`getPlayQualities`）和恢复（`resolvePlayUrlsForRecoveryRaw` 先取元数据）都走这里；直播间显示“平台显示在播，但没有给出可播放的地址”（`room_status.dart` 的 `_unplayable`，重试、换房间两个按钮）；录制照旧当作暂时失败、稍后重试（`live_record` 的 `resolver.dart`）。
- 只判元数据，不判单档的回答：样本 `S09-24422-r2-hw-h5`（9 月 27 日，房间 24422 在播，同一时刻元数据 `S08-meta-24422` 是 1）里“高清”那一档的回答是 0，那条地址当时能不能播不知道，所以不拿它作依据。
- c2 巡检 `tools/live_cli/lib/src/patrol/checks.dart` 的 P9：在播房间 `discoverPlayQualities` 报 `StreamUnavailable` 时写“没有流，平台状态，跳过”，不算失败；全部没有流时写“没测到”。CHECKS.md 第 2 节 P9 同步。
- 核对（2026-10-08，直连，临时程序不进仓库）：推荐前 40 个和英雄联盟、王者荣耀分区后部的房间共 70 多个，`streamStatus` 为 1 的约 60 个线路全部 200；为 0 的 14 个（含 9263298）每档每条线路都是 404。

## 验证

- 自动测试：`douyu_api_test.dart` 加 2 个（新样本 `S08-meta-9263298-nostream`：元数据为 0 是 `StreamUnavailable`、录过的能播的元数据是 1、没有字段不变；单档回答为 0 的 `S09-24422-r2-hw-h5` 照旧给线路），`douyu_site_test.dart` 加 1 个（列画质和恢复都报 `StreamUnavailable`、各只发一次元数据请求）；`tools/live_cli/test/checks_test.dart` 加 2 个。
- 巡检：`patrol douyu` 正常 12、失败 0（P9 写“9263298 没有流……跳过”）。
- 真机：待真机（K90：进一个这样的房间，看到“平台显示在播，但没有给出可播放的地址”和重试、换房间按钮，没有长时间转圈；正常房间照旧能播）。

## 留下的问题

- 这类房间在分区列表后部很多（王者荣耀、英雄联盟后部各有好几个），卡片上仍显示“在播”：卡片数据里没有 `streamStatus`，要知道得每个房间多发一次签名请求，不做。
