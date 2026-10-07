# E02.12 六间房

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 31-1～31-6，31-4 部分完成）记在 [record.md](record.md)；聊天由 D01.28 接上
- 旧编号：M4.31、M4.U.31、T02b.12
- 相关：模型 [E05.1](../../E05-平台框架和模型/E05.1-基础模型与接口/README.md)、[E05.2](../../E05-平台框架和模型/E05.2-模型扩展/README.md)（合并规则、受限类型）；链接 [E04.1](../../E04-链接解析和分享口令/E04.1-平台框架与链接解析/README.md)；聊天 [D01.28](../../../D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/README.md)（用 `SixRoomDanmakuArgs`）；分区页 A09.4、A09.5；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/sixroom/`（`sixroom_api.dart` 1058 行解析和链接，`sixroom_site.dart` 497 行请求编排）；样本 `fixtures/sixroom/`（ls 共 28 项：26 组接口录制，另有 `legacy_expected.dart` 补出 3.x 冻结输出和弹幕样本目录 `danmaku/`）；应用在 `apps/pure_live/lib/app/platforms.dart:183` 建 `SixRoomSite(http)`

## 目标

把 3.x 的六间房适配器（`lib/core/site/sixroom/` 三个文件共 910 行）重构进 `live_core`。3.x 最严重的问题是“没在本次运行里列过的房间一律打不开”：房间页正则要求 `roomid: '<n>'` 带引号，页面改了以后解析失败，关注刷新、从关注进房、录制、粘贴链接、按房间号搜索全都报错，只有先看过目录或搜索的房间能借 `_known` 缓存打开。共修掉 15 个问题；升级落地后列表改用移动端接口（不再每次下载 0.5～1.1 MB 的首页）、头像和标题取对字段、搜索标出直播中。

## 平台接口要点

| 功能 | 接口（匿名，网页请求用 Chrome 140 UA、`Accept-Language: zh-CN`、`Referer`，移动端请求用 iOS App 的 UA；不跟随跳转，单个请求 15 秒、每次调用 20 秒，回答最多 8 MiB） | 位置 |
|---|---|---|
| 分类 | 一个分类“六间房直播”，六个分区：全部、歌区、舞区、脱口秀、星颜、派对（id `all`、`song`、`dance`、`talk`、`face`、`party`，和 3.x 相同）；不发请求 | `sixroom_site.dart:294`；`sixroom_api.dart:338`、`:476` |
| 推荐、分区 | 推荐和歌区、舞区、脱口秀、派对：移动端 `coop/mobile/index.php`（`special`、`u0`、`u1`、`u2`、`u8`），每页一个请求，同一列表从第 1 页起跨页去重；“全部”：首页 `v.6.cn/` 的 `window.__SMARTY_ALL_VARIABLES__.typeList`；星颜：网页 `/subareaIndex/getSubareaIndexNew.php?subarea=10`（移动端 `u10` 是空的）；这两个一次读全、本地分页，第 1 页重新读、之后 90 秒内共用（31-4） | `sixroom_site.dart:189`、`:211`、`:233`、`:261`、`:301-318`；`sixroom_api.dart:432`、`:448`、`:547`、`:583`、`:607` |
| 搜索 | 房间号或链接查房间（不取流）；其他关键词 `search.php?type=use&key=`（只有一页；超过 80 字不发请求，16～80 字时网站回“过长”提示，给空结果）；按 `<i class="live">` 标直播中，`/profile/<房间号>` 链接标未开播（31-3） | `sixroom_site.dart:326`、`:337`；`sixroom_api.dart:452`、`:670` |
| 详情 | 冷启动时先读房间页取用户 id，再 POST 移动端 `coop-mobile-inroom.php`（表单 `av=3.1&…&rid=&ruid=`，回答约 19 万字节）；列过的房间直接用记住的用户 id（1 个请求）；`flag` 必须是 `001`；头像取 `roominfo.uoption.picuser`（31-1），标题取直播标题、再主播签名 `roomParamInfo.operation.userMood`（31-2）；私密房（`isPriveRoom`）`private`、黑屏（`blackScreenInfo.msg`）`unplayable`，有场次号就是直播中；记住最多 2000 个列过的房间补缺的字段（热度、开播时间、场次号只在同一场时补，31-5） | `sixroom_site.dart:17`、`:176`、`:374`、`:392`、`:407-422`；`sixroom_api.dart:459-462`、`:746`、`:783`、`:895` |
| 取流 | 一档 `flv:source`（“FLV 原始线路 · 1024x768 · 2652 kbps”），地址 `https://wlive.6rooms.com/httpflv/v<用户 id>-<场次>[-many].flv`，流名必须对得上主播和场次；线路编号 `wlive`，没有租期；不发请求（恢复时重新读详情） | `sixroom_site.dart:438`、`:460-486`；`sixroom_api.dart:325-333`、`:870`、`:940`、`:955` |
| 链接 | 纯房间号（2～12 位）和 `v.6.cn`、`m.6.cn` 的 `/<房间号>`、`/profile/<房间号>` | `sixroom_site.dart:496`；`sixroom_api.dart:393` |

