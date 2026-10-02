# A09.7 搜索

- 日期：2026-10-01
- 设计：[docs/A-界面设计/A09-浏览界面/A09.7-搜索/README.md](README.md)（用户已确认；X1～X4 按 A）；卡片见 [A09.1 记录](../A09.1-房间卡片/record.md)
- 改动的目录：`apps/pure_live/lib/features/search/`（`search_view.dart`、`search_widgets.dart`、`search_scope.dart`、`search_capability.dart`）、`packages/live_ui`（只做添加，见下）、翻译文件。没有改原生部分，没有构建 APK，没有往手机安装

## 逐条对照

| 编号 | 内容 | 做到 | 说明 |
|---|---|---|---|
| c1 | 页面结构、平台条、包含未开播（默认开）、四种排序、继续网页搜索、结果网格、滑到底自动加载、“加载更多结果”“已加载全部结果” | ✅ | 返回在框内左边、搜索在右边；回车搜索；拖动结果收起键盘；平台条选中项滚到中间、有字时换平台自动重搜；离底 480 自动加载（同 v3）。网格边距 6、间距跟设置（A09.1 c15 统一，v3 搜索页是固定 8） |
| c2 | 焦点时保持圆角 24；清除 / 粘贴；回车键“搜索”；提示改短 | ✅ | 焦点时只把边框换成主色 2；提示“搜索直播间、主播或粘贴链接”（改了 `search_hint` 的值，只有这一处用） |
| c3 | 筛选行放不下就换行 | ✅ | `Wrap`；单个平台时“继续网页搜索”在第二行完整显示 |
| c4 | 排序按钮“综合 ⌄”，菜单当前项主色加勾 | ✅ | 按钮“≡ 综合 ⌄”，悬停提示“排序”；菜单用 live_ui 的小菜单 `showAppMenu`，新加可选参数 `selected`（当前项主色、半粗、行尾勾） |
| c5 | 一句通俗说明，最多两行，点开搜索范围面板 | ✅ | v4 已有的说明；排除了平台时写“同时搜索 N 个平台（共 M 个，已排除 K 个），点此查看或修改。”（新文字） |
| c6 | 搜索范围合成一个面板 | ✅ | `showSearchScopePanel`：竖屏底部升起、宽 600 起在右侧 360（live_ui `showAdaptivePanel`）；说明、“只搜国内平台”“全选”、国内 / 海外分组带“已选 N / M”、每行勾选框 + 标志 + 名称 +“主播”“网页”标签 + 一句能搜到什么。关闭面板时生效（记住并重搜“全部”），最后一个选中的平台不能取消 |
| c7 | 直播间 / 主播切换放在筛选行最前 | ✅ | 照设计去掉了 v4 分段按钮上的两个图标 |
| c8 | 骨架卡片、“还有 N 个平台在搜索…” | ✅ | 骨架改用 A09.1 的 `RoomGridSkeleton`（和真卡同尺寸、静态），v4 自己的骨架网格删掉 |
| c9 | 失败说明卡 | ✅ | 按钮：查看是哪些、重试、搜索范围（全部时）、代理设置（有海外平台失败时）、继续网页搜索（单个平台时）；右上角可关 |
| c10 | 四种空状态各有说明，按钮配对应图标 | ✅ | 网页搜索是浏览器图标、显示未开播是眼睛、重试是刷新；按钮样式随 A02.1 C1（浅色实心） |
| c11 | 搜索历史、识别直播链接 | ✅ | 历史最近 20 条、单条删除、清空；“识别到直播链接 · 进入”照设计改成次色容器底、无前置图标 |
| c12 | 横屏和宽屏搜索框和平台条一行；往下滑收起筛选行 | ✅ | 页面宽 600 起一行（`searchOneRowWidth`）；筛选和说明并成一行，放不下时说明换到下一行（`_LeadThenRest`）。收起用 `SliverFloatingHeader`：竖屏收平台条和筛选区，横屏和宽屏收筛选区，搜索框一直在；往上滑出现（X1 A） |
| c13 | 宽屏搜索框最宽 480；列数按计划书 5.3 节 | ✅（有偏差） | 框宽 = 页宽 × 0.38，夹在 280～480：852 宽时 324（设计图 330），1280 宽时 480。列数用 `RoomGridGeometry`（393 → 2、852 → 4、1280 → 6，测试固定） |
| c14 | “全部”的结果卡片看得出平台 | ✅ | 卡片换成 A09.1 的 `RoomGridCard`（`LiveRoomCard`）；选“全部”时 `mixedPlatforms: true`，卡片设置为“自动”时封面左上显示平台；单个平台不传 |
| c15 | WebView2 提示只在点网页搜索时出现，可点外面关，多“用系统浏览器打开” | ✅ | 打开搜索页不检查；对话框：错误色警告图标“系统组件缺失”、新说明、取消 / 打开下载页 / 用系统浏览器打开（实心）。下载页地址同 v3；选系统浏览器进入网页搜索的系统浏览器页（A09.8 c7） |
| c16 | 滚轮横滚平台条；Tab 顺序 | ✅ | 平台条上竖向滚轮横着滚；Tab 顺序按控件的位置（没有特别处理） |

