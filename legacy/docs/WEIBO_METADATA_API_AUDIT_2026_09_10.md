# 微博直播目录/状态合同与一直播访问审计（2026-09-10）

## 基线与范围

基线 `c2c437ec8abdd43c2e97572bc7537123a4a388a2`。新增微博直播底层元数据 API、脱敏夹具和 opt-in 生产探针，尚未注册 LiveSite。没有合并上游，没有更新版本、构建、发布或操作手机。

## 冻结参考与当前官方证据

只读比对 [bililive-go 微博适配器](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/weibolive/weibolive.go)，blob `e36041af3c90e4e280bf8a26cdb2fbe5f9976198`。其路径数组检查只检查长度小于 5 后读取下标 5，且会以 q 参数重写质量 URL；本项目本批不移植此路径解析或猜测画质，不宣称已经修复参考仓库。首次请求误用了 weibo/weibo.go 路径得到 404，随后从冻结树确认真实 weibolive 路径并核对 blob，未将 404 内容当源码。

2026-09-10 11:02–11:10 UTC，读取[官方旧房间入口](https://weibo.com/l/wblive/m/show/1022%3A2321325147123120210016)、其 301 指向的 PC 页面与页面明确预取的 [live.js](https://js.t.sinajs.cn/t6/apps/live/livepc/js/live.2c216a65.js)。静态读取，没有执行下载的脚本或访问购买、关注、点赞接口。

| 请求/合同 | 当前观察 | 解释边界 |
| --- | --- | --- |
| `/l/wblive/`，Clash 7897 | HTTP 200，正文 0 B | 不是有效目录，不把空壳算成功 |
| 旧 m/show，DIRECT | HTTP 301 指向同源 p/show；后者 HTTP 200/1531 B，is_login=0 | 单独跟随已核对跳转；不是登录态 |
| 旧房间 `show_pc_live.json` | HTTP 200/code=999999/error_code=20003/data=[] | API 错误，不是下播 |
| `pc_recommend/list.json?count=10&uid=` | HTTP 200/code=100000/error_code=0；data.data 9 行 | 有限推荐快照，不推断分页、总数或观看人数 |
| 第一条推荐对应详情 | HTTP 200；liveId/UID 匹配；status=1、watch_limit=0、pay_live_status=1、play_switch=1、1280×720 | 公开元数据与声明在播，不是完整播放证明 |
| 详情两个媒体字段 | live_origin_hls_url 与 live_origin_flv_url 同指 FLV | 字段名字不是 MIME/协议保证，不生成不存在的画质 |
| 声明媒体前缀 | HTTP 200 忽略 Range；64 KiB 上限停止，curl=63；FLV 魔数成立 | 有界前缀证据；保留非零退出，不算完整解码/实录通过 |

除表中首页外，以上官方读取均 DIRECT；原始 HTML、JS、JSON、头、媒体前缀与 SHA-256 清单存于忽略目录 `local-artifacts/weibo-public-20260910/contract.json`。媒体与图片时效地址不进入 Git。一次组合命令的 PowerShell 正则引号解析失败发生在请求执行前，修正为 here-string 后才取得 PC 页面。

官方播放器严格以 code=100000 开始使用详情；status=1 走直播、3 走回放，play_switch=0 单独处理；watch_limit、pay_live_status、试看片段和仅 App 分支参与访问控制。新层保留这些区分，非公开状态不输出媒体。已付费账户接入属于后续会话合同，本批匿名层对所有非零 watch_limit 保守标注 restricted，不推断用户权益。

## 实现与测试边界

- [API](../lib/core/site/weibo/weibo_api.dart)分开保存 broadcast liveId 和主播 UID，优先校验请求身份/预期 owner；未知状态不猜离线。
- 返回有限不可变目录，空图片保留；严格成功 envelope/字段类型，HTTP、业务、身份、结构、取消分开。
- 实际两个相同 URL 去重，保留不同 URL 和查询串；没有根据字段名写死 HLS，也没有 q 后缀替换。回放/播放关闭/受限状态不输出直播 URL。
- 复用共享 Dio 与请求取消作用域；独立 transport token、总截止时间、1 MiB 严格 UTF-8 流读取、订阅清理，迟到结果不污染调用方。
- [夹具说明](../test/fixtures/weibo/README.md)明确哪些来自捕获、哪些来自官方分支的合成变体。直播成功和旧链接错误是真实合同；回放/限制样本尚非本次现网观察。
- [确定性测试](../test/weibo_api_test.dart)验证身份、双格式去重、访问优先级、失败分类、超时/取消/正文释放；[探针](../tool/probes/weibo_metadata_probe_test.dart)只读生产 API，临时独立 DIRECT Dio 并 finally 恢复，不读取媒体或保存用户会话。

## 验证结果

两阶段均通过，去重覆盖 **155 项**，其中本批新增确定性 **54 项**和真实生产探针 **1 项**。不把重复运行的生命周期用例叠加成新覆盖：

| 阶段 | 实际结果 | 记录 |
| --- | --- | --- |
| 确定性与相邻回归 | **154/154**：微博 48、既有 Bigo 40、共享 Dio 生命周期 66（新增微博 6）；API/新增单测两文件严格分析无问题 | `20260910T112640803Z-weibo-metadata-first.json` |
| 真实探针与传输复验 | **67/67**：真实生产探针 1 + 上述生命周期 66；探针/生命周期测试两文件严格分析无问题 | `20260910T113928578Z-weibo-metadata-production.json` |

真实探针于 **2026-09-10 11:34:14 UTC** 通过生产 WeiboApi/Dio 发出目录和详情 GET，两次 HTTP 200；9 行目录、broadcast/owner 均匹配、access=public/state=live、去重后 1 个声明媒体 URL。没有媒体解码或录制，mediaValidated=false。该探针重新取得当前目录和详情，不复用早先 curl 响应冒充生产网络。

第一阶段含资源排队耗时 1015.243 秒，峰值 CPU 28.43%、工作集 12341456896 B；第二阶段 697.861 秒、峰值 CPU 47.2%、工作集 12229611520 B。第一阶段结束活跃重型进程为 0；第二阶段结束快照仍为 2，因此不声称全机后台已归零。排队时保留原运行句柄，未重启测试或终止其他任务的搜索/Java 进程；没有 Flutter 测试或分析失败。提交前四份 Dart 文件哈希逐一匹配通过记录。

忽略目录 `local-artifacts/weibo-metadata-20260910/` 保留运行脚本、日志、首阶段输入哈希、探针报告和续接检查点。后续接线仍需按新变更做相应验证；这不是平台注册或全目标验收通过。

## 一直播仍需有效现网输入

[冻结一直播实现](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/yizhibo/yizhibo.go)，blob `ba85cfd0167ce71155cc09a8aeb5ebd6be16c179`，旧合同 GET `http://www.yizhibo.com/live/h5api/get_basic_live_info?scid=…`、result=1/status=10 与网页 play_url。实际只做官网主页访问：DIRECT curl=6 DNS 失败；Clash 7897 curl=28 连接超时，均无 HTTP 响应。没有据此判定停运，也没有把搜索中的相似 .net 域名直接当官网替换。

reverse-api-engineer 0.13.0/schema 1 对一直播任务 dry-run 成功；没有启动代理、生成客户端或运行另一模型，run_id/har_path/script_path 均 null。原件保留在 `local-artifacts/yizhibo-public-20260910/`；这些访问结果不阻断其他平台开发。

## 剩余工作

微博直播还需完整媒体解码、播放/录制输入、精确分享路由和直播/用户身份续播策略、LiveSite 注册及导航/搜索/收藏/双语/迁移、双端原生验收。当前仍为 20 直播站点 + IPTV、7 组未注册、历史宏观 42 组未闭环；本批不缩减这些范围。48154d15 Android APK 不包含本批或最近音量修订，版本保持 3.1.8+4121；完整验收后再发布全平台 3.2.0。

回滚只需撤回本批 API/测试/探针/夹具及记录，没有配置迁移或用户数据变更。
