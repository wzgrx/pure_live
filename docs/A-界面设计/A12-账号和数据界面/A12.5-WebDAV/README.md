# A12.5 WebDAV：设计（第 1 版，已确认，已开发，待真机）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)（登记为完成，2026-10-02；K90 上没有记录，见“实现和验证”）
- 旧编号：U.11b、T09d.1（见 [MAPPING.md](../../../MAPPING.md)）
- 范围：WebDAV 页（文件列表、路径、各种状态、上传）、服务器抽屉、顶栏菜单和文件菜单、配置对话框、恢复和删除确认、使用帮助页、提示条
- 对应：[inventory/UI.md](../../../inventory/UI.md#a125)、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a125)；功能点 F-BAK-04（[inventory/FEATURES.md](../../../inventory/FEATURES.md)）；请求和认证在 [J03.1](../../../J-设置和数据/J03-备份恢复/README.md)、[J04](../../../J-设置和数据/J04-WebDAV/README.md)（J04.1 Digest）；恢复预览和 [A12.4](../A12.4-备份与恢复/README.md) 共用；相关决定 D-003（R1～R4 按建议 A）、D-009（下拉刷新）
- 评审页：claude.ai 私有页面（已发布，用户评审确认）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（公用部分 [src/skit.py](src/skit.py)）；按章节导出在 [page/](page/01-说明.jpg)
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）。服务器名、地址、用户名都是占位；帮助页里 v3 写的坚果云地址（`web_dav_help.dart:19`、帮助文字里的官网和服务器地址）换成了占位或“坚果云官网”；坚果云网页截图用灰块代替
- 记录：[record.md](record.md)

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A12.5-02 | WebDAV 页（`WebDavPage`） | 备份与恢复“WebDav”（`backup/backup_page.dart:150-156`）；v4 另在设置“数据” | 竖屏、横屏、宽屏 | 没有配置、保存的选择失效、没选服务器、加载中、加载失败、空目录、有文件、上传中、删除中、恢复中 |
| A12.5-05 | 顶栏 ⋮ 菜单 | 顶栏 | 同上 | “仅上传关注列表”不能上传时变灰 |
| A12.5-06 | 文件 ⋮ 菜单 | 文件行右边 | 同上 | 文件夹只有“删除”；有操作进行中时 ⋮ 变灰 |
| — | 服务器抽屉（`endDrawer`） | ⋮“打开配置列表”、空状态按钮 | 同上 | 选中、配置操作进行中 |
| A12.5-03、07 | 配置对话框（`_WebDavConfigDialog`） | 抽屉“添加新配置”、编辑；空状态“创建新配置” | 同上 | 添加、编辑（名称不能改）、校验错误、保存中 |
| A12.5-04 | 确认对话框（`_showConfirmation`） | 删除配置、删除文件、恢复全部、仅恢复关注 | 同上 | 删除是红色按钮 |
| A12.5-01 | 使用帮助（`WebDavHelpPage`） | ⋮“使用帮助教程” | 同上 | 截图加载失败；点截图看大图 |
| — | 提示条（`SnackBar`，2 秒） | 上传、删除、恢复、配置保存 / 删除 / 选择失败 | 全部 | 普通是浅灰，失败是错误容器色 |

## v3 的样子

文件在 `lib/modules/web_dav/` 下。

- **顶栏**（`web_dav_page.dart:248-296`）：会随滚动收起的 `SliverAppBar`；返回；标题“WebDav”（20 号常规，居中）；右边 ⋮（`Icons.more_vert`，`onPrimaryContainer` 色），菜单：刷新（`Icons.refresh`）、打开配置列表（`Icons.menu`）、使用帮助教程（`Remix.question_line`）、仅上传关注列表（只有字）。
- **路径**（`:310-386`）：固定在顶栏下，高 50；先空 48，再“我的文件”和每一级（`TextButton`，13 号 500，当前一级主色），中间 `Icons.navigate_next`；可以横向滚动，自动滚到最后。
- **进行中**（`:101-114`）：路径下面一行字（正在下载并恢复配置 / 正在处理删除 / 正在下载并恢复关注列表）+ 线形进度条。
- **列表**（`:472-550`）：`ListTile` 三行高；左图标 28 主色（文件夹 `folder_outlined`，按类型 图片 / 视频 / 音频 / 文字 / 其他）；名字 15 号 500，最多两行；副标题是修改时间 `DateTime.toString()`；右边 ⋮：恢复全部设置、仅恢复关注列表（只有文件有）、删除。点文件夹打开，点文件没有反应（`web_dav_controller.dart:303-310`）。
- **右下角**（`:89-97`）：`FloatingActionButton`，`Icons.cloud_upload_outlined`，提示“备份到当前目录”，上传中转圈。
- **状态**（`:388-470`）：没有配置：`Icons.add_circle_outline` 48 +（有问题时的说明）+“暂无配置，请先创建WebDAV配置”+“创建新配置”；没选服务器：`Icons.cloud_queue` 48 +“请从侧边栏选择WebDAV配置”+“打开配置列表”；出错：`Icons.error` 64（`onPrimaryContainer`）+“无法加载目录: <异常文字>”12 号 +“重试”；加载中：转圈；空：“暂无数据”。
- **服务器抽屉**（`:116-176`）：右侧，直角，`surfaceContainer`；顶上空 56；每个配置：名字（最多两行）下面一行右对齐的编辑（`Icons.edit`）、删除（`Icons.delete`）；选中的高亮；最后“添加新配置”（`Icons.add`）。
- **配置对话框**（`:579-759`）：圆角 16；标题行 `Remix.add_box_line` / `edit_box_line` 24 主色 +“添加新配置”/“编辑配置: {name}”20 号粗；四个输入框（描边，前缀图标 20）：配置名称 `Remix.bookmark_line`（编辑时不能改）、地址 `Remix.global_line`、用户名 `Remix.user_3_line`、密码 `Remix.lock_password_line`（隐藏）；按钮：描边“取消”、实心“添加 / 更新”（都是圆角 8、高 48）。
- **确认**（`:178-246`）：删除——“确定要删除吗？”/“确定要删除配置 "{name}" 吗？”或“确定要从 WebDAV 删除“{name}”吗？”/ 红色“删除”；恢复——“恢复备份”/“确定要使用“{name}”恢复并覆盖本机设置吗？恢复将应用备份中的全部配置。”；仅关注——“仅恢复关注列表”/“确定只从“{name}”恢复关注列表吗？ 其他本机设置将保持不变。”。
- **使用帮助**（`web_dav_help.dart`）：标题“WebDAV 设置帮助”；组标题 16/600；卡片圆角 20；开始前说明 → 连接参数（服务器地址 + 复制、用户名、应用密码）→ 注册坚果云账号（两步、两张截图）→ 在网页端登录 → 生成独立应用密码（四步四张截图）→ 在 Pure Live 中填写配置 → 常见问题（五条）→ 当前服务限制 → 快速参考 → “打开官方 WebDAV 帮助”。截图点开是黑底大图，右上角关闭。
- **提示条**（`web_dav_controller.dart:29-44`）：浮动 `SnackBar`，普通 `surfaceContainerHighest` 底 + `onSurfaceVariant` 字，失败 `errorContainer` 底。
- **宽度分支**：帮助页参数行窄于 360 或字体大于 1.5 倍时竖排（`web_dav_help.dart:158-197`）；其他没有。

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| W1 | 看不出连的是哪个服务器；换服务器要两步 | `web_dav_page.dart:248-296`、`:116-176` |
| W2 | 上传只有图标；“仅上传关注列表”藏在菜单最后 | `web_dav_page.dart:89-97`、`:287-291` |
| W3 | 刷新只在菜单里，不能下拉 | `web_dav_page.dart:276-278` |
| W4 | 点备份文件没反应 | `web_dav_controller.dart:303-310` |
| W5 | 恢复确认看不到会改什么 | `web_dav_page.dart:194-204` |
| W6 | 出错原样显示异常，图标不是错误色，不能改配置 | `web_dav_page.dart:563-576`、`web_dav_controller.dart:222` |
| W7 | 空目录只写“暂无数据”；没有配置时不提帮助 | `web_dav_page.dart:390-441` |
| W8 | 时间原样 `toString()`，没有大小 | `web_dav_page.dart:501-506` |
| W9 | 配置不能先测试连接、不能显示密码，按钮样式另一套 | `web_dav_page.dart:579-759` |
| W10 | 抽屉只有名字，编辑删除另起一行，删除不是红色，没有标题 | `web_dav_page.dart:122-170` |
| W11 | 路径前空 48；宽屏每行拉满 | `web_dav_page.dart:343`、`:472-550` |
| W12 | 结果提示浅灰底，成功和普通消息分不出 | `web_dav_controller.dart:29-44` |

## v4 现在的偏差（`apps/pure_live/lib/features/web_dav/`）

顶栏标题下写当前服务器，右边服务器（`Remix.server_line`）、刷新、⋮（仅上传关注列表、使用帮助教程）；下拉刷新；带文字的上传按钮；没有配置和空目录有说明；出错写原因；文件写时间和大小，备份文件用 `Remix.file_shield_2_line`；点文件弹底部操作面板；恢复用备份页的预览；抽屉有标题、地址、同一行的编辑删除；配置对话框有测试连接、显示密码；返回键在子目录先回上一级。这一版保留修 v3 问题的部分，点文件改成和备份页一样（R2），返回键照 v3（R4）。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 对比、状态、对话框、帮助、四处待选 | 用户 2026-10-02 确认；R1～R4 按建议 A（D-003） |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：竖屏](page/02-对比-竖屏.jpg)
- [菜单和服务器列表](page/03-菜单和服务器列表.jpg)
- [各种状态](page/04-各种状态.jpg)
- [对话框](page/05-对话框.jpg)
- [使用帮助](page/06-使用帮助.jpg)
- [横屏和宽屏](page/07-横屏和宽屏.jpg)
- [v3 的问题](page/08-v3-的问题.jpg)
- [改了什么](page/09-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/10-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/11-各客户端.jpg)
- [需要你选的](page/12-需要你选的.jpg)
- [性能要点](page/13-性能要点.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-webdav.jpg](v3-webdav.jpg)、[v4-webdav.jpg](v4-webdav.jpg)、[v4-webdav-n.jpg](v4-webdav-n.jpg) | 文件列表 / 编号 |
| [v3-webdav-nav.jpg](v3-webdav-nav.jpg)、[v4-webdav-nav.jpg](v4-webdav-nav.jpg)、[v4-drawer-n.jpg](v4-drawer-n.jpg) | 顶栏菜单、服务器抽屉、文件菜单 / 抽屉编号 |
| [v3-webdav-states.jpg](v3-webdav-states.jpg)、[v4-webdav-states.jpg](v4-webdav-states.jpg) | 没有配置、出错、空目录、恢复中、完成 / 上传中 |
| [v3-webdav-dialogs.jpg](v3-webdav-dialogs.jpg)、[v4-webdav-dialogs.jpg](v4-webdav-dialogs.jpg) | 配置、恢复、删除 |
| [v3-help.jpg](v3-help.jpg)、[v3-help-full.jpg](v3-help-full.jpg)、[v4-help.jpg](v4-help.jpg) | 使用帮助 |
| [v3-webdav-land.jpg](v3-webdav-land.jpg)、[v4-webdav-land.jpg](v4-webdav-land.jpg) | 手机横屏 852×393 |
| [v3-webdav-wide.jpg](v3-webdav-wide.jpg)、[v4-webdav-wide.jpg](v4-webdav-wide.jpg) | 宽屏 1280×800 |

