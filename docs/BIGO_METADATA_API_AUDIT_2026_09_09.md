# Bigo 目录与受限状态 API 审计（2026-09-09）

实现 `cf704d5fd1f6372ecd2c692d496e968f81542f23`，基线 `17d9c4845b9cc2ab5ea91045c1a7fb7d8efa2562`。本批只新增底层目录/状态 API、脱敏夹具和 opt-in 生产 HTTP 探针；**尚未注册 Bigo，不声明播放或录制支持**。

## 证据与实际合同

只读比对 [冻结 biliup 适配器](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/bigo.rs)（blob `d46b223d2fa9b193c5d9f1638e2f13cfe2584e6b`），没有合并或执行参考代码。参考直接取 URL 末段、POST siteId，只处理单个 HLS，并把多个异常条件归为 Offline；本批不照搬该状态判断。

2026-09-09 06:19—06:23 UTC，经本机 Clash 7897 读取 [官网](https://www.bigo.tv/)、[请求实现](https://www.bigo.tv/_nuxt_cdn_/app.4addcc.js)、[首页调用](https://www.bigo.tv/_nuxt_cdn_/pages/index/index.dc1082.js) 和 [播放器状态实现](https://www.bigo.tv/_nuxt_cdn_/14.1716ef.js)。脚本下载跟随已观察的官方静态站重定向，没有执行脚本。reverse-api-engineer 0.13.0 只运行 dry-run；没有启动其代理、改模型或产生 HAR，合同来自手动 HTTP 与静态 JS 阅读。

| 调用 | 当前观察 |
|---|---|
| GET `ta.bigo.tv/official_website/OInterfaceWeb/vedioList/72` | 官网 US/en 首页参数 `tabType=00,fetchNum=10`；HTTP 200，code=0、data.resCode 字符串 `0`，返回 20 行；没有分页标记 |
| POST `/official_website/studio/getInternalStudioInfo` | 表单 siteId、supportHevc=0；HTTP 200，返回 uid 与目录 owner 一致，canonical alias 可与请求 siteId 不同 |
| 同路径，仅参考代码的 siteId 表单 | 同样 HTTP 200、needLogin=true、alive=0、空 hls_src/cdn_src；不是缺少 supportHevc 导致的差异 |

所选目录房间显示未锁定，但状态响应要求登录。官方播放器在 alive 分支之前处理 needLogin；因此 **该样本的 alive=0 保留为未知，而非下播**。该观察只针对当前样本，不概括全站所有房间。没有获取登录凭据或付费媒体，也没有有效媒体 URL/分片样本。

## 实现与首轮真实失败

- 目录独立保存 public siteId、owner、sid 和 int64 broadcast ID，原始 viewer 值与未知值分开；不会把 room_flag 当直播状态。Web 超出精确整数范围的广播 ID 显式失败，原生保留整数十进制拼写。
- 只实现已观察的有限首页快照，不假设 fetchNum 是响应长度或末页条件，不伪造全站搜索/分页。
- 首轮 76 项确定性测试通过，但实时生产探针在目录 cover_m 失败。保存的同批官方目录 20 行中有 2 行封面为 null；原实现将封面视为必填字符串，属于本批新代码的合同遗漏。修订为可空封面并新增回归，仍拒绝非空非字符串，不因缺图丢失房间或虚构图片。
- 状态先核对 owner，再区分 loginRequired、restricted 与 public；非公开状态的 reportedAlive 为 null。公开布尔分支目前只有合成夹具，不充当实际在线/离线或可播证明。
- 固定 API origin 和路径、Origin/Referer、表单编码；复用共享 Dio 路由，禁止自动重定向。独立 transport 令牌、总时限、1 MiB 严格 UTF-8 响应上限及订阅收尾；取消和迟到错误回归不影响调用方及并行请求。HTTP/API/结构/身份失败与直播状态分离，异常不含响应原文。
- 新增测试 `test/bigo_api_test.dart` 与探针 `tool/probes/bigo_metadata_probe_test.dart`。后者临时使用独立 Dio+Clash 运行生产 BigoApi，finally 恢复共享客户端并关闭自有客户端；日志只保留合同结果，不保存媒体签名或账号内容到 Git。

## 验证账本

| 记录 | 结果 | 总耗时 / 峰值 CPU / WS |
|---|---|---|
| `20260909T063216287Z-bigo-metadata-green.json` | 76 项确定性测试通过，在线探针 **0/1**：可空 cover_m 未处理；testExit=1，分析未执行 | 99.45 秒 / 9.09% / 7,129,632,768 B |
| `20260909T064017616Z-bigo-metadata-green.json` | **78/78**：38 项 Bigo + 39 项 TTing 相邻回归 + 1 项在线探针；三文件 `analyze --fatal-infos` 无问题，两退出码 0 | 293.59 秒（含重型资源排队） / 75.11% / 10,037,362,688 B |

最终探针 **06:38:25 UTC** 启动，生产 Dio 的 GET 目录和 POST 状态均 HTTP 200；20 个目录卡片，所选 owner 匹配、请求和 canonical alias 不同、access=loginRequired、reportedAlive=null。该探针验证元数据分类，不读取媒体。最初失败报告/源码哈希已独立保留；提交前核对三个 Dart 文件与最终 green-source.json 一致。两次记录结束活跃重型进程均为 0。

原始网页、JS、HTTP 响应保留在忽略目录 `local-artifacts/bigo-public-20260909/`；本批 `metadata-contract-20260909.json` 汇总合同和十份原件 SHA-256，旧 evidence.json 未覆盖。探针报告、首轮失败和输入哈希在 `local-artifacts/bigo-metadata-20260909/`。Git 中夹具替换频道、主播、广播身份和图片地址。

## 剩余范围

Bigo 仍缺有效媒体合同、质量/线路、续期与录制输入、精确分享链接、LiveSite 注册及相关导航/搜索/收藏/能力/迁移/双语接线，随后才是双端原生验收。下一步先取得当前公开可播响应或按站点正常登录机制验证所需会话合同；在此之前不以空 HLS 猜测协议，不把受限状态改写成离线。

当前仍 **18 个直播站点 + IPTV、9 组参考平台未注册、42 个历史宏观大项未闭环**，不是 42 个未修复 bug。版本 3.1.8+4121；Android 候选 bee143e2、Windows f3de664a 均未包含本批。没有构建/安装/发布、ADB/MT 操作、Root/LSP 修改、重启、清数据或上游同步。完整稳定 3.2.0 目标继续，本批元数据测试不代表全部完成。
