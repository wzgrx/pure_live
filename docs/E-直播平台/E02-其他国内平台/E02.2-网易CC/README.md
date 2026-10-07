# E02.2 网易 CC

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：平台
- 来源：3.x 平台逐个重构（D-001）；之后的升级落地（2026-09-29，UPGRADES 9-1～9-7）和国内平台完善（2026-10-01，弹幕调查）都记在 [record.md](record.md)
- 旧编号：M4.09、M4.U.9、T02b.2
- 相关：模型 [E05.1](../../E05-平台框架和模型/README.md)、[E05.2](../../E05-平台框架和模型/README.md)；链接 [E04.1](../../E04-链接解析和分享口令/README.md)；未开播显示（UPGRADES A-6）在 [E06.1](../../E06-平台层升级/E06.1-已批准升级的余项/README.md) 确认；弹幕没有接上（UPGRADES C-22）；决定 D-001、D-017、D-018
- 代码：`packages/live_core/lib/src/sites/cc/`（`cc_api.dart` 895 行解析，`cc_site.dart` 449 行请求编排）；样本 `fixtures/cc/`（34 组，`legacy_expected.dart` 补出 14 个 3.x 冻结输出）

## 目标

把 3.x 的网易 CC 适配器（`lib/core/site/cc/cc_site.dart` 424 行、`cc_catalog.dart` 118 行）重构进 `live_core`。首次重构保持 3.x 用户实际看到的样子（画质名称、可选项、播放地址），只在 3.x 报错的地方兜底；升级落地时按用户采用的 9-1～9-7 换成真正不同的画质、移动端分类、重播频道标回放、关注刷新区分不存在。

## 平台接口要点

| 功能 | 接口 | 位置 |
|---|---|---|
| 分类 | 移动端 `api.cc.163.com/v1/wapcc/gamecategory?catetype=0` 取 4 个一级分类（网游、手游、竞技、综艺），再各请求一次取分区（约 106 个）；同时读大神的游戏表（`inf.ds.163.com/…/base-info-list/by-type`）和直播配置（`inf-act.ds.163.com/…/commonAppConfig`）得到“官方房间/专题”入口；共 7 个请求 | `cc_site.dart:98-138` |
| 分区房间 | `cc.163.com/api/category/<gametype>/`，每页 30，满页才有下一页（目录分页 `getDirectoryPage`） | `:154`、`:168`、`:441` |
| 推荐 | `cc.163.com/api/category/live/`，条数照调用方（热门页要 100） | `:181`、`:184` |
| 搜索 | `cc.163.com/search/anchor/`（路径带斜杠，3.x 少斜杠多一次 301），每页 1～50 | `:197`、`:201`、`:212` |
| 详情 | `api.cc.163.com/v1/activitylives/anchor/lives?anchor_ccid=` 拿频道号，再 `cc.163.com/live/channel/?channelids=`；没有频道就是未开播；进房时读房间页 `cc.163.com/<ccid>/` 补全并区分不存在；关注刷新另请求 `api.cc.163.com/v1/wapcc/recommendbyccid?ccid=`（约 2.5 KB，`code` 4 是不存在，8 秒超时） | `:232-262`、`:276-291` |
| 画质和线路 | `vapi.cc.163.com/video_play_url/<ccid>`：`vbrname_list` 从高到低，名字用 `vbrname_mapping`（原画、蓝光5M、蓝光3M、超清、高清、标清），FLV 两个 CDN（`hs`、`ali`），`auth_key` 300 秒、`cutsConnection` 为假；失败时退回 3.x 的跳转播放列表 `cgi.v.cc.163.com/redirect/video/<ccid>.m3u8` | `:302-373` |
| 链接 | `cc.163.com/<数字>`、`ds.163.com/glive/?ccid=`、`h5.cc.163.com/cc/<ccid>`，只收数字 | `:394` |

## 3.x 和现状

