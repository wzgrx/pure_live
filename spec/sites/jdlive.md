# 平台规格：京东直播（jdlive）

第 7 阶段第三批。只写行为和外部契约，不规定类名和函数拆分。

- 平台 id：`jdlive`，显示名“京东直播”。
- 证据写法：`文件:行号` 相对 `legacy/lib/core/site/jdlive/`（A = jd_live_api.dart，S = jd_live_site.dart，L = jd_live_link.dart）。样本编号见 §11。
- 状态：**保留（能力受限）**。2026-09-27 直连实测：精选列表和播放接口 `getImmediatePlayToM` 匿名可用，FLV/HLS 可播；详情接口 `liveDetailToM` 需要京东的 h5st 签名（匿名请求返回空的 403，S03-detail-403），所以详情没有标题和主播名。不满足 ADR 0003 的下线条件（有公开目录、取流匿名可用）。
- 能力：推荐（精选直播购物，分页）、详情（只有状态和封面）、取流（`_fhd` 的 FLV + HLS，AVC）、链接解析。
- 不提供：分类、搜索（旧版的“搜索”只在当前页本地筛选，zh.json `jdlive_directory_scope`）、弹幕、登录。

---

## 1. 房间身份与链接

**规范身份**：直播场次 `liveId`（5–18 位数字，L:2）。每场一个新 id（旧场次的 id 仍能查到 `status 3`），收藏跟踪这一场。

| 输入 | 例 | 处理 | 证据 |
|---|---|---|---|
| 纯 id | `48378944` | 直接使用 | L:14-15 |
| 直播页 | `https://lives.jd.com/#/<id>`，可带 `/live`、`/notice`、`/closed`、`/replay` 和 `?origin=0` | 页面按 URL 片段路由，从片段取 id | L:3,16-26 |
| 分享文本 | 链接前后有文字 | 抽出第一个 URL | — |

- 外部打开：`https://lives.jd.com/#/<id>`（L:4）。

## 2. 目录

### 2.1 分类

没有。

### 2.2 精选列表（推荐）

- `GET https://api.m.jd.com/api?appid=h5-live&functionId=liveListWithTabToM&v=<毫秒>&body={"tabId":1,"currentCount":"<已取条数>","page":<n>,"timestamp":<首页时刻>}`，请求头 UA（iOS Safari）、`Origin`/`Referer: https://lives.jd.com/`（A:98-121）。
- 响应 `{code: "0", subCode: "0", data: {currentCount, list: [...]}}`；`list` 里 `templateType == 1` 的项是直播间（`data` 对象），`-100` 是运营位（S01-list-p1）。
- 翻页：游标 = `<下一页码>:<currentCount>:<首页时刻>`；本页有直播间就继续（S01-list-p2：第 2 页 30 条，与第 1 页不重叠，`currentCount` 从 37 到 67）。旧版“条数 ≥ 30”才继续（A:147），第 1 页只有 30 张卡片混着运营位时会误判。
- 卡片：id `liveId`；标题 `title`；主播 `userName`（店铺名）；头像 `userPic`；封面 `indexImage`；累计观看 `pv`（旧版同样按累计，zh.json `jdlive_chat_notice`）；状态见 §4。

## 3. 搜索

不提供。

## 4. 房间详情（播放接口）

