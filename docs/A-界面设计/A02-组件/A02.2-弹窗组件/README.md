# A02.2 弹窗组件：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：四种弹窗——小菜单、对话框（通用的确认、消息、输入、选项）、面板（画面下方 / 右侧 / 底部同一个组件）、提示条，加按钮名称提示。是一份组件目录：每个组件 v3 和新设计并排，按默认、悬停、键盘焦点、按下、禁用、进行中排，浅色和深色各一张；再放进真实页面（视频设置的三个对话框、首页和全屏的提示条）
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a022)（A02.2-01～06）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a022)；计划书 [specs/UI.md](../../../specs/UI.md) 第 7 节；通用组件在 [A02.1](../A02.1-通用组件/README.md)
- 评审页：claude.ai 私有页面（待发布）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（用 [A02.1/src](../A02.1-通用组件/src) 的 `parts.py` 和设置页）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；封面、画面是示意图片，键盘是示意；“无法打开画中画”的正文、“发现新版本 v3.2.12”是示意
- 弹法照 v3，不改（计划书第 3 节第 8 条）；小菜单和面板照 [A07.6](../../A07-直播间界面/A07.6-直播间弹窗/README.md) 已确认的样子

生成：`python3 docs/A-界面设计/A02-组件/A02.2-弹窗组件/src/gen.py && python3 tools/ui/mock/render.py docs/A-界面设计/A02-组件/A02.2-弹窗组件/src --annotate`；四张组件图（menu、dialog、panel、toast）再加 `--dark`。

## 界面清点表

| 编号 | 界面（组件） | 从哪出现 | 形态 | 状态 |
|---|---|---|---|---|
| — | 小菜单（`PopupMenuButton`，10 处） | 首页左上菜单、右上菜单、直播间清晰度和线路、右上角菜单、搜索排序、翻页栏每页条数、WebDAV、多画面格子 | 竖屏、横屏、宽屏 | 默认、当前项、悬停、焦点、按下；新：说明行、标题行、分组线、危险项、禁用项、上方 / 下方 |
| A02.2-01、05 | 确认（`showAlertDialog` → `_SharedAlertDialog`） | 退出登录、网页搜索认出房间号 | 同上 | 默认；按钮悬停、焦点、按下 |
| A02.2-02 | 消息（`showMessageDialog`） | 没有调用处 | — | — |
| A02.2-03、04、06 | 输入（`showEditTextDialog` → `_EditTextDialog`；各页自己写的输入框） | 通用的只有 GitHub 登录（v4 已去掉）；自己写的：屏蔽弹幕关键词、自动助眠播放时长、网络电视、标签等 | 同上（键盘弹出） | 空、输入中、出错、保存中 |
| — | 选项（`showOptionDialog` → `_OptionDialog`；各页自己写的单选框） | 请选择登陆方式；首选清晰度、移动网络清晰度等设置 | 竖屏、横屏 | 当前项；放不下时滚动 |
| — | 危险确认（各页自己写） | 重置小窗位置和大小、清空历史、删除 | 竖屏、宽屏 | — |
| — | 面板（`showModalBottomSheet` 9 处、`showRightDialog`、直播间右侧面板） | 长按弹幕、多画面、本地弹幕样式；全屏弹幕设置、清晰度（A07.6 已改） | 竖屏、横屏、宽屏 | 标题栏、滚动后、加载、空、关闭按钮的状态 |
| A02.2 提示条 | 提示条（`ToastUtil` 225 处；`SnackBar` 21 处） | 各种操作结果 | 竖屏（有底部导航）、全屏、宽屏 | 一句、两句、带操作、带 ✕；深色 |
| — | 按钮名称提示（`Tooltip`） | 悬停、长按图标按钮 | 电脑、手机 | — |

退出时的选择（`_ExitDecisionDialog`，`utils.dart:321-393`）在 `utils.dart` 里，但属于 A16.1（桌面窗口），这里只用它的按钮规则。

## v3 的样子（`v3.2.11`，`lib/` 下）

**对话框主题**（`common/style/theme.dart:177-183`）：表面容器高色、无阴影、圆角 24、标题 `titleLarge`（20 号）600、正文 `bodyMedium`（13 号）。按钮：`TextButton` 主题 `labelLarge`（13 号 500）圆角 8（:145-150）；`FilledButton` 默认圆角全圆、高 40；遮罩 54% 黑；点外面关（`barrierDismissible` 默认 true）。