| 方面 | 3.x（`lib/core/site/cc/`） | 现在 | 说明 |
|---|---|---|---|
| 分类 | `cc_site.dart:32`、`cc_catalog.dart`：大神配置“直播分类”20 个分区 | 移动端 4 组 106 个分区 + 官方入口 | 9-4；3.x 存下的分区 id（`gametype`）照常能打开 |
| 画质 | `getPlayQualites` `:128`、`getPlayUrls` `:219`：每档都是同一个跳转播放列表拼签名，服务端忽略签名，全部 302 到同一路 1 Mbps；跳转后的 HLS 300 秒过期 | `video_play_url`，每档不同的流 | 9-1；画质 id 对照 `CcApi.qualityIdFromLegacy`（`high` → `ultra`、`medium` → `high`、`low` → `standard`，只能套用一次） |
| 详情 | `:262`；`:297-300` 未开播时拿 `null` 查频道，`data[0]` 抛 RangeError，进房“状态未知”；`:314` 房间号取响应 | `:276` | 未开播如实返回；进房区分不存在；房间号保持请求时的号码 |
| 重播频道 | “【重播】”开头仍是直播中 | 回放（有流照常播） | 9-3 |
| 推荐卡片 | `:248` 读 `game_name`，推荐的行只有 `gamename`，没有分区名 | 读 `gamename` | 9-2 |
| 搜索卡片 | 头像作封面、粉丝数作人数 | 在播的用直播封面和热度 | 9-5 |
| 链接 | `common/utils/live_url_tool.dart:143-145` 把 `cc.163.com/任何单词` 当房间 | 只收数字 ccid | 3.x 问题 11、12 |
| 弹幕 | `getDanmaku()` `:27` 是 `EmptyDanmaku` | 不登记，界面显示“不支持”（`app/platforms.dart` 的弹幕登记表注释） | 匿名加入房间没有回答 |

## 结果

- 首次重构（2026-09-28，提交 `480454577`）：15 个 3.x 问题、11 条有意差异见 record.md；实测确认 3.x 的画质选择不起作用（4 档全部 302 到同一个 `…tc2.m3u8`）。
- 升级落地（2026-09-29，`c64520ece`）：9-1～9-7 全部做完；开播时间取 `startat`（北京时间，按 `liveMinute` 核对时区）；有档位表的在播房间受限类型为 `none`；分区列表的坏行只跳过这一行。请求数：分类 2 → 7，未开播的关注刷新 1 → 2，取画质 0 → 1。
- 国内平台完善（2026-10-01）：真实接口全部正常（线路全是 H.264 的 FLV）；弹幕调查：`wss://weblink.cc.163.com/` 能连、设备注册和心跳都通，但匿名“加入房间”（`{512, 1}`）没有任何回答，判断要登录用户，按任务要求不硬做（候选 C-1）。
- 测试：`packages/live_core/test/sites/cc_api_test.dart` 39 个 `test(` 写法、`cc_site_test.dart` 33 个（record.md 统计 79 个用例）。

## 验证

- 自动测试：样本逐键对照 3.x 冻结输出，9-2、9-3、9-5、9-6 的变化用 `changed:` 列出；画质 id 对照表核对 3.x 每一档都能在同一房间的新列表里找到；关注刷新的 `NotFound`、超时和异常回答。E06.1 的 A-6 引用 `cc_site_test.dart` 的“an offline anchor on room entry: the room page fills the room”。
- 真实接口：2026-09-28 逐档逐线路请求核对；2026-09-29、2026-10-01 各跑一遍（推荐、分类、分区、搜索、2 个直播 1 个重播 1 个未开播、画质和线路、弹幕探针）。
- 真机：播放 K90 看过（[FEATURES.md](../../../inventory/FEATURES.md) 第 14 节）。

## 留下的问题

- 弹幕：匿名加入不回应（UPGRADES C-22、候选 C-1），等支持 CC 登录 Cookie 后再试登录用户的 `{2, 2}`；现在“只存，未用于请求”。
- 付费、私密、密码房没有在播的例子（2026-09-29 扫了全站 100 个在播房间），受限类型只填 `none`。
- `ultra`、`standard`、`blueray_5M_avc` 与 3.x 档位的对应是实测核对，没有录成样本。
- 分类名“官方房间/专题”要多语言（界面层）。
