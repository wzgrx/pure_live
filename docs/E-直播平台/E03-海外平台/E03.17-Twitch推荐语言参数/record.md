# E03.17 Twitch 推荐的 GraphQL 语言参数类型变了：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E03.17]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书：登记表的 note 就是任务）

## 复现

- `live_cli patrol twitch --proxy 127.0.0.1:7897`：P1 失败，`ApiChanged：streams: no data (Variable "$languages" of type "[String!]" used in position expecting type "[Language!]".)`，其余正常。
- 直接请求 `gql.twitch.tv/gql`（经代理）：同一个查询，`[String!]` 带不带 `languages` 变量都被拒；换成 `[Language!]` 两种都正常给房间。

## 根因

- `packages/live_core/lib/src/sites/twitch/twitch_api.dart:156`（修之前）：`streamsQuery` 声明 `$languages: [String!]`。Twitch 把 `StreamOptions.broadcasterLanguages` 的类型改成了 `Language` 枚举，GraphQL 校验变量类型时整个请求被拒。查询是原始查询（网页客户端没有对应的持久化查询），所以平台改 schema 就会直接坏。

## 改了哪些文件

- `packages/live_core/lib/src/sites/twitch/twitch_api.dart`：`$languages: [Language!]`，注释写明原因。
- `fixtures/twitch/S03-top-zh-ko-language/`、`fixtures/twitch/S03-top-string-rejected/`：新样本（经代理 127.0.0.1:7897，Device-Id 用 `S03-top-zh-ko` 的合成值，响应头不含 Set-Cookie）。
- `packages/live_core/test/sites/twitch_api_test.dart`、`twitch_site_test.dart`：见下。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试：查询里要有 `$languages: [Language!]`；新样本的请求体等于 `TwitchApi.streamsQuery`；语言设置那条按新样本回放。改之前 5 个失败（其中 1 个是新测试自己把解码的位置写错了，已改），改之后 `twitch_*` 117 个全部通过。
- 新增 3 个、改了 4 个（`S03-top` 三条和语言设置一条改成按适配器的请求回放或用新样本）；`packages/live_core` 全部 3646 个通过。

## 巡检复测

- `patrol twitch --proxy 127.0.0.1:7897`：正常 11、失败 0、没测到 1（P13 弹幕没跑）、不支持 1；P1 第 1 页 30 个，第 2 页为空（没有更多）。

## 真机上要看的

- K90（经代理）：首页“热门”切到 Twitch 有房间；设置“Twitch 语言筛选”选“中文”后，推荐里都是中文房间。

## K90 复查（2026-10-08，提交 `9126ec299`，应用代理指向电脑的 Clash 192.168.1.238:7897）

- 热门切到 Twitch 有房间（DEMACIA CUP、Team Yandex 等）✓；设置“Twitch 语言筛选”选“中文”后，推荐里全是中文直播 ✓；测完改回“全部语言”。

结论：通过。