## 确认的改动

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| c1 | 保留 | 路径、文件夹打开、文件菜单三项、上传按钮、服务器抽屉、配置四个字段和校验、删除确认、帮助内容 | — |
| c2 | 修改 | 标题下写当前服务器；顶栏服务器、刷新、⋮；下拉刷新（v4 已有） | W1、W3 |
| c3 | 修改 | 上传按钮带文字（v4 已有） | W2 |
| c4 | 修改 | 点备份文件预览后恢复，⋮ 和右键同一菜单 | W4 |
| c5 | 增强 | 恢复用备份页的预览（v4 已有） | W5 |
| c6 | 修改 | 出错写原因，“重试”“编辑配置” | W6 |
| c7 | 增强 | 没有配置、空目录写下一步，没有配置时给帮助入口 | W7 |
| c8 | 修改 | 时间 · 大小；备份文件专用图标（v4 已有） | W8 |
| c9 | 增强 | 测试连接、显示密码、按钮统一（v4 已有） | W9 |
| c10 | 修改 | 抽屉标题、地址、同一行编辑删除、删除红色（v4 已有） | W10 |
| c11 | 修改 | 路径从左开始；宽屏最宽 720 | W11 |
| c12 | 修改 | 统一的提示条，失败带“重试” | W12 |
| c13 | 保留 | 帮助内容照 v3，换卡片样式 | — |