选择：X1 A ✅；X2 A ✅；X3 A ✅；X4 A ✅。

另外：Esc 等于返回（设计“手势和键盘”），用 `CallbackShortcuts` 接（见下面第 1 条）；“主播”结果第二行改成“平台 · 房间号 N”，和 A09.1 卡片对话框一致。

## 和设计 / v3 不一样、需要你知道的

1. **Esc 的做法**：`Scaffold` 自己给 `DismissIntent` 挂了一个关抽屉的动作，没抽屉时它不生效但会挡住外层的 `Actions`，所以页面级的 Esc 要用 `CallbackShortcuts` + `FocusScope`（搜索、网页搜索、观看记录都这样）。其他页面要做 Esc 返回时照这个写。
2. **Linux 点“继续网页搜索”**：v3 直接打开系统浏览器、不经过网页搜索页；现在进网页搜索页（标题、怎么回来、网址），同时立刻打开系统浏览器（A09.8 c7）。
3. **搜索范围面板关闭时才生效**，不是每勾一下就重搜。
4. 横屏 852 宽时搜索框 324，比设计图的 330 窄 6（按比例算，避免写死）。

## v3 文件 → v4 文件

| v3 | v4 |
|---|---|
| `modules/search/search_page.dart` | `features/search/search_view.dart` |
| `modules/search/search_platform_strip.dart` | `features/search/search_widgets.dart` 的 `SearchPlatformStrip` |
| `modules/search/search_controller.dart`（状态、请求） | `features/search/search_model.dart`（没改） |
| `search_controller.dart` 的说明文字、WebView2 对话框 | `search_widgets.dart` 的 `SearchCoverageLine`、`search_view.dart` 的 `_askWithoutWebView2` |
| （v4 新增）搜索范围 | `features/search/search_scope.dart` 的 `showSearchScopePanel` |

## live_ui 里加的东西

- `AppIcons`：搜索、网页搜索、观看记录用到的 17 个用途（`submitSearch`、`paste`、`allPlatforms`、`sort`、`webSearch`、`openDetails`、`searchStart`、`noResults`、`loadMore`、`searchHistory`、`clearAll`、`componentMissing`、`filter`、`filterOff`、`historyLimit`、`clearHistory`、`historyEmpty`），都是 v3 在该位置用的图标。
- `showAppMenu` 新加可选参数 `selected`（当前项主色加勾，计划书第 7 节），不传时和原来一样。
- `PageTitle`：顶栏两行标题（名字 17 号半粗，下一行 12 号次要色），A09.8、A09.9 用。

## 新设置项

无。“全部”搜哪些平台和搜索历史照旧存在 meta 记录里（`search.allExcluded`、`search.history`，键没改）。

## 门禁

- `search` 直接写的颜色和图标 33 → 0，`ui_baseline.json` 去掉这一项。
- 跨功能引用没有新增；`search -> settings/settings_model.dart`（代理设置跳到“网络”分组要用 `SettingsSection`）照旧。
- `logic/` 没有引用 material。

## 测试

`test/features/search/search_test.dart` 29 个（原 14 个，其中网页搜索路由的 1 个挪到 `web_search_test.dart`）。新增：每个平台都有不带平台名的一句范围说明；搜索框（焦点时圆角 24、回车键“搜索”、返回 / 粘贴 / 清除 / 搜索的顺序和图标、清除和粘贴互换）；竖屏排法（框、平台条、筛选区上下顺序，筛选顺序，单个平台时“继续网页搜索”换行、说明在下面两行）；852 和 1280 宽时框和平台条一行、框宽、说明在筛选右边一行、排序悬停提示；393 / 852 / 1280 的列数和“全部”标平台、单个平台不标；往下滑收起、往上滑出现；排序菜单（四项、当前项主色加勾、选后按钮变字）；搜索范围面板（竖屏底部、分组和数量、标签、最后一个不能取消、关闭后生效）；骨架和“还有 1 个平台在搜索…”、没结果和都没开播两种空状态的说明和按钮图标、加载完显示“已加载全部结果”；网页搜索传平台和关键词；缺 WebView2 时只在点网页搜索时问、点外面关、三个按钮的顺序和作用；滚轮横滚平台条；附录 A 第 14 条（右键 = 长按）；Esc 返回（打开时键盘弹出，搜索后再按 Esc 也返回）。

和新设计冲突、照实改的旧测试：“搜索范围 3/3”按钮去掉了（X3 A 合进说明行和面板），改为检查说明行文字；范围对话框改成面板（没有“确认”，关闭即生效）；网页搜索不再由搜索页直接开浏览器，改为检查传给网页搜索页的参数。

live_ui `app_menu_test.dart` +2（小菜单当前项、`PageTitle`）。全部：`apps/pure_live` 417 个、`live_ui` 69 个通过。

## 没做的

- 没有在真机和 profile 模式看帧时间（这次不安装）。
- 苹果平台（Cmd 快捷键）不单独处理：Esc 在 macOS 同样有效。
