# 克拉克拉 / 红豆 FM：公开入口与媒体合同（2026-09-08）

## 阶段

参考平台扩展的输入取证；尚无本项目适配器、注册入口或原生验收。当前未注册分组数仍为 13，不因网站/API 返回 200 减少计数。与映客应用接入是不同批次，不复用其测试结论。

本机原始响应、来源源码、采样器和 SHA256 清单位于忽略目录 `local-artifacts/kilakila-contract-20260908/`。国内站点匿名直连；GitHub 来源请求单独使用本机 7897 代理，不修改系统或应用网络设置。未发送用户 Cookie、登录、关注或购买请求；只选择目录明确 `goldPrice=0` 的公开样本。响应中附带的推流字段不作为播放输入，不写入公共日志或版本库。

## 来源与静态差异

- [biliup 固定源码](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/kilakila.rs)：读取房间详情，状态 4 表示在播；返回 HLS/FLV，未接入弹幕。路径拆分只认 `/room/` 与带尾斜线的详情形式，错误码统一当下播，后续适配不直接照搬。
- [bililive-go 固定源码](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/hongdoufm/hongdoufm.go)：品牌域名合并，另处理带 `id` 查询及不透明分享参数；使用旧详情主机。本轮只审查代码，没有执行参考程序或其分享解码函数。
- 当前官方[公共模块](https://live.kilakila.cn/static/pclive/js/chunk-common.1053f4ac.js)及[首页调用模块](https://live.kilakila.cn/static/pclive/js/chunk-5b86f1f0.7d0cbe13.js)明确展示 GET 目录/推荐/详情调用。首页默认页大小 10；本机分别请求 12 条的第一页和第二页，两次响应回显该页大小，不将 12 描述成官网默认。

这属于独立现网合同核验。参考 URL 拆分/错误分类与现有输入之间的差异仍须由其自身测试验证，不声称复现参考应用崩溃。

## 2026-09-07 22:42–22:50 UTC 本机观测

| 请求 | 已取得的响应 |
| --- | --- |
| `https://www.kilakila.cn/` 与 `https://live.kilakila.cn/` | 200、同一 9,780 B SPA 壳；HTML 的房间注入值为空，不据此判定平台没有直播 |
| `/pcLive/timeline?tag=0&type=0&genderType=0&pageNo=1&pageSize=12` | 200；外层 `code/msg/data`，内层 `data.body.h/b`；`b` 含 `pageNo/pageSize/data/isLastPage`，12 个 `dataType=8` 房间，`isLastPage=false` |
| 同目录第二页 | 200；回显 pageNo=2、pageSize=12，12 个房间，`isLastPage=false`；跨时刻两页重叠 2 个房间，消费端仍需去重且继续原生页码，不据此宣称服务端分页错误 |
| `/pcLive/recommend` | 200；内层成功头但没有 `b`，而同时目录有在播房间；缺推荐体不代表全站下播 |
| `/pcLive/hourly` | 200；嵌套响应有排名、房间和公开评论字段；排名分数不直接等于观众人数，评论字段存在不等于已接入弹幕 |
| `/LiveRoom/getRoomInfo?roomId=<免费目录样本>` | 200；直接 `h/b`，没有目录的包装层；`h.code=200`、`b.status=4`，房间字符串 ID、主播 UID、HLS/FLV、价格等分列 |
| `https://live.hongdoulive.com` 上同一详情路径 | 200；同样的匹配房间及状态结构。旧主机本次可达，不外推全部旧域名兼容 |
| 固定参考注释中的历史房间 ID | HTTP 200，业务码 **5966**，信息为“暂不支持查看历史回放”，无状态/媒体。不是网络失败，也不是已经证明的“当前下播”合同 |
| `/room/<数字 ID>` | 最终转到详情页 `_specific_parameter` 查询；200 仍是空注入 SPA 壳。查询形式 `detail?id=<ID>` 也是同壳，未做浏览器渲染或分享解码验收 |

目录的 `roomResq.roomIdStr` 是大整数字符串，与 `userResp.id` 的主播 UID 不同。后续要证明跨开播周期身份/收藏和在线查询语义，不将房间 ID 默认为永久主播 ID，也不经浮点转换。`watchNumber`、排名分数、钻石、点赞、主播等级分别处理；在线人数的实际语义尚需官方页面与动态事件对照。

## 有界媒体证据

仅使用详情返回的 `flvPlayUrl/hlsPlayUrl`，HTTPS 主机为 `pull.live.hongrenshuo.com.cn`，原样保留播放签名；没有由推流地址拼装播放地址。

- FLV：HTTP 200，`video/x-flv`，只读 65,536 B；143 个完整标签（1 脚本、116 音频、26 视频），FLV 音视频标志、AAC/AVC 序列头及完整标签的 PreviousTagSize 校验通过。采样终点落在下一标签内部是读取上限，不是完整文件损坏证据。SHA256 `4a2c12dd998ed15036dc5c2c0cdbbc420b70805a97f616a713585fd29d0163a7`。
- HLS：HTTP 200、409 B，3 个媒体片段，目标时长 4 秒，无 ENDLIST、无 KEY 标签。只读取列表，未下载片段或做解码。SHA256 `33dfa5ca1566786c2b14c0296dcc29fe86ff766ba06bafe1f1b0b8b2ed466c6e`。

这不是实际声音输出、视频首帧、短录完整封装/解码、原生后台或长期续签通过。没有执行 FFmpeg、构建、手机操作或修改其他正在运行的任务。

## 下一实施合同

1. 独立解析目录包装层与详情层，分类 HTTP 错误、业务错误、历史回放、明确下播、付费/登录条件和未知结构；禁止全部映射离线。
2. 验证 ID 跨开播周期、分享链接与大整数精度；精确主机/路径/参数，拒绝重复关键参数、损坏编码和相似域名。
3. 按服务器页码与 isLastPage 接入目录；推荐空体、空后页、重复房间、请求取消及旧响应归属有确定性测试。
4. 只使用已验证可观看媒体，保持协议和线路身份，另核验签名刷新期限；不把音频平台名称当作纯音轨证据。
5. 完成配置/备份迁移、能力说明、共享请求头、严格录制与恢复后再注册；搜索、分类和实时弹幕独立取证。随后串行执行 Android/Windows 原生与长期验收。

工具流程说明：此为直接 HTTP/静态源码审查，没有启动 reverse-api-engineer 的外部代理流程，没有 HAR、run_id 或自动生成客户端。保留之前 CLI 能力检查的限制，不将这些原始响应冒充浏览器捕获结果。
