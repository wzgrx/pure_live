# T07i.3 工具箱（链接解析）：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：链接解析页（输入、进行中、支持列表）、选择清晰度和选择线路对话框、自动填充提示和结果提示
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#t07i3)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#t07i3)
- 评审页：claude.ai 私有页面（待发布）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公用部分 [src/skit.py](src/skit.py)）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；直播流地址是占位；平台标签的图标是示意（首字 + 颜色），开发时用 `PlatformLogo`

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| T07i.3-01 | 链接解析页（`ToolBoxPage`） | 手机首页搜索旁的链接按钮（`common/widgets/search_button.dart:12-19`）；宽屏侧栏链接按钮（`modules/home/tablet_view.dart:121-127`）；顶栏菜单“链接访问”（`common/widgets/common_appbar_actions.dart:45-55`） | 竖屏、横屏、宽屏 | 空、已填、自动填充、跳转中、获取中（可取消） |
| — | 选择清晰度、选择线路（`_choose`） | 获取直链 | 同上 | 清晰度列表；线路列表带地址；取消 |
| — | 提示 | 自动填充（`Get.snackbar`）；链接不能为空、无法解析此链接、读取直链失败（无法读取清晰度）、该直播源需要应用内会话…、已复制直链、复制失败 | 全部 | — |

## v3 的样子

文件在 `lib/modules/toolbox/` 下。

- **顶栏**：“链接解析”居中（`toolbox_page.dart:16`）。
- **两张卡片**（`:51-126`）：`cardColor` 白底、圆角 12、5% 黑阴影；`ExpansionTile`（默认展开）：左 `Remix.external_link_line` / `Remix.link_m` 主色，标题 12 号粗“直播间跳转”/“获取直链”，右边折叠箭头；输入框 3–5 行（13 号，提示“请在此处粘贴平台链接...”，5% 灰底、圆角 8、无边框，右边 `Remix.close_circle_line` 20“清除”）；整宽实心按钮（圆角 8）“链接跳转”（`Remix.play_circle_line`）/“获取解析”（`Remix.download_2_line`）；进行中按钮里转圈、另一个按钮变灰，下面出现“取消”。
- **支持解析列表**（`:128-149`）：接在第二张卡片里、折叠范围外：分隔线 → `Remix.information_line` 14 +“支持解析列表”（灰、粗）→ 一段可选中的灰字（各平台的示例网址，七十多行）。
- **自动填充**（`toolbox_controller.dart:242-299`）：打开页面读一次剪贴板，有支持的链接就填进还空着的框（两个都填），弹 `Get.snackbar`“检测到链接 / 已自动填充剪贴板中的直播链接”。
- **获取直链**（`toolbox_direct_link_flow.dart`）：读房间 → 选择清晰度（对话框，标题 `headlineSmall` 24，选项居中）→ 读地址 → 选择线路（“线路1”+ 地址小字）→ 复制，提示“已复制直链”。
- **按宽度分支**：没有；宽屏卡片拉满。没有快捷键。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| T1 | 同一个链接要贴两次；自动填充填两个框 | `toolbox_page.dart:21-45`、`toolbox_controller.dart:285-288` |
| T2 | 卡片标题 12 号，比输入的字还小 | `toolbox_page.dart:73` |
| T3 | 卡片能折叠没有用；支持列表七十多行一直显示 | `toolbox_page.dart:71-77`、`:121-149` |
| T4 | 支持列表写死，和实际平台不同步 | `toolbox_page.dart:140-147` |
| T5 | 支持列表灰字约 2.7:1 | `toolbox_page.dart:136-147` |
| T6 | 自动填充用另一种提示 | `toolbox_controller.dart:289-297` |
| T7 | 选择对话框标题 24 号、选项居中、整条地址 | `toolbox_controller.dart:170-206` |
| T8 | “获取解析”和“获取直链”两种叫法 | `toolbox_page.dart:37-41` |
| T9 | 白底阴影卡片和别的设置页不同；宽屏拉满 | `toolbox_page.dart:17-19`、`:62-67` |

## v4 现在的偏差（`apps/pure_live/lib/features/toolbox/`）

