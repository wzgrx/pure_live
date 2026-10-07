# L03.1 哔哩哔哩点播和音乐核心包

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（新包 `packages/live_vod`；按平台任务的做法带了真实接口样本）
- 来源：模块重构计划 M14.0（电视版的点播和音乐搬进 4.x，先做没有界面的核心）；参考 pure_live_TV `b9d2f739`（本机 `~/ref/pure_live_TV`）
- 旧编号：M14.0、T11c.1
- 相关：复用 E01.1（`BilibiliSite.wbiSign`、`BilibiliApi.wbiKeys`、`buvid`、`userAgent`）、Q01.1（`LiveHttp`）、J02.1（`CookieVault` 的 Cookie）、G01.1（`LivePlayLine` 的线路回退和租期）；之后的界面 A17.6（电视点播）、A17.7（电视音乐，第三档）；记录 [record.md](record.md)

## 目标

把电视版的哔哩哔哩点播和音乐的全部非界面逻辑做成纯 Dart 包：请求只走注入的 `LiveHttp`、登录复用直播的哔哩哔哩账号、错误统一成 `SiteError`、解析是用样本测过的纯函数、存储和文件读写注入；修掉电视版的问题。界面以后在电视端（A17.6、A17.7）做。

## 3.x 和现状

| 方面 | 电视版 pure_live_TV（3.x 手机版没有这个功能） | 现在（`packages/live_vod/lib/src/`） | 要做到 |
|---|---|---|---|
| 请求和登录 | 单例客户端、全局设置；所有请求带游客 buvid（取流因此 412，`bilibili_api_client.dart` 的 `headers`） | 注入 `LiveHttp` 和 `CookieVault`；取流只带登录 Cookie（`client.dart:26`） | 完成 |
| 取流 | 删掉了 DASH，只播合流 MP4（画质封顶、没有音频档），注释说 COS 节点对 FFmpeg 回 400 | 恢复 DASH（`fnval=4048`），线路带浏览器 UA 和稿件页 Referer（实测是请求头的问题，不是节点）；MP4 留作备选（`streams.dart`） | 完成；播放器的外挂音轨没做 |
| 弹幕 | 未知字符串字段后面的字段全读错（`parseDanmakuSegment` 的 `default:`） | 按线型跳过（`danmaku.dart:21`） | 完成 |
| 歌词 | BGM 歌词从来取不到（`mv_lyric` 是地址）；rangotec 的区间时间戳全丢；第一句在 1 分钟后的丢 | 下载 `mv_lyric` 的文件；`Lrc.parse` 认区间时间戳；只要有带时间的行就算（`music/lyrics.dart:70`） | 完成 |
| 歌单导入 | 酷狗歌名和歌手对调 | 歌手优先用 `singerinfo`，歌名取“ - ”之后（`music/third_party.dart:119`） | 完成 |
| 队列和缓存 | 随机播放很快重复、“上一首”跳到邻居；推荐历史无限增长；音频缓存从不清理 | 洗牌顺序；历史保留 2000；缓存默认 1 GB、按最近播放淘汰（`music/queue.dart:49`、`daily.dart:22`、`audio_cache.dart:47`） | 完成 |
| 评论翻页 | 第 2 页起发页码（接口要游标原文） | 原样传 `next_offset`（`ugc_api.dart`） | 完成 |
| 写接口 | 进度上报、删除历史、收藏是“发出去不等结果” | 都返回 Future，失败抛类型化错误 | 完成 |

## 结果

- 提交：`11d579e05`（2026-10-01 合并）。
- 做了什么（详见 [record.md](record.md)）：
  - c1 `BilibiliVodClient`、`BilibiliUgcApi`、`BilibiliPgcApi`、`BilibiliMusicApi`：电视版的接口全部保留，番剧改用时间表和索引（电视版的推荐流 `pgc/page/web/feed` 没搬）。
  - c2 解析写成纯函数（`VodParse`、`VodDanmakuParse`、`Lrc`、歌单解析），模型是普通 Dart 类（电视版是 23 个 freezed 模型，约 8000 行含生成代码；现在约 1100 行）。
  - c3 音乐领域：歌单导入（网易云、酷狗、QQ）、匹配器（打分规则照电视版）、歌词链、每日推荐、播放队列、音频缓存规则。
  - c4 第三方服务的地址都可配（`ThirdPartyEndpoints`），请求平台 id `music_third_party`。
  - c5 修了电视版 13 个问题（record“电视版的问题和处理”）。
  - c6 匿名只读录制 38 个样本（`fixtures/live_vod/`，2026-10-01 05:36～05:43 UTC，合计不到 3 分钟），脱敏（buvid、地址里的客户端 IP、签名、`ip_info`、`seid`、midHash、酷狗 `userid`），门禁的样本隐私检查通过。
- 门禁：根 `pubspec.yaml` 的 workspace 加 `packages/live_vod`；`tools/gate/check_deps.py` 允许它依赖 `live_core`、`live_net`，应用可以依赖它（现在没依赖）。没有新的第三方包。
- 测试：48 个（`parse_test.dart` 23、`client_test.dart` 10、`music_test.dart` 15），全部通过。

## 验证

- 自动测试：`cd packages/live_vod && dart test`。
- 真实接口：录样本时跑过一遍（record“实测”表：游客能用的接口正常；`x/player/wbi/playurl` 对游客 412 不用；UP 主信息游客 -352；动态、历史、稍后再看要登录；评论游客受限）。**登录后才能用的接口没碰**（不登录就不碰）。
- 真机：没有界面，不适用。

## 留下的问题

- 界面（视频页、详情、播放页、评论、动态、UP 主空间、收藏、稍后再看、历史、搜索、番剧时间表和索引、会员集试看提示；音乐页、播放器、歌词、歌单导入对话框、每日推荐、缓存设置、第三方地址设置和说明）→ A17.6、A17.7（第三档，设计已确认）。旧编号里的 M14.3、M14.4 就是它们。
- DASH 播放：视频档 + 音频档作外挂音轨（mpv `audio-files`），`expiresAt` 前重新取流 → 接界面时在 G 组开任务。
- 点播弹幕的显示（按 6 分钟分段预取，高级弹幕不画）、字幕、进度上报的节奏 → 接界面时做。
- `VodKeyValueStore`、`AudioCacheFiles` 的实现、播放队列的保存和恢复 → 接界面时在应用里做。
- 登录后的接口要核对，`sendDanmaku` 用 `x/v2/dm/post`（电视版是 `x/v2/dm/send`）→ 接界面时用测试账号核对。
- 所有用户能看到的文字（错误提示、来源名的中文）→ 接界面时加翻译。