**通用对话框**（`plugins/utils.dart`）
- `showAlertDialog`（:110-131）→ `_SharedAlertDialog`（:395-445）：`AlertDialog(scrollable: true)`，左右留 16、上下 20；标题可空；正文最宽 420、上下各 12；按钮：“取消”（`cancel` 为空字符串时显示“取消”）和“确认”两个 `TextButton`（最小 48×48），可追加按钮；返回 `bool`。调用处：退出登录（`account_controller.dart:54`，标题“退出登录”、正文“确定要退出哔哩哔哩账号吗？”）、网页搜索认出房间号（`web_search_controller.dart:515`）。
- `showMessageDialog`（:137-147）：同上只有“确认”；没有调用处。
- `showEditTextDialog`（:212-222）→ `_EditTextDialog`（:507-652）：`Dialog` 宽 468；标题 18/600；`TextField` 自动聚焦、4–5 行、等宽字体 13 号、表面容器最高 40% 底、圆角 14、聚焦主色 1.5 边；分隔线；按钮“取消”（文字）和“确认”（主色实心，圆角 10）；屏幕窄于 420 或字体放大 1.6 倍竖排占满（:547-548、:630-644）。调用处只有 GitHub 登录（`firebase_email_auth.dart:321`，“GitHub 登录”/“请粘贴授权链接”），v4 去掉了 Firebase。
- `showOptionDialog`（:224-226）→ `_OptionDialog`（:447-505）：标题可空；每项 `SimpleDialogOption`、最小高 48：单选圈 + 文字（`bodyLarge`）；点一项选中并关闭；没有按钮。调用处：“请选择登陆方式”（`routes/app_navigation.dart:99`）。
- `showRightDialog`（:149-201）：`SmartDialog` 从右滑入、宽 320、`cardColor`、左边圆角 4、返回箭头加标题、分隔线；没有调用处。

**各页自己写的同类对话框**（`showDialog` 76 处，40 个文件）
- 屏蔽弹幕关键词（`danmaku_message_actions.dart:107-124`）：`AlertDialog`，标题“屏蔽弹幕关键词”，输入框（主题：表面容器低底、圆角 12 的描边、聚焦主色 1.5）带字数“x/40”、提示“请输入关键词”，按钮“取消”（文字）“确认”（实心）。
- 首选清晰度（`video_settings_page.dart:444-492`）：标题 16 号粗体（`t16Bold`）；单选圈 + 文字（13 号）；“取消”是灰色 14 号（`t14Muted`）；宽度跟内容（`AlertDialog` 的 `IntrinsicWidth`，最窄 280）；选项：原画、蓝光8M、蓝光4M、超清、流畅。
- 自动助眠播放时长（Android，`video_settings_page.dart:577-714`）：标题 16 号粗体；说明 12 号；快捷时长 `ActionChip`（15 分钟、30 分钟、45 分钟、1 小时、90 分钟、2 小时、4 小时、8 小时、12 小时、1 天）；描边输入框“自定义播放时长”、后缀“分钟”、说明“请输入 1 分钟至 365 天之间的分钟数”；“取消”（灰色）“保存”（实心，保存中转圈、两个按钮和返回键都不可用）。
- 重置小窗位置和大小（Windows，`video_settings_page.dart:526-556`）：标题 16 号粗体，正文 14 号“确定要清除已保存的小窗位置和大小吗？”，“取消”（灰色）“重置”（红色实心）；完成后提示条“已清除保存的小窗位置和大小”。
- 其他：清空历史、删除一条是红色“清除 / 删除”（A09.9）；取消关注是“取消”“确认”两个文字按钮（A07.1、A09.1）；口令导入圆角 16（A06.3）。

