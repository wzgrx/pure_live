# E02.14 小红书推荐对游客为空：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E02.14]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书：登记表的 note 就是任务）

## 复现

- `live_cli patrol xiaohongshu`（直连）：P1 “第 1 页为空”，P4 没有关键词，P6～P12 没测到。

## 根因

- `packages/live_core/lib/src/sites/xiaohongshu/xiaohongshu_site.dart:91-100`：`getDirectoryPage` 和 `getRecommendRooms` 照 3.x 永远返回空、不发请求；网页的直播列表要登录签名（E02.7 记录“仅链接，照 v3”，接口 HTTP 406）。应用热门页显示目录说明 `xiaohongshu_directory_scope`。这不是平台失效。
- 巡检判错：对象表（`tools/live_cli/lib/src/patrol/targets.dart` 小红书一行、CHECKS.md）只把 P2、P3 标了“不支持”，漏了 P1；P4 “按房间号查”只从推荐取房间号（`checks.dart` 的 `_keyword`）。

## 改了哪些文件

- `tools/live_cli/lib/src/patrol/targets.dart`：小红书 P1 不支持（原因写进去）、P12 固定链接、说明。
- `tools/live_cli/lib/src/patrol/checks.dart`：`SearchKind.roomLookup` 没有推荐时用第一个固定房间号。
- `docs/E-直播平台/E07-平台巡检/CHECKS.md`：第 2 节 P4、对象表小红书一行。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试 2 个：没有推荐时按固定房间号查（改之前 `keywords` 为空）、小红书一行 P1 不支持；改之后 `tools/live_cli` 全部 60 个通过。

## 巡检复测

- `patrol xiaohongshu`：正常 4（P4 按固定房间号 1 个、P7 offline、P8 NotFound、P12 分享页）、失败 0、没测到 4（P6、P9～P11）、不支持 5（P1、P2、P3、P5、P13）。
- `probe xiaohongshu 570486981772704052`（结束页推荐的在播房间，直连）：详情在播、一档“原画”、4 条线路（3 条 FLV、1 条 HLS）都是 HTTP 200，开头字节对得上。

## 真机上要看的

- 不需要：应用和适配器没有改。
