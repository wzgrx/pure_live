# niconico 原生分类目录与关键词搜索（2026-09-10）

## 目标与当前边界

基线 `637c7c856b4ad8f83fd3bb170fe363c4f5020444`。上一轮完成 watch 元数据、画质发现及 owned 播放配方；本轮接入真实分类目录和关键词搜索。未合并上游，未把目录适配的局部测试当作平台注册、双端 GUI 或完整验收。

## 来自实际页面和接口的合同

官方 [recent 页面](https://live.nicovideo.jp/recent) 和 [搜索页面](https://live.nicovideo.jp/search?keyword=%E3%82%B2%E3%83%BC%E3%83%A0) 的脚本提供当前调用方式，原始响应、脚本 URL/字节数/SHA-256/采集 UTC 保留于 `local-artifacts/niconico-directory-20260910/http-evidence.json`。仅阅读脚本，不执行下载的代码。

- Recent 请求 `/front/api/pages/recent/v1/programs`，`tab`、`offset`、`sortOrder=recentDesc`；`offset` 是从 0 开始的页编号，不是行偏移。页面声明每页 70，实际两页均返回 70。总数位于 `meta.totalCount`，节目列表在 `data`。
- 官方脚本的七分类：`common`、`try`、`live`、`req`、`face`、`totu`、`vtuber`。其中 `live` 表示游戏，不是全站直播。七入口均实际 HTTP 200；综合是默认分类，不将其命名为全站榜单，双语常驻范围提示明确这一点。
- Search 请求 `/front/api/pages/search/v1/programs`，关键词、`column=main`、`status=onair`、从 1 开始的 `page`，`disableGrouping=true`。每页 40，实际第一页和第二页均返回 40；数据在 `data.programs`、总数在 `data.totalCount`。
- 空关键词搜索和仅频道过滤的空关键词搜索实测 HTTP 200、总数 0。因此不使用空搜索代替目录，不宣称空结果意味着 niconico 没有直播。未接入回放/预约/主播历史或相关主播列表，也不将搜索页面旁栏内容混入关键词结果。

## 实现

`NiconicoApi` 复用现有有界流式正文、请求期限、取消和 HTTP 错误映射，listing 入口仅接受已观察到的两个路径。`NiconicoDirectory` 分别校验两个响应信封，保留服务端总数分页信息，不用短页推断结束；验证节目 ID 与分享链接身份、正在直播状态、来源类型、标题、归属和非负累计观看次数。图片沿用经过校验的公开图片地址，动态截图优先；未知观看次数保留空值。

`NiconicoSite` 实现已有 `LiveSiteDirectoryPager` 与 `LiveDirectoryNotice`，目录按调用者传入的取消令牌隔离；分类页输出七个双语名称。旧列表接口保持服务端每页 70/40 边界，不根据界面的 pageSize hint 切片而跳行，参数仍有上限校验。原生 pager 提供 hasMore，搜索控制器既有逻辑按非空新增结果推进，而不是强制每页 20。不建立共享游标/节目缓存，不分配 watch seat，不保存凭据。

## 定向验证

四文件 **127/127 PASS**，其中新增目录合同测试 **35 项**；六 Dart 文件严格分析 **No issues found**。记录 `local-artifacts/build-records/20260910T071329754Z-niconico-directory-initial.json`。覆盖原生页偏移、40/70 条页边界、Unicode 关键词、七分类与外站分类隔离、服务端总数分页、取消/期限/迟到响应、HTTP 错误、重复/错配身份、非法信封及图片/人数语义；并回归既有 watch/API、Site 和质量发现。

耗时 467.19 秒，包括其他工作区活跃 rg 的资源排队以及编译/分析/收尾。共享资源峰值 CPU 31.79%、工作集 11284021248 B，终态活跃重型进程 2。未终止其他工作区任务；守卫和监控按 finally 收尾，缓存保留。无本地化上下文的 headless 测试输出键名警告，另行核对中英文词典中本批八键存在，不把静态词典核对视为双端文案布局验收。

## 外部响应回放与生产验证

Opt-in 探针 **2/2 PASS**：第一项将 13 份实际保存响应（415 个节目条目，含有效空搜索）送入生产 parser；第二项于 2026-09-10T07:16:55.369342Z 通过本机 Clash 127.0.0.1:7897 执行实际七分类、综合第二页及关键词「ゲーム」两页，十次请求全部解析成功。分别返回综合 70、创作与挑战 24、游戏 70、视频介绍 6、露脸 48、连麦 13、VTuber 37、综合第二页 70，以及关键词两页各 40。其余分类为末页，综合、游戏及关键词响应仍有后续页；以实际 totalCount 推导，非猜测。

记录 `local-artifacts/build-records/20260910T071708310Z-niconico-directory-production.json`，报告 `local-artifacts/niconico-directory-20260910/20260910T071338058Z-production.json`；本轮生产请求耗时含编译与资源排队 209.92 秒，终态活跃重型进程 0。请求只涉及公共节目目录，没有 watch seat、媒体解码、账号登录或凭据修改；探针 finally 还原测试 Dio 实例并关闭本轮 HTTP 客户端。所有来源/记录/修改文件哈希汇总于 `local-artifacts/niconico-directory-20260910/evidence.json`。

## 待续与回滚

待完成：平台注册、搜索能力表与网页跳转、分享输入路由、设置迁移/能力审计、质量发现的页面取消链，以及新候选 Android/Windows 原生界面与真实长录。目录和搜索的实时排序不是快照，跨请求节目变化仍可能导致跨页重复；控制器既有按身份合并行为仍需随平台注册验收。保留总目标的其他站点、所有功能/性能验收、全平台 3.2.0 构建/签名/发布及文档交付。

保持 19 站点 + IPTV、8 组未注册、42 组未闭环；版本与 Android/Windows 候选不变。本轮未操作手机、安装、构建、发布，也未变更 ADB/Root/LSP/MT 或系统代理。回滚撤回本批目录/parser、Site 目录入口、API listing 抽取和相关文案/测试；保留已验证的 watch/session/owned 消费路径。