**小菜单**（`PopupMenuButton`，E04.1 默认：表面容器色、圆角 4、阴影、每行 48、上下留 8）
- 首页左上（`menu_button.dart:14-84`）：圆角 8、按钮下方右移 12；每行图标 24 次要色 + 12 + 字 12 号（`labelMedium`）。
- 首页右上（`common_appbar_actions.dart:13-68`）：圆角 14、下移 10；图标 20 主色 + 字 14 号。
- 清晰度、线路（`resolution_selector.dart:24-80`）：表面容器最高色、圆角 8、下移 5；字 11 号（`labelSmall`），当前项只变主色（A07.6 已改）。
- 搜索排序（`search_page.dart:261-280`）、每页条数（`desktop_components.dart:238-262`）：默认圆角 4；排序靠 `initialValue`，每页条数当前项主色粗体。

**面板**
- 底部面板主题（`theme.dart:171-176`）：表面容器色、无阴影、顶角 24、把手；没有标题和关闭按钮。长按弹幕（`danmaku_message_actions.dart:10-56`）：第一行“用户名: 内容”，然后“复制”“屏蔽该用户的弹幕”“屏蔽弹幕关键词”（`ListTile`）。多画面 6 处、本地弹幕样式 1 处也是底部面板。
- 竖屏录制、弹幕设置是居中对话框；全屏弹幕设置、清晰度是右半边（A07.6 已改成一个面板）。

**提示条**
- `ToastUtil.show`（`common/utils/toast_util.dart`，225 处）：`SmartDialog.showToast`，配置显示 3 秒、间隔 0.1 秒（`common/global/initialized.dart:170-175`）；同一句 3 秒内不重复（:13-18）。样子是 flutter_smart_dialog 5.3.0 默认（`toast_widget.dart:13-21`、`view_utils.dart:79-87`）：黑底（深色主题 #606060）、圆角 20、内边距 25/10、白字、底部居中、离屏幕边 30 / 底 50、淡入 0.2 秒；不能带按钮。
- `SnackBar`（11 个文件 21 处，如 `web_dav_help.dart:295`、`version_page.dart:470`、`version_history.dart:449`、`download_apk_dialog.dart:486`）：主题没设，E04.1 默认贴底整条、反色底、13 号；Cookie 编辑器用浮起样式（`account_cookie_editor.dart:108-109`）。

**按钮名称提示**：Flutter 默认 `Tooltip`：浅色主题深灰 90%、深色主题白 90%，圆角 4；电脑 12 号、悬停出现；手机 14 号、长按出现。

**按宽度分支**：`_EditTextDialog` 窄于 420 竖排按钮；对话框宽度跟内容；其他没有。

**快捷键**：对话框和菜单的 Esc、返回键关闭是 Flutter 默认；没有“回车 = 主要按钮”。

