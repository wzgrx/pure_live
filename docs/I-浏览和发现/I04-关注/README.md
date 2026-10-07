# I04 关注

关注列表背后的逻辑：关注的房间怎么分成“已开播 / 录播 / 未开播”、平台标签和标签筛选怎么算、怎么排序；开播状态怎么核验和刷新（启动、下拉、再点、定时、回到前台、直播间“看其他”），并发、超时、失败冷却，刷新结果怎么合并回存储。

## 范围

- 包括：
  - `apps/pure_live/lib/features/favorite/favorite_rules.dart`：分组（`groupOf`）、平台标签（`platformTabs`）、排序（`FollowOrder`）、筛选（`roomsOf`）、可选标签（`tagsOf`）、各组数量（`groupCounts`）。
  - `features/favorite/follow_refresher.dart`：一次刷新（`FollowRefresher`：一个房间一个请求、并发上限、10 秒超时、失败 5 分钟冷却、已下线平台不请求、`bindToFollow`）。
  - `features/favorite/favorite_controller.dart`：`FavoriteController`（整个应用一个，`favoriteControllerProvider`）：监听关注、标签、标签分配和设置；刷新的时机和排队；`firstCheck`（启动页等它）；`lastFailed`、`lastFullRefreshAt`（直播间“看其他”的刷新按钮显示）。
  - `favorite_page.dart` 里调控制器的地方（下拉、刷新失败提示 `:142-146`）。
  - 和关注有关的设置怎么生效：`autoRefreshFavorite`、`autoRefreshInterval`、`refreshFavoriteOnResume`、`maxConcurrentRefresh`、`preferRealOnlineCounts`、`realOnlinePlatforms`、`hotAreasList`（平台标签顺序）。
- 不包括（归哪里）：
  - 关注页**长什么样**（状态标签、平台标签、分组行、网格和未开播紧凑行、翻页栏、空状态）→ [A09.3 关注](../../A-界面设计/A09-浏览界面/A09.3-关注/README.md)；卡片和卡片对话框（关注、取消关注和撤销、设置标签）→ [A09.1](../../A-界面设计/A09-浏览界面/A09.1-房间卡片/README.md)、`shared/rooms/room_menu.dart`。
  - 关注的存储（`live_store` 的 `FollowStore.update` 用 `LiveRoom.mergeFrom` 合并、3.x `favorites` 的导入、身份迁移 `IdentityMigration`）→ [J02](../../J-设置和数据/J02-存储和加密/README.md)、[J06](../../J-设置和数据/J06-3.x数据迁移/README.md)；`LiveRoom.followGroup`、`pendingAfterError`、`withAudienceFallbackFrom`（模型）在 `packages/live_core`（E05）。
  - 标签和标签分配的存储、标签管理页 → [I07](../I07-标签和分组/README.md)。
  - 直播间“看其他”面板（用这里的 `refreshAll`）→ [A07.13](../../A-界面设计/A07-直播间界面/A07.13-切换直播间面板/README.md)；各平台的刷新接口 `getRoomDetailForRefresh` → E。
  - 录制的开播检测（和关注无关）→ [H04](../../H-录制/H04-自动录制和排队/README.md)。

## 现状：做到哪、怎么工作的

