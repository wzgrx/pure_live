# A09.12 浏览界面真机对照修正：记录

- 日期：2026-10-08
- 执行者：Claude（Opus 5.5）
- 分支和提交：本机工作区，代码提交 `348d7b106`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | `ScrollableTabBar` 加参数 `endFade`（常量 `tabStripEndFade` = 24）：后面还有标签时最右 24 渐隐，滚到头不渐隐。热门和分区页都用这个参数（分区页实际也没有渐隐，设计图 A09.4 v4-phone 有，一起补上） |
| c2 | 做了 | `ScrollJumpButtons` 在列表第一次滚动之前两个按钮都不出现，之后照原来的 400 阈值。回到一个已经滚过的列表（保留了位置）时照常显示 |
| c3 | 做了 | `showAdaptivePanel` 加 `openHeight`：底部面板先停在屏幕高度的这个比例，往上拉到全屏，往下拉到 40% 以下关闭。“全部平台”平台多（放不下设计高度）时停在 71%（顶边约 29%，和 A09.2 v4-phone-picker 一样）；平台少时照旧按内容高度。说明改成“点一个直接切过去；在“平台显示”里隐藏和排序”，去掉了平台数（加上平台数在 393 宽放不下一行） |
| c4 | 做了 | A09.7 的确认改动里没写这一条，按设计图：“全部”一直用四宫格图标（`AppIcons.allPlatforms`，原来定义了没用），选中时不换成勾；选中底色照共用芯片（`secondaryContainer`，和“包含未开播”一样），单个平台选中时仍是勾 |

## 根因

- 01：热门的 `ScrollableTabBar`（`popular_page.dart`）右边紧接 ⌄，`TabBar` 自己没有渐隐，被裁到的标签硬截断。
- 02：`ScrollJumpButtons` 在 `initState` 的下一帧就按位置算一次（`jump_buttons.dart` 原 `:43`），列表下面还有超过 400 就显示“回到底部”；3.x 只在滚动监听里更新（`base_page_view_extension.dart` 的 `showBackToBottom` 初值 false）。
- 03：`showAdaptivePanel` 的底部面板是按内容高、最高 85%（`adaptive_panel.dart` 原 `:36`），35 个平台的内容超过 85%，于是一打开就在 15% 处；没有停靠档位。
- 04：`AppChip` 选中时把 `leading` 换成勾，“全部”原来没有 `leading`，所以选中时只有勾。

## 改了哪些文件

- `packages/live_ui/lib/src/widgets/scrollable_tab_bar.dart`（`endFade`、`ScrollableTabBarState.fadesEnd`）
- `packages/live_ui/lib/src/widgets/jump_buttons.dart`
- `packages/live_ui/lib/src/widgets/adaptive_panel.dart`（`openHeight`）
- `apps/pure_live/lib/features/popular/popular_page.dart`（渐隐、面板高度、`PlatformPicker.heightOf`、`platformPickerOpenHeight`）
- `apps/pure_live/lib/features/areas/areas_page.dart`（渐隐）
- `apps/pure_live/lib/features/search/search_widgets.dart`（“全部”芯片）
- 翻译：`popular_all_platforms_hint` 的 zh、en 改短（不再用 `{count}`）

## 新设置、翻译键、门禁基线

- 没有新设置和新翻译键。

## 测试

- 新增 3 个、改了 3 个：`live_ui` `components_test.dart`（没滚动时两个都不显示、滚动后显示；回到已滚动的列表立即显示）；`popular_test.dart`（393 宽 24 个平台：标签条渐隐、滚到头不渐隐、没滚动没有悬浮按钮、滚动后有；全部平台面板顶边在 29%、说明一行、往上拉到顶、点平台关闭；2 个平台时按内容高）；`search_test.dart`（“全部”是四宫格、不加勾）。
- 通过：`live_ui` 全部 185 个；`apps/pure_live` 的 popular、search、areas、favorite、history、i18n 测试。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. 首页 → 热门（第一个平台） | 第三个标签右边渐隐，不再硬截成“虎.”；右下没有悬浮按钮 |
| 2. 往下滑一屏 | 出现回到顶部 / 回到底部 |
| 3. 点 ⌄ | 面板顶边约在屏幕 29% 处，说明一行；按住平台网格往上拉能到全屏，往下拉能关闭 |
| 4. 分区页 | 平台标签最后一个也渐隐 |
| 5. 搜索页 | “全部”芯片是四宫格图标，选中不加勾 |
| 6. 关注、观看记录、分区房间 | 刚打开没有悬浮按钮，滚动后才有 |

## K90 复查（2026-10-08，master 521163209）

- 热门首屏：第三个标签“虎”渐隐，没有生硬截断 ✓；没滚动时右下没有悬浮按钮，滑一屏后“回到顶部 / 回到底部”出现 ✓。
- ⌄ 全部平台面板：顶边约在 29%，说明一行 ✓（“SHOWROOM”被截断，A01.4 跟进里改成略微缩小）。
