# E04.2 小红书分享短链认 xhslink.com/o/ 前缀：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E04.2]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书）；上游参考 `6229284a8`（remote `upstream`）

## 复现（直连、匿名）

- 用上游提交里的那段真实分享文案（`…正在直播，来和我一起支持ta吧。 https://xhslink.com/o/<码> 复制本条信息，打开【小红书】，直接观看直播！`）跑 `live_cli probe xiaohongshu '<整段文案>'`：改之前输出“Not a xiaohongshu room”，没有发任何请求。
- 同一个短链 `curl`（不跟跳）：302 到 `www.xiaohongshu.com/livestream/dynpath<8>/<房间号>?…`，说明短链本身有效，是 4.x 不认。

## 根因

- `packages/live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart:534`（改之前）：`_shortPath = ^/(?:m/)?[A-Za-z0-9]{1,64}/?$`，只认 `/<码>` 和 `/m/<码>`。`/o/<码>` 不匹配，`shortLink` 返回 null，`needsResolving`、`searchRooms` 的短链分支、`resolveUrl` 都不接。
- 从文案里抽链接不是问题：`LinkParser.sharedHttpUrls`（`packages/live_core/lib/src/links.dart:227`）按空白切开，中文标点截断，已经能抽出 `https://xhslink.com/o/<码>`。

## 改了哪些文件

- `packages/live_core/lib/src/sites/xiaohongshu/xiaohongshu_api.dart`：`_shortPath` 改成上游的 `^/(?:[A-Za-z]{1,4}/)?[A-Za-z0-9]{1,64}/?$`（一到四个字母的前缀）；`shortLink` 的注释。主机只认 `xhslink.com`、跟跳规则、每跳 12 秒都不变。
- 测试：`xiaohongshu_api_test.dart`（新用例：`/o/AbC123`、`/a/…`、`/abcd/…/`、大写前缀认；五个字母的前缀、字母加数字的前缀、多一级路径、两级前缀、别的主机不认；原来“不认”名单里的 `/a/fixture` 移到“认”）、`xiaohongshu_site_test.dart`（整段分享文案经 `LinkParser` 打开房间、只跟一跳不取最终页；搜索框粘 `/o/` 短链找到房间；“不认”名单里的 `/a/fixture` 换成 `/abcde/fixture`）。样本都是编的码（`AbC123`），没有真实链接。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试：上面 3 个新用例改之前都失败。
- `packages/live_core` 全部 3663 个通过；`dart analyze --fatal-infos` 无问题；格式检查通过。

## 巡检

- 改之后同一段真实分享文案 `live_cli probe xiaohongshu '<整段文案>'`：882 ms 解析出房间号（`link 5704…6278`），详情 `offline`（那一场已经结束，正常）。
- `live_cli patrol xiaohongshu`（直连）：正常 4、失败 0（P4、P7、P8、P12 正常；P6 起没测到是因为匿名拿不到在播房间，和改之前一样）。

## 留下的问题

- 无。

## 真机上要看的

- 不需要专门看：应用的搜索框和“打开链接”走的就是巡检用的 `LinkParser`。K90 平时从小红书分享直播间时，整段粘进搜索框应该直接出那个房间；打不开的话先看文案里的短链前缀。