- 用户看得到的：
  - 三组：已开播（含受限的直播）、录播（能播的回放）、未开播（其余，含不能播的回放、轮播、已下线平台的关注）。标签上带数量。已开播和录播按人数（按“优先实时在线”设置）排，选了标签时先按标签顺序；未开播保持关注顺序。
  - 平台标签：“全部”+ 所有有关注的平台——“平台显示”里的按它的顺序在前，其余按应用的平台顺序，已下线和未知的最后（3.x 只列平台显示里的，I04.1 问题 3）。平台列表变了按 id 留在原平台。标签条只列当前组和平台下用到的标签，切平台或组时回到“全部”。
  - 启动核验：应用首帧后开始（`AppStartup.start`，`lib/app/startup.dart:84`），先等身份迁移（`followsReady`），期间卡片“正在核验”、留在原组；启动页最多多等 350 毫秒。失败的卡片“状态待确认”（人数保留）。
  - 刷新：下拉、电脑翻页栏的“刷新”、再点首页“关注”→ 只刷当前平台和标签（不分组）；定时刷新（默认关，间隔默认 30 分钟、5～360）→ 全部、不显示进度、遵守失败冷却；回到前台（默认开）→ 全部，距上次全部刷新不到 15 秒不刷；直播间“看其他”的刷新 → 全部、不显示进度。手动刷新有失败时提示“N 个直播间暂时获取失败，已标为状态待确认”。同一时间只跑一轮，正在跑“全部”时来的请求等它结束直接返回。
  - 一次刷新：同时最多“并发刷新数”个（默认 4，1～20），每个请求 10 秒超时；失败的房间 5 分钟内不再请求（手动、启动、回到前台不受限）；已下线平台不请求；一轮的结果一次写回存储（卡片不会随单个请求跳动），合并不覆盖存下的名字、头像（`FollowStore.update`）。
  - 电脑（宽 > 680 且不是手机系统）有翻页栏（A09.3 c1 恢复 3.x 的），手机一次给出全部、懒加载。
- 内部怎么工作：

```text
favoriteControllerProvider（favorite_controller.dart:16，应用期间一个）
  FavoriteController.start（:104）：watch follows / tags / assignments / settings → _notify
      → _verifyAll（:201）：等第一次读到关注 → 等 followsReady（身份迁移）
          → 迁移动过关注就重读 → _enqueue(全部, bypassCooldown)
  _enqueue（:223）：排在正在跑的那轮后面；正在跑的是“全部”就直接返回
  _pass（:246）：FollowRefresher.refresh(targets, concurrency: maxConcurrentRefresh, onProgress)
      → store.follows.update(结果)（合并）→ lastFailed、lastFullRefreshAt
  时机：refreshVisible（:182，当前平台和标签）、refreshAll（:193）、_reselected（:276）、
        _resumed（:281，15 秒）、_scheduleAutoRefresh（:298，Timer.periodic）
FollowRefresher.refresh（follow_refresher.dart:54）
  过滤：已下线平台；冷却中的（除非 bypass）→ N 个 worker 取队列
  _load（:91）：getRoomDetailForRefresh（没有就 getRoomDetail）.timeout(10 s)
      成功 → bindToFollow（平台回了另一个房间号时按关注的身份）→ withAudienceFallbackFrom
      失败 → 记失败时间，结果用 pendingAfterError()
```

- 完成度（和 3.x 对照）：
  - 一致的：三组和排序、标签筛选和标签顺序、启动核验和“正在核验 / 状态待确认”、启动页等 350 毫秒、四种刷新时机、并发、10 秒超时、5 分钟冷却、一轮一次写回、15 秒、`bindToFollow`、电脑翻页栏。
  - 确认过的改动：刷新合并不清空存下的名字和头像（I04.1 问题 1、升级 X-2）；失败用 `pendingAfterError`（问题 2）；平台标签列出所有有关注的平台（问题 3，A09.3 c9）；已下线平台不请求、归未开播（问题 4）；手动刷新失败提示数量（问题 7，A09.3 c11）；没有关注时按钮“搜索直播”（问题 8，A09.3 c7）；标签带数量（A09.3 c4）；“全部”里卡片标平台（c10）；核验从首帧后开始（不等关注页打开，I01.2 接上）。
  - 后来改回的：I04.1 去掉了分页（问题 6），A09.3 c1 照 3.x 在电脑上恢复翻页栏（`favorite_page.dart:524-544`）；I04.1 加的“平台栏右侧刷新按钮”没有了，刷新靠下拉、再点“关注”、电脑翻页栏的“刷新”。
  - 还缺：无功能缺口；见“已知问题”。

## 代码地图