新加的文字：v4 已有 `webdav_servers`、`webdav_folder_empty`、`webdav_folder_empty_hint`、`webdav_intro`、`webdav_error_*`、`webdav_check`、`webdav_checking`、`webdav_check_ok`、`webdav_show_password`；新键：“编辑配置”（出错页按钮）。

## 按钮的作用和用法

| 编号 | 控件 | 怎么用 |
|---|---|---|
| 1 | 返回 | 回到备份与恢复（R4） |
| 2 | 服务器 | 打开服务器抽屉 |
| 3 | 刷新 | 重新读目录；也可下拉 |
| 4 | ⋮ | 仅上传关注列表、使用帮助教程 |
| 5 | 标题 | 当前服务器名 |
| 6 | 路径 | 跳回上一级 |
| 7 | 文件夹 | 打开 |
| 8 | 备份文件 | 预览后恢复 |
| 9 | ⋮ / 右键 | 恢复全部、仅恢复关注、删除 |
| 10 | 备份到当前目录 | 上传完整备份 |
| 11 | 服务器 | 切换 |
| 12 | 编辑 | 改配置 |
| 13 | 删除 | 删配置，先确认 |
| 14 | 添加新配置 | 可先测试连接 |

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 竖屏如图；横屏同一列表 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 列表和路径最宽 720 居中，抽屉在右；悬停说明，右键等于 ⋮，Esc 依次关闭 |
| 电视 | 不适用（pure_live_TV 已去掉 WebDAV，`backup_settings_section.dart:69`） |
| 苹果平台差异 | iOS 滑动返回和返回键同一行为 |