- `GET https://api.m.jd.com/api?appid=h5-live&functionId=getImmediatePlayToM&t=<毫秒>&body={"liveId":"<id>"}`（A:123-137）。
- 响应 `data`：`liveId`、`status`、`videoUrl`/`pcVideoUrl`（FLV）、`h5VideoUrl`（HLS）、`blurredImg`（封面）、`secret`、`slide`（上一场、下一场的预取）（S02-play-live）。`liveId` 必须等于请求的 id。
- 状态 `status`：1 → 直播；0 预告、2 结束、3 回放、10/11 暂停 → 未开播（A:193-203）；其它 → ApiChanged。
- 不存在的 id 与结束的场次无法区分：很早的 id（`10000`）也返回 `status 3`、地址为空（S02-play-old）。
- `secret == 1`：仅限京东 App 观看（zh.json `jdlive_restricted_notice`）→ 取流 NeedsLogin。
- **没有标题和主播名**：带这些字段的 `liveDetailToM` 需要网页脚本生成的 h5st 签名和风控 eid（官方脚本在请求前调用签名组件 `db40a`/`e8d68`），匿名请求返回空的 HTTP 403（S03-detail-403）。v4 不移植 h5st（算法随脚本版本变化，还要执行下发的 JS 片段）。详情的标题、主播名为空，界面显示列表卡片里已知的名称。
- 注意客户端指纹：同样的 `getImmediatePlayToM` 请求，Python urllib 发出时被网关回 403，`dart:io` 发出时正常（2026-09-27）。v4 走 `live_net`（`dart:io`），不受影响；换网络库前要复测。

## 5. 画质与线路

- 一档 `fhd`“超清”（流名后缀 `_fhd`）。
- 线路：FLV（`videoUrl`，缺时 `pcVideoUrl`）、HLS（`h5VideoUrl`），线路 id 为格式名；主机 `zt-pull-ai.jdcloud.com`。
- 编码：AVC（FLV 头 codec id 7；FLV 头的音视频标志位为 0，FFmpeg 照常识别）。
- 旧版取流前还要下载并校验 HLS 列表（A:131-135）；v4 不预先下载，交给播放器。

## 6. 取流

取流时重新请求播放接口（§4）：不在播 → StreamUnavailable；`secret == 1` → NeedsLogin；没有地址 → StreamUnavailable。地址没有签名和过期参数，`lease` 为空。请求头 UA、`Origin`/`Referer`，实测不带也能拉。

## 7. 弹幕

不做（旧版未接入；评论走京东私有长连接，[待确认]）。

## 8. 登录与 Cookie

不支持。

## 9. 错误与风控

| 情况 | 识别 | v4 |
|---|---|---|
| 传输失败、超时、HTTP 5xx | 传输层 / 状态码 | NetworkFailure |
| HTTP 401/403 | 状态码 | RiskControl |
| HTTP 429 | 状态码 | RateLimited |
| `code != "0"`（如 `code: "2"`“the current API does not exist”） | JSON | ApiChanged |
| `subCode != "0"` | JSON | NotFound（旧版 A:187） |
| id 不符、未知状态 | JSON | ApiChanged |
| 仅限 App | `secret == 1` | 取流 NeedsLogin |

## 10. 踩过的坑

| 现象 | 根因 | 正确做法 | 证据 |
|---|---|---|---|
| 精选只翻一页 | 按条数判断，列表里夹着运营位 | 有直播间就继续 | A:147；S01-list-p1 |
| 探测脚本以为播放接口要签名 | 网关按客户端指纹拦截 Python | 用 `dart:io` 复测 | §4 |

## 11. 样本清单

2026-09-27 直连录制（规则 tools/live_cli/lib/src/fixture/rules/jdlive.dart）。没有旧版期望值（ADR 0016），测试 packages/live_core/test/sites/jdlive_test.dart 直接对照正文。

| # | 样本 | 覆盖 |
|---|---|---|
| S01 | `S01-list-p1`、`-p2` | 精选列表两页、运营位、`currentCount` |
| S02 | `S02-play-live`、`S02-play-old` | 在播（FLV/HLS）、旧 id（`status 3` 无地址） |
| S03 | `S03-detail-403` | 详情接口没有 h5st 时的 403（证据） |

**需要脱敏的字段**：没有。只有店铺公开信息；匿名 Cookie 由工具统一替换。

## 12. 待确认

1. 不用 h5st 取得标题和主播名的途径。
2. `secret == 1` 的真实样本。
3. 签名/过期是否会加到 `_fhd` 地址上。
