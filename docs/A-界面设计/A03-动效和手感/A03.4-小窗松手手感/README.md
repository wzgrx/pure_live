# A03.4 小窗松手手感：两轴弹簧带上手指速度，滑动中能接住

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：性能（手感）
- 来源：用户 2026-10-14：“优化动画，流畅度，物理手感”
- 相关：小窗本身见 [A07.24](../../A07-直播间界面/A07.24-小窗重构和增强/README.md)；弹簧和松手模拟见 [A03.2](../A03.2-翻页和面板/README.md)
- 任务书：[brief.md](brief.md)；记录：[record.md](record.md)；真机：[verify.md](verify.md)

## 目标

应用内小窗拖动松手后，和面板、换台一样顺着手指的速度走，不从 0 速重新起步；滑动途中手指按上去能接住，从它当时的位置继续拖。

## 改之前和现在

| 方面 | 改之前（A07.24） | 现在 |
|---|---|---|
| 松手后的滑动 | 260 毫秒 easeOutCubic，从 0 速起步，手指的速度只用来算终点 | 横、竖两根弹簧（`AppMotion.floatingSpring` = 面板弹簧 1/500/1，约 0.3 秒），各带手指在这一轴上的速度，到目标就停、不越过（`ReleaseSpringSimulation`）；从屏幕上正在显示的那一帧开始计时（`animateRelease`） |
| 终点 | `inAppMiniSettle`：按速度 × 0.18 秒推出去，再贴近的一边或收进边缘 | 不变 |
| 途中接住 | 拖动开始时停下动画，从当时的位置跟手 | 不变（测试补上） |
| 系统“移除动画” | 直接到位 | 不变 |

## 代码

- `packages/live_ui/lib/src/theme/motion.dart`：`AppMotion.floatingSpring`。
- `apps/pure_live/lib/features/live_play/mini/floating_window.dart`：`_settle` 改成 `AnimationController.unbounded`，只当时钟；`_SlideSimulation`（两轴各一根 `ReleaseSpringSimulation`，都停了才算停）；`_slide(..., velocity)`。
- 测试：`apps/pure_live/test/features/live_play/live_play_mini_window_test.dart` 的 “let go, it springs on at the finger's speed; caught on the way, it stays under the finger”。

## 审查其他拖动（2026-10-14）

标签翻页、侧面板、三档面板、详情面板、竖屏换台、下拉刷新已经是带松手速度的弹簧（A03.1～A03.3），小窗是最后一个用固定时长曲线的拖动；亮度、音量手势没有松手动画；竖屏全屏上滑回面板只判断阈值。没有别的要改。