一个输入框（空时“粘贴”、有字时“清除”）和两个按钮“链接跳转”“获取直链”；进行中写“正在解析链接…/正在读取直播流地址…”和“取消”；“支持解析列表”单独一张可展开卡片，按实际平台生成带图标的标签；内容最宽 960。这一版保留，宽度改成 720，自动填充提示和对话框统一。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 对比、使用过程、两处待选 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [使用过程](page/03-使用过程.jpg)
- [横屏和宽屏](page/04-横屏和宽屏.jpg)
- [v3 的问题](page/05-v3-的问题.jpg)
- [改了什么](page/06-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/07-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/08-各客户端.jpg)
- [需要你选的](page/09-需要你选的.jpg)
- [性能要点](page/10-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-toolbox.jpg](v3-toolbox.jpg)、[v4-toolbox.jpg](v4-toolbox.jpg)、[v4-toolbox-n.jpg](v4-toolbox-n.jpg) | 竖屏 / 编号 |
| [v3-toolbox-full.jpg](v3-toolbox-full.jpg)、[v4-toolbox-full.jpg](v4-toolbox-full.jpg) | 完整内容（新设计展开支持列表） |
| [v3-toolbox-states.jpg](v3-toolbox-states.jpg)、[v4-toolbox-states.jpg](v4-toolbox-states.jpg) | 自动填充、获取中、选清晰度、选线路 |
| [v3-toolbox-land.jpg](v3-toolbox-land.jpg)、[v4-toolbox-land.jpg](v4-toolbox-land.jpg) | 手机横屏 852×393 |
| [v3-toolbox-wide.jpg](v3-toolbox-wide.jpg)、[v4-toolbox-wide.jpg](v4-toolbox-wide.jpg) | 宽屏 1280×800 |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 入口、标题、自动填充、多行输入和清除、两个动作、进行中转圈和取消、选清晰度和线路、提示文字 | — |
| c2 | 修改 | 一个输入框、两个按钮并排（v4 已有） | T1、T8 |
| c3 | 修改 | 组标题在卡片外，卡片里一句说明（v4 已有） | T2 |
| c4 | 修改 | 输入卡片不折叠；支持列表单独一张、默认收起、平台标签（v4 已有） | T3、T4、T5 |
| c5 | 增强 | 空时“粘贴”，有字时“清除”（v4 已有） | — |
| c6 | 修改 | 进行中写在做什么（v4 已有） | — |
| c7 | 修改 | 自动填充用统一提示条 | T6 |
| c8 | 修改 | 选择对话框标题 20 号、选项左对齐、地址一行 | T7 |
| c9 | 修改 | 卡片同其他设置页；宽屏最宽 720 | T9 |

新加的文字都是 v4 已有的键：`toolbox_link_title`、`toolbox_link_subtitle`、`toolbox_paste`、`toolbox_support_count`、`toolbox_support_hint`、`toolbox_opening`、`toolbox_reading_stream`。

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 回到上一页 |
| 2 | 输入框 | 粘贴链接或分享文字；打开时自动填 |
| 3 | 粘贴 / 清除 | 空时粘贴，有字时清空 |
| 4 | 链接跳转 | 打开直播间 |
| 5 | 获取直链 | 选清晰度 → 选线路 → 复制 |
| 6 | 支持解析列表 | 展开 / 收起 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同一列 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 最宽 720 居中；侧栏链接按钮照 v3；悬停说明 |
| 电视 | 不适用：pure_live_TV 没有这一页，链接从手机浏览器打开的遥控网页发给电视（`tv_remote_receiver.dart`，T18a.3） |
| 苹果平台差异 | iOS 读剪贴板时系统会提示，照常 |

## 待选（A 是建议）

- Y1 输入框：A 一个框、两个按钮（v4 已有）；B 照 v3 两张卡片。
- Y2 支持解析列表：A 收起的卡片、平台标签（v4 已有）；B 照 v3 一直显示文字。

## 拿不准的地方

1. “共 45 个平台”是按 v4 翻译里的平台名数出来的示例，实际数量由 `linkPlatforms` 按已注册的平台算。
2. v3 的 `cardColor` 按 Material 3 默认画成白色，没有真机截图核对。

## 需要改工具的地方

- 无。
