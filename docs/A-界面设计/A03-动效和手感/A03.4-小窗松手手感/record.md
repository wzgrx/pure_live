# A03.4 记录

## 2026-10-14

- c1～c4 做完：`AppMotion.floatingSpring`（= `panelSpring`）；`floating_window.dart` 的 `_settle` 改成无界控制器当时钟，`_SlideSimulation` 两轴各一根 `ReleaseSpringSimulation`；`_dragEnd` 把 `details.velocity.pixelsPerSecond` 传给 `_slide`；点收起的小窗回到边上速度为 0。
- 新测试一开始用 2000 px/s 甩，小窗直接收进了左边（终点规则本来如此），改成 1200 px/s、40 px 后通过。
- c5 审查结果写在 README。
- `flutter test test/features/live_play/live_play_mini_window_test.dart` 全部通过。
