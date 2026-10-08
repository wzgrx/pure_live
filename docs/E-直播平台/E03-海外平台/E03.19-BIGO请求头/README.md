# E03.19 BIGO 请求头换成完整浏览器形态

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：上游对照 [W01.3](../../../W-上游借鉴/W01-定期对照/W01.3-2026-10-08上游对照/README.md)：上游 pure_live `2e84d68d3`（“请求指纹升级为完整浏览器头 —— WAF 按客户端指纹发降级答案”）、`3a960050b`（BIGO 账号 Cookie）、`21e981da5`（匿名接口对每个在播房间都回 `needLogin:true`）
- 相关：BIGO [E03.11](../E03.11-BIGOLIVE/README.md)；平台巡检 [E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)

## 目标

上游 2026-10-06 发现 BIGO 的防火墙按请求指纹给降级答案：只带 `User-Agent: Mozilla/5.0` 时 `www.bigo.tv` 的接口直接回 418，`getInternalStudioInfo` 回 `needLogin:true` 的空壳（同一台机器、同一出口，网页能播、应用拿不到详情）。4.x 用的正是这个请求头，BIGO 很可能已经播不了。先确认，再换成完整的浏览器请求头；还要登录的话另开账号任务。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 请求头 | `origin`、`referer`、`user-agent: Mozilla/5.0` | 同：`packages/live_core/lib/src/sites/bigo/bigo_api.dart:308-314`（所有接口和媒体都用这一组） | 完整桌面浏览器 UA，加 `Accept`、`Accept-Language`、`X-Requested-With`（上游 `lib/shared/platforms/bigo/bigo_api.dart` 的 `headers`） |
| 要登录时 | — | `bigo_api.dart:89`：`needLogin` 是 `NeedsLogin`，界面说要登录 | 不变；换请求头后仍是 `needLogin` 才考虑账号 |
| 账号 | 没有 | 没有（`apps/pure_live/lib/features/account/account_platforms.dart` 没有 BIGO） | 本任务不做 |

## 方案

- c1：用 E07 的巡检工具（或 `tools/live_cli`）跑 BIGO 的在播列表和三个房间的详情、取流，记下现在的回答（418、`needLogin`、正常）。
- c2：现在拿不到的话，`BigoApi.headers` 换成完整浏览器形态，再跑一遍；媒体请求（HLS）是否也要同样的头，按实测定。先写改之前会失败的测试（请求头断言）。
- c3：换了请求头仍然 `needLogin`：记录、在 K 组登记“BIGO 账号 Cookie”任务（上游 `3a960050b` 的做法），本任务到此为止。

## 验证

- 自动测试：请求头的断言；`needLogin` 回答仍报 `NeedsLogin`。
- 巡检：BIGO 在播列表、详情、取流通过；K90 进一个 BIGO 房间有画面（经代理）。

## 留下的问题

- 账号 Cookie 要不要做，看 c3 的结果。