**v4 现在**：直播间的面板（`features/live_play/layout/room_panel.dart` 的 `RoomSidePanel`，A07.6）、清晰度和线路菜单已按 A07.6 做；其余对话框和底部面板各页自己写（`showDialog`、`showModalBottomSheet` 共 51 个文件），提示条是浮起的 `SnackBar`、3 秒（`app/app.dart:70-76`），删除关注房间带“撤销”（`shared/rooms/room_menu.dart:278-283`）。`live_ui` 里还没有公共的对话框、菜单、提示条组件。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| Q1 | 小菜单四种样子（字号 11 / 12 / 13 / 14、圆角 4 / 8 / 14、图标灰色或主色） | `menu_button.dart:14-84`、`common_appbar_actions.dart:13-68`、`resolution_selector.dart:24-80`、`search_page.dart:261-280` |
| Q2 | 当前项各自表示（只变色、粗体、靠 initialValue），计划书要“主色 + 勾” | `resolution_selector.dart:75-80`、`desktop_components.dart:255-257` |
| Q3 | 菜单没有说明行、标题行、禁用项；键盘焦点只是底色 | Flutter 默认 `PopupMenuButton` |
| Q4 | 对话框正文和按钮 13 号，低于计划书弹窗最小 14 | `theme.dart:83`、`:181` |
| Q5 | 标题三种：20/600、16 号粗体、18/600 | `theme.dart:180`、`video_settings_page.dart:454`、`:533`、`utils.dart:590` |
| Q6 | 按钮各写各的：确认两个文字按钮；输入主色实心；重置红色实心；“取消”有主色、有灰色 14 号 | `utils.dart:414-427`、`danmaku_message_actions.dart:118-122`、`video_settings_page.dart:485-489`、`:540-555` |
| Q7 | 确认按钮只写“确认”，看不出会做什么 | `utils.dart:424`、`favorite_floating_button.dart` |
| Q8 | 宽度跟内容，同类对话框宽窄不一（280、300 多、468） | `utils.dart:429-443`、`:572` |
| Q9 | 通用输入框固定 4–5 行等宽字体；窄于 420（所有手机）按钮竖排 | `utils.dart:548`、`:593-598`、`:630-634` |
| Q10 | 选项用单选圈，不是“主色 + 勾” | `utils.dart:489`、`video_settings_page.dart:471` |
| Q11 | 横屏手机里 `scrollable` 对话框的标题跟着内容滚走 | `video_settings_page.dart:452`、`utils.dart:465` |
| Q12 | 面板三种弹法（底部面板、居中对话框、右半边，A07.6 已改）；底部面板没有标题和关闭按钮；`showRightDialog` 没用上 | `theme.dart:171-176`、`utils.dart:149-205` |
| Q13 | 提示条两套（ToastUtil 胶囊、SnackBar 整条）；深色主题 ToastUtil 是灰底 | `initialized.dart:171-174`、`toast_widget.dart:13-21` |
| Q14 | ToastUtil 离屏幕底 50，竖屏压在底部导航栏上，不看安全区 | `toast_widget.dart:14` |
| Q15 | ToastUtil 不能带操作：删除没有撤销，失败没有重试 | `toast_util.dart:11-33` |
| Q16 | `showMessageDialog`、`showRightDialog` 没用上；同类对话框 40 个文件各自写 | `utils.dart:137-205` |

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 四张组件对照图（浅色、深色）、视频设置的三个对话框（竖屏、横屏、宽屏）、提示条（竖屏、全屏）、引用 A07.6 / A09.2 的面板位置图、“用在哪”对照、四处选择 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：小菜单](page/02-对比-小菜单.jpg)
- [对比：对话框](page/03-对比-对话框.jpg)
- [对比：面板](page/04-对比-面板.jpg)
- [对比：提示条和按钮名称提示](page/05-对比-提示条和按钮名称提示.jpg)
- [放在页面里：对话框](page/06-放在页面里-对话框.jpg)
- [放在页面里：提示条](page/07-放在页面里-提示条.jpg)
- [面板放在页面里（已出的图）](page/08-面板放在页面里-已出的图.jpg)
- [用在哪（已出的设计）](page/09-用在哪-已出的设计.jpg)
- [v3 的问题](page/10-v3-的问题.jpg)
- [改了什么](page/11-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/12-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/13-各客户端.jpg)
- [需要你选的](page/14-需要你选的.jpg)
- [性能要点](page/15-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-menu.jpg](v3-menu.jpg)、[v4-menu.jpg](v4-menu.jpg)（及 `-dark`） | 小菜单：样子、当前项、说明和标题行、状态、位置 |
| [v3-dialog.jpg](v3-dialog.jpg)、[v4-dialog.jpg](v4-dialog.jpg)（及 `-dark`） | 对话框：确认、危险确认、消息、输入、输入出错、选项、带勾选、按钮的状态 |
| [v3-panel.jpg](v3-panel.jpg)、[v4-panel.jpg](v4-panel.jpg)（及 `-dark`） | 面板：位置示意、标题栏、底部带把手、滚动后、加载、✕ 的状态 |
| [v3-toast.jpg](v3-toast.jpg)、[v4-toast.jpg](v4-toast.jpg)（及 `-dark`） | 提示条、按钮名称提示 |
| [v3-option-phone.jpg](v3-option-phone.jpg)、[v4-option-phone.jpg](v4-option-phone.jpg)、[v4-option-phone-n.jpg](v4-option-phone-n.jpg) | 首选清晰度，竖屏 |
| [v3-option-land.jpg](v3-option-land.jpg)、[v4-option-land.jpg](v4-option-land.jpg) | 首选清晰度，横屏 852×393 |
| [v3-input-phone.jpg](v3-input-phone.jpg)、[v4-input-phone.jpg](v4-input-phone.jpg)、[v4-input-phone-n.jpg](v4-input-phone-n.jpg) | 自动助眠播放时长，键盘弹出 |
| [v3-confirm-wide.jpg](v3-confirm-wide.jpg)、[v4-confirm-wide.jpg](v4-confirm-wide.jpg)、[v4-confirm-wide-n.jpg](v4-confirm-wide-n.jpg) | 重置小窗位置和大小，Windows 1280×800 |
| [v3-toast-phone.jpg](v3-toast-phone.jpg)、[v4-toast-phone.jpg](v4-toast-phone.jpg)、[v4-toast-phone-n.jpg](v4-toast-phone-n.jpg) | 首页的提示条 |
| [v3-toast-fs.jpg](v3-toast-fs.jpg)、[v4-toast-fs.jpg](v4-toast-fs.jpg) | 全屏 852×393 的提示条 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 四种弹法和用在哪；对话框主题（表面容器高色、圆角 24、标题 20/600）；取消在左、动作在右；点外面、返回键、Esc 关；保存中不能关；提示条 3 秒、同一句不重复；按钮名称提示 | — |
| c2 | 修改 | 一个小菜单（A07.6 的样子）：表面容器最高色、圆角 8、行高 48、14 号、图标 24 次要色 | Q1 |
| c3 | 修改 | 当前项一律主色、600、右边勾（菜单和选项对话框） | Q2、Q10 |
| c4 | 增强 | 菜单行可带说明、第一行标题、分组线、危险项、禁用项；上下键、回车、Esc；焦点框 | Q3 |
| c5 | 修改 | 对话框正文和按钮 14 号，标题一律 20/600 | Q4、Q5 |
| c6 | 修改 | 按钮规则：取消文字按钮；动作实心写明动作；危险红色（D2）；回车 = 主要按钮，Esc = 取消 | Q6、Q7 |
| c7 | 修改 | 宽 = 屏宽减 32，最宽 400（长内容 560）；高最多屏高减 32，只滚内容区 | Q8、Q11 |
| c8 | 修改 | 输入默认单行、正文字体；说明、错误、字数在框下；只在字体放大 1.5 倍以上竖排按钮（D4） | Q9 |
| c9 | 修改 | 选项点一项就关；放不下时标题和“取消”不动 | Q10、Q11 |
| c10 | 保留 | 面板一个组件三个位置（A07.6 已确认）；没有画面的页面竖屏底部带把手、宽屏右侧 | Q12 |
| c11 | 修改 | 一种提示条：反色底（D1）、圆角 8、14 号、最多两行、左对齐（D3） | Q13 |
| c12 | 修改 | 提示条位置：底部导航栏上方 16；全屏画面中下部；宽屏底部居中最宽 560 | Q14 |
| c13 | 增强 | 提示条可带一个操作和 ✕；带操作 4 秒；要用户选的不自动消失 | Q15 |
| c14 | 去掉 | `showRightDialog` 不做；“消息”就是一个按钮的对话框；各页都用这一个对话框 | Q16 |

