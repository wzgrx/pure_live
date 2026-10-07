# E05.4 平台层小问题合集：任务书

## 背景

- 来源：2026-10-07 docs v2 各组核对时发现、维护者归到一起的八个小问题（详见本文件夹 `README.md` 的对照表）：E 组（克拉克拉到底、LOOK 搜索说明、占位名、`getDanmaku` 死代码、斗鱼注释），D 组（AcFun 付费直播、百度签名、六间房），H、I 组更正（六间房录制不受影响，受影响的是多画面）。
- 现象（按问题编号）：
  1. 推荐 → 克拉克拉，往下翻到第 3 页左右列表就显示“没有更多了”，实际第 4 页还有新主播（E02.6 实测：热门第 3 页全是重复）。
  2. 搜索选 LOOK，提示“LOOK：只能用房间号或直播链接查找，不支持昵称搜索。”，但输入昵称其实能搜到推荐里的主播。
  3. 进一个 AcFun 付费直播间：画面说要购票（受限，正确），聊天区却是“弹幕连接失败”。
  4. 百度直播间连续开着到签名过期：弹幕结束后每 60 秒“重连”一次又马上结束。
  5. 多画面里放一个六间房（或 AcFun、克拉克拉）直播间，选中它，聊天区没有弹幕；直播间里有。
  6. 老用户关注里的京东、酷狗、百度主播，名字显示 `JD Live` / `Kugou Live` / `Baidu Live`。
  7、8：开发者看到的：死代码、注释写错。
- 为什么现在做：第二档；单个都很小，合起来规模中（三个阶段各约 1 小时）。
- 已经做过的：克拉克拉去重和 3 页上限（E02.6，UPGRADES 15-3）；搜索能力表（I05.1 照 3.x 搬）；受限但在播时连弹幕（U.2g c11）；百度弹幕（D01.27）；多画面（N01.1）；占位名不再写（E02.9 的 28-2、UPGRADES X-2）。

## 目标和验收

1. 克拉克拉（以及任何适配器）返回“空页 + 还有下一页”时列表接着取；连续两页没有新房间才到底（和 3.x 一样）；平台说 `hasMore: false` 时照旧到底。
2. 搜索 LOOK 的说明是“输入号码或粘贴链接可精确查找；其他关键词只在平台当前推荐的直播里按昵称筛选，搜不到未开播的主播。”（`search_scope_showcase`）。
3. 直播间：房间没有弹幕参数（`danmakuData == null`）时不去连，聊天区是空闲状态，不出现“弹幕连接失败”；有参数的受限直播（U.2g c11）照旧连。
4. 百度：刷新（`getRoomDetailForRefresh`）在直播中带 `danmakuData`，不多发请求；`data`（播放数据）仍只在进房和录制时带。
5. 六间房、AcFun、克拉克拉的录制详情带弹幕参数，多画面选中这些格子时有弹幕；其他平台逐个核对的结果写进记录（表：平台、进房带不带、录制带不带、补不补、理由）。
6. `live_core` 导出 `legacyPlaceholderNames`（`jdLive` → `JD Live`、`kugouLive` → `Kugou Live`、`baiduLive` → `Baidu Live`），带 3.x 出处注释；本任务不改任何存储的数据。
7. `LiveSite.getDanmaku`、`LiveDanmaku`、`EmptyDanmaku` 删掉，`packages/live_core` 测试全部通过，注释不再提它们（`grep -rn "getDanmaku\|EmptyDanmaku" packages apps` 只剩 3.x 的说明文字或为空）。
8. `douyu_site.dart` 的注释写 `douyuForceRenew`。
9. 门禁通过；没有新设置、没有新翻译键。

## 现状（读代码得出，写文件:行）