| 文件 | 职责 |
|---|---|
| `apps/pure_live/lib/features/favorite/favorite_rules.dart`（135 行） | `allPlatforms`、`allTags`（`:5`、`:8`）；`groupOf`（`:13`，已下线平台一律未开播）；`platformTabs`（`:22`：平台显示顺序 → 应用平台顺序 → 其余排序）；`onPlatform`（`:39`）；`FollowOrder`（`:42`，`compare` `:58`、`_tagRank` `:71`）；`roomsOf`（`:87`）；`tagsOf`（`:111`）；`groupCounts`（`:129`） |
| `features/favorite/follow_refresher.dart`（114） | `FollowRefreshResult`（`:9`）；`FollowRefresher`（`:30`：`timeout` 10 秒、`cooldown` 5 分钟、`refresh` `:54`、worker `:72`、`_load` `:91`）；`bindToFollow`（`:112`） |
| `features/favorite/favorite_controller.dart`（338） | `favoriteControllerProvider`（`:16`）；`FavoriteController`（`:41`：`rooms`、`tags`、`assignments`、`group`、`platform`、`tagId`、`verifying`、`refreshing`、`progress`、`lastFullRefreshAt` `:81`、`lastFailed` `:84`、`start` `:104`、`roomsFor` `:145`、`selectGroup`/`selectPlatform`/`selectTag` `:153-172`、`showGroup` `:178`、`refreshVisible` `:182`、`refreshAll` `:193`、`firstCheck` `:198`、`_verifyAll` `:201`、`_enqueue` `:223`、`_pass` `:246`、`_reselected` `:276`、`_resumed` `:281`、`_settingChanged` `:288`、`_scheduleAutoRefresh` `:298`） |
| `features/favorite/favorite_page.dart`（606） | 页面（界面归 A09.3）；和逻辑有关的：下拉和刷新后的失败提示（`:142-146`）、手机 `AppRefreshView`（`:509`）、电脑翻页栏（`:524-544`） |
| `apps/pure_live/lib/app/startup.dart:84`、`app/app.dart:86-93` | 首帧后开始核验；直播间“看其他”的刷新用 `refreshAll(visible: false)`，按钮显示 `lastFullRefreshAt`、`lastFailed` |
| `packages/live_store/lib/src/settings/settings.dart:738-759` | `autoRefreshFavorite`（默认关）、`refreshFavoriteOnResume`（默认开）、`autoRefreshInterval`（30，5～360 分钟）、`maxConcurrentRefresh`（4，1～20） |

测试：

| 测试文件 | 覆盖什么 |
|---|---|
| `apps/pure_live/test/features/favorite/favorite_test.dart`（16） | 规则 3 个（三组的归属含受限、回放、轮播、已下线；平台标签顺序；排序和标签筛选）；刷新 3 个（合并不清空、失败变待定、已下线不请求；并发上限和冷却、手动绕过；`bindToFollow`）；控制器 2 个（启动等身份迁移、期间“正在核验”；再点只刷当前平台、回到前台刷全部且 15 秒内不重复）；页面 8 个（没有关注；标签、数量、平台、标记、“查看未开播”；手机标签不截断；标签筛选、设置标签、取消关注和撤销；手机平台标签第二排 / 840 起并到顶栏；“全部”卡片标平台、未开播紧凑行；点卡片带着本组房间进直播间；没有在播时的说明） |

## 3.x 基线

- `~/ref/v3ref/lib/modules/favorite/`（`git show v3.2.11:lib/modules/favorite/...`）：`favorite_controller.dart`（842 行：冷却 5 分钟 `:43`、回到前台 15 秒 `:48`、10 秒超时 `:49`、事件 `refresh_favorite_rooms` `:238`、并发设置 `:772`、冷却判断 `:806`、请求 `:817`；平台栏只列平台列表 `:67-75`；失败只写日志 `:821-838`）、`favorite_startup_policy.dart`（127：结果整条替换 `:82`、`:121`，失败快照 `:123`）、`favorite_page.dart`（319：本地数据套服务器分页 `:139-147`；没有关注时“重试” `:289-297`）、`room_grid_view.dart`（139：下拉只在手机或窄屏 `:6-11`）。
- 再点关注刷新：`lib/modules/home/home_page.dart`（`favoriteController.tabBottomIndex`）；启动页等核验：`lib/routes/app_pages.dart`。
- 必须保留的操作习惯（[specs/UI.md](../../specs/UI.md) 附录 A）：第 14 条（卡片长按或右键 = 操作菜单）；另照 3.x：再点“关注”刷新、下拉刷新、启动核验。

