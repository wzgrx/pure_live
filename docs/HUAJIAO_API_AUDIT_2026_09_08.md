# 花椒 H5 合同与底层 API（2026-09-08）

## 范围与来源

基线 `0879e57c838b46cacbea33b6d79f57bd9a2eae52` 尚无花椒应用适配器。
本批是用户要求的参考平台扩展，不是已发布 Pure Live 花椒功能的回归修复。
没有同步上游、升级依赖、修改版本、打包或操作手机。
实现提交 `9106e379c831e1f810c9b0856ab8f9dd8721ecae`；源码与证据哈希清单为
`local-artifacts/huajiao-public-20260908/validation-source.json`。

- [bililive-go 冻结参考](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/huajiao/huajiao.go)
  使用旧 `User/getUserInfo`、`User/getUserFeeds`、直播页作者 span 和 `live/substream`。
  文件 3988 B，SHA-256 `a617fc5ea88565c0a9004d3653bc307274a9c5515e3e2b229c2108aac7af09b0`。
- [花椒官网](https://www.huajiao.com/)现为宣传/下载页；旧 `/l/` 样本重定向至首页。
- [官方移动主页](https://h.huajiao.com/site/profile_213358115.html)及其
  [应用脚本](https://s2.ssl.qhimg.com/static/0ce88072faebbef7.js)提供当前用户状态和公开目录合同；
  [供应商脚本](https://s2.ssl.qhimg.com/static/865f9feae76b840d.js)包含当前 H5 广播入口。
- [官方 H5 广播页](https://h.huajiao.com/l/index?liveid=350295619)内联脚本使用 `/api/getFeedInfo`。
  页面与脚本只作静态读取，没有执行抓取内容中的代码。

原始证据在 `local-artifacts/huajiao-public-20260908/`，含请求时间、状态、响应哈希。
原始资料保持忽略状态；提交的四份夹具仅保留必要结构并替换身份、图片、串号、签名地址。
reverse-api-engineer 0.13.0 仅做 CLI 预检/dry-run，未运行自主代理，未生成 HAR 或客户端；
实际取证是显式匿名 GET，不将 dry-run 记为浏览器抓包通过。

## 现网差异与实现决策

| 证据 | 决策 |
| --- | --- |
| 旧用户动态接口 HTTP 200、errno 111，提示登录 | 归类 access，不当作主播下播；不依赖该历史动态接口 |
| `Web/UserInfo/full` 的 living 为广播 ID；另一样本为 0 | UID 是持久身份；只有显式 0 表示当前下播，每次播放重读当前广播 |
| 已在播用户的 `feed/getUserFeeds` 仍返回空 feeds | 空历史列表不证明下播，不选推荐主播来替代当前用户 |
| getFeedInfo 返回 data.feed.feed/author 和 data.live | 匹配请求广播、作者 UID、feed/live 串号后才返回媒体 |
| getLives4H5 返回 sections[].feeds 和顶层 feeds | 合并并按广播去重；同广播不同 UID 报身份异常 |
| 两行目录下一 offset 为 30；后页零行、offset 36、more=true | 保留原生游标和 more，条数不代替分页状态；拒绝停滞游标 |
| 目录 point 为 `{lat:0,lon:0}`，直播详情为 `""` | point 是位置字段，不用于播放限制；以状态、隐私、特殊房间和模式判断公开视频 |
| 真实直播 title 为 `""` | 空标题使用主播名；缺失或类型错误仍报结构错误 |
| 无效广播返回 point-only feed、无作者/type、live=null | 识别这个明确缺媒体哨兵，不升级成用户下播 |
| 请求 encode=h264 后响应 encode/path 仍标识 h265 | 不根据请求、字段名或文件名虚构编码；仅保留 URL 指示的容器类型 |

H5 `main` 与 `pull_m3u8` 的有界 GET 都得到 HLS 列表；旧 substream 的 main 得到
32 KiB FLV 前缀，视频标签头为 `0x17`（AVC 标识），与 h265 元数据不一致。
这是容器/包头证据，不是全流解码或设备播放验收。历史文件 `flv-prefix.body` 实际为 HLS，
对应元数据已标注；真正 FLV 前缀为 `substream-flv-prefix.body`，不按文件名推断格式。

## 红测与修订

首轮 32 项：28 通过、4 失败，见 `red.log` 和
`local-artifacts/build-records/20260908T130607032Z-huajiao-api-Red.json`。

1. 真实地理 point 对象被草稿过滤，目录漏行。
2. 真实空标题被草稿拒绝，完整媒体结果也报 schema。
3. point-only 缺广播哨兵被当成普通 feed，错误分类不准确。
4. 真实 Dio 适配器夹具中，取消包装流订阅没有触发上游取消。

前三项按当前响应修订。第四项核对锁定 Dio 5.11.1 的 `handleResponseStream`：
包装控制器未将订阅取消转发至响应源，而请求 CancelToken 会停止源及接收定时器。
花椒请求因此使用独立令牌，转发调用方取消，在 finally 解除转发并结束本请求；
不取消调用方令牌或共享 Dio，也不升级/补丁修改依赖。

最终 **34/34** 定向测试通过，**三文件 analyze 无问题**，
记录 `local-artifacts/build-records/20260908T131312192Z-huajiao-api-Final.json`。
覆盖实际脱敏结构、身份、游标/空页、访问限制、错误分类、URL 原样保留与域名边界、
UTF-8 字节上限、绝对读取期限，以及真实 Dio 包装后的错误/溢出/取消收尾。
新增两项回归证明上游关闭及调用方令牌保留；失败记录和输入哈希均保留。

生产 API 探针 **1/1 通过**，2026-09-08 13:15:19 UTC：默认每次请求 num=30，
两页分别返回 3/1 个公开房间，原生 offset 30/60、more 均为 true；两次房间读取均匹配
主播和当前广播，解析到 HLS/FLV。未观察到两次读取之间切换广播，不把刷新调用当作跨开播验收。
使用生产 API 默认请求方法和直接 Dio，没有下载媒体、测试应用代理或进行原生操作。
结果 `production-probe.json`，资源记录
`local-artifacts/build-records/20260908T131523153Z-huajiao-production-probe.json`。

## 仍待完成与下一步

- 只完成底层 API；花椒尚未注册到导航、设置迁移、分享/搜索、收藏、播放或录制。
- 目录游标需要接入现有分页控制器，处理空页仍有 more 的有界继续与刷新事务；不伪装页号乘条数。
- `back` 字段样本为空，备用媒体合同待取证；音频/特殊房间和弹幕尚未实现。
- native HLS/FLV 解码、短录、源恢复、Android/Windows 操作及布局仍待验。
- 相邻映客/克拉克拉请求也有直接取消 Dio 包装流的写法；下一步先补同级适配器回归，
  按证据修订已有平台的资源收尾，再继续花椒应用接入。本批未宣称相邻平台已修好。
- 源码注册表仍为 **15 个直播站点 + IPTV，12 组参考平台未注册**；宏观验收仍
  **20 PASS / 32 RUN / 10 NR**。本批无原生 PASS、安装或发布增量。
- Android 候选仍为 c97a61aa，Windows 候选仍为 f3de664a，均不含花椒底层代码。
  保留用户全部远程设备边界；升级安装前做一致性数据库备份和签名核对。

回滚只移除本批未注册的 API、测试、夹具和探针；不动既有用户配置/收藏或归档候选。
