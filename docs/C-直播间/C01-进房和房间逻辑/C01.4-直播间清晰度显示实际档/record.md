# C01.4 直播间清晰度显示平台实际给的档：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（接在 E05.3 后面，从 master `820129343` 开始），提交 `[C01.4]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `live_core` 新函数 `resolveServedPlayQuality({platform, qualities, requested, resolution})`（`live_site.dart`，就是 H01.3 `servedQuality` 的规则原样搬过来）；`RecordStreamResolver.servedQuality` 只转调它，行为不变 |
| c2 | 做了 | 直播间 `_openQuality`、多画面 `_openQuality` 改用新函数；列表外的实际档照旧替换请求的那一项，按钮和菜单显示“超清” |
| c3 | 做了 | 直播间：实际档和请求不同（按 `selectionId` 比）就提示；进房（不是用户选的）每个直播间只提示一次（`_servedToastShown`），刷新、重新加载不再提示；用户自己选档照旧每次提示。提示文字用实际档的名字（原来用列表里那一项的名字，列表外时会错） |
| 多画面提示 | 偏差 | 多画面只在用户自己选档时提示（和原来一样），进房不提示：四个格子同时进房会连弹四次。命名规则和直播间相同 |
| 验收 1～5 | 做了 | 见“测试”；验收 4 录制的 `applied_quality_test.dart` 照旧通过 |

## 根因

- `packages/live_core/lib/src/live_site.dart:223-239`（改之前）的 `resolveAppliedPlayQuality` 遇到“平台确认的编号不在列表里”时退回请求的那一项并标未确认；直播间 `apps/pure_live/lib/features/live_play/logic/room_controller.dart:512`（改之前）、多画面 `multiview_controller.dart:595` 直接用它，所以显示“原画?”。录制在 H01.3 时另外加了一层 `servedQuality`（`packages/live_record/lib/src/resolver.dart:359-375`），按平台编号命名成“超清”，两边规则分叉。
- 提示：`room_controller.dart:515`（改之前）只在 `userChoice && playing != index` 时提示；进房不提示，列表外的档 `playing == index` 也不提示。

## 改了哪些文件

- `packages/live_core/lib/src/live_site.dart`：加 `resolveServedPlayQuality`。
- `packages/live_record/lib/src/resolver.dart`：`servedQuality` 转调新函数。
- `apps/pure_live/lib/features/live_play/logic/room_controller.dart`：`_openQuality` 用新函数；进房提示一次。
- `apps/pure_live/lib/features/multiview/logic/multiview_controller.dart`：`_openQuality` 用新函数；提示条件改成按 `selectionId` 比。
- 电视直播间用的也是 `LiveRoomController`，不用另改。
- 测试：`packages/live_core/test/live_site_test.dart`、`apps/pure_live/test/features/live_play/live_play_controller_test.dart`、`apps/pure_live/test/features/multiview/multiview_controller_test.dart`。

## 新设置、翻译键、门禁基线

- 无（用已有的 `quality_limited_to`）。

## 测试

- 新增 7 个、改了 1 个：
  - `live_core`：`C01.4: the served quality` 4 个（在列表里、列表外且确认、没确认（含编号为空）、`appliedQuality`）。改之前编译失败（没有这个函数）。
  - 应用：“a Bilibili guest in a room listing 原画 only sees the 超清 it is served, told once”（哔哩哔哩游客样本 `S06-live`、`S07-guest-qn0` 改写成只列 10000、`S07-guest-qn10000`、`S09-guest` 等；进房显示“超清”、确认、提示一次；`load()` 再进一次不再提示）——改之前是“原画?”，失败。“a quality the platform did not confirm keeps the request, unconfirmed, without a toast”（改之前也通过，保护验收 2）。多画面“C01.4: a cell names a served quality outside the list…”——改之前是“原画?”，失败。
  - 改：“a quality the platform downgrades shows the quality really played”：进房现在提示一次，手动选档再提示一次。
- `packages/live_core` 3649 个、`packages/live_record` 61 个、`apps/pure_live` 915 个全部通过；format、`dart analyze --fatal-infos` 无问题。

## 真机上要看的

- brief“真机验证”1～4：游客进只有“原画”的哔哩哔哩直播间，按钮“超清”（不带“?”）、提示一次；录制面板也是“超清”；断网 10 秒恢复后不再提示；登录后能拿原画时显示“原画”、不提示。
- 顺带看电视直播间的清晰度菜单也是“超清”。
- 注意：进房提示是新加的，其他平台请求的档被降档时（平台确认了别的档）进房也会提示一次，这是验收 3 的本意；真机上如果觉得打扰再议。

## 可能冲突

- E06.2（暂停）半成品在工作区 `agent-af6f5e80c4e19804f`，也改 `room_controller.dart` 的 `_refreshPlan` 附近；本任务没有动 `_refreshPlan`，只改 `_openQuality`。这次没能查看那个工作区的改动（工作区隔离），合并时要看一眼。
