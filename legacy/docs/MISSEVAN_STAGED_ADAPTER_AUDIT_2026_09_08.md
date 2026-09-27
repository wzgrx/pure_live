# 猫耳 FM 暂存适配与公开接口审计（2026-09-08）

本批为用户要求的平台扩展，不是已注册平台的缺陷修复。起点 `b02290fbccc04d21ecbf08b93084c25fdcfbf0b0`。
**仅暂存 API/站点适配器，尚未加入 Sites、设置迁移或入口；参考平台未注册数仍为15。**
不提升版本、不合并上游、不发布；本批没有手机、ADB、MT、Root/LSP操作。

## 来源与独立核验

只读比较两个冻结实现，没有执行或合并其代码：

- [bililive-go missevan.go](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/missevan/missevan.go)：提供房间 API、`status.open`、FLV入口及 `AudioOnly` 提示。未复制宽松路径拆分、所有非200/非零code均视为不存在的行为。
- [biliup missevan.rs](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/missevan.rs)：同一公开详情契约；未复制所有非零code视为下播、宽松host正则的行为。
- [猫耳 FM 官网](https://fm.missevan.com/)与其页面实际引用的[官方脚本](https://s1.hdslb.com/bfs/static/maoer-static/assets/fm/js/bundle.30d30c6d.js)：只下载为文本阅读，未执行脚本。核对 `/api` baseURL、目录参数、分类、详情、HTTPS转换，以及 `score` 的“热度”与 `attention_count` 的“粉丝”文案。

当地09-08、UTC09-07 16:15起做匿名HTTP/媒体元数据采样，没有注入账号Cookie/Token。
原始响应含临时CDN签名，保留在忽略目录 `local-artifacts/work/reverse-api/missevan-20260908/`，不进入Git。
`evidence-index.json`保留原始文件SHA256、字节数；审计仅记host/字段/结果，不公开签名URL。

### 公开请求合同

| GET路径（相对 `https://fm.missevan.com/api/v2/`） | 实测结果 | 本批处理 |
| --- | --- | --- |
| `meta/data` | 200/code0；5个父catalog、18个子catalog、6个首页tab | 暂以官网6个tab为分类：catalog与tag分开传递；子分类展示后续核验 |
| `chatroom/open/list?p=1` 与 `p=2` | 200/code0；`info.Datas`，声明pagesize20但实测20或22条，pagination包含p/pagesize/count/maxpage | 保留原生页码与全部返回条目，hasMore看p/maxpage，不按名义20条裁剪；每次1请求、最多100条及1MiB响应上限 |
| 同目录加 `catalog_id=104` | 200/code0，20条；响应catalog_id可以是子分类 | 按父筛选结果接纳，不错误要求每行catalog_id等于父ID |
| 同目录加 `tag_id=1` | 200/code0，20条 | tag和catalog不同命名空间，不互相替换 |
| `live/{room_id}` | 200/code0，info.room/creator/websocket/vtuber | 绑定请求房间及creator身份，只读room/creator；未接入websocket |
| `live/1` | HTTP404/code500030004 | notFound；其他未知错误保持失败，不伪造下播 |

公开列表中的 `status.broadcasting=false` 与 `status.open=1` 可同时出现，不能用前者过滤全部直播。
未知/missing/nonbinary open保持schema错误；明确open0才下播，忽略其所有旧channel URL。
`score`映射热度；`online=0`、`accumulation`不作为同时在线人数。只有详情有明确followers时才写入粉丝值。
搜索endpoint在脚本中出现于连麦/PK调用，尚未证明全站搜索语义；本批没有将其伪装为公开全站搜索。

### 媒体证据纠正

同一个公开音乐房间的HTTP地址，经官网相同的HTTPS转换后：

- FLV：`d1-missevan04.bilivideo.com`，200；只读13字节文件头时flags=5。
- HLS：`d1-missevan104.bilivideo.com`，200；359 B媒体列表，EXTINF存在。
- FFprobe分别以18秒总预算、5秒读超时、1MiB probe/3秒分析上限检查两个来源，都退出0、stderr为空：**AAC 48kHz双声道 + H.264 16×16**。

这是一个房间的外部FFprobe证据，不是所有猫耳房间的纯音频证明、应用首帧证明或FFmpegKit录制证明。
因此不复制参考实现的全平台AudioOnly强制值，也不从“FM”名称推断无视频轨；小尺寸画面/封面展示和真正无视频轨仍需验收。
采样记录 `media-probe.json`，资源记录 `20260907T162303322Z-missevan-media-contract.json`，7.533秒、结束活跃重型进程0。

## 真实接口揭示的分页反例

首轮59/59确定性测试通过，但生产API探针在目录处schema失败，记录
`20260907T163503131Z-missevan-staged-contracts.json`保留失败；当轮未进入analyze。
同时间公开HTTP对照显示主页 `pagesize=20` 却有22个Datas条目，category和p2各20条。

随后核对官方脚本 `ROOM_GET_LIST_SUCCESS`：对整份Datas转换并按room_id追加去重，滚动条件采用 `pagination.page < page_count` 后请求page+1。
这说明不能按固定20个条目计算跨页offset，也不应按trace中的推广字段猜测并删除两条。
修订为 `MissevanDirectoryPage` 保留rooms/page/maxPage/count与hasMore，每次读取一个真实服务器页，所有返回行在100条安全上限内保留并去重。
`directory(pageSize)`仅为暂存LiveSite兼容参数，不代表服务器支持客户端请求大小；正式UI接入必须使用原生分页元数据，不能直接使用30条阈值判断末页。
22条推广混合fixture覆盖19/20尾部条目保留、后续21..65无跳过、元数据终止条件。

## 暂存实现与不变量

- `lib/core/site/missevan/missevan_api.dart`：生产请求使用已有Dio，保留应用代理/超时基础；禁跟随API重定向；响应1MiB上限、20秒总body deadline、所有退出取消body订阅；注入式响应同样按UTF-8字节核限。
- 错误区分transport/access/rateLimited/service/notFound/schema/cancelled/qualityUnavailable。异常不包含响应正文或签名URL。请求前后检查取消，过期响应不提交为房间状态。
- 房间数字ID和链接精确host/path校验；CDN播放地址只接纳已见的bilivideo子域、HTTP(S)、默认端口、对应媒体扩展名；拒绝userinfo/fragment/重复或毫秒expires。
- HTTPS转换保留签名query并清除HTTP默认端口；质量ID为 `hls`/`flv`，标签只写协议，不虚构分辨率或音频码率。
- `missevan_site.dart`实现刷新/录制详情/同协议重新解析和lease元数据。`expires`按Unix秒解释；提前1分钟刷新与硬失效是不同字段。续签仍调用新详情，不重复使用旧quality.data。
- 不修改其他平台、全局播放器、录制器或持久化模型；没有新增第三方依赖。

## 验证记录

- 首轮：59/59确定性通过，真实探针因20声明/22实返反例失败，保留原始日志与上方记录。
- 第二轮：58通过、1失败，记录 `20260907T163932244Z-missevan-staged-contracts.json`。新增推广位fixture对泛型List调用insertAll时类型不匹配，传输注入边界把该异常归类为transport；补上明确Map列表类型后重跑，不是再次放宽API业务校验。
- 行为复测：59/59通过（猫耳27、相邻TwitCasting32）；生产Dio/API探针1/1通过，6分类、分类20房、首页22房、第二页20房、HLS/FLV、新详情刷新、expires和404分类均通过。见 `adapter-probe.json`（UTC16:41:42），没有获取媒体片段或执行StreamResolverService/原生录制。
- 记录 `20260907T164254996Z-missevan-staged-contracts.json` 的unit/probe均0，但analyze有1条括号风格info，整体记录保持failed；为该if补花括号，无行为变化，不重复网络或整批测试。最终四文件analyze无诊断（51.7秒），记录 `20260907T164503960Z-missevan-staged-style.json` succeeded；含资源守卫全过程82.249秒、结束活跃重型进程0。

reverse-api-engineer CLI已核对0.13.0/schema1并执行dry-run；没有运行其外部agent、生成客户端或捕获HAR。
`cli-preflight.json`中的run/HAR/script均未产生，实际证据来自上述直接公开HTTP与官方源码，不标记为浏览器HAR回放。

## 尚未关闭的接入门禁

1. 消费原生目录分页元数据的UI分页桥接（包括筛选后少于20条但hasMore仍true）、Sites注册、平台默认配置迁移与用户排序保留、链接识别、搜索能力/UI声明、热度能力表及平台图标。
2. 播放/录制headers与现有代理、StreamResolverService、签名续租调用链的集成测试；目前外部探针不替代应用代理验收。
3. FFmpegKit原生录制、完整严格解码、停止/转封装/源文件保留、音频模式/前后台/封面与16×16视频表现；真正无视频轨另外测。
4. 公开离线房间与结构漂移样本补充；本批离线是确定性fixture，不是实测离线房间。目录跨请求会动态变化，测试只保证静态页算术与页内去重，不承诺实时列表无重排。
5. 搜索、弹幕协议、子分类、Android及Windows原生验收仍待完成。

以上完成相应合同后再开放入口并更新平台数量；不是现在就宣布“猫耳已接入”。
回滚可移除本批两个适配器与其测试/探针，不涉及用户数据或当前候选APK。
当前Android待安装候选继续为b5f39c2b，当前已验证安装仍80b7431c；本批没有构建新包。