- 1：`apps/pure_live/lib/shared/rooms/room_feed.dart`：`_collect`（`:459-488`）：`unchanged = fresh.isEmpty ? unchanged + 1 : 0`（`:482`），`hasMore = chunk.hasMore && chunk.rooms.isNotEmpty && unchanged < 2`（`:483`）。适配器：`packages/live_core/lib/src/sites/kilakila/kilakila_site.dart:146-190`（`idle`、`maxPagesWithoutNew = 3` `:59`）。测试：`apps/pure_live/test/features/popular/popular_test.dart:163`（“an empty page ends the list”，假平台第 3 页的 `hasMore` 要核对）。
- 2：`apps/pure_live/lib/features/search/search_capability.dart:139`；`SearchCoverage.showcaseSnapshot`（`:20`）、说明键的选法（`:176-186`）；`mayIncludeOffline`（`:58-61`）`roomLookup` 算“可能有未开播”，`showcaseSnapshot` 不算（LOOK 的筛选只在推荐里，本来就没有未开播的）。LOOK 搜索：`packages/live_core/lib/src/sites/looklive/looklive_site.dart:225-260`。测试 `apps/pure_live/test/features/search/search_test.dart`。
- 3：`apps/pure_live/lib/features/live_play/logic/room_controller.dart:807` `_danmakuStage`，`_syncDanmaku`（`:809-846`）；`packages/live_danmaku/lib/src/connection_base.dart:53-56` `connect` 对类型不符（含 null）抛 `ArgumentError`；`_syncDanmaku` 的 `on Object` 分支（`:839-845`）显示 `live_play_danmaku_connect_failed`。AcFun：`packages/live_core/lib/src/sites/acfun/acfun_site.dart:446-457`（付费直播没有 `data` 和 `danmakuData`）。
- 4：`packages/live_core/lib/src/sites/baidulive/baidulive_site.dart:314-321`（进房 `withData: true`、刷新不传）；`baidulive_api.dart:907-935` `liveRoom({bool withData = false})`，`:933-934`。
- 5：`apps/pure_live/lib/features/multiview/logic/multiview_controller.dart:486-490`、`:861-867` `_danmakuTarget`；六间房 `sixroom_site.dart:392-417`（`_detail(…, danmaku:)` `:392`、`:400`；录制 `:416`）；AcFun `acfun_site.dart:466-471`；克拉克拉 `kilakila_site.dart:300-337`（`_entered({withDanmaku = false})` `:300`、`:320`；录制 `:337`）。全部平台的录制详情：`grep -rn "getRoomDetailForRecording({required String roomId})" packages/live_core/lib/src/sites`（34 处）。
- 6：`packages/live_store/lib/src/legacy/legacy_rules.dart`（`LegacyRules`，只有陈旧公告 `:11-14`、`:28`）；E02.9 记录的清理建议（`docs/E-直播平台/E02-其他国内平台/E02.9-京东直播/record.md` 第 265 行起）。
- 7：`packages/live_core/lib/src/live_site.dart:26-27`；`packages/live_core/lib/src/live_danmaku.dart`；`packages/live_core/lib/live_core.dart:16`；测试 `grep -rn "getDanmaku\|EmptyDanmaku" packages/live_core/test`（37 个文件、47 处，例如 `sites/picarto_site_test.dart:118`、`live_site_test.dart:224`）；注释 `apps/pure_live/lib/app/services.dart:19`、`:57`、`:114`，`packages/live_danmaku/lib/src/registry.dart:42`，`packages/live_core/lib/src/sites/missevan/missevan_site.dart:27`，`fc2live/fc2live_site.dart:21`。
- 8：`packages/live_core/lib/src/sites/douyu/douyu_site.dart:73`；`packages/live_store/lib/src/settings/settings.dart:117`。

## 3.x 基线

- 1：3.x 列表（`lib/common/base/`）连续两页没有新房间才结束——4.x 的 `unchanged < 2` 就是照它写的（`room_feed.dart:460-461` 注释“Two chunks in a row without a new room end the list (3.x)”），多出来的 `chunk.rooms.isNotEmpty` 是 4.x 自己加的。
- 2：`git show v3.2.11:lib/modules/search/search_capability.dart:111-115` 同样写成 `roomLookup`，3.x 就和自己的搜索实现不一致；按实现改，属于修正。
- 3：3.x AcFun 付费直播整个加载失败（没有“受限但在播”）。
- 6：3.x 的占位：`lib/core/site/jdlive/jd_live_api.dart:231-232`、`:261-262`；`lib/core/site/kugoulive/kugou_live_api.dart:396-397`、`:505-506`；`lib/core/site/baidulive/baidu_live_api.dart:390`。
- 要保留：克拉克拉 3 页没有新主播就结束（15-3）；搜索能力的其他平台不变；受限但在播时有参数就连弹幕（U.2g c11）；录制的弹幕照旧走 `getRoomDetail`。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层：`live_core` 不能依赖 `live_danmaku`）；`docs/specs/UPGRADES.md` 的 15-3、X-2、28-2、30-10。
3. 本文件夹的 `README.md`；`docs/E-直播平台/E02-其他国内平台/README.md`（“已知问题”）；`docs/E-直播平台/E02-其他国内平台/E02.6-克拉克拉/README.md`；`docs/D-弹幕/D01-平台弹幕协议/D01.27-百度直播弹幕/README.md`、`D01.28-六间房弹幕/README.md`。

## 范围

- 可以改：`apps/pure_live/lib/shared/rooms/room_feed.dart`（只改 `:483` 和注释）；`features/search/search_capability.dart`（只改 LOOK 一行）；`features/live_play/logic/room_controller.dart`（只改 `_danmakuStage`）；`packages/live_core`（百度、六间房、AcFun、克拉克拉的适配器；新文件放占位名；删 `getDanmaku`；斗鱼注释）；`apps/pure_live/lib/app/services.dart`、`packages/live_danmaku/lib/src/registry.dart`（只改注释）；对应测试；本文件夹。
- 不能改：存储的数据（占位名清理在 J06.2）；`mergeFrom`；弹幕协议；多画面控制器的逻辑（只靠平台层补参数）；其他平台的搜索能力；设置键名和含义（D-018）；翻译文件（D-024：不删不加）；版本号、`assets/version.json`、`assets/releases.json`；签名配置。

## 方案和阶段