## 待选（A 是建议）

- R1 服务器和刷新：A 顶栏两个按钮、标题下写服务器（v4 已有）；B 照 v3 在 ⋮ 里。
- R2 点备份文件：A 预览后恢复（同备份页）；B 弹操作菜单（v4 现在）。
- R3 上传按钮：A 带文字（v4 已有）；B 只有图标。
- R4 子目录里按返回：A 照 v3 直接离开；B 先回上一级（v4 现在）。

## 拿不准的地方

1. 文件图标：v3 用 `*_outlined` 图标，效果图工具只有 Material Icons 的填充和圆角字体，图里用填充版近似。
2. 文件时间：`webdav_client` 把服务器时间转成本地时间（`str2LocalTime`），`toString()` 显示成“2026-10-01 21:30:12.000”；没有真机核对。
3. v3 文件名带 uuid（`web_dav_controller.dart:335-337`），v4 上传的名字没有 uuid（同秒时加 `_2`）；图里两种都有。
4. 出错原因的分类（账号密码、网络、目录不存在、服务器错误）用 v4 已有的文字，是否覆盖坚果云的所有返回码没有核对。

## 需要改工具的地方

- 效果图工具没有 Material Icons Outlined 字体（`tools/ui/mock/fonts.txt`），v3 的 `*_outlined` 图标只能用填充版近似；建议加上。

## 实现和验证

**实现**（详见 [record.md](record.md)；2026-10-02，开发提交 `2c6563bb1`“feat(web_dav): WebDAV per the U.11b design”，和 A10.2、A12.4、A12.6 一起在 `f5351b91c` 合并；登记表写的是记录提交 `965d41956`。一并把中英文的“WebDav”统一成“WebDAV”）

| 编号 | 做到 | 现在的代码（`apps/pure_live/lib/features/web_dav/` 省略前缀） |
|---|---|---|
| c1 | ✅ | 路径、文件夹打开、文件菜单三项、上传按钮、服务器抽屉、配置四个字段和校验、删除确认、帮助内容都保留；配置对话框标题前加回 v3 的图标（`web_dav_config_dialog.dart:110`），编辑时名称不能改 |
| c2 | ✅ | `web_dav_page.dart:382-423`：`settingsPageAppBar` 标题“WebDAV”下一行当前服务器名（没有时“还没有服务器”）；顶栏服务器（开抽屉）、刷新、⋮ 小菜单（仅上传关注列表——不能上传时变灰、使用帮助教程）；下拉刷新（`_pullLoad` `:135`，`AppRefreshView`） |
| c3 | ✅ | “备份到当前目录”带文字的按钮，上传中转圈 +“正在上传备份”；目录出错时不显示（`:426-435`） |
| c4 | ✅ | 点备份文件 = 预览后恢复（`_open` `:324`，`purelive_favorites` 开头的只恢复关注，`:327`）；`_EntryRow`（`:662`）的 ⋮、右键、长按打开同一个 `showAppMenu`（`_fileMenu` `:331`）：恢复全部设置、仅恢复关注列表、（线）红色删除；文件夹只有删除 |
| c5 | ✅ | `restoreWithPreview`（`_restore` `:284-299`）；恢复、删除时路径下一行字和进度条（`:443-453`），列表变灰（`:736`） |
| c6 | ✅ | 出错状态（`:490-502`）：“无法加载目录”+ 原因（`webDavFailureText`，`web_dav_config_dialog.dart:11`：账号密码、网络、目录不存在、服务器错误）+“重试”+“编辑配置” |
| c7 | ✅ | 没有配置（`:465-478`）：说明 +“创建新配置”+“使用帮助教程”；空目录（`:505-521`）：“这个目录是空的”“点右下角按钮把当前数据备份到这里”，可下拉刷新 |
| c8 | ✅ | 文件行“时间 · 大小”，文件夹只写时间（`:687-691`，`formatFileTime`、`formatFileSize` 来自 `shared/backup/backup_files.dart:116-127`）；名字以 `purelive` 开头的用备份文件图标（`:686`、`:700-705`） |
| c9 | ✅ | 测试连接、显示密码（`web_dav_config_dialog.dart:43`、`:156`）；成功用语义色 `LiveSemanticColors.success`（`:104`） |
| c10 | ✅ | 抽屉 `_drawer`（`:597-657`）：标题“WebDAV 服务器”、名字和地址、当前服务器实心图标和选中底色、编辑和红色删除同一行、“添加新配置” |
| c11 | ✅ | 路径从左开始，长了跳到最后一级（`_breadcrumbs` `:547-595`）；路径和列表在一个最宽 720 的居中列里（`:438-439`，`readableContentMaxWidth`） |
| c12 | ✅ | 普通结果用应用统一的提示条；上传、删除失败用带“重试”的提示条（`_failed` `:150-155`） |
| c13 | ✅ | 帮助页 `web_dav_help.dart:12`：内容照 3.x；组标题 13 号主色（`:24-30`）、卡片圆角 16（`:35`）、最宽 720（`:54`）；截图点开全屏看大图（`WebDavScreenshot` `:156`、`:193-195`） |
| R4 | ✅ | 去掉 v4 原来的 `PopScope`（先回上一级），子目录里按返回直接离开；回上一级用路径 |

