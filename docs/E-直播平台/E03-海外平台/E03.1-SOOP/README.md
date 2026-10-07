# E03.1 SOOP

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；升级落地（2026-09-29，[UPGRADES](../../../specs/UPGRADES.md) 7-1～7-9，另按统一原则填开播时间和受限类型；`hd8k` 和 7-1 同一个根因，一并处理）。过程记在 [record.md](record.md)
- 旧编号：M4.07、M4.U.7、T02c.1
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（SOOP 的 BJ id 不分大小写、受限类型）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；弹幕 [D01.8](../../../D-弹幕/D01-平台弹幕协议/D01.8-SOOP弹幕/README.md)（用 `SoopDanmakuArgs`）；分区页、搜索页按页加载 I03.1、I05.1（UPGRADES A-4）；直播间的受限说明、主页资料 C01.1、A07.7；海外平台走代理（Q 组）；决定 D-001、D-017、D-018（见 [DECISIONS.md](../../../DECISIONS.md)）
- 代码：`packages/live_core/lib/src/sites/soop/`（`soop_api.dart` 879 行解析，`soop_site.dart` 388 行请求编排）；应用里在 `apps/pure_live/lib/app/platforms.dart:159` 建 `SoopSite`；样本 `fixtures/soop/`（31 组接口样本；另有 `danmaku/` 下 3 组弹幕样本归 D01.8）

## 目标

把 3.x 的 SOOP（原 AfreecaTV）适配器（`lib/core/site/soop/soop_site.dart` 698 行）重构进 `live_core`：分类、分区、推荐、搜索、详情、取流、链接都和 3.x 一样，用户存了 Cookie 时所有请求、媒体和弹幕握手都带上。修掉 3.x 的 18 个问题（未开播的主播进房提示“获取房间信息失败”、19 禁直播进房“状态未知”且取流悄悄返回空地址、房间号换成响应里的 `BJID`、720p 预设 `hd4k` 排在 360p 之后等）。

## 平台接口要点

