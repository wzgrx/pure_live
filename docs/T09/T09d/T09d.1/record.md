# T09d.1 WebDAV

- 日期：2026-10-02
- 设计：[docs/T09/T09d/T09d.1/README.md](README.md)（第 1 版，用户已确认；R1～R4 都按建议 A：顶栏服务器和刷新、点备份文件预览后恢复、上传按钮带文字、子目录里按返回直接离开）
- 一并处理的跨任务待同步：T10c.1 → T09d.1（统一写法）：中英文的 `webdav`、`backup_to_webdav`、`auth_webdav_desc` 里的“WebDav”都改成“WebDAV”（设计图的写法；其他文字原来就是 WebDAV）
- 改动的目录：`apps/pure_live/lib/features/web_dav/`、`packages/live_ui`（只做添加）、翻译文件、门禁基线、文档；恢复预览和文件文字用 `shared/backup/`（T09c.2 搬过去的）
- 没有改原生部分，没有构建 APK

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| c1 | 保留路径、文件夹打开、文件菜单三项、上传按钮、服务器抽屉、配置四个字段和校验、删除确认、帮助内容 | ✅ | 全部保留；配置对话框标题前加回 v3 的图标（添加 `add_box_line`、编辑 `edit_box_line`），编辑时名称不能改 |
| c2 | 标题下写当前服务器；顶栏服务器、刷新、⋮；下拉刷新 | ✅ | 标题“WebDAV”靠左（标题下有服务器名，和返回键挨着，同设计图）；没有服务器时写“还没有服务器”；⋮ 是统一小菜单：仅上传关注列表（心形，不能上传时变灰）、使用帮助教程（问号） |
| c3 | 上传按钮带文字 | ✅ | “备份到当前目录”，上传中转圈 +“正在上传备份”；目录出错时不显示 |
| c4 | 点备份文件预览后恢复，⋮ 和右键同一菜单 | ✅ | 点文件 = 恢复（`purelive_favorites` 开头的恢复关注），先预览；⋮、右键、长按打开同一个小菜单：恢复全部设置、仅恢复关注列表、（线）红色删除；文件夹只有删除 |
| c5 | 恢复用备份页的预览 | ✅ | `restoreWithPreview`；恢复中路径下一行字和进度条，列表变灰 |
| c6 | 出错写原因，“重试”“编辑配置” | ✅ | `AppStatusView` 出错样子：“无法加载目录”+ 原因（账号密码、网络、目录不存在、服务器错误）+“重试”（实心）+“编辑配置”（打开当前服务器的配置） |
| c7 | 没有配置、空目录写下一步，没有配置时给帮助入口 | ✅ | 没有配置：说明 +“创建新配置”+“使用帮助教程”；空目录：“这个目录是空的”“点右下角按钮把当前数据备份到这里”（可下拉刷新） |
| c8 | 时间 · 大小；备份文件专用图标 | ✅ | 文件夹只写时间；`file_shield_2_line` 是备份文件，其他文件普通图标 |
| c9 | 测试连接、显示密码、按钮统一 | ✅ | v4 已有；成功绿色改用语义色 `LiveSemanticColors.success` |
| c10 | 抽屉标题、地址、同一行编辑删除、删除红色 | ✅ | “WebDAV 服务器”；当前服务器用实心云和选中底色；编辑、红色删除同一行 |
| c11 | 路径从左开始；宽屏最宽 720 | ✅ | 路径改成从左排（v4 原来是从右排），路径长时自动滚到最后一级；路径和列表在一个最宽 720 的居中列里 |
| c12 | 统一提示条，失败带“重试” | ✅ | 成功和普通结果用应用统一的提示条；上传、删除失败用带“重试”的提示条（4 秒） |
| c13 | 帮助内容照 v3，换卡片样式 | ✅ | 内容不变；组标题 13 号主色、卡片低表面容器色圆角 16、最宽 720；看大图黑底用画面颜色角色 |
| R4 | 子目录里按返回直接离开（照 v3） | ✅ | 去掉了 v4 的 `PopScope`（先回上一级）；回上一级用路径 |

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/web_dav/web_dav_page.dart`、`web_dav_controller.dart` | `features/web_dav/web_dav_page.dart`（页面、抽屉、菜单、文件行）、`web_dav_config_dialog.dart`、`web_dav_client.dart`（不变） |
| `modules/web_dav/web_dav_help.dart` | `features/web_dav/web_dav_help.dart` |

## 新设置项

无（服务器仍存在 `LiveStore.webdav`，密码加密）。

## 门禁（`ui_baseline.json`）

- `web_dav` 直接写的颜色和图标 **36 → 0**；新图标进 `AppIcons`（`webDavServers`、`webDavFolder`、`webDavBackupFile`、`webDavUpload`、`help`、`edit`、`pathSeparator`、配置框的 `webDavName`/`webDavAddress`/`userName`/`password`/`showPassword`/`hidePassword`/`checkPassed`、帮助的 `link`/`copyValue`/`mail` 等）。
- 跨功能引用删掉 `web_dav -> backup/backup_data.dart`、`backup_files.dart`、`backup_preview_dialog.dart` 三条（改引 `shared/backup/`）。

## 测试

- `apps/pure_live/test/features/web_dav/web_dav_page_test.dart`：3 → 9 个。原来的“adds a server … restores a file after the preview”和“opens folders … deletes after asking”断言了“点文件弹操作菜单”（v4 的 R2 B），和确认的 R2 A 冲突，改成点文件直接预览、删除走 ⋮ 菜单。新增：顶栏三个按钮的顺序和图标、⋮ 菜单两项和帮助页、路径从左开始、文件行图标和“时间 · 大小”；⋮ / 右键 / 长按同一菜单、文件夹只有删除、删除红色带线、空目录说明；出错原因和“编辑配置”（名称不能改）；抽屉标题、地址、编辑和红色删除同一行；上传失败的“重试”；子目录里返回直接离开；宽屏 720 居中。
- 测试里只用 `dav.test`、`example.com` 这类假地址。
