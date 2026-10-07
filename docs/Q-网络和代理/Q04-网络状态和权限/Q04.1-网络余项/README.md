# Q04.1 网络余项：功能清点里网络部分的 1 项缺失、1 项没验证

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（状态“不做”，不计进度）
- 类型：功能
- 来源：功能清点 [inventory/FEATURES.md](../../../inventory/FEATURES.md) 第 6 节（网络）2026-10-02 的余项：F-NET-02 播放代理“缺失”、F-NET-04 Twitch 网页完整性令牌“没验证”；整理文档时登记（旧编号 T03d.1）
- 旧编号：T03d.1
- 相关：决定 D-029；做完缺失项的 [O03.2](../../../O-Android系统集成/O03-分享接收和快捷方式/O03.2-接回半成品/README.md)（c5 播放代理）；接手验证的 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)；核对的 [V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md)

## 这是什么

登记时，功能清点的网络部分有两项没到“完成”：

| 功能点 | 当时的状态 | 内容 | 3.x |
|---|---|---|---|
| F-NET-02 播放代理 | 缺失 | 独立的一组代理设置（`enableProxy`、`proxyHost`、`proxyPort`），只管直播间的视频流；关掉时视频直连，即使应用代理开着；录制的中继走应用代理 | `git show v3.2.11:lib/player/core/playback_proxy_policy.dart:6`、`lib/modules/settings/pages/network_proxy_settings_page.dart:16` |
| F-NET-04 Twitch 网页完整性令牌 | 没验证 | 在无界面浏览器里打开 twitch.tv 空白页跑 KPSDK，拿令牌后再发 GraphQL（Twitch 拒绝没有令牌的请求时的最后一层回退） | `lib/core/utils/twitch/twitch_web_integrity.dart:9` |

本任务原来要做的就是：补上播放代理，并在真机上看这两项。

## 为什么不做（D-029）

- **缺失项已经由别的任务做完**：O03.2 c5（2026-10-02 合并）加了 `PlaybackProxyPolicy`（`apps/pure_live/lib/app/platforms.dart:35-48`，读 `enableProxy`、`proxyHost`、`proxyPort`），在 `apps/pure_live/lib/app/bootstrap.dart:232-236` 交给 `MediaOpener`（直播间、多画面、小窗共用；mpv 的 `http-proxy` 和中继的上游都用它），录制仍走应用代理；测试在 `apps/pure_live/test/platforms_test.dart`。F-NET-02 因此从“缺失”改成“没验证”（代码已合并，媒体请求真的走代理要真机看）。
- **两项的真机验证都并入 S02.4**：CHECKLIST 第 5 节第 6 条（播放代理指向局域网代理，进海外直播间；关掉再进）、第 7 条（有代理时进 Twitch、Kick，含 F-NET-04 和原生通道 F-AND-09）。单独留一个任务只为“验证”，会和 S02.4 重复。
- V03.3（2026-10-03）核对时按这个结论把本任务改成“不做”，原因写进 D-029（同一批还有 C01.3、D06.1）。

## 结果

- 没有代码改动。F-NET-02 的实现见 O03.2 记录；F-NET-04 的实现是 I01.1 时加的 `apps/pure_live/lib/platform/twitch_webview_http.dart`（`TwitchWebViewHttp`，在 `bootstrap.dart:175-178` 作为 Twitch GraphQL 的回退）。
- 功能清点里两项现在都是“没验证”，“依据”列写明由 S02.4 验证。

## 验证

- 由 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md) 做（CHECKLIST 第 5 节第 6、7 条）；本任务没有自己的 verify.md。

## 什么时候重新考虑

- S02.4 看下来播放代理没生效（媒体请求没走代理）或 Twitch 令牌拿不到：不重开本任务，在 Q02（播放代理）或 Q03（Twitch 无界面浏览器）开修补任务，`from` 写 S02.4 的记录。
- 功能清点以后在网络部分又发现缺失项：按 PROCESS 第 6 节在 Q01～Q04 对应的子分类开新任务，不复用本编号。

## 留下的问题

- 本轮读代码发现、和本任务无关但同属“网络部分清点不准”的：F-NET-01（应用代理）的“图片”一项实际没走代理（见 [Q02 已知问题](../../Q02-代理和镜像/README.md#已知问题和限制)）；F-NET-03（断网预检）只在热门页（见 [Q04 已知问题](../README.md#已知问题和限制)）。都需要维护者决定开任务。
