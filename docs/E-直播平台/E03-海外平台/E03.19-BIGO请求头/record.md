# E03.19 BIGO 请求头换成完整浏览器形态：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（`[E03.19]` 提交）
- 设计或说明：[README.md](README.md)（没有任务书）；上游参考 `2e84d68d3`（remote `upstream`）

## 先在真实接口上看（经代理 127.0.0.1:7897、匿名）

- 改之前 `live_cli patrol bigo --proxy 127.0.0.1:7897`（2026-10-08 03:36 UTC）：P1～P12 全部正常（P13 没测）。P10 是“配方，未打开”，巡检不开配方，所以另写了临时程序（放在 `tools/live_cli/bin/` 下，用完删掉，没有提交）走一遍 `getRoomDetail` → `resolveInput` → 变体列表 → 第一个分片。
- TrimHost、Tony_Bee99、RROIEL 三个在播房间，3.x 的请求头（`Mozilla/5.0`）：`webjs/t`、`webjs/status`、`getInternalStudioInfo` 全部 200、`code:0`，都有 `hls_src`，**没有 `needLogin`**；变体列表 200、第一个分片 200（210～290 KB）。
- 同样三个房间换成上游的完整浏览器请求头：结果一样（详情、变体列表、分片都 200）。
- `curl` 对 `www.bigo.tv/official_website/studio/getInternalStudioInfo` 用 `Mozilla/5.0`：302（跳转），不是 418；`ta.bigo.tv` 的列表 200。4.x 的接口都在 `ta.bigo.tv`、`sec.bigo.sg`，不走 `www.bigo.tv`。
- 结论：这个出口现在复现不了上游说的 418 和 `needLogin` 空壳；防火墙按指纹和出口给答案，用户的出口可能不同。两种请求头这里都能用，按 README 的目标换成完整浏览器形态当预防（同 E01.8 虎牙 UA 的做法），不加账号（c3 不需要）。

## 根因

- `packages/live_core/lib/src/sites/bigo/bigo_api.dart:310-314`（改之前）：`BigoApi.headers` 是 3.x 的 `origin`、`referer`、`user-agent: Mozilla/5.0`，所有接口和媒体（`BigoApi.line`）都用它；弹幕握手（`packages/live_danmaku/lib/src/sites/bigo.dart:107`）也写死了 `Mozilla/5.0`。

## 改了哪些文件

- `packages/live_core/lib/src/sites/bigo/bigo_api.dart`：新常量 `BigoApi.userAgent`（桌面 Chrome 140，和其他平台同一个写法）；`BigoApi.headers` 加 `accept`、`accept-language`、`x-requested-with`（照上游 `2e84d68d3`）。接口、变体列表、分片、弹幕的 `getWebSocketLink` 都跟着变。
- `packages/live_danmaku/lib/src/sites/bigo.dart`：弹幕握手的 UA 用 `BigoApi.userAgent`（注释本来就说“用适配器的 UA”）。
- 测试：`bigo_site_test.dart`（每个请求的请求头、对照 3.x 时请求头单独断言是浏览器形态、关注合并后保留存下的请求头——只有 IPTV 取刷新的，BIGO 的媒体用线路自己的请求头）、`bigo_api_test.dart`（线路请求头；对照 3.x 的卡片把 `httpHeaders` 列为有意的差异）、`live_danmaku` 的 `bigo_test.dart`（握手 UA）。

## 新设置、翻译键、门禁基线

- 没有。

## 测试

- 先写的失败测试：`bigo_site_test.dart` 的“browser headers everywhere”、`bigo_api_test.dart` 的“the playlist line: browser headers”，改之前 2 个失败。
- `needLogin` 仍报 `NeedsLogin`：原有用例（`bigo_site_test.dart` 的登录门几条）不变，照样通过。
- 改过的包全部测试见提交前的门禁（`live_core`、`live_danmaku`）。

## 巡检

- 改之后 `live_cli patrol bigo --proxy 127.0.0.1:7897 --danmaku 15`（2026-10-08，经代理）：P1～P13 正常 12、不支持 1（P5 搜主播），失败 0；P13 THEBOSS8 15 秒内就绪、人数 2 次、重连 0 次（握手用新 UA）。
- 临时程序再走一遍 TrimHost：新请求头下详情、变体列表、分片都 200。

## 留下的问题

- 上游另外两条（`3a960050b` 账号 Cookie、`21e981da5` 匿名接口对在播房间都回 `needLogin`）这里没有复现，不开 K 组任务；哪天巡检 P6 出现成片的“要登录”再开。

## 真机上要看的

- K90 开代理进一个 BIGO 房间（推荐 → BIGO），有画面、有声音、弹幕能连上（媒体请求头变了，经本机中继和分片还原）。

## K90 复查（2026-10-08，提交 `9126ec299`，经代理）

- 推荐 → Bigo Live 进第一个房间：有画面（首帧约 9.6 秒）、弹幕服务器连接正常 ✓；请求没有再被拒（418）。经这个代理带宽不够，之后几次缓冲停顿和恢复；声音没听（测试时媒体音量为 0）。

结论：通过（慢是代理的带宽）。
