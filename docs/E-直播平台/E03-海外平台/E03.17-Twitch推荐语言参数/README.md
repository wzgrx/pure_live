# E03.17 Twitch 推荐的 GraphQL 语言参数类型变了

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：E07.1 第一轮巡检（2026-10-08，经代理，[报告](../../E07-平台巡检/E07.1-平台巡检工具/runs/2026-10-08.md)）：P1 推荐 `ApiChanged`
- 相关：[E03.2](../E03.2-Twitch/README.md)（Twitch 平台）；[E07.1](../../E07-平台巡检/E07.1-平台巡检工具/README.md)（巡检工具）
- 记录：[record.md](record.md)

## 目标

Twitch 的推荐（热门页里的 Twitch，以及“Twitch 语言筛选”生效的推荐）重新能打开。

## 3.x 和现状

| 方面 | 3.x | 修之前（文件:行） | 要做到 |
|---|---|---|---|
| 推荐 | 3.x 的热门用分区接口，没有这个查询 | `twitch_api.dart:156` 的 `streamsQuery` 把 `$languages` 声明成 `[String!]`；平台的 schema 现在要 `[Language!]`，整个请求被拒（`Variable "$languages" of type "[String!]" used in position expecting type "[Language!]"`），不论有没有传语言，推荐第 1 页报 `ApiChanged` | 推荐有房间 |
| 分区 | — | 分区用持久化查询 `DirectoryPage_Game`（`gameOperation`），不受影响（巡检 P3 正常） | 不变 |

## 结果

- c1 `streamsQuery` 的 `$languages` 改成 `[Language!]`（`twitch_api.dart:157`）。设置里能选的 15 种语言（`settings_editors.dart:294`）大写后都是这个枚举的合法值（经代理实测一次全传，正常返回）。
- 样本：新录 `S03-top-zh-ko-language`（新查询、ZH+KO，26 个房间）和 `S03-top-string-rejected`（旧查询被拒的原样回答）；`S03-top`、`S03-top-cursor` 是旧查询录的，测试里改成按适配器的请求回放（同文件里已有的 `_answer` 做法）。
- 巡检复测：P1 第 1 页 30 个，第 2 页为空（没有更多：后续页要浏览器的完整性令牌，原来就是这样）；Twitch 正常 11、失败 0。

## 验证

- 自动测试：`twitch_api_test.dart` 加 2 个（新样本按适配器的查询录、旧查询被拒报 `ApiChanged`），`twitch_site_test.dart` 加 1 个（查询声明的是枚举；平台拒绝时是 `ApiChanged`），语言设置那一条改用新样本（旧查询不再能匹配）。
- 真机：待真机（K90 经代理看热门里的 Twitch 有房间；设置里选“中文”后推荐只剩中文房间）。

## 留下的问题

- 无。