| 阶段 | 做什么（对应 README 的 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 列表和搜索：克拉克拉空页、LOOK 搜索说明 | c1、c2 | `room_feed.dart`、`search_capability.dart`、`popular_test.dart`、`search_test.dart` | 验收 1、2 |
| 2 弹幕参数：AcFun 付费直播、百度刷新带参数、录制详情带弹幕参数 | c3、c4、c5（含逐平台核对表） | `room_controller.dart`、`baidulive_site.dart`、`baidulive_api.dart`、`sixroom_site.dart`、`acfun_site.dart`、`kilakila_site.dart`（和核对后要补的）、测试 | 验收 3、4、5 |
| 3 清理：3.x 占位名常量、getDanmaku 死代码、斗鱼注释 | c6、c7、c8 | `packages/live_core`（新文件、`live_core.dart`、`live_site.dart`、删 `live_danmaku.dart`、37 个测试文件）、两处应用和 `live_danmaku` 的注释 | 验收 6、7、8 |

每个阶段都要能单独合并（门禁通过、不留半截功能）。阶段 3 的占位名常量最好先于 J06.2 合并。

## 测试

- 阶段 1（改之前会失败）：`popular_test.dart` 加“an empty page that says more may follow does not end the list; two in a row do”：假平台第 1 页 2 个、第 2 页全重复（去重后空，`hasMore: true`）、第 3 页 1 个新的；`ensure(10)` 后有 3 个、请求了 1～3 页；再造连续两页空，列表到底。`search_test.dart`：LOOK 的说明是 `search_scope_showcase` 的文字。
- 阶段 2（改之前会失败）：`live_play_controller_test.dart` 加“a live room without danmaku arguments does not connect (AcFun paid show)”：`liveRoom(…, restriction: paid, danmakuData: null)` 且取流 `StreamUnavailable` → `controller.chatConnection == ChatConnection.idle`，`danmaku.connects` 为空，聊天里没有“弹幕连接失败”。`baidulive_site_test.dart`：刷新回答有 `danmakuData`、没有 `data`（用现有的 `fixtures/baidulive/S02-room-chat`）。`sixroom_site_test.dart`、`acfun_site_test.dart`、`kilakila_site_test.dart`：录制详情的 `danmakuData` 和进房的相同。`multiview_controller_test.dart`：六间房格子选中后 `connect` 被调用（用 `multiview_support.dart` 的假平台模拟“录制详情带参数”）。
- 阶段 3：删断言后 `packages/live_core` 全部测试通过；`legacyPlaceholderNames` 加一个小测试（三个平台、值和 3.x 一致）。
- 测试里的定时器至少 1 秒（D-017）；不访问真实平台（用 `fixtures/`）。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 推荐 → 克拉克拉，一直往下翻 | 翻过以前停住的位置（约第 3 页）还能加载出新主播；最后出现“没有更多了” |
| 2. 搜索 → 平台选 LOOK，看输入框下的说明；输入一个推荐里主播的昵称 | 说明是“输入号码或粘贴链接可精确查找；其他关键词只在平台当前推荐的直播里按昵称筛选……”；能搜到 |
| 3. 进一个 AcFun 付费直播间（找不到就跳过） | 画面写要购票；聊天区没有“弹幕连接失败” |
| 4. 多画面 → 加一个在播的六间房直播间，点选它 | 聊天区出现弹幕；AcFun、克拉克拉同样 |
| 5. 百度直播间进房、开着 2 分钟 | 弹幕正常（签名过期等不到，看自动测试） |

## 风险和注意

- c1 改的是共用列表：所有平台的“空页 + 还有下一页”都会多取一页（最多两页）才到底；有的平台在最后一页之后返回空页却说 `hasMore: true`（写错的适配器），会多一次请求，可以接受。`maxRequests`（每次 `ensure` 的请求上限）照旧兜底。
- c3 会让“播放中但没有参数”的房间也不连：确认没有平台在进房详情里故意不带参数、要靠连接自己取（`grep -n "danmakuData" packages/live_core/lib/src/sites/*/`）；有的话写进记录，别改坏。
- c5 录制详情多带参数会让录制任务的 JSON 变大一点（`danmakuData` 不进录制任务的存储时没影响，核对 `packages/live_record` 存了什么）。
- c7 删公开接口：`live_core` 是本仓库内部包，没有外部使用者；`archive/v4` 分支不管。
- `live_core` 不能依赖 `live_danmaku`（分层门禁），占位名表只放字符串。
- 可能冲突的文件：`room_controller.dart`（C01.4、C01.5、C01.6）；`room_feed.dart`（I03.2 改 `retry`）；`search_capability.dart`（I05 的后续）。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/E05.4` 或本机工作区；提交信息以 `[E05.4]` 开头（英文）；不推 master。
- 提交前：改过的包（`packages/live_core`、`apps/pure_live`、只改注释的 `packages/live_danmaku`）跑 `dart format --output=none --set-exit-if-changed .`、analyze、测试；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

八条各做到没有；录制详情逐平台核对表；测试数量（改之前失败几个）；改了哪些文件；删掉的公开接口；要在真机上看的；可能冲突的文件。
