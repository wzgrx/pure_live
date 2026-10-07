# A11.5 数据：设计（第 1 版）

- 状态：以登记表为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)
- 范围：缓存与数据管理、本地配置预览两页，以及清空缓存确认、操作结果提示、加载和出错状态
- 对应：[TASKS.md](../../../TASKS.md)、[inventory/UI.md](../../../inventory/UI.md#a115)（A11.5-01～03）、[inventory/UI_FILES.md](../../../inventory/UI_FILES.md#a115)
- 评审页：claude.ai 私有页面（只有项目所有者能打开）；源文件 [page.json](page.json)，效果图源文件 [src/gen.py](src/gen.py)（共用部分 [src/smock.py](src/smock.py)，和 A11.3 同一份）
- 图片：v3 按 `v3.2.11` 代码还原（文字取自 `assets/translations/zh.json`）；配置预览里的数字（128、57、6）是示意
- 和 A11.1、A02.2 的关系：行的样子同 A11.3、A11.4，统一行组件以 A11.1 为准；提示条用 A02.2 的统一提示条

## 界面清点表

| 编号 | 界面 | 从哪打开 | 形态 | 状态 |
|---|---|---|---|---|
| A11.5-01 | 缓存与数据管理 | 设置总览“缓存与数据管理” | 竖屏、横屏、宽屏 | 默认目录 / 自定义目录；计算中、刷新缩略图中、清除中（各自转圈，其余行不能点） |
| A11.5-02 | 确认清空本地缓存 | 清空本地缓存 | 对话框 | — |
| — | 操作结果提示 | 计算、刷新缩略图、清除、选目录之后 | 提示条 | 缩略图已刷新、缓存已清除、部分没清掉（剩余大小）、缓存操作失败、下载目录已更新、无法选择下载目录、缺存储权限（Android 随后打开系统设置） |
| A11.5-03 | 本地配置预览 | 设置总览顶栏“配置预览”（窄于 520 只有图标） | 竖屏、横屏、宽屏（概况 1 / 2 / 4 列） | 加载中、出错、正常 |

## v3 的样子

行的组件和顶栏、对话框见 [A11.3](../A11.3-播放/README.md#v3-的样子)。

**缓存与数据管理**（`cache_data_settings_page.dart:146-241`）：一组“缓存与数据管理”：当前缓存大小 `database_2_line`（没有说明，右边“12.34 MB”12 号主色 + 16 号 60% 灰的 `refresh_line`，点一下重新计算，计算中换成转圈）、刷新直播缩略图 `image_2_line`（右边 24 号 `refresh_rounded`）、清空本地缓存 `delete_bin_6_line`（右边红色垃圾桶，清除中红色转圈）、下载目录 `folder_2_line`（说明“当前使用默认目录”或自定义路径，右边箭头）、（自定义时才有）恢复默认 `refresh_line`。清空先确认：“确认清空本地缓存？”、说明、取消 / 红色“清除”（`:51-105`）。结果用 `Get.snackbar`：标题“完成”或“错误”、底部、黑字、20% 灰半透明加 7 的模糊（`:25-28`；`get/get_navigation/src/extension_navigation.dart:413-433`）。下载目录用于安装包、下载的文件和字体（`:110-111`），Android 默认在 `getDownloadsDirectory()/pure_live`（`cache_controller.dart:48-54`）。

**本地配置预览**（`local_config_preveiw.dart`）：加载中和出错时顶栏没有标题（`:55-69`）；出错用 `AppStatusView` 的出错样子，原始报错当标题，下面是默认的“请检查您的网络连接或稍后再试”、断网图标，没有重试按钮。正常时：页面底色 `surfaceContainerLowest`；概况卡片（齿轮头像、“本地备份配置”、“backup v3”小标签、分隔线、收藏直播间 / 历史记录 / 标签 / 配置模块四格，数字 12 号粗体、名称 11 号；宽 <520 一列、≥520 两列、≥900 四列，`:133-296`）→ 组标题“本地配置原始预览” → 圆角 24 的框，高度是页面的 70%（320–720），里面是 flutter_json 的树：默认展开两层、每行最少 32、粗体、键主色、数字 `#199B4D`、字符串 `#CD44D9`、布尔值橙色、对象和数组灰色（“Object”“Array<String>[8]”），框内单独滚动（`:86-124`）。内容是不含 Cookie 和 WebDAV 的备份数据（`backup_controller.dart:56-88`），17 个配置模块。

## 各版的经过

| 版 | 内容 | 用户意见 |
|---|---|---|
| 第 1 版 | 缓存页分两组、动作行统一、下载目录写出路径；提示条统一；配置预览状态补齐、一个滚动、颜色跟主题 | 待评审 |

## 对比页（按章节导出）

- [说明](page/01-说明.jpg)
- [对比：缓存与数据管理](page/02-对比-缓存与数据管理.jpg)、[宽屏、横屏](page/03-对比-缓存与数据管理-宽屏-横屏.jpg)
- [对比：本地配置预览](page/04-对比-本地配置预览.jpg)、[宽屏](page/05-对比-本地配置预览-宽屏.jpg)
- [对比：各种状态和提示](page/06-对比-各种状态和提示.jpg)
- [v3 的问题](page/07-v3-的问题.jpg)
- [改了什么](page/08-改了什么.jpg)
- [每个按钮是干什么的、怎么用](page/09-每个按钮是干什么的-怎么用.jpg)
- [各客户端](page/10-各客户端.jpg)
- [需要你选的](page/11-需要你选的.jpg)
- [性能要点](page/12-性能要点.jpg)
- [拿不准的地方、交给其他任务的](page/13-拿不准的地方-交给其他任务的.jpg)

## 单张图

| 图 | 内容 |
|---|---|
| [v3-cache.jpg](v3-cache.jpg)、[v4-cache.jpg](v4-cache.jpg)、[v4-cache-n.jpg](v4-cache-n.jpg) | 缓存与数据管理，手机 |
| [v3-cache-wide.jpg](v3-cache-wide.jpg)、[v4-cache-wide.jpg](v4-cache-wide.jpg) | 1280×800，自定义下载目录 |
| [v3-cache-land.jpg](v3-cache-land.jpg)、[v4-cache-land.jpg](v4-cache-land.jpg) | 手机横屏 |
| [v3-preview.jpg](v3-preview.jpg)、[v4-preview.jpg](v4-preview.jpg)、[v4-preview-n.jpg](v4-preview-n.jpg)、[v4-preview-full.jpg](v4-preview-full.jpg) | 本地配置预览，手机；新设计往下滚 |
| [v3-preview-wide.jpg](v3-preview-wide.jpg)、[v4-preview-wide.jpg](v4-preview-wide.jpg) | 本地配置预览，1280×800 |
| [v3-states.jpg](v3-states.jpg)、[v4-states.jpg](v4-states.jpg)、[v4-states-n.jpg](v4-states-n.jpg) | 加载、出错、清空确认、清除中、提示 |

## v3 的问题

| 编号 | 问题 | 位置 |
|---|---|---|
| E1 | 缓存页一组、组名同页名；四行右边四种东西，看不出哪行跳转、哪行立即执行 | `cache_data_settings_page.dart:156-236` |
| E2 | 点“当前缓存大小”会重新计算，提示只有 16 号浅灰小箭头 | `cache_data_settings_page.dart:158-189` |
| E3 | GetX 提示条：带标题、字固定黑色（深色主题看不清）、半透明加模糊，和别处不一样 | `cache_data_settings_page.dart:25-28`；`extension_navigation.dart:413-433` |
| E4 | 默认下载目录不写路径 | `cache_data_settings_page.dart:215-226`；`cache_controller.dart:48-54` |
| E5 | “恢复默认”只在自定义时出现，单看标题不知恢复什么 | `cache_data_settings_page.dart:227-232` |
| E6 | 没说下载目录管什么，容易和录制文件目录混淆 | `cache_data_settings_page.dart:110-111` |
| E7 | 配置预览加载、出错时顶栏没标题 | `local_config_preveiw.dart:55-69` |
| E8 | 出错时原始报错当标题、提示查网络、没有重试 | `local_config_preveiw.dart:62-69`；`app_status_view.dart:415-470` |
| E9 | 原始内容在固定高度的框里单独滚动，两层滚动 | `local_config_preveiw.dart:86-124` |
| E10 | 概况数字 12 号、名称 11 号；“backup v3”英文 | `local_config_preveiw.dart:213-295` |
| E11 | 原始内容固定颜色，橙色布尔值对比度约 2.2:1，深色主题不变 | `local_config_preveiw.dart:121`；flutter_json `json_widget.dart:146-154` |

## 改动（待确认）

| 编号 | 类型 | 内容 | 对应问题 |
|---|---|---|---|
| e1 | 保留 | 两页和入口、全部操作和文字、权限处理、预览内容和默认展开两层 | — |
| e2 | 修改 | 缓存、下载两组；立即执行的行不带箭头，清空红字；只有下载目录带箭头 | E1 |
| e3 | 修改 | 当前缓存大小写明“点一下重新计算”，数值加 20 号刷新图标 | E2 |
| e4 | 修改 | 提示统一用 A02.2 提示条（无标题、跟主题、不模糊），清除成功写释放多少 | E3 |
| e5 | 修改 | 下载目录写实际路径、右边默认 / 自定义；组下写用途和录制目录在哪 | E4、E6 |
| e6 | 修改 | “恢复默认下载目录”一直显示，默认时变灰 | E5 |
| e7 | 增强 | 清空确认写出现在多大；清除中只有这一行转圈 | — |
| e8 | 修改 | 预览加载、出错有标题；出错写“读取本地配置失败”+原始错误+“重新读取” | E7、E8 |
| e9 | 修改 | 原始内容和页面一起滚动 | E9 |
| e10 | 修改 | 概况数字 22 号、名称 12 号；“备份格式 v3”和不含 Cookie、WebDAV 的说明 | E10 |
| e11 | 修改 | 原始内容颜色用主题角色 | E11 |
| e12 | 增强 | 预览顶栏加“备份与恢复”入口 | — |

## 按钮的作用和用法

见对比页“每个按钮是干什么的、怎么用”（缓存 1–5、预览 1–3），编号和 `v4-cache-n.jpg`、`v4-preview-n.jpg`、`v4-states-n.jpg` 一致。

## 各客户端

| 客户端 | 怎么做 |
|---|---|
| Android 手机 | 同图；横屏最宽 720 居中 |
| 宽屏（平板、Windows、Linux、iPad、macOS） | 最宽 720 居中；预览概况四列；目录用系统文件夹选择框 |
| 电视 | A17.9：pure_live_TV 的 `cache_settings_section.dart`、`local_config_preview_section.dart`，同一个行组件的电视样式 |
| 苹果平台 | 同上；iOS 选下载目录的授权见“拿不准的地方” |

## 待选

- Z1 “恢复默认下载目录”：建议 A 一直显示、默认时变灰；B 照 v3 自定义时才出现。
- Z2 配置预览加“备份与恢复”入口：建议 A 加；B 不加。
- Z3 原始内容：建议 A 和页面一起滚动；B 照 v3 固定高度框内单独滚动。

## 拿不准的地方

1. Android 默认下载目录的实际路径（图里按 `/storage/emulated/0/Android/data/com.mystyle.purelive/files/Download/pure_live` 画），v4 的包名和路径以实际为准。
2. iOS 上选下载目录和长期访问（沙盒、书签授权）没有设备验证。
3. v3 的加载动画随“加载样式”设置（A11.2），图里画的是默认转圈。
4. 配置预览里的数字和 JSON 内容是示意（键名和顺序照 `toJson()`）。

## 交给其他任务的

- A11.1：设置总览右上角“配置预览”入口。
- A02.2：统一提示条的样子（这里只要求无标题、跟主题配色、不用模糊）。
- A12.4：备份与恢复页（e12 的入口指向它）。

## 实现和验证

- 定稿：用户确认第 1 版，Z1～Z3 按建议 A；A12.4 的 Q1（日志管理移到设置）按 A 一并做。
- 实现：e1～e12 做到，详见 [record.md](record.md)。`apps/pure_live/lib/features/settings/data_tools.dart`（缓存大小、清空确认写出现在多大、刷新缩略图、下载目录写实际路径和“默认 / 自定义”、恢复默认目录一直显示、配置预览 `ConfigPreviewPage`）、`packages/live_ui/lib/src/widgets/json_tree.dart`（`JsonTreeSliver` 和页面一起滚动，只建屏幕上的行）；总览“数据”组最后一行“日志管理”。
- 偏差：去掉 v4 自加的“恢复全部默认设置”和配置预览的“复制全部”；Android 选公共目录缺权限时只提示、不打开系统设置（当时没有打开系统设置页的插件，归 A14.1）；日志页当时没有路由、从总览直接推一页——现在已有 `RoutePath.kLogs`，`SettingsSection.log` 已改成路由（`settings_model.dart`）。
- 提交：同 A11.3（`6b87e96f9`，合并 `ccd54d3c7`，记录 `e9e41d557`，2026-10-02）。
- 测试：`apps/pure_live/test/features/settings/settings_data_test.dart` 7 个（缓存页两组和行序、动作行没有箭头、清空红字和确认、下载目录、配置预览的概况四格和两层树、顶栏去备份、日志入口）；`live_ui` JSON 树 1 个。出错状态没有组件测试（内存存储读不出错）。
- 真机：没有单独记录。登记表已是“完成”，建议在 [S03.1](../../../S-质量和验证/S03-统一验证/README.md) 补看清空缓存、换下载目录（含 Android 公共目录的权限提示）、配置预览。
- 留下的问题：Android 选公共下载目录缺权限时仍只提示（`data_tools.dart:352`）；平台层的 `apps/pure_live/lib/platform/system_access.dart`、`system_permissions.dart` 现在只有安装、本地网络、通知、电池的入口，没有打开存储权限设置页的方法，这件事没有登记任务（建议在 [O04 权限](../../../O-Android系统集成/O04-权限/README.md) 下登记）。
