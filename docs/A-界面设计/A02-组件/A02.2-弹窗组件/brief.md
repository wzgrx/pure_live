# A02.2 弹窗组件开发：任务书

> 本任务的开发已经合并（合并提交 `276925183`，2026-10-02），现在是“待真机”：剩下的是维护者按 [verify.md](verify.md) 在 K90 上看，以及看出问题时的修补。下面保留开工时的全部要求（原任务单，旧编号 U02），按任务书模板 v2 重排，“现状”一节是合并后读代码写的。真机发现问题时，照本任务书的范围和规则修，或开新任务（标题写“接 A02.2”）。

## 背景

- 来源：界面重构计划书 [specs/UI.md](../../../specs/UI.md) 第 7 节（四种弹窗）；设计 [README.md](README.md)（第 1 版，“需要你选的”D1～D4 由维护者按 D-003 选 A）；全面审查 B-7（[V03.1](../../../V-需求和反馈/V03-审查和调研/V03.1-全面审查/README.md)：直播间右上菜单是原生 `PopupMenuButton`、画面比例从菜单进是居中对话框、方向 / 定时 / 音量 / 直链 / 投屏都是居中对话框、切换直播间和长按弹幕是底部表单、横屏全屏时对话框压在画面中间——“落实 A02.2：小菜单、对话框、面板各统一成一个组件；直播间里的‘设置’和‘选择’一律用面板或贴着按钮的小菜单”）。
- 现象（开工前）：对话框标题 16 / 18 / 20 三种、正文 13 号、按钮“确认”“确定”混用、宽度跟内容走（280～480）、横屏时标题跟着内容滚走；提示条两套（`AppNavigator.toast` 写死的 SnackBar 和各页自己的 `showSnackBar`），带“撤销”的提示条一直不消失；面板标题栏 `live_ui` 和直播间各画一份。
- 规模：大；分组：组件；依赖：A02.3 之后；能否和别的任务同时做：组件组，依次做。
- 出设计：不用（照已确认的设计和本任务书）。
- 已经做过的：A02.3（小菜单，`66492c34c`）；A07.6（直播间面板 `RoomSidePanel` 和清晰度、线路菜单的样子）。

## 目标和验收

1. 照设计实现对话框：正文和按钮 14 号、动作按钮写明动作、危险动作红色、宽度屏宽减 32 最宽 400、选项点一项就关、横屏标题不跟着滚走。
2. 面板：一个组件三个位置（画面下方、右侧、底部）。
3. 提示条：放在底部导航栏上方、可带一个操作和 ✕、深色主题反色、3 秒，带操作 4 秒。
4. 全应用的对话框、底部表单、提示条改用统一组件；直播间里的“设置”和“选择”一律用面板或贴着按钮的小菜单（A02.3 已做小菜单）。验收：全应用只有一种对话框、一种面板、一种提示条。
5. 测试：每种弹窗在三种布局里的位置、键盘操作、深浅主题。
6. 真机：首页长按卡片、设置里的选择项、录制中心的删除确认，样子一致（[verify.md](verify.md)）。

## 现状（读代码得出，写文件:行）

合并后的代码（2026-10-03）：

- 对话框 `packages/live_ui/lib/src/widgets/app_dialog.dart`：`AppDialog`（`:42`）、宽度常量（`:18-24`）、`DialogActionButton`（`:214`）、`DialogCancelButton`（`:281`）、`DialogOptionRow`（`:309`）、`dialogFieldDecoration`（`:414`）、`showAppDialog`（`:450`）、`showAppConfirmDialog`（`:466`）、`showAppMessageDialog`（`:508`）、`showAppOptionDialog`（`:585`）、`showAppInputDialog`（`:638`）；`dialog_buttons_theme.dart:6`、`dialog_keys.dart:12`、`card_dialog.dart:38`。
- 面板 `adaptive_panel.dart`：`showAdaptivePanel`（`:23`）、`PanelHeader`（`:79`）、`PanelFrame`（`:155`）；直播间 `apps/pure_live/lib/shared/panels/side_panel.dart:24`（`RoomSidePanel`）。
- 提示条 `app_toast.dart`：`AppToast`（`:23`）、`showAppToast`（`:123`）、`AppToaster`（`:145`）；主题 `live_theme.dart:370-378`；接线 `apps/pure_live/lib/app/app.dart:70,78-79`、`routes/app_navigator.dart:33,38`。
- 用在页面：`AppDialog` 20 个文件、`showAppConfirmDialog` 16 个文件、`DialogActionButton` 19 个文件、`AppToast` 8 个文件、`showAdaptivePanel` 4 个文件、`RoomSidePanel` 10 个文件。应用里（除电视）已经没有 `AlertDialog(`、`SimpleDialog(`、`showModalBottomSheet`；剩下的 `Dialog(` 是版本的三个（`features/version/release_history_view.dart:256`、`update_prompt.dart:202`、`update_download.dart:606`，A06.3 版式）和桌面关闭窗口（`app/desktop/close_dialog.dart:224`，A16.1）；原生 `SnackBar` 只剩启动失败页（`app/launch_failure.dart:119`）；`showGeneralDialog` 只剩本地发送星标行（`features/live_play/local_interaction/local_composer.dart:344`）。
- 直播间：A07.12、A07.13 已把记录末尾表里的弹窗换成面板和小菜单。

## 3.x 基线

