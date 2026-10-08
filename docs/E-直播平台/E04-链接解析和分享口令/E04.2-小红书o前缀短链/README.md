# E04.2 小红书分享短链认 xhslink.com/o/ 前缀

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：上游对照 [W01.3](../../../W-上游借鉴/W01-定期对照/W01.3-2026-10-08上游对照/README.md)：上游 pure_live `6229284a8`（“分享文案里抽出链接 + 认 /o/ 前缀短链 —— 整段粘贴可开直播间”）
- 相关：链接解析 [E04.1](../E04.1-平台框架与链接解析/README.md)；小红书 [E02.7](../../E02-其他国内平台/E02.7-小红书/README.md)

## 目标

小红书 App 现在分享直播间给的是“#xxx正在直播… https://xhslink.com/o/<码> 复制本条信息…”，短链带 `/o/` 前缀。4.x 只认 `xhslink.com/<码>` 和 `xhslink.com/m/<码>`，整段粘贴到搜索或“打开链接”里打不开。改成认一到四个字母的前缀。

## 3.x 和现状

| 方面 | 3.x | 现在（文件:行） | 要做到 |
|---|---|---|---|
| 从文案里抽链接 | 小红书、微博从第一个中文标点处截断 | 已有，而且对所有平台：`packages/live_core/lib/src/links.dart:227`（`sharedHttpUrls`） | 不变 |
| 短链路径 | `/<码>`、`/m/<码>` | 同：`packages/live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:534`（`_shortPath`）、`:585-588`（`shortLink`） | 再认 `/o/<码>` 这类一到四个字母的前缀（上游 `^/(?:[A-Za-z]{1,4}/)?[A-Za-z0-9]{1,64}/?$`） |
| 跟跳 | 只在 `xhslink.com` 里跟跳、只接受本站直播间 | 同：`xiaohongshu_site.dart:243` 起 | 不变 |

## 方案

- c1：`_shortPath` 放宽成上游的写法；其余（主机只认 `xhslink.com`、跟跳规则、最多 12 秒）不变。
- c2：先写改之前会失败的测试：`https://xhslink.com/o/AbC123`、整段分享文案（带中文标点和“复制本条信息”）都解析成短链；`/abcde/xyz`（五个字母）、别的主机不认。

## 验证

- 自动测试：`packages/live_core/test` 里小红书短链和整段文案的用例。
- 真机（K90）：从小红书 App 分享一个直播间，整段粘贴进搜索框，能打开。

## 留下的问题

- 无。
