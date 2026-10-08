# A02.4 带“撤销”的提示条在开着无障碍服务时一直不消失：记录

- 日期：2026-10-08
- 执行者：Claude
- 分支和提交：本机工作区，提交 `[A02.4]`
- 任务书：[brief.md](brief.md)；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 开着无障碍服务、带操作的提示条显示 ✕ |
| c2 | 做了 | 这种提示条 30 秒后自动消失（`AppToast.accessibleActionDuration`） |
| c3 | 做了 | 只关“带操作、不是要用户回答的”提示条（撤销、重试，`AppToast.belongsToPage`）；普通的一句话（3 秒）照 3.x 跨页面显示完，要用户回答的（画中画被关“去设置”）不关；对话框、面板、菜单不是页面，打开关闭都不算换页面 |
| 验收 3 | 做了 | 没开无障碍服务时：普通 3 秒、带操作 4 秒，不变 |

## 根因

- `packages/live_ui/lib/src/widgets/app_toast.dart:63`（改前）：`persist: persistent || (accessible && actionLabel != null)`，`accessible` 是 `MediaQuery.accessibleNavigation`（`:137`）。任何无障碍服务（K90 的“选择朗读”）都会让它为真，带操作的提示条就 `persist`，`ScaffoldMessengerState.build` 的定时器到点后直接返回（Flutter `scaffold.dart:622`），而 ✕ 只在 `closable || persistent` 时出现，于是没有办法关。
- 提示条都在根 `ScaffoldMessenger` 上（`app.dart` 的 `scaffoldMessengerKey`），它在路由之上，换页面不会关它。
- 3.x 的 `ToastUtil` 不看无障碍设置（`git show v3.2.11:lib/common/utils/toast_util.dart`）。

## 改了哪些文件

- `packages/live_ui/lib/src/widgets/app_toast.dart`：`accessibleActionDuration`（30 秒）、`belongsToPage`；`snackBar()` 开着无障碍服务时带操作的用 30 秒、显示 ✕、不再 `persist`；`showAppToastOn` 记下每个 messenger 当前的提示条；新函数 `closePageAppToast`。
- `apps/pure_live/lib/app/page_toasts.dart`（新）：`closeToastsOnNewPage` 监听 GoRouter 的 `routerDelegate`，顶层页面的 `pageKey` 变了就调 `closePageAppToast`。
- `apps/pure_live/lib/app/app.dart`：挂上和取下监听（切换电视界面时换路由也重挂）。
- `docs/specs/UI.md`：提示条一行补上规则。

## 新设置、翻译键、门禁基线

- 无。

## 测试

- 新增 6 个：`packages/live_ui/test/popups_test.dart` 4 个（无障碍下有 ✕、29 秒还在 30 秒消失；✕ 能关；无操作的仍 3 秒无 ✕；`closePageAppToast` 只关带操作的）；`apps/pure_live/test/page_toasts_test.dart` 2 个（离开页面关撤销提示条；对话框开关不关、普通一句话跨页面留着）。
- 原有“带操作 4 秒”“要回答的一直留着”测试不变并通过。
- 全部通过：`packages/live_ui`、`apps/pure_live` 全量测试。

## 真机上要看的

| 步骤 | 期望 |
|---|---|
| 1. K90（开着选择朗读）直播间关注再取消关注 | 提示条有 ✕ |
| 2. 等 30 秒 | 消失 |
| 3. 再取消关注后马上返回首页 | 提示条跟着关掉 |
| 4. 关掉无障碍服务（或在别的手机上）取消关注 | 4 秒消失，没有 ✕（和以前一样） |

## K90 复查（2026-10-08，master fc9ee0ea4，开着“选择朗读”）

- 直播间取消关注：提示条“已取消关注 老实憨厚的笑笑”带“撤销”和 ✕ ✓；31 秒后已经消失 ✓。
- 再取消一次后马上返回首页：提示条跟着关掉 ✓。
- 没开无障碍时的 4 秒没在真机上看（手机的无障碍服务属于共用环境，没去关）。