- `lib/plugins/utils.dart`：`showAlertDialog`（`:110-131`）→ `_SharedAlertDialog`（`:395-445`）、`showMessageDialog`（`:137-147`，没有调用者）、`showRightDialog`（`:149-201`，没有调用者）、`showEditTextDialog`（`:212-222`）→ `_EditTextDialog`（`:507-652`）、`showOptionDialog`（`:224-226`）→ `_OptionDialog`（`:447-505`）；各页 `showDialog` 76 处（40 个文件）。
- `lib/common/style/theme.dart:171-183`：底部面板（表面容器色、顶角 24、把手）、对话框（表面容器高色、圆角 24、标题 20/600、正文 13）。
- `lib/common/utils/toast_util.dart`（SmartDialog，225 处）：3 秒、同一句 3 秒内不重复（`:13-18`）、深色灰底、离底 50。
- 要保留：四种弹法和用在哪（规范第 3 节第 8 条“弹法照 3.x”）；对话框主题（表面容器高色、圆角 24、标题 20/600）；取消在左、动作在右；点外面、返回键、Esc 关；保存中不能关；提示条 3 秒、同一句不重复（设计 c1）；[specs/UI.md](../../../specs/UI.md) 附录 A 第 7 条（返回链）、第 14 条（卡片长按 = 操作菜单）。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节、第 8 节、第 14 节）。
2. `docs/specs/ENGINEERING.md`；`docs/specs/UI.md` 第 3、7、8 节。
3. 本文件夹的 `README.md`（已确认，按 A）、[record.md](record.md)；[A02 子分类页](../README.md)；审查报告 B-7。

## 范围

- 可以改：`packages/live_ui`；各功能目录（只替换成统一组件）；`docs/TASKS.md` 当时的跨任务条目（现在 `docs/TASKS.md` 是生成的，不再手改）。当时按协调人的限制，`features/live_play/`、`features/multiview/` 没动，直播间里的弹窗由 A07.13、A07.12 用这里的组件替换。
- 不能改：其他组的界面和逻辑；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；小菜单（A02.3 已做）。

## 方案和阶段

当时按一个大阶段做完（`live_ui` 组件 → 应用改用 → 测试）。真机修补时按下表定位：

| 部分 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 对话框 | c1～c9、c14：一个框子、字号、按钮规则、宽度、只滚内容区、输入、选项 | `app_dialog.dart`、`dialog_buttons_theme.dart`、`dialog_keys.dart`、`card_dialog.dart`、`live_theme.dart`、各页对话框 | `popups_test.dart` 的 dialog 组通过 |
| 面板 | c10：一个组件三个位置 | `adaptive_panel.dart`、`shared/panels/side_panel.dart` | panel 组通过 |
| 提示条 | c11～c13 | `app_toast.dart`、`live_theme.dart`、`app/app.dart`、`routes/app_navigator.dart` | toast 组通过 |
| 替换 | c2（任务单）：全应用改用 | `features/`（直播间、多画面除外）、`shared/` | 应用里没有自己写的 `AlertDialog`、`showModalBottomSheet`、`SnackBar` |

## 测试

- 已有：`packages/live_ui/test/popups_test.dart`（对话框在 393×852、852×393、1280×800 的宽度和居中、字号、按钮顺序、键盘、危险确认焦点、横屏只滚内容区、输入、消息、大字体竖排、深浅主题；面板位置和标题栏；提示条位置、时长、操作、`persistent`、反色、不重复）；`apps/pure_live` 15 个测试文件改了查找。
- 真机修补时：先写能复现的 widget 测试（改之前失败），竖屏、横屏、宽屏各一个；定时器至少 1 秒（提示条的 3 秒、4 秒用 `tester.pump(Duration(seconds: …))`）；不访问真实平台。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. 首页关注页长按一张房间卡片，点“已关注” | 居中对话框，左右留 16，按钮在右下；“取消关注？”红色“取消关注”在右；确认后导航栏上方“已取消关注 xx · 撤销”，4 秒消失 |
| 2. 设置 → 视频 → 首选清晰度 | 标题 20 号、当前项蓝色加勾，点一项立即关闭 |
| 3. 录制中心任务卡片“⋮ → 删除任务” | 红色“删除”在右，和第 1 步的对话框样子一致 |

完整步骤见 [verify.md](verify.md)（9 条）。

## 风险和注意

- `scope.dart`、`live_ui.dart`、`live_theme.dart` 多任务常改（合并 A03.1 时就冲突过一次）。
- `shared/panels/side_panel.dart` 也被 A03.2（下拉手感）、A07.12、A07.13 改过；改标题栏时注意 `AnimatedBuilder` 和 `onVerticalDragStart`。
- 底部面板主题（表面色、圆角 16）全应用生效，直播间里还在用 Material 底部面板的地方会跟着变。
- Flutter 3.47 带 `action` 的 SnackBar 默认 `persist`：自己建 SnackBar 时要显式给 `duration` 和 `persist`，否则“撤销”不消失；开着读屏时带操作的不自动消失是 Flutter 的规则，不要改。

## 环境和提交

- `source ~/tools/purelive-env.sh`（本机）或按 `toolchain.env` 装 Flutter；根目录先 `bash tools/ffmpeg_kit/fetch.sh`，再 `flutter pub get`。
- 分支 `ai/A02.2` 或本机工作区；提交信息以 `[A02.2]` 开头（英文）；不推 master。
- 提交前：改过的包跑 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；`apps/pure_live` 跑全部 `flutter test`；`python3 tools/gate/check_ui_structure.py`；`python3 tools/docs/docs.py --check`。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 末尾写“停在哪”、更新登记表的 `done`、`next`、`branch`。

## 报告（中文，简洁）

每条做到没有；根因；测试数量；改了哪些文件；新设置和翻译键；要在真机上看的；需要维护者决定的；可能冲突的文件；还没换的弹窗（文件:行）。