## 已知问题和限制

| 问题 | 位置 | 影响 | 处理 |
|---|---|---|---|
| 平台没有适配器（不是已下线、也没登记，例如某个构建去掉了它）时算失败，但不记失败时间，不受 5 分钟冷却限制，每轮都再算一次失败 | `follow_refresher.dart:91-93`（`site == null` 直接返回 null，没写 `_failedAt`） | 定时刷新时这些关注每轮都算进“失败数”；不发请求，所以不耗流量 | 没有任务；影响小，顺手改时把它当已下线处理或记冷却 |
| 刷新失败的提示只在关注页的下拉 / 刷新后出现；定时和回到前台的失败不提示 | `favorite_page.dart:142-146` | 后台刷新失败时只看到卡片“状态待确认” | 有意（静默刷新不打扰）；不做 |
| 关注很多时（几百个）一轮全部刷新要一两分钟，期间新的“全部”请求被合并、“当前平台”请求排队 | `favorite_controller.dart:223-243` | 再点“关注”可能要等前一轮 | 照 3.x；性能问题出现时开 R 组任务 |
| I04.1 记录和代码不符：`favorite_cards.dart`、`room_menu.dart` 已挪到 `shared/rooms/room_cards.dart`、`room_menu.dart`；“去掉分页”已被 A09.3 改回；“平台栏右侧刷新按钮”已没有；“留给后续”的首帧后核验（`startup.dart:84`）和直播间“看其他”刷新关注（`app.dart:86-93`）都已做 | [I04.1 记录](I04.1-关注/record.md) | 只是记录过时 | I04.1 README 已注明 |
| I04.1 登记“完成”，记录写“本次没装机”；S02.2、S02.3 看过关注冷启动、核验、下拉 | [S02.3 记录](../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md) | 定时刷新、回到前台刷新、并发上限的效果没有真机记录 | 建议并入 S02.6 第 3 阶段（写进本单元报告） |

## 相关决定和规范

- D-009（下拉刷新回弹）、D-017（测试不访问真实平台、用固定的“现在”）、D-018（`autoRefreshFavorite` 等设置键照 3.x）、D-021（直播间里取消关注用贴着按钮的小菜单；首页长按卡片仍是居中确认框）、D-022（切换直播间面板默认小卡片网格，关注从这里取）。
- [specs/UPGRADES.md](../../specs/UPGRADES.md)：统一原则“受限”（关注照常显示、卡片标出）、1-1、3-1、17-1、23-1、28-2、X-2、7-9、10-3、25-12、33-7（I04.1 做了关注页部分）。

## 测试和验证

- 自动：`cd apps/pure_live && flutter test test/features/favorite`（16 个）；关注的合并和身份迁移在 `packages/live_store`、`packages/live_core` 的测试里。缺的：定时刷新的计时器（只测了设置变化后重排）；“平台没有适配器”的冷却。
- 真机：[S02 真机清单](../../S-质量和验证/S02-真机验证/CHECKLIST.md)第 4 节（关注）；S02.3 走过冷启动核验和下拉刷新。

## 路线

本子分类没有未完成的任务。关注页的样子由 A09.3 管（已完成）；关注多时的刷新耗时如果有反馈，在 R 组开性能任务；新想法（例如按开播时间排序、开播提醒）写进 [V01](../../V-需求和反馈/V01-新功能提议/README.md)。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [I 浏览和发现](../README.md)。

- 代码：`features/favorite/`
- 进度：`████████████████████` 100%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| I04.1 | 关注 | 功能 | 完成 | 2026-10-01 | dc167d266 | [设计或说明](I04.1-关注/README.md)、[记录](I04.1-关注/record.md) |

<!-- docs:生成结束 -->
