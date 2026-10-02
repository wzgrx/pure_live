# A15.1 工具箱（链接解析）

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A15-小页面/A15.1-工具箱/README.md](README.md)（第 1 版，用户已确认；Y1、Y2 按建议 A）；计划书 [specs/UI.md](../../../specs/UI.md) 第 3、5、7–10 节
- 一并处理的跨任务待同步：A17.5 → A15.1（链接放映和工具箱用同一份“支持解析列表”）
- 改动的目录：`apps/pure_live/lib/features/toolbox/`、`apps/pure_live/lib/shared/links/`（新）、`packages/live_ui`（只加图标）、门禁基线、文档。没有改原生部分，没有构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 入口、标题、自动填充、多行输入和清除、两个动作、进行中转圈和取消、选清晰度和线路、提示文字 | ✅ | 入口（首页搜索旁、宽屏侧栏、顶栏菜单）不在本任务目录，没有动；控制器（`ToolboxController`）的逻辑没改 |
| c2 | 一个输入框、两个按钮并排（Y1 A） | ✅ | “链接跳转”实心（`AppIcons.linkJump`，v3 的 `Remix.play_circle_line`）、“获取直链”浅色（`AppIcons.streamLink`，v3 的 `Remix.link_m`），各 48 高、圆角 12；宽度 <320 时上下排 |
| c3 | 组标题在卡片外，卡片里一句说明 | ✅ | `SettingsGroup`（A11.1 的组）：组标题“平台链接”，卡片里 13 号次要色说明 |
| c4 | 输入卡片不折叠；支持列表单独一张、默认收起、平台标签（Y2 A） | ✅ | `shared/links/supported_platforms.dart` 的 `SupportedPlatformsCard`，平台由 `linkPlatforms` 按已注册的平台算（A17.5 用同一份） |
| c5 | 空时“粘贴”，有字时“清除” | ✅ | 粘贴用 `AppIcons.pasteText`（和 IPTV 的粘贴同一个图标），清除用 `AppIcons.clearField` |
| c6 | 进行中写在做什么 | ✅ | “正在解析链接…/正在读取直播流地址…”，右边“取消”（48 的点击区） |
| c7 | 自动填充用统一提示条 | ✅ | `AppNavigator.toast`（v4 原来就是） |
| c8 | 选择对话框标题 20 号、选项左对齐、每行 ≥48、地址一行 | ✅ | `ToolboxChoiceDialog`：标题 20/600，每项最少 56 高、左边距 24，名字 15 号、地址 12 号一行截断，去掉了 v4 的右箭头；底部“取消” |
| c9 | 卡片同其他设置页；宽屏最宽 720 | ✅ | 内容区 `ReadableContent`（720，居中），滚动区是整个窗口宽；窗口高度 <480（横屏手机）时顶栏 48 高，和设置页一致；标题居中（v3） |

### 各客户端

| 客户端 | 做到 | 说明 |
|---|---|---|
| 手机竖屏、横屏 | ✅ | 同一列；横屏最宽 720 |
| 宽屏（平板、Windows、Linux） | ✅ | 最宽 720 居中；粘贴、清除按钮悬停有说明 |
| 电视 | — | 不适用（pure_live_TV 没有这一页）；电视的链接放映（A17.5）开发时用 `SupportedPlatformsCard`/`linkPlatforms` |
| 苹果平台 | — | iOS 读剪贴板时系统提示，照常 |

## 偏差

- 无。“共 N 个平台”按 `linkPlatforms` 实际数（测试环境里注册的平台），不是设计图里的 45。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/toolbox/toolbox_page.dart` | `features/toolbox/toolbox_page.dart`（页面、`ToolboxChoiceDialog`）、`shared/links/supported_platforms.dart`（支持解析列表） |
| `modules/toolbox/toolbox_controller.dart`、`toolbox_direct_link_flow.dart` | `features/toolbox/toolbox_actions.dart`（没改，只把 `linkPlatforms` 挪到 shared） |

## 新设置、新文字

- 设置：无。
- 文字：无新增（都是 v4 已有的键）。

## `live_ui` 的添加

`AppIcons.linkJump`（其余新图标见 A15.2、A09.10 记录）。

## 门禁

- `toolbox` 直接写的颜色和图标 **7 → 0**（`ui_baseline.json` 去掉这一项）。没有新增跨功能引用。

## 测试

- `test/features/toolbox/toolbox_page_test.dart`：6 → 9 个。新增：竖屏（组标题在卡片外、一个框、粘贴 / 清除切换、两个按钮的顺序和图标和高度、支持列表单独一张且收起、宽度）；进行中（说明文字、按钮变灰、对话框标题 20 号、选项左对齐 24 和高度 ≥56、没有箭头、地址一行）；852×393 和 1280×800（最宽 720 居中、横屏 48 高顶栏、按钮一行）。
- 原有测试只改了 `linkPlatforms` 的导入位置（挪到 `shared/links/`）。
