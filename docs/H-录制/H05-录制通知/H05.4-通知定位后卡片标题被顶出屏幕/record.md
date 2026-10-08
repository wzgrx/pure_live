# H05.4 点录制通知定位到任务后，卡片标题被顶出屏幕：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区（从 master `bbd52a2a3` 开始）
- 设计或说明：[README.md](README.md)

## 根因

- `apps/pure_live/lib/features/recorder/recorder_page.dart:182-186`（改前）`_reveal` 用 `Scrollable.ensureVisible(alignment: 0.2)`：目标位置 = 卡片顶边 − (视口高 − 卡片高) × 0.2，**不管卡片是不是已经整张在屏幕里都会滚**。
  - 视口比卡片矮时（视口高 − 卡片高为负），目标位置大于卡片顶边，第一张卡片也会往下滚，标题行跑到筛选栏下面。组件测试复现：窗口 393×320（列表视口 197，录制中的卡片 271 高）时滚了 26.8，窗口恢复成 393×852 后位置不变，标题行仍被盖住。
  - K90 上第一张卡片本该不滚，最可能是打开那一刻窗口还矮：从直播间按 Home 时开着“离开时自动小窗”（`autoPipOnLeave`）会进系统小窗，点通知后应用从小窗回到全屏，录制中心在小窗尺寸下先排了一次版。没有在真机上确认是不是这个时机，见“真机”第 1 步。
  - 同一个原因的另一面：第一屏里已经整张可见的第二张卡片也会被滚 118（393×852），卡片停在视口 20% 处。

## 做了什么

- `_reveal` 不再用 `ensureVisible`，改用新的 `_revealOffset`（`recorder_page.dart`）：用 `RenderAbstractViewport.getOffsetToReveal` 求“卡片顶边贴视口顶”和“卡片底边贴视口底”两个位置；现在的位置在两者之间（整张可见）就不滚；否则卡片顶边停在列表顶上留白（手机 12，宽屏 16，和第一张卡片上面的空一样）的位置，夹在可滚范围里。卡片比视口高时总是先露出标题行。
- 滚动照旧：动画 300 ms（系统关了动画时直接跳），滚完再闪高亮。
- 列表的上留白改由页面传进 `_TaskGrid`（`top`），定位和列表用同一个值。

## 测试

- `apps/pure_live/test/features/recorder/recorder_centre_test.dart` 的“opened at a task”组加 4 个：
  - `H05.4: the first card is already in view: the list stays at the top`（录制中的卡片在第一张；改前也通过，作守卫）；
  - `H05.4: a window shorter than the card when it opens keeps the head in view once it grows`（改前滚了 26.8，失败）；
  - `H05.4: a card whole on the first screen is highlighted without scrolling`（第二张，改前滚了 118，失败）；
  - `H05.4: a card further down comes to the top, the list's top gap above it`（第七张，改前顶边在 228.8 而不是 135，失败）。
- 原有的定位用例（第十二张、宽屏、后到的任务、找不到的任务）照旧通过。

## 真机

待 K90（README“验证”）：

1. 开着“离开时自动小窗”，在直播间开始录一个任务，按 Home（进小窗），下拉通知点“正在录制”：录制中心里这张卡片整张可见，标题行在筛选栏下面，描边闪一下。
2. 关掉“离开时自动小窗”再做一遍：同上。
3. 录制中心里留十几条任务，点“录制已停止”提醒定位到一条不在第一屏的失败任务：卡片顶边离筛选栏留一点空（和第一张卡片上面的空一样），不是停在屏幕中间。