新加的文字：知道了；屏蔽（作按钮）；退出登录、重置、清除等动作名用 v3 已有的键（`logout`、`reset`、`clear`、`delete`）；撤销（v4 已有 `room_undo`）。

## 用在哪（已出的设计）

见对比页同名一节。要同步给其他任务的：

| 任务 | 要改的 |
|---|---|
| A09.5 | 取消关注分区的确认框写的是“照 v3”（按钮“确认”）；按 D2 和 A09.1 c12 一样写“取消关注” |
| A09.1、A09.4、A09.6 | 卡片长按：房间卡片是居中对话框（A09.1 A1），分区卡片新加的是小菜单（A09.4 X3）；同是“卡片长按”两种弹法，请一起定 |
| A07.2 | 本直播间画面方向对话框用这里的选项行（主色加勾）；“已进入竖屏全屏”是画面上的提示，不是提示条，照 v3 |
| A06.3 | 对话框宽度（560 / 440 / 400）在这里的规则内；“不再提醒这个版本”的勾选行照这里放 |
| A09.8 | 认出直播间的提示条是“要用户选的”那种（不自动消失，带“进入”和 ✕） |
| 计划书第 7 节 | 提示条写的“2 秒后自动消失”和 v3（3 秒）不一致，建议改成 3 秒、带操作 4 秒 |

## 按钮的作用和用法

