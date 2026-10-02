# A11.5 数据

- 日期：2026-10-02
- 设计：[docs/A-界面设计/A11-设置界面/A11.5-数据/README.md](README.md)（第 1 版，用户已确认；Z1～Z3 按建议 A）
- 一并处理的跨任务待同步：A12.4 → A11.5（日志管理移到设置，Q1 按 A）
- 改动的目录、行组件、对话框见 [A11.3 的记录](../A11.3-播放/record.md)（三个任务共用）

## 逐条对照

| 编号 | 要求 | 做到 | 说明 |
|---|---|---|---|
| e1 | 两页和入口、全部操作和文字、权限处理、预览内容和默认展开两层 | ✅（有偏差） | 重新计算、刷新缩略图、清空（先确认）、选下载目录、恢复默认目录；预览不含 Cookie 和 WebDAV（`BackupService.exportAll` 默认）；树默认显示两层（各段展开、段里的列表和对象收起，同效果图）。**偏差**：Android 选公共目录缺权限时 v4 只提示（`download_directory_permission_hint`），不会打开系统设置——v4 没有打开系统设置页的插件，归 A14.1 |
| e2 | 缓存、下载两组；立即执行的行不带箭头，清空红字；只有下载目录带箭头 | ✅ | |
| e3 | 当前缓存大小写明“点一下重新计算”，数值加刷新图标 | ✅ | 计算中右边转圈（只有这一行）；手动重新计算失败提示“缓存操作失败，请重试” |
| e4 | 提示统一用应用的提示条；清除成功写释放多少 | ✅ | 全用 `AppNavigator.toast`（A02.2 的提示条）；“缓存已清除，释放 12.34 MB”；没清干净时“部分缓存文件正在使用，剩余缓存：1.20 MB” |
| e5 | 下载目录写实际路径，右边默认 / 自定义；组下说明 | ✅ | 默认目录的真实路径（`defaultDownloadDirectory`）；“下载目录用于安装包、下载的文件和字体；录制文件的位置在录制设置里。” |
| e6 | “恢复默认下载目录”一直显示，默认时变灰 | ✅ | 变灰写“现在用的就是默认目录” |
| e7 | 清空确认写出现在多大；清除中只有这一行转圈 | ✅ | 确认框末行“现在约 12.34 MB。”；按钮红色“清除”；清除中说明“正在清除…”，红色转圈，其他行照常 |
| e8 | 预览加载、出错有标题；出错写清楚、原始错误、“重新读取” | ✅ | `AppStatusView` 出错样子（出错图标，不是断网），按钮“重新读取”重新读取 |
| e9 | 原始内容和页面一起滚动 | ✅ | `CustomScrollView` 里的 `JsonTreeSliver`（`live_ui` 新加），只建屏幕上的行；点带箭头的键展开或收起 |
| e10 | 概况数字 22 号、名称 12 号；“备份格式”和说明 | ✅ | 内容宽 ≥560 四列，否则两列；“备份格式 v4；这里不显示账号 Cookie 和 WebDAV 设置。”（版本号照实际备份写，v4 是 4，图里写的 v3） |
| e11 | 原始内容颜色用主题角色 | ✅ | 键主色 600、数字成功绿、字符串 `tertiary`、布尔值警告黄、对象和数组次要色；深浅色各一套（`LiveSemanticColors`） |
| e12 | 预览顶栏加“备份与恢复” | ✅ | 跳 `RoutePath.kBackup` |
| A12.4 Q1 | 日志管理移到设置 | ✅（有偏差） | 设置总览“数据”组最后一行“日志管理”，打开现有的日志页（`log_page.dart` 的 `LogPage`）。v4 的日志页还没有路由，所以像 IPTV、备份那样从总览直接推一页（两栏时盖住整个设置）；A12.4 给它路由后，把 `SettingsSection.log` 改成 `route:` 即可。原来缓存页里的“日志管理”一行去掉 |

## 和设计不同的地方

1. **去掉 v4 自加的两项**：缓存页原来的“恢复全部默认设置”（v3 没有、设计也没有，A11.1 留给这里定）和配置预览顶栏的“复制全部”（v3 没有、设计只有“备份与恢复”）。按 A11.1 去掉 v4 自加项的做法去掉；需要的话可以加回。
2. 日志入口的打开方式（见上表）。
3. 出错状态没有组件测试：内存里的存储读不出错，难以在测试里造出读取失败；出错分支用的是 `AppStatusView` 的标准用法。

## v3 文件 → v4 文件

| v3 | v4（`features/settings/`） |
|---|---|
| `modules/settings/pages/cache_data_settings_page.dart`、`common/services/cache_controller.dart` | `data_tools.dart`（`CacheSizeModel`、`CacheSizeTile`、`RefreshCoversTile`、`ClearCacheTile`、`DownloadDirectoryTile`、`DownloadResetTile`；`ImageCacheTools`、`CoverRefreshTimer` 没改）、`settings_catalog.dart`（缓存一节） |
| `modules/settings/pages/local_config_preveiw.dart`（flutter_json） | `data_tools.dart`（`ConfigPreviewPage`）、`packages/live_ui/lib/src/widgets/json_tree.dart` |

## 测试

- `apps/pure_live/test/features/settings/settings_data_test.dart`：7 个——缓存页两组和行序、动作行没有箭头、清空红字、下载目录默认 / 自定义、恢复默认变灰和原因、选目录和恢复的提示；清空确认的文字和取消；大小的写法；配置预览（有标题、概况四格、说明、树和页面一起滚动、两层、点键收起、不含 Cookie）；顶栏去备份；树的类型写法和展开；总览“数据”组最后是日志、打开日志页。
- `packages/live_ui/test/settings_playback_widgets_test.dart` 的 JSON 树一项（显示两层、展开后展平）。
