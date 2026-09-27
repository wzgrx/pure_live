# 平台规格：微博直播（weibo）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`weibo`（legacy/lib/core/sites.dart），显示名“微博直播”（legacy/assets/translations/zh.json `site_weibo`）。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/weibo/`（A = weibo_api.dart，S = weibo_site.dart，L = weibo_link.dart）。样本编号见 §11。
- 状态：**保留**。2026-09-27 本机默认出口实测（2026-09-28 查明本机默认出口经系统层隧道在境外，不是中国大陆直连）：推荐列表、房间接口、FLV 媒体都能匿名访问，不需要 Cookie、签名或特殊请求头。不满足 ADR 0003 的任何下线条件（有公开推荐列表；直播链接稳定；取流匿名可用）。
- 能力：推荐（一页快照）、详情、取流（HTTP-FLV，AVC）、链接解析。
- 不提供：分类（平台网页没有分类目录）；搜索（没有匿名搜索接口，旧版只是在推荐快照里按昵称过滤，A:196-201、zh.json `search_coverage_weibo`，v4 不做这种伪搜索）；弹幕（旧版未接入，v4 本阶段也不做，见 §7）；回放播放。

---

## 1. 房间身份与链接

**规范身份**：直播场次 id `liveId`，形如 `1022:2321325347923495092258`（新）或 `1022:2320508a306db1bc389510651e77d5feb4f90d`（旧，S02-ended）。

- 一个 id 对应**一场**直播，不是主播：主播下一次开播是新 id。收藏跟踪的是这一场，结束后状态为未开播（旧版同样如此，zh.json `weibo_room_scope`）。
- 旧版只接受 `1022:232132` + 16 位数字和 `1042152:` + 32 位十六进制两种（A:180-186），S02-ended 的 `1022:2320508…` 被拒。v4 放宽为 `^\d{3,8}:[0-9A-Za-z]{16,48}$`，不存在的 id 由接口报 NotFound（S02-notfound）。
- 主播 `user.uid` 只作为详情信息，不作身份。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯 id | `1022:2321325347923495092258` | 直接使用 | L:9 |
| 网页直播页 | `https://weibo.com/l/wblive/p/show/<id>`、`/l/wblive/m/show/<id>` | 主机是 `weibo.com` 或 `www.weibo.com`，取 `show/` 后一段；`%3A` 解码成 `:` | L:11-24 |
| 媒体中心链接 | `https://live.media.weibo.com/live/show?id=<id>` | 取查询参数 `id`（v4 新增，搜索引擎收录的旧链接是这种形式） | 实测 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | legacy/lib/common/utils/live_url_tool.dart:60 |

- 个人主页 `weibo.com/u/<uid>`、微博正文链接不是房间，返回“不是本平台的房间”。
- 外部打开：`https://weibo.com/l/wblive/p/show/<id>`（L:40）。

## 2. 目录

### 2.1 分类

没有。`categories()` 返回空列表，`areaRooms()` 对任何分区报 NotFound。

### 2.2 推荐

- `GET https://weibo.com/l/!/2/wblive/pc_recommend/list.json?count=100&uid=`，请求头 `Referer: https://weibo.com/l/wblive/`（A:91,172）。
- `count` 决定条数：10 → 9 条，30 → 29 条，100 → 51 条；`page` 参数被忽略，第 2、3 页和第 1 页相同（2026-09-27 实测）。旧版用 `count=10`（A:173）。v4 用 `count=100`，只有一页，不返回游标。
- 响应 `{code: 100000, error_code: 0, data: {data: [...]}}`；每项 `liveid`、`uid`、`nickname`、`cover`（S01-recommend）。
- 卡片：房间 id = `liveid`；昵称 = `nickname`；**标题也用昵称**（列表没有标题）；封面 = `cover`；人数为空。
- 状态：列表只收录正在直播的场次。录制时 51 条逐个查房间接口，`status` 全是 1（直播中）；其中 2 条 `watch_limit` 非 0（S01-recommend）。所以卡片状态标为直播，进房以房间接口为准。

## 3. 搜索

不提供（见文首）。

## 4. 房间详情

- `GET https://weibo.com/l/!/2/wblive/room/show_pc_live.json?live_id=<查询编码的 id>`，请求头同 §2.2（A:176-178）。
- 成功：`code == 100000` 且 `error_code == 0`，`data` 是对象（S02-live）。
- 不存在：`{code: 999999, error_code: 27401, msg: "LiveRoom does not exists! (<id>)", data: []}`，HTTP 200 → NotFound（S02-notfound）。
- 其它 `code`/`error_code` → ApiChanged（带 `msg`）。
- 字段映射：

| 目标 | 来源 | 说明 |
|---|---|---|
| 房间 id | `data.liveId` | 必须等于请求的 id，否则 ApiChanged |
| 标题 | `data.title` | |
| 昵称、头像 | `data.user.screenName`、`data.user.avatar`（大图），缺时用 `profileImageUrl` | 头像 URL 带 `Expires`/`ssig` 图床签名，原样保存 |
| 封面 | `data.cover` | |
| 开播时间 | `data.startTime`（毫秒） | 0 视为没有 |
| 人数 | 无 | 接口不给观看人数（zh.json `audience_weibo_detail`），三个口径都为空 |
| 原站链接 | `https://weibo.com/l/wblive/p/show/<id>` | |

- 状态（`data.status`）：