| 图 | 编号 | 控件 | 怎么用 |
|---|---|---|---|
| [选项](v4-option-phone-n.jpg) | 1 | 当前项 | 主色加勾；点了直接关 |
| 选项 | 2 | 其他选项 | 点一项就选中并关闭；电脑上下键、回车 |
| 选项 | 3 | 取消 | 不改；点外面、返回键、Esc 一样 |
| [输入](v4-input-phone-n.jpg) | 1 | 快捷时长 | 点一个把数字填进输入框（照 v3） |
| 输入 | 2 | 输入框 | 直接输入；超出范围时框下变红写原因 |
| 输入 | 3 | 取消 | 不保存；保存中不可用 |
| 输入 | 4 | 保存 | 保存并关闭；保存中转圈；电脑回车 |
| [危险确认](v4-confirm-wide-n.jpg) | 1 | 取消 | 不做；Esc；电脑上默认焦点在这里 |
| 危险确认 | 2 | 重置 | 红色，写明动作 |
| [提示条](v4-toast-phone-n.jpg) | 1 | 撤销 | 4 秒内点了恢复 |
| — | — | 小菜单 | 选完就关；点外面、返回键、Esc 关；电脑上下键、回车 |
| — | — | 面板的 ✕ | 关面板；返回键、Esc；竖屏在画面下方时往下拖标题栏 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏对话框只滚内容区；全屏提示条在画面中下部；返回键先关弹窗 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 对话框最宽 400（长内容 560）；菜单悬停、上下键、回车、Esc；对话框回车 = 主要按钮、Esc = 取消，危险确认默认焦点在“取消”；面板在右侧；提示条底部居中最宽 560；悬停显示按钮名称 |
| 电视 | 同一组件的电视样式（A17.1）：焦点放大、字号大一级；对话框默认焦点在主要按钮（危险确认在“取消”）；菜单方向键；面板在右侧 |
| 苹果平台差异 | 不换系统样式；iPhone 底部面板避开主屏指示条、可下拉关；iPad 键盘和指针同宽屏；macOS 用 Cmd |

## 待选（A 是建议）

- D1 提示条在深色主题：A 跟主题反过来（浅底深字）；B 照 v3 一律深底（v3 深色是灰底）。
- D2 确认按钮的字：A 写明动作；B 照 v3 一律“确认”。
- D3 提示条形状：A 圆角 8 的条、左对齐；B 照 v3 居中胶囊。
- D4 输入对话框的输入框：A 默认单行；B 照 v3 4–5 行大框。

## 拿不准的地方

1. v3 默认 `PopupMenuButton` 用 `initialValue` 时当前项有没有底色，没在真机上看（同 A09.7 的拿不准）；图里没画底色。
2. v3 `AlertDialog` 的宽度按 `IntrinsicWidth` 推算（选项 280，确认 300 多），没有截图核对。
3. v3 Windows 标题栏在对话框遮罩外面（`DesktopManager.buildWithTitleBar` 包在导航器外），图里遮罩盖住了示意标题栏；以 A16.1 为准。
4. 全屏时 v3 提示条离底 50，按 A07.4 的 v3 下栏（56 高）是紧贴下栏、略压一点；新设计放到下栏上方，差别不大。
5. 电视上危险确认的默认焦点放“取消”是建议，pure_live_TV 的做法没逐个查。

## 需要改工具的地方

- 同 A02.1：`kit.css` 的 `.toast` 没有深色主题的反色、`.menu` 没有说明行和禁用项、`.dlg` 没有按钮规则；这次写在任务样式里（`src/gen.py` 的 `CSS`），建议收进 kit。
- `page.py` 引用别的任务的图（`../U.2f/…`）可以用，但导出的章节图里会把那几张图再嵌一次。

## 文件对照

| v3 | v4 现在 |
|---|---|
| `plugins/utils.dart`（通用对话框） | 没有公共组件；各页 `showDialog`、`showModalBottomSheet`（共 51 个文件） |
| `PopupMenuButton` 各处 | A07.6 的清晰度、线路菜单（`features/live_play/`）；其余各页自己写 |
| `showModalBottomSheet`、直播间右侧面板 | `features/live_play/layout/room_panel.dart`（`RoomSidePanel`，直播间专用） |
| `common/utils/toast_util.dart`（SmartDialog） | `app/app.dart:70-76`（浮起 `SnackBar`）、`routes/app_navigator.dart` 的 `ToastPresenter` |
