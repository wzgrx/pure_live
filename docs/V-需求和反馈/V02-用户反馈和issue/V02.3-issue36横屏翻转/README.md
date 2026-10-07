# V02.3 issue #36：横屏全屏不随手机方向翻转

- 编号、状态、档位、规模：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 类型：验证（反馈的复现和归类）
- 来源：GitHub issue [#36](https://github.com/wzgrx/pure_live/issues/36)“功能缺失”（`957957qwer`，2026-10-02 03:14 UTC）：“手机端横屏全屏看直播时，没有自动旋转功能，就是那个横屏全屏时整个界面会随手机的方向而改变”
- 相关：决定 D-023（横屏全屏按传感器翻转，开着旋转锁也翻）；修复 [O05.2](../../../O-Android系统集成/O05-方向、刷新率、常亮/O05.2-横屏全屏随手机方向翻转/README.md)（`3c1aa45ee`）；回复 [V02.1](../V02.1-回复issue36和37/README.md)；真机 [O05.2 的 verify.md](../../../O-Android系统集成/O05-方向、刷新率、常亮/O05.2-横屏全屏随手机方向翻转/verify.md)、S02.5 的 1B-21、1B-22、1D-06

## 目标

用户横屏全屏看直播时把手机转 180°，画面要跟着翻过来（不倒着）。

## 3.x 和现状

| 方面 | 3.x（`v3.2.11:lib/`） | 修之前的 4.x | 修之后（O05.2） |
|---|---|---|---|
| 横屏全屏请求的方向 | `landscapeLeft` + `landscapeRight`（Flutter 的两个横向） | 照 3.x | `apps/pure_live/lib/platform/screen_orientation.dart:13` 的 `ScreenOrientation.landscape()`：先 Flutter 的两个横向，再用原生通道设 `SCREEN_ORIENTATION_SENSOR_LANDSCAPE` |
| 开着系统旋转锁时 | Android 把“两个横向”当成 `USER_LANDSCAPE`，旋转锁打开就固定在一边，转手机不翻 | 同 3.x（这就是 issue 说的） | 传感器横屏不受旋转锁限制，两边都翻（D-023：常见视频应用的做法） |
| 退出全屏 | 回竖屏 | 回竖屏 | 先竖屏，3 秒后放开（`apps/pure_live/lib/features/live_play/live_play_page.dart:598-604`） |

## 结果

- 复现：根因在 Flutter 把 `landscapeLeft + landscapeRight` 映射成 Android 的 `USER_LANDSCAPE`，用户开着旋转锁时不随传感器翻转；3.x 同样有这个问题。
- 去向：O05.2（`3c1aa45ee`，2026-10-02），随构建号 5001 发布；提交时只用 `dumpsys` 核对了请求的方向值（横着时 `SENSOR_LANDSCAPE`，离开时 `PORTRAIT`，3 秒后 `UNSPECIFIED`），没手动翻转手机。
- 回复：V02.1（“已经修复”，已关闭）。

## 验证

- 真机：O05.2 待真机，步骤在它的 `verify.md`；S02.5 阶段 1 的 1B-21（开着旋转锁转 180°）、1B-22（退出全屏 3 秒后放开）、1D-06（多画面横屏全屏）是同样的操作。

## 留下的问题

- O05.2 真机不通过时：在 issue #36 补一条说明（V02.1 的“留下的问题”），开返工任务。
