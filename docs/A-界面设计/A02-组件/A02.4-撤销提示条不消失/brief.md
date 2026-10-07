# A02.4 带“撤销”的提示条在开着无障碍服务时一直不消失：任务书

## 背景

- 来源：S02.5 清单 1A-14（2026-10-08 K90）：“已取消关注 X · 撤销”一分钟后还在，跟到首页。
- 原因：`packages/live_ui/lib/src/widgets/app_toast.dart:63` 在 `accessibleNavigation` 时让带操作的提示条一直留着，又没有 ✕。
- 为什么做：第二档；开着无障碍服务的手机（包括维护者的 K90）上每个撤销提示条都会挂住。

## 目标和验收

1. `accessibleNavigation` 为真、提示条带操作时：显示 ✕，30 秒后自动消失。
2. 换页面时上一页的提示条关掉。
3. 没开无障碍服务时行为不变（4 秒）。

## 现状（读代码得出，写文件:行）

- `app_toast.dart:22-65`（`AppToast`、`snackBar()`）、`:137`（`accessible: media.accessibleNavigation`）。

## 3.x 基线

- 3.x 用 `ToastUtil`，不受无障碍影响（`git show v3.2.11:lib/common/utils/toast_util.dart`，开工核对）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5、8、14 节）；`docs/specs/UI.md`（提示条）。
2. 本文件夹的 `README.md`；`docs/A-界面设计/A02-组件/A02.2-弹窗组件/README.md`。

## 范围

- 可以改：`packages/live_ui/lib/src/widgets/app_toast.dart`、显示提示条的入口（`AppNavigator.toast` 一类）、测试。
- 不能改：提示条的样子和普通时长。

## 方案和阶段

| 阶段 | 做什么 | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1～c3 | `app_toast.dart`、显示入口、测试 | 验收 1～3；门禁通过 |

## 测试

- `MediaQuery(data: MediaQueryData(accessibleNavigation: true))` 下显示带操作的提示条：找到 ✕；`pump(30 秒)` 后消失。
- 普通情况 4 秒消失的测试不变。

## 真机验证（K90）

| 步骤 | 期望 |
|---|---|
| 1. 直播间关注再取消关注 | 提示条有 ✕ |
| 2. 等 30 秒 | 消失 |
| 3. 再取消关注后马上返回首页 | 提示条跟着关掉 |

## 风险和注意

- Flutter 的 `SnackBar.persist` 是为读屏用户设计的；保留“留得更久”，只是加上 ✕ 和上限。

## 环境和提交

- `source ~/tools/purelive-env.sh`；分支 `ai/A02.4`；提交以 `[A02.4]` 开头；不推 master。

## 停下时

照 `docs/PROCESS.md` 第 5.2 节。

## 报告（中文，简洁）

每条验收；改了哪些文件；测试数量；要在真机上看的。