| 值 | 含义 | v4 | 样本 |
|---|---|---|---|
| 1 | 直播中 | live | S02-live、S02-watch-limit |
| 3 | 已结束，有回放 `replay_origin_url` | offline | S02-ended-replay |
| 5 | 已结束（2021 年的场次，没有任何播放地址） | offline | S02-ended |
| 其它 | 未见 | ApiChanged | 旧版当作未知（A:260-266），v4 不允许未知状态（ADR 0010） |

  状态 3 虽有回放地址，但这个房间 id 是一场已经结束的直播，不是“轮播/回放中的房间”，所以是 offline，不是 replay。v4 不播放回放。

- 访问限制：
  - `watch_limit != 0`：不给播放地址，`pay_dialog_info.buy_tip` 说明原因，例如 10 = “本场直播只有主播的好友可观看”（S02-watch-limit），9 在录制时也出现过（原因未录到）。房间状态照常是直播，取流报 **NeedsLogin**（需要有权限的账号，v4 没有微博登录）。
  - `play_switch == 0`：播放关闭，取流报 StreamUnavailable（旧版 A:252-256，未录到样本）。
  - `pay_live_status`：普通公开直播也是 1（S02-live），录到的好友专属直播是 0，**不能**当作付费标记（旧版注释 A:250 也不用它）。

## 5. 画质与线路

- 只有一档：画质 id `origin`，名称“原画”。流名里的 `wb720avc`/`wb1080avc` 是编码档位，没有其它档可选。
- 线路：`live_origin_flv_url` 一条（S02-live 为 `https://plwb01.live.weibo.com/alicdn/<流 id>_wb720avc.flv`）。
- `live_origin_hls_url` 字段名是 HLS，但实测值与 FLV 地址相同（也是 `.flv`）。v4 按扩展名判断格式，和 FLV 相同就去重，只留一条。
- 线路 id：路径第一段（`alicdn`），没有时用主机名。
- 服务端确认的画质：无，`confirmed` 为空。
- 编码：AVC（2026-09-27 读取 FLV 头：video codec id 7，音频 AAC）。

## 6. 取流

- 取流时重新请求房间接口（§4），不复用详情里的地址。
- 状态不是直播 → StreamUnavailable；`watch_limit != 0` → NeedsLogin；`play_switch == 0` 或没有地址 → StreamUnavailable。
- 请求头：媒体不需要 Referer、Cookie（带不带 Referer 都能拉到 FLV，实测）。StreamLine 的 `headers` 只放 `user-agent`。
- 租期：地址不带签名和过期参数，`lease` 为空。

## 7. 弹幕

不做。旧版返回空弹幕（S:37 `EmptyDanmaku`）。微博直播间的评论走登录后的私有接口，匿名没有找到可用的实时评论通道 [待确认]。

## 8. 登录与 Cookie

不支持。所有接口匿名可用；好友专属等受限直播报 NeedsLogin。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| 房间不存在 | `error_code == 27401` | NotFound |
| 其它 `code != 100000` 或 `error_code != 0` | JSON | ApiChanged |
| 返回的 `liveId` 与请求不同 | JSON | ApiChanged |
| 未知 `status` | JSON | ApiChanged |
| 好友专属等访问限制 | `watch_limit != 0` | 取流 NeedsLogin |
| 已结束 | `status` 3/5 | 房间 offline；取流 StreamUnavailable |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 旧链接打不开 | 旧版只认两种 id 形态，搜索引擎收录的 `1022:2320508…` 被拒 | 放宽 id 形态，交给接口判断是否存在 | A:180-186；S02-ended |
| 推荐只有 9 个 | `count=10` 被服务端截成 9 条 | `count=100`（上限约 51 条） | 实测 |
| 把 `pay_live_status` 当付费 | 普通直播也是 1 | 用 `watch_limit` 判断限制 | S02-live 对照 S02-watch-limit |

## 11. 样本清单

2026-09-27 本机默认出口录制（`live_cli fixture capture`，规则 tools/live_cli/lib/src/fixture/rules/weibo.dart）。旧应用已归档、不能再运行（ADR 0016），没有旧版期望值 `expected.json`；v4 测试（packages/live_core/test/sites/weibo_test.dart）直接对照样本正文断言。

| # | 样本 | 请求 | 覆盖 |
|---|---|---|---|
| S01 | `S01-recommend` | `pc_recommend/list.json?count=100` | 51 条推荐 |
| S02 | `S02-live` | `show_pc_live.json` 直播中 | 字段映射、FLV 地址、HLS 字段是 FLV |
| S02 | `S02-watch-limit` | 好友专属直播 | `watch_limit=10`，没有地址 |
| S02 | `S02-ended-replay` | 已结束有回放 | `status=3` |
| S02 | `S02-ended` | 2021 年旧场次 | `status=5`，旧 id 形态 |
| S02 | `S02-notfound` | 不存在的 id | `error_code=27401` |

**需要脱敏的字段**：没有。两个接口只返回主播公开信息（ADR 0009 第 4 条保留）；匿名访客 Cookie 若出现在 Set-Cookie 里由工具统一替换。

## 12. 待确认

1. `status` 除 1、3、5 以外的取值（预告、暂停）。
2. `watch_limit` 9 的含义（录到 1 场，没有录下正文）。
3. 能否按主播 uid 找到当前直播，从而把收藏改成跟随主播。
4. 匿名可用的实时评论通道。
5. `play_switch == 0` 的真实样本。
