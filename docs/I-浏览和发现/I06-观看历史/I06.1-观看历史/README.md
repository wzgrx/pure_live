# I06.1 观看历史

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：功能（页面重构）
- 来源：模块重构计划的页面部分（D-001）；3.x 的 `lib/modules/history/history_page.dart`（407 行）、`lib/common/services/settings/history_controller.dart`（236 行，存储部分 J02.1 已做成 `HistoryStore`）、`common/widgets/room_card.dart` 的点击和长按菜单
- 旧编号：M13.6、T07g.1
- 相关：J02.1（`HistoryStore`、`historyLimit`）；I01.2（卡片和菜单挪到 `shared/rooms/`）；C01（进房时记录历史）；之后的 A09.9（观看记录界面）；提交 `070024e43`；记录 [record.md](record.md)

## 目标

在 4.x 里做出 3.x 的观看历史页：上限、删除、清空、下拉刷新、保留数量对话框、长按菜单；修掉 3.x 的五个问题（没点“应用”的数字被丢掉、刷新失败仍显示旧的“直播中”、鼠标拉不出刷新、刷新中离开页面结果全丢、每条都取完整详情太重）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11`） | 当时做成 | 现在（文件:行） |
|---|---|---|---|
| 保留数量框 | `history_page.dart:295-299`：`_save` 只存 `draftLimit`，输入框里的数字没点“应用”就丢 | 确认时先采用输入的数字；“应用”改成输入框里的勾 | 采用规则同（`history_limit_dialog.dart:80-86`）；“应用”按 A09.9 c1 恢复 3.x 的整宽按钮 |
| 刷新失败 | `:51-54` 失败返回原房间，旧“直播中”一直显示 | `pendingAfterError()`，卡片“状态未知” | `history_refresh.dart:73-77` |
| 鼠标刷新 | 拉不出下拉刷新 | 顶栏刷新按钮 | 同（A09.9 c4） |
| 刷新中离开页面 | `:58` 保存前就 return，全丢 | 不再发新请求，已取到的照样存 | `history_page.dart:96-105` |
| 请求 | 每条取完整详情 | 有轻量刷新接口的平台用它 | `history_refresh.dart:13-20` |
| 分组、筛选、结果提示 | 没有 | 按日期分组、筛选、“已刷新 N 个” | 同（A09.9 c3～c5） |
| 卡片和菜单 | `room_card.dart` | 自己的 `history_cards.dart`、`history_room_menu.dart` | 都没了：卡片是 A09.1 的 `LiveRoomCard`，菜单是共用的卡片对话框加“从历史删除”（`history_page.dart:200-217`） |
| 标题 | “历史记录 (条数/上限)” | 同 | “观看记录”，第二行“18 / 50 条”（A09.9 c2） |

## 结果

- 做了什么（详见 [record.md](record.md)“做法”）：页面、`history_refresh.dart`（并发设置、12 秒、轻量刷新、失败标未知、离开后不发新请求）、`history_sections.dart`（四个日期分组、筛选、观看时间文字）、保留数量对话框；存储语义沿用 J02.1（新的在前、重看移到最前、截断、只删当时显示的、刷新合并不改顺序）。
- 3.x 功能逐项对照（record.md 12 行）：分享和标签当时没有（后来 I01.2 统一菜单补上），“没有更多”的底部去掉（历史一次全部显示）。
- 修了 3.x 问题 5 条（record.md“v3 问题及处理”）；另外平台回了另一个身份的房间时算失败、不替换（3.x 会替换）。
- 界面改进 10 条（之后 A09.9 c1～c8 定稿）。
- 已批准的升级：统一原则“卡片标出受限类型”、28-2、统一原则“占位信息不覆盖存下的值”历史页完成。
- 提交 `070024e43`（2026-10-01）。现在 `features/history/` 4 个文件：`history_page.dart` 434、`history_limit_dialog.dart` 194、`history_refresh.dart` 86、`history_sections.dart` 93。
- 测试：当时 9 个（`test/pages/history/history_page_test.dart`）。

## 验证

- 自动测试：现在 `apps/pure_live/test/features/history/history_page_test.dart` 17 个（之后 A09.9、P02、F.5a 加的）；“没点‘应用’直接确认也采用”的用例是 `the limit dialog warns about removed entries and trims the history`（`:302`）。
- 真机：record.md 没有 K90 结果；S02.3（[记录](../../../S-质量和验证/S02-真机验证/S02.3-K90验证主流程/record.md)）看过观看记录的列表和点进房。刷新、筛选、保留数量没有真机记录（见[子分类说明](../README.md)“已知问题”）。

## 留下的问题

- record.md“留给后续”现在的去向：卡片对话框的分享和标签 → I01.2、A09.1（完成）；卡片适配共用 → I01.2（完成）；图片请求头 → I01.2（完成）；轮播、封禁标记 → 完成（`history_page_test.dart:271`）；进房时记录 → C01（`room_controller.dart:440`，完成）；“看其他”和多画面的历史来源 → A07.13、N01（完成）。
- 已下线平台的记录每次刷新都算失败（`history_refresh.dart:15`）：见子分类“已知问题”，没有任务。
