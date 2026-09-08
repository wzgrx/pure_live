# OPENREC / mellow-fan 公开合同与底层 API（2026-09-09）

## 范围与来源

本批从 `5075948c76d80c35cb89177c1510c1abb313bbd0` 推进参考平台扩展；不是既有
Pure Live OPENREC 功能的回归修复。当前仅新增底层 API、脱敏夹具与探针，**尚未注册应用入口**。
源码仍为 **16 个直播站点 + IPTV、11 组参考平台未注册**。没有合并上游、更新依赖、修改版本、
构建、发布或操作手机。现有 Android 候选 1d318bba 和 Windows 候选 f3de664a 保持原样。
实现提交 **`37bdd9c941fc3f3a797806bea211d29cfced82eb`**。

- [官方更名公告](https://openrec.co.jp/news/8667979283)于 2026-06-19 公告 7 月 1 日将
  OPENREC.tv 更名为 mellow-fan；[官方服务页](https://openrec.co.jp/service)已链接新站。
- [冻结 bililive-go 参考](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/openrec/openrec.go)
  使用旧站 HTML 正则和首个 m3u8，把非 200 归类为房间不存在。本实现不沿用该错误分类或正则。
  本地参考 `local-artifacts/openrec-20260907/reference.go`，1893 B，Git blob
  `a5edb128ad461ba602b987ca131de7a21f0e7af2`。biliup 的冻结内置树未列 OPENREC。
- 新合同来自匿名 GET 的实际响应，而不是把参考 README 的平台名称当作当前功能可用证据。
  reverse-api-engineer 0.13.0 只完成 CLI/dry-run，未启动自主代理、生成 HAR 或执行生成客户端。
  隐藏浏览器首页返回 CloudFront 403，没有把远端 web 工具的页面成功记成本机代理通过。

原始取证在 `local-artifacts/openrec-public-20260908/`。目录名沿用起始日期；
15:xx UTC 为北京时间 09-08，16:xx UTC 已为 09-09。原始响应和带时效的媒体路径保持忽略状态；
五份提交夹具只保留必要字段并替换频道、数字身份、标题、头像、封面和媒体路径。

## 实测合同

| 请求或字段 | 证据与决策 |
| --- | --- |
| `GET https://public.mellow-fan.com/external/api/v5/movies` | `is_live=true&onair_status=1&page=1&limit=1&sort=live_views` 返回 JSON 数组；page 2 为空，page 0 为 400；默认 limit 30 的样本只有一行 |
| `GET /channels/{publicId}` | 大小写保留的公开 ID 返回频道和 `onair_broadcast_movies`；已知 `openrec_user_id` 与 `recxuser_id` 用作同一路径均为 404，未假设数字 ID 可直接寻址 |
| `registered_user_id` | 实测是 boolean，不是稳定数字身份；保留 public ID 作为查询键，另用 `openrec_user_id` 核对频道归属，支持调用方传入预期数字身份 |
| `GET /movies/{movieId}` | 返回单个广播对象，重新匹配请求广播及频道；每次 room 解析重读频道当前广播，不缓存上一场的播放地址 |
| 频道明确离线 | 官方服务页关联的公开频道实测 `is_live=false` 且 `onair_broadcast_movies=[]`；只有一致状态返回离线，直播标记与空列表不一致时报告异常 |
| 不存在的频道或广播 | 404 JSON `{message, status:-4}`；与 401/403、429、5xx、损坏响应分开，均不升级成频道离线 |
| `onair_status=1` 与未来 `ended_at` 同时存在 | 以明确的直播状态为准，不用非空结束时间推导下播；`live_views` 与累计 `total_views` 分开，隐藏人数保持未知 |
| 原始分页 | 数组没有 hasMore 包装；生产探针请求 limit=1 却返回 2 行，说明请求条数不是可靠页长；只有明确空原始页才结束，不使用过滤后的卡片数或请求 limit 推导末页 |
| 多个当前广播 | 保留广播列表；room 在未有明确选择策略时报告 ambiguous，不猜第一条，也不替换成推荐主播 |
| 订阅、PPV、加密、隐藏、封禁、过期或首映 | 元数据与媒体权限分开；保留可读取的身份，不将试看、回放或音频字段当作完整直播源 |

当前频道查询依赖公开 ID；频道改名后的持久收藏恢复尚未有合同证据，数字身份校验不是自动改名恢复。
初始只有一行在线目录，后续生产探针返回两行；这仍不足以证明全站目录覆盖、频道过滤、
所有直播模式或订阅功能完成。

## HTTP 头与媒体证据：修正首轮解释

首轮普通主列表、低延迟主列表及子列表不带 Referer/Origin 时返回 401。
这**不是已证明的登录或订阅要求**：补齐相同 `User-Agent: Mozilla/5.0`、
`Referer: https://www.mellow-fan.com/`、`Origin: https://www.mellow-fan.com` 后，匿名请求得到：

| Clash 请求 | 结果 | 本地证据 |
| --- | --- | --- |
| `media.url` 普通 HLS | 200 / 1195 B；5 档，最高声明 1280×720、60 fps、H.264/AAC | `clash-url-with-headers.*` |
| `media.url_ull` | 200 / 233 B；主列表引用 ull01.openrec.tv | `clash-url_ull-with-headers.*` |
| `media.url_public` | 200 / 256 B；声明 640×360、30 fps | `clash-public-master-v2.*` |
| 公开 HLS 的子列表 | 200 / 603 B；5 个 2 秒分片引用，无 ENDLIST | `clash-child-with-headers.*` |
| 新域目录 API（同样的头） | **403 / 919 B** | `clash-list-with-headers.*` |

因此 API 返回三个源族，不预先降级为公开低清流，不虚构清晰度或编码实测。
后续播放/录制需要把这些头传递至主列表、子列表和媒体请求；测试尚未拆分 Referer 与 Origin
各自作用，保留已验证的组合。尚未获取媒体分片或测试完整解码，不把主列表 200 当作原生播放通过。
媒体 API 不改写 URL，不将 `subs_trial_media` 或未知地址作为回退。

Clash 7897 监听由本机 verge-mihomo 持有。本批仅显式指定单次请求的路由，
没有修改系统代理、Clash 选择器、应用设置或自动降级到 DIRECT。
目录 API 的代理路线仍待解决；直连元数据成功与代理媒体成功不是一条完整的代理播放链路。

另一次 archive-list 虽 HTTP 200，但原始字节在 UTF-8 字符中间结束，JSON 不完整，
该响应未用于回放合同或注册能力。夹具补截断 UTF-8/JSON 错误测试；未把控制台编码问题或
HTTP 状态独立解释成有效 JSON。

## 实现、验证与余项

实现位于 `lib/core/site/openrec/openrec_api.dart`，使用共享 Dio 和独立请求取消作用域：
无重定向、2 MiB UTF-8 字节上限、20 秒读取总期限，错误/超限/取消均收尾，
保留调用方令牌和共享客户端。HTTP 错误只暴露类别，不泄漏上游正文或带时效的地址。

首轮 **28/28** 定向测试通过，三文件分析报告 10 处多行 if 的括号风格提示（退出码 0 不代表
No issues）。补括号后 **28 项定向 + 1 项直连生产探针 = 29/29**、三文件分析 No issues found。
同一批的 **Clash 生产探针 0/1，access 失败**，不计为通过。
记录 `local-artifacts/build-records/20260908T162701706Z-openrec-api-final-and-routes.json`：
585.901 秒，峰值 CPU 73.24%、工作集 72,507,109,376 B，结束活跃重型进程 0；
这些是共享重型进程观测值，不是 App 性能。

真实直连探针记录 `production-direct.json` 的 rawRows=2、requested limit=1、nextPageRawRows=0，
推动修订草稿中 `rows.length >= limit` 的推导。新增短页/超请求条数页继续及分页边界回归，
改为只有空页结束。未宣称发现了现网丢失的第二页，
本次修订消除的是未经证据支持的服务端页长假设。

最终 **30 项确定性测试 + 1 项真实直连生产探针 = 31/31**，三文件 analyze **No issues found**。
这是最终重跑总数，不与首轮 28 或中间 29 重复相加。`production-direct-final.json` 记录
requestedLimit=30、rawRows=2、hasMore=true，随后实际第二页为空；频道与当前广播、数字身份、
三种源族及刷新匹配均通过。并未下载媒体或验证注册适配器。

最终记录 `local-artifacts/build-records/20260908T163532759Z-openrec-api-pagination-final.json`：
396.928 秒（含等待另一 Java 重型任务结束），峰值 CPU 56.36%、工作集 13,242,695,680 B，
结束活跃重型进程 0。`pagination-final-source.json` 的三个 Dart 工作文件哈希在提交前重新匹配。
所有验证父会话均取得退出结果，没有因观察超时重启任务。保留 FFmpegKit 既有的远端 SHA
元数据缺失提示；它不构成原生依赖重新校验通过。

Clash 的 HTTP 403/typed access 位于分页解析之前，本次仅修订成功页的继续条件，
故保留此前独立失败证据，没有为这两行逻辑重复探测或把 proxy 测试遗漏解释为通过。

复现入口为 `test/openrec_api_test.dart` 与 `tool/probes/openrec_public_contract_probe_test.dart`。
后者默认跳过，显式设置 `PURELIVE_OPENREC_CHANNEL`（当前公开在线频道）、
`PURELIVE_OPENREC_ROUTE`（`DIRECT` 或 `PROXY 127.0.0.1:7897`）及可选
`PURELIVE_OPENREC_OUTPUT` 后，通过构建资源守卫串行运行固定 SDK 的 Flutter test。
代理错误会让探针真正失败并保存 failure 类别；程序不将它变成成功的跳过或直连重试。

尚需：应用注册及新旧域名分享、公开 ID/数字身份持久化策略、多广播选择、HLS 真实画质/线路、
头部贯穿播放/录制、代理目录失败反馈、续期与短录解码、双端原生交互；搜索、分类、弹幕、订阅
和特殊模式继续逐项核验。原生 42 个宏观未闭环项和 32 组候选场景均未因此提升状态。

另外只读查看 Picarto 的旧流读取实现发现其尚未复用请求取消作用域，需后续单独复现错误/超限
的上游收尾与总期限；本批没有顺手修改无关平台或把静态疑点直接记为已确认缺陷。