聊天（6.cn 私有 WebSocket）归 [D01.28](../../../D-弹幕/D01-平台弹幕协议/D01.28-六间房弹幕/README.md)：进房时给 `SixRoomDanmakuArgs`（房间号、用户 id），不多发请求。

## 3.x 和现状

| 方面 | 3.x（`~/ref/v3ref/lib/core/site/sixroom/`） | 现在（`packages/live_core/lib/src/sites/sixroom/`） | 说明 |
|---|---|---|---|
| 没列过的房间 | `sixroom_api.dart:280-283`、`:383` 房间页正则要求带引号，失败报 `schema` | 先读房间页取用户 id 再 inroom，能打开 | 3.x 问题 1 |
| 头像 | `sixroom_api.dart:447` 读空的 `headPicUrl` 和不存在的 `picuser`，界面显示封面并随关注存下 | inroom 的 `roominfo.uoption.picuser` | 31-1 |
| 详情标题 | `sixroom_api.dart:424` 读不存在的 `roominfo.userMood`，总是昵称，刷新盖掉卡片的签名 | 直播标题，再主播签名 | 31-2 |
| 搜索 | `sixroom_api.dart:269` 超过 80 字报错，`:338-341` 网站的“过长”提示被当成“无权访问”；`:364` 状态总是“未知” | 给空结果；标直播中、未开播 | 3.x 问题 4；31-3 |
| 列表 | `sixroom_api.dart:238-262` 每次刷新下载 0.5～1.1 MB 首页，本地筛选 | 移动端列表按分区分页（“全部”、星颜仍读全） | 31-4 |
| 补全 | `sixroom_api.dart:87` 已下播的房间仍显示最近一张卡片的热度 | 同一场才补 | 31-5 |
| 受限 | 显示“未知” | 私密房、黑屏的房间有场次号就是直播中，标 `private`、`unplayable`，取流说明原因 | 统一原则 |
| 占位 | `sixroom_api.dart:314`、`:424` 昵称、标题空时 `Six Rooms` | 留空 | 统一原则 |
| 网页解析 | `package:html` | `HtmlElement`（`packages/live_core/lib/src/html.dart`） | 不加依赖，结果逐字段相同 |
| 公告 | “远端聊天尚待接入”等开发说明 | `chatNotice`“人数是平台的热度，不是正在观看的人数。”、`restrictedNotice` | 统一原则“说明文字” |
| 聊天 | 没有 | `packages/live_danmaku/lib/src/sites/sixroom.dart`（D01.28） | 31-6 |

## 结果

- 首次重构（2026-09-28，提交 `98c644829`）：15 个 3.x 问题、12 条有意差异见 record.md；补录了 3.x 自己的请求（首页、在播房间 8838 的房间页和 inroom 等，同一分钟）。
- 升级落地（2026-09-29，`8e55bea2c`）：31-1～31-5 完成（31-4 只做了列表），31-6 交给 D01.28；开播时间取 `realstarttime` 和 inroom 的 `liveinfo`；两个公告改通俗；新样本 `S06-*`。分区 id 不变，已关注的分区不用迁移。
- 测试：`packages/live_core/test/sites/sixroom_api_test.dart` 24 个 `test(` 写法、`sixroom_site_test.dart` 30 个（与 record.md 统计的 54 个用例相同；对照用例里按样本逐个比较）；聊天 `packages/live_danmaku/test/sites/sixroom_test.dart` 27 个。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出（首页 443 个房间、38 个链接、48 种 inroom 改动等）；没列过的房间能打开、头像和签名、搜索直播中标记、超长关键词、移动端列表的跨页去重、“全部”和星颜的 90 秒快照；时钟 +30 天、+5 年下也通过。
- 真实接口：2026-09-28 20:48～21:03 UTC（北京时间凌晨）直连逐个试了移动端列表的类型、首页脚本里的分区接口；同一时刻首页 109 个在播房间、移动端合起来 81 个。不用代理。
- 真机：没有在 K90 上专门看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节六间房一行“播放：完成”“弹幕：新增”，指样本和探针测过）。

## 留下的问题

- 31-4（UPGRADES，部分完成）：列表完成；“详情改读房间页”受阻：房间页（约 6.5 万字节）没有关注数和私密房标记，签名也不是卡片用的那段，所以详情仍读约 19 万字节的 inroom。没有任务管。
- 31-5 的界面部分：关注刷新时 `LiveRoom.mergeFrom` 遇到空热度会保留存下的值，重新开播后在拿到新卡片前可能仍显示上一场的热度（record.md 建议界面合并关注时状态变化就清掉热度），没有任务管。
- 私密房、黑屏没有真实样本；私密房在播时 inroom 给不给场次号和流名不知道。
- 移动端列表只在凌晨录过，晚高峰的数量没核实；移动端列表卡片没有头像（界面显示昵称首字，看过的房间用记住的头像）。
- 表外发现：inroom 的 `roomlist.content.num` 看起来是热度，可以让没看过卡片的直播间也显示热度；会改变用户看到的内容，要先问用户，没有任务管。
- 分区名、画质名、公告是平台层给的中文，英文界面仍显示中文 → [Z05.2](../../../Z-工程文档和维护/Z05-多语言/Z05.2-英文界面里平台给的中文/README.md)。