| 功能 | 接口（请求头 `Origin`、`Referer` 为 `www.sooplive.co.kr`，Chrome 128 UA；`site` 是 `soop`，代理由应用按平台配） | 位置 |
|---|---|---|
| 分类 | `sch.sooplive.co.kr/api.php?m=categoryList`，每页 120 个，按 `is_more` 逐页读（2026-09 共 5 页，最多读 20 页防止服务端一直说还有），第 1 页失败报错 | `soop_site.dart:124-130` |
| 分区、推荐、搜索 | 分区和搜索 `sch.sooplive.co.kr/api.php`；推荐 `live.sooplive.co.kr/api/main_broad_list_api.php`；开播时间 `broad_start` 是韩国时间（UTC+9） | `:161-198` |
| 详情 | `live.sooplive.co.kr/afreeca/player_live_api.php?bjid=`（`type=live`）：`RESULT` 1 有 `VIEWPRESET` 才算在播；0 未开播；-2 屏蔽；-6 成人（19 禁）、-8 密码、-14 仅订阅等受限都是直播中 + 受限类型；进房时同时请求主页接口 `chapi.sooplive.co.kr/api/<id>/station`（头像、简介、在线人数，区分主播不存在） | `:101`、`:248`、`:270-295` |
| 取流 | 先 `RMD/broad_stream_assign.html` 要播放列表地址，再 `type=aid` 要播放密钥，地址 `view_url?aid=…`（自带查询参数时用 `&aid=`）；一条线路，带 3.x 播放层的请求头、编码、CDN 码，没有租期；恢复时重新请求播放接口（主播重新开播后直播号会变） | `:303-323`、`:340` |
| 画质 | 3.x 的预设顺序，`hd4k`（720p）叫“超清”排在原画之后，1440p 直播的 `hd8k`（1080p 转码）叫“蓝光” | `soop_api.dart:674` 的 `qualityName`、`:693` 的 `qualitySort` |
| 弹幕参数 | `CHDOMAIN` 的 `CHPT + 1` 端口（`wss`）、`CHATNO`、握手请求头、明文端口地址；只有 `CHIP` 时主机是 `chat-<十六进制>.sooplive.com` | `soop_api.dart:26` 的 `SoopDanmakuArgs`，主机规则 `:630-637` |
| 链接 | `sooplive.co.kr`、`sooplive.com` 和 `afreecatv.com` 一套规则：`/<id>`、`play.…/<id>`、`station/<id>`；`live`、`vod`、`player` 等页面不算主播；id 统一小写；分享文本里的 App 深链 `sooplive://player/live?broad_no=&user_id=` | `:32`、`:367`、`:383`；深链 `soop_api.dart:183`、`:192` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/soop/soop_site.dart`） | 现在 | 说明 |
|---|---|---|---|
| 进房 | `getRoomDetail` `:348`；`:433-444` 把 `RESULT != 1` 一律当失败，返回“当前播放房间”的快照 | `soop_site.dart:270`，0 未开播、-2 屏蔽，和刷新一致 | 3.x 问题 1、2；7-4 |
| 19 禁和受限 | `:392-395`、`:417`、`:538` 进房“状态未知”、刷新和录制抛 `StateError`、取流密钥为空返回空地址 | 直播中 + `adult`、`password`、`subscribersOnly`，取流时报 `NeedsLogin` 或说明原因 | 3.x 问题 3；统一原则 |
| 房间号 | `:473` 换成响应的 `BJID` | 保持请求时的写法（小写） | 3.x 问题 4 |
| 画质 | `getPlayQualites` `:237`；`:270-282` `hd4k` 排在 360p 之后，显示“hd4k” | “原画、蓝光、超清、高清、标清” | 7-1 |
| 文字 | `:219`、`:330`、`:658` HTML 实体原样显示 | 解码 | 7-2 |
| 搜索 | `searchRooms` `:629`，`:659` 读已不存在的 `standard_broad_cate_name`，没有分区 | 读 `broad_cate_name` | 7-3 |
| 主页接口 | 不请求 | 进房时并发请求，补头像、简介、在线人数，区分不存在 | 7-5 |
| 分类 | `getCategores` `:44`，`:122-142` 一页失败悄悄返回部分目录，按“满 120 条”判断下一页 | 读 `is_more`，第 1 页失败报错 | 3.x 问题 10 |
| 链接 | `lib/modules/search/web_search_room_parser.dart:159-160` 把 `station/<id>` 识别成主播 “station” | 两个域名一套规则；认 `afreecatv.com` 和 App 深链 | 3.x 问题 12；7-7、7-9 |
| 弹幕 | `getDanmaku()` `:41` | `live_danmaku/lib/src/sites/soop.dart`（D01.8） | 聊天主机规则 7-6 |

## 结果

- 首次重构（2026-09-28，提交 `71fbb1982`，当天 `7ea69383c` 改回 3.x 用户看到的样子）：18 个 3.x 问题、13 条有意差异见 record.md；冻结输出按 SOOP 口径补出（后来 AcFun 等照这个做法）。
- 升级落地（2026-09-29，`046a5866d`）：7-1～7-9 完成（7-8 只做到识别密码房，输入密码受阻）；`hd8k` 按 7-1 一并处理；开播时间取 `broad_start`（韩国时间）；受限类型 `adult`、`password`、`subscribersOnly`、`unplayable`。
- 测试：`packages/live_core/test/sites/soop_api_test.dart` 54 个 `test(` 写法、`soop_site_test.dart` 31 个（record.md 最后统计为 62、31 个用例，样本对照是循环生成的）；弹幕测试 `packages/live_danmaku/test/soop_test.dart` 30 个 `test(` 写法，归 D01.8。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（`changed:` 列出 7-1、7-2、7-3、7-4、7-5 带来的差异）；`RESULT` 各值、主页接口（含超时、取消、502 时照常进房）、受限类型、`hd4k`/`hd8k` 顺序、链接（S04 的 30 个 `afreecatv.com` 地址）和 App 深链、`view_url` 自带查询参数。
- 真实接口：2026-09-28 首次重构时录了新样本；2026-09-29 用改好的适配器请求了推荐全部 40 页（约 2370 个房间），每种受限类型挑一个房间进房、刷新、取画质和取流，另查了不存在和未开播的主播、搜索（record.md“升级落地”开头的“实测”）。记录没有写是否经代理。没有做过国内五大平台那样的“真实环境检查”。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节 SOOP 一行各列都是“完成”，没有“K90 看过”）；海外平台的条目只在用户开着代理时做（[S02 的 CHECKLIST.md](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 的“准备”）。

## 留下的问题

- 7-8 密码房（部分完成）：识别和提示已做（卡片标“密码房”，播放失败按受限类型说明，C01.1 的 `restrictionReason`）；输入密码受阻：没有知道密码的密码房可以验证 `pwd` 字段的用法（只在 `type=aid` 带上够不够、密码错时怎么回答）。UPGRADES 写“受阻”，没有任务管；找到能验证的房间后在本平台加密码来源、界面在直播间任务做。
- 7-9 分享文本带 App 深链（部分完成）：平台层已有 `SoopApi.appLink` 和 `appLinkRoomId`，粘贴带深链的分享文本能进房；列表和直播间的开播时间已显示。分享时带深链没做：v4 的分享是 3.x 格式的分享码（`encodeRoomShareCode`），改格式会让 3.x 读不出，UPGRADES 写“未排”，列在 [V03.3](../../../V-需求和反馈/V03-审查和调研/V03.3-功能清点和已批准升级核对/README.md) 的“需要维护者决定”，没有任务管。
- 登录后播放接口对 19 禁、仅订阅直播回答 `RESULT` 1 时按 `GRADE`、`P_MIN_TIER` 标受限类型，是按字段名推断的，没有登录样本；`RESULT` -2（屏蔽）也没有样本，按 3.x 注释处理。没有任务管。
- 进房时多一个主页接口请求（和播放接口同时发出）：7-5 要求的，关注刷新和录制仍只发一个请求，不是缺口。
- 弹幕 TLS 端口不通时是否退回明文端口（REG-SOOP-002）、受限房间进房时没有弹幕参数：归 [D01.8](../../../D-弹幕/D01-平台弹幕协议/D01.8-SOOP弹幕/README.md)。
- 海外平台在国内要代理，接口改版没有国内五大平台那样的定期巡检任务，没有任务管。
