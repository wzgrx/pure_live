# CC 迁移取证与分类分页修订（2026-09-08）

## 结论边界

[上游 #855](https://github.com/liuchuancong/pure_live/issues/855)关联的网页/分类迁移已证实，但本批没有取得其所述停运公告原文，也不从部分接口 200 推导全站运营状态。**分类房间分页已有源码修订，分类总目录迁移仍未完成。** 保留 CC 平台、旧分类收藏和房间 ID，没有整体删除平台、导入配置或修改用户数据。

初始源码 `f86b22f0`。旧分页实现与本地冻结上游 `c6c9bd70aedc503c003110dae10a83ad0bb891d8` 一样，每页读取固定 Next.js 首屏，没有使用 page/pageSize，且解析失败返回空集合；分页问题归为 `upstream-existing`。总目录响应变化归为 `external-drift`。本轮只读比较相关方法，没有 fetch/merge/push。

## 官方输入链（2026-09-07 23:40–23:45 UTC）

1. [大神直播页](https://ds.163.com/glive/)的 HTML 引用 umi 与 runtime 资源；路由分块 [p__glive](https://g.166.net/res/a19/p__glive.49dd25a7.async.js)显示这是游戏入口加 CC iframe，而非整个 CC 后台消失。
2. 页面调用 `GET https://inf.ds.163.com/v1/web/game-center/basic/base-info-list/by-type?gameType=NETEASE`，本次返回 **106 个游戏元数据**。这不是 106 个直播分类。
3. 页面读取配置的 `POST https://inf-act.ds.163.com/v1/act-web/pageConf/commonAppConfig`，body 为静态公开配置 ID `67b32cdd1801fc391a6c2657`。本次匿名响应中直播入口共 **23 项：20 个 `/n/ds_category/<gametype>/`，3 个房间/专题入口**，均有匹配的游戏 appKey 元数据。POST 在这里是配置查询，不是账号写入；没有登录、Cookie、关注、购买或签名仿造。
4. CC 新分类页的 `__NEXT_DATA__` 中，分类 3 首屏 4 条、分类 1005 首屏 2 条；这些是初始化展示，不是分页合同。一个专题入口 249133 的初始化数据实际含业务 302 与 NBPL 活动跳转，不把三个房间/专题项伪装成普通分类。
5. CC [当前分类组件](https://livestatic.cc.163.com/_next/static/chunks/5765-c9280773faeb076c.js)使用 `GET /api/category/<gametype>/?format=json&tag_id=0&start=<offset>&size=<size>`。正文分 `lives`、`videos`；官网在直播不足一页时可能补视频，本项目直播列表不混入视频。
6. Next.js build manifest 仍列 `/category`；按其 nextjs build 读取 `/_next/data/nextjs/category.json?format=json` 得到 HTTP 200/JSON，但 **pageProps.categoryData 是大神 HTML 字符串**，不是 game_list。该字符串 SHA 与大神首页相同，不能把换一个 Next.js URL 当作总目录迁移完成。

直接 API 采样：分类 3 的 start=0/2、size=2 分别得到 2/2 个不同房间；分类 1005 得到 2/0，分类回显一致。没有取流、媒体字节或原生播放/录制证据。

### 工具和浏览器范围

reverse-api-engineer 0.13.0 / schema 1 与本任务 dry-run 成功；dry-run 提示所选外部 SDK 凭据未配置。没有启动外部代理流程，run_id/har_path/script_path 均为空。上述结果是直接 HTTP、静态源码和手写探针，不是 HAR 或生成客户端。

大神浏览器页创建被站点策略拒绝；没有创建成功的页面，也没有换浏览器、CDP 或其他渲染方式。大神静态文件/两个配置响应均在该尝试之前取得；其后仅验证独立 CC 数据接口与本地代码，不将这些结果充作大神浏览器渲染验收。

原始静态资源、响应、来源 URL/时间/哈希、脚本和派生摘要位于忽略目录 `local-artifacts/cc-migration-20260908/`。原始媒体字段不进入 Git。关键 SHA：大神 HTML `7d687bcc3f67fe0abf09aa8fab918b7dc13de3ded135da9cf12c3270bbc9769d`；入口配置 `d8d86c33395ea8b8008827b3f599a351f163326991103e93d363f1ccda5bd4aa`；CC 分类组件 `2ee38afb6206d8b578cde3f1dc12987381ca2ddc5002df2df70b9351dca2b829`。

## 应用修订

源码提交 `06f92b44877121ba32c460d24f22bd7d35e4f4ca`，仅本地提交。

`CCSite.getCategoryRooms()` 现在直接消费当前分类 API，start=(page-1)*pageSize。已有收藏的 areaId 保持原数字 ID，父类别和显示名称不参与请求身份，也不写回用户对象。

- 请求前校验分类、平台和分页范围；响应校验分类回显、lives 容器及房间 ID。错误/HTML/错分类不再当正常空页返回，合法空 lives 仍返回空集合。
- 只解析 lives；不保留原始播放字段。继续分别保留热度与在线观众；状态 1/0 对应 live/offline，其余为 unknown，不一律标在播。
- 分类房间名称兼容 game_name/gamename。没有修改播放画质、房间详情、录制或播放器生命周期。

总目录 getCategores 尚保留旧路径与四个空父分类处理，本批明确不把它列为通过。下一步需完成新官方入口的分类/专题差异建模、旧 ID 与父类型兼容、失败/空状态提示及实际分类导航，不能仅用 20 项覆盖 23 项或将 106 个游戏全当直播分类。

## 验证

应用源码不变时，实际 CCSite + Dio 测试适配器的 **12 项中 10 个红项、2 个通过**，记录 `20260907T234757523Z-cc-migration-red.json`。测试同时提供旧 SSR 和新 API 结构，页 2 错误来自旧请求仍读首屏，不是遗漏旧接口夹具；其余覆盖分类错配、HTML、缺少身份、无效分页及元数据。

修订后原断言未放宽，四个测试文件 **20/20 通过**；三文件 analyze 无诊断（29.2 秒）。生产 CCSite 公开探针 **1/1 通过**，2026-09-07 23:50:26 UTC 分类 3 为 2/2 条、分类 1005 为 2/0 条，请求 offset 确认为 0/2/0/2，旧父类型 2 保持。探针使用匿名直连 Dio；应用代理配置、目录 UI 和原生端没有由此验收。

公开探针启动的既有 FFmpegKit build hook 报告远端 SHA 查询缺失；本次没有运行 FFmpeg、构建或验证原生分发工件，不把 API 测试通过当作该原生供应链校验通过。正式候选仍需独立工件门禁。

成功记录 `20260907T235030878Z-cc-category-green.json`：110.768 秒，峰值 CPU 9.43%、工作集 13,563,551,744 B，结束活跃重型进程 0。与红测分开保存，最终输入由 `validation-source.json` 绑定。版本仍 3.1.8+4121；没有新候选、手机操作或发布。Android/Windows 旧候选不含本批，3.2.0 保持完整验收后发布的要求。