- 偏差：记录写“无（设计的每一条都照做）”。两处补充：①标题“WebDAV”靠左（下面一行服务器名，和返回键挨着，同设计图）；②上传后的文件名照 3.x 不带 uuid，同一秒加 `_2`（`shared/backup/backup_files.dart:18`），设计“拿不准的地方”第 3 条。
- 后来的变化（以现在的代码为准）：A02.2（`fc5bcdd46`）配置对话框、确认框、提示条换成共用组件；A03.1（`a048ea540`）列表接 `AppRefreshView`（D-009 两端回弹、经典下拉刷新头）；D-011（`e320e0e72`）去掉一处标题居中设置；J04.1（开发提交 `5919208a1`，登记表记的是 `c168fdb99`）请求按服务器的要求选 Basic 或 Digest（`web_dav_auth.dart`），界面没变。
- 新文字：出错页的“编辑配置”（`webdav_edit_current`）、“还没有服务器”（`webdav_no_server`）等；`webdav`、`backup_to_webdav`、`auth_webdav_desc` 里“WebDav”改“WebDAV”。没有新设置（服务器仍存在 `LiveStore.webdav`，密码加密）。
- 门禁：`web_dav` 直接写的颜色和图标 36 → 0；`web_dav -> backup/...` 三条跨功能引用改引 `shared/backup/`。

**验证**

- 自动测试：`apps/pure_live/test/features/web_dav/web_dav_page_test.dart`（现在 10 个；当时 3 → 9，A03.1 加了 1 个下拉刷新）：PROPFIND 解析；加服务器先测试、上传、点文件预览后恢复；下拉刷新时行不消失；顶栏三个按钮、⋮ 两项和帮助页、路径从左、文件行图标和“时间 · 大小”；⋮ / 右键 / 长按同一菜单、文件夹只有删除、删除红色带线；出错原因和“编辑配置”；抽屉；上传失败“重试”；子目录里返回直接离开（R4）；宽屏 720 居中。`web_dav_auth_test.dart`（5）测 Digest（J04.1）。只用 `dav.test`、`example.com` 这类假地址。
- 真机：**记录里没有 K90 结果**，也没有 `verify.md`。登记表已是“完成”，不符合 PROCESS 3.2（问题记在[子分类页](../README.md)“已知问题”）。要看的：[CHECKLIST](../../../S-质量和验证/S02-真机验证/CHECKLIST.md) 第 5 节第 2 条（坚果云：添加服务器、测试连接、上传、点文件预览后恢复、删除），归 [S02.4](../../../S-质量和验证/S02-真机验证/S02.4-K90验证数据和其他/README.md)；坚果云的各种错误码是否都落到四类原因里（设计“拿不准的地方”第 4 条）也在那时看。
- 留下的问题和去向：Esc 返回链（抽屉、页面）→ A05.1；电视不做 WebDAV（pure_live_TV 已去掉，A17.9）。
