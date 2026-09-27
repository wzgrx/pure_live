# 克拉克拉主播定位与新版分享证据（2026-09-08）

## 本批结论

源码 `847f4dbcb897378fc43d31abcab9706d53059f15` 在既有 KilakilaApi 上增加公开 UID→当前直播卡片→匹配房间详情的链路；不持久缓存单次广播 ID，不通过扫描整个目录寻找主播。62 项确定性回归、最终三文件 analyze、生产 API 探针通过。**尚未注册应用、构建或进行原生播放/录制验收**；14 个直播站点 + IPTV、13 个未注册参考分组的计数保持。

上一轮已完成累计 Android 候选是有效进展，本批继续处理下一平台接入前的身份缺口。Android 候选仍为 `3a7716b0`，Windows 仍为 `f3de664a`，均不含本批 API 增量；版本仍 3.1.8+4121，未同步上游或发布。

## 官方页面与接口证据

本次通过临时后台浏览器打开[官方首页](https://live.kilakila.cn/)，实际点击热门房间及主播头像。没有登录、关注、发送消息、购买或操作手机。官网自行加载媒体、评论与 wxauth 请求；页面可见结果不是 Pure Live 原生验收。未保存聊天内容，临时标签已关闭。

| 来源/动作 | 实际合同 |
| --- | --- |
| 首页热门房间→详情 | `_specific_parameter` 查询形式成功渲染房间标题；观察到 GET `/LiveRoom/getRoomInfo?roomId=…` |
| 点击主播头像 | POST `/PcLive/getQueryUserInfo`，表单 `uid`；返回外层 code/data，data.id 与请求主播相同，但 roomResp 没有当前广播 ID |
| [官方详情模块](https://live.kilakila.cn/static/pclive/js/chunk-82396490.92aab596.js) `goUser` | 公共主页路径 `/index/roomuser/uid/<UID>`，主机由公共模块 `d9bb` 指向 `https://live.hongrenshuo.com.cn` |
| 主页 [app 模块](https://live.hongrenshuo.com.cn/static/activedetail1/js/app.a45476f1.js) `getData` | GET `/Tg/personalH5?uid=…`；`data.userResp` 为主播展示信息，`data.liveCard` 为当前直播；页面只对 status=4 显示直播入口 |

2026-09-08 01:00–01:01 UTC 匿名 HTTP 检查两个先前公开样本：当前主播 liveCard 有与请求相同的 UID、字符串 roomIdStr、status=4、goldPrice=0；另一位此前在播主播的 liveCard 只含 roomSourceType/recommendSource 两个默认字段。后者之前的广播详情有历史回放错误证据，但本次空卡片仅表示**主页未公布当前广播**，不将任意接口失败视作下播。

重要差异：personalH5 的 userResp **没有 UID/id**，不要从头像 URL 或昵称推断身份。当前卡片必须携带并匹配请求 UID，随后详情再校验房间与主播配对；空卡片的个人展示信息只能归属于请求的官方主页，未声称存在响应内独立 UID 回显。

公开响应可能带推流字段。本批只保留脱敏后的 userResp/卡片必要字段与原响应摘要，不使用或输出推流地址；未下载媒体。目录/历史房间 ID 与主播 UID 始终分开。

## 实现

- `KilakilaOwnerSnapshot` 保存请求 UID、展示名称、头像和可空的当前广播元数据。空当前广播与抛出的网络/结构/业务异常分开。
- `owner` 请求固定官方主机和路径；验证 code、容器、名称、卡片及身份。仅明确空对象/已观察到的默认路由字段视作无当前卡片；缺失、null、部分房间字段、陌生结构或身份不符均报错。未知状态保持原值，不假装下播；元数据 DTO 不带播放地址。
- `detailForOwner` 每次重新请求主播主页，再以该次 roomId 和 expectedUserId 读取详情。播放模式仍遵守免费/已知直播状态、受支持媒体主机及房间路径，原有历史回放分类保持；不跨房间接受迟到数据。
- `numericOwnerFromUri` 仅处理已观察到的 HTTPS 官方数值 UID 主页，精确主机/路径、无查询/片段/用户信息/异常端口；与单次广播链接解析器分离。不将不透明分享串或显示房间号当 UID。
- 抽出内部 JSON 读取供两种包装层共用，保留 1 MiB、正文总期限、HTTP 错误与取消处理。既有底层 API 的 33 项回归一并执行。

## 分享链接：已取证，未应用实现

浏览器实际详情页加载[官方新版分享脚本](https://download.hongrenshuo.com.cn/h5/assets/oss/uxin-security-url-crypto-v2.min.js)，SHA-256 `2a031560d9ccd3770ff57969b8818e5eafd6d8a1e4f54c87e0f4bd983d4607e2`。该脚本支持多组公开读取参数、AES-CBC/PKCS7，并将主机/路径/参数纳入链接签名；克拉克拉详情代码开启签名检查。

独立 .NET 重建本次观察到的一条详情分享链接，解出的房间 ID 与浏览器实际 GET 参数一致，签名相等；仅改变主机后签名不相等。没有执行下载的完整脚本或调用远程解码服务。复现脚本 `local-artifacts/kilakila-identity-20260908/share-check.ps1` 再执行通过。

这是单条分享的合同证据，不是通用分享解析器验收。后续应覆盖不同官方主机、路径/查询形式、新旧读取参数、错误编码、重复参数和签名不符，不应直接采用参考项目的旧单参数解码方式。当前应用仍未处理不透明分享。

## 验证与失败记录

1. 首轮 56 通过、1 失败：测试夹具内层 Map 被推断为不接受 null，异常发生在注入坏输入时，未进入 API。修订内层显式 Map<String, dynamic>，并补充五个无效资料/缺失卡片用例；不将该夹具异常描述为生产 Bug。
2. 第二轮 **62/62 通过**（既有 API 33 + 主播定位 29）；三文件 analyze 报一处探针 if 缺少花括号。测试与失败 analyze 日志均保留。
3. 仅补该花括号；最终 analyze **无诊断，30.4 秒**。API 与测试文件哈希同第二轮，复用 62 项行为测试，没有再跑全库测试。
4. 生产 KilakilaApi 默认请求探针 **1/1 通过**，01:13:54 UTC：当前 UID 与详情主播一致、两次查询广播 ID 不变、解析 FLV/HLS；另一公开样本仍没有公布当前广播。匿名直连 Dio，未验证应用代理。

跨次广播 ID 变化目前由确定性序列测试覆盖；**没有真实观察同一主播停止后再次开播并更换 ID**。不得将本次短时查询写成长期续签或跨开播实测通过。

资源记录位于 `local-artifacts/build-records/`：

| 记录 | 结果 | 耗时 | 峰值 CPU / 工作集 | 结束活跃重型进程 |
| --- | --- | ---: | --- | ---: |
| `20260908T010846409Z-kilakila-owner.json` | 测试夹具失败 | 243.365 s | 9.02% / 13,306,900,480 B | 0 |
| `20260908T011121134Z-kilakila-owner-retry.json` | 62 测试通过，1 lint | 110.392 s | 17.8% / 13,342,507,008 B | 0 |
| `20260908T011357523Z-kilakila-owner-final.json` | analyze/公开探针通过，复用测试 | 134.681 s | 10.2% / 14,294,269,952 B | 0 |

包含资源队列等待；其他任务未被终止。`validation-source.json` 绑定最终提交、4 个源码/测试输入和 32 个来源、日志及资源记录摘要，全部重新核对。原资源记录在提交前产生，保留原 base SHA 和 dirty=true；通过输入哈希关联最终提交，不改写原记录。

reverse-api-engineer 0.13.0/schema 1 的 dry-run 已检查；没有配置环境 SDK key，未启动外部代理任务，没有 run_id/HAR/生成客户端。本批浏览器证据来自 CUA 网络事件和可见界面，与直接 HTTP、独立分享校验及 Dart API 探针分开保存。

## 下一步

完成新版/旧版分享解析及 UID 收藏入口，接入 LiveSite、原生目录消费、配置/备份迁移、能力说明、播放请求头、严格录制和恢复，然后注册平台。后续再串行补 Android/Windows UI、代理、原生媒体及长期验收；不以现有 API 测试替代这些项目。
