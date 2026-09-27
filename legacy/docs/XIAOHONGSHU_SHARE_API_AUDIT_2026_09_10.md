# 小红书公开分享状态与媒体合同（2026-09-10）

## 范围与结论

基线 `52fd16f9bd6796e865165a8bc02603b92dc670fd`；实现 **`3abad7a4235489bcf74ba931735184dbadd6667e`**。本批新增底层公开分享页 API、状态/源解析、真实输入夹具与生产探针，尚未注册 LiveSite。当前仍 **18 个直播站点 + IPTV，9 组参考平台未注册，历史 42 组未闭环**。版本及 Android/Windows 候选不变，没有构建、安装或发布。

实测官网下播页与公开直播页均 HTTP 200；直播页声明四个媒体 URL、一档 h264/HD。其中 HLS 列表和一个完整 TS 已取得，外部 FFmpeg 对该分片严格解码通过。这不是 Pure Live 播放器、录制器或 Android/Windows GUI 验收通过。

本轮手机只读：显式 `-s 192.168.1.2:5555` 核对 `25102RKBEC / myron`；前台为 `com.bilibili.app.in/tv.danmaku.bili.MainActivityV2`。没有接管前台、唤醒、安装、Root/LSP/MT 操作或网络设置变化。

## 来源与现网差异

- [冻结参考实现](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/live/xiaohongshu/xiaohongshu.go)，blob `86f1ec5b86ce8b1d591bb19f011b17d2b8be9b14`：旧 `outside/share_info` API，页面全文包含“直播已结束”与否决定状态，按 roomId 拼接固定 FLV 主机。参考源码只读，没有合并。
- 当前[官方前端主入口](https://fe-static.xhscdn.com/formula-static/ranchi/public/js/main.74f3f35.js)、[直播页面 chunk](https://fe-static.xhscdn.com/formula-static/ranchi/public/js/5137.9e0b459.chunk.js)、[接口声明](https://fe-static.xhscdn.com/formula-static/ranchi/public/js/vendor.8a59246.js)来自实际分享页与 runtime 清单；只读取，没有执行下载脚本。
- 官方直播 chunk 使用 `roomData.roomInfo.status=2`、结构化 `pullConfig`，另有 paid、family、区域条件、回放和下播推荐。`liveStatus` 初始默认 success，不能单独证明开播；本模块只确认实测 2/3，其余状态保留 unknown。
- 参考旧 API 在本次无账号请求中 HTTP 200、code=-101；公开分享 HTML 同时可读。无房间号的 `/livestream` 则 302 到 404，不是公共目录入口。
- 发现的当前浏览器接口为 `GET https://live-room.xiaohongshu.com/api/sns/red/live/h5/v1/room/current_room_info`，参数 room_id、source=share_out_of_app；一次无账号重建请求返回 HTTP 406、code=-1，原样保留，未据此构造可用 API 或登录绕行。
- 实际采用 `GET https://www.xiaohongshu.com/livestream/{roomId}` 的公开服务端页面状态，不依赖以上两个失败接口。所有请求由本机直接发出，无账号 Cookie/令牌注入、代理设置修改或手机流量采集。

归因是参考取流方法与当前客户端合同差距，不是对已注册 Pure Live 小红书功能的修复。公开网页可读不证明全部账号、地区或房间条件均可访问。

## 身份、访问与媒体解析

1. 房间号保留数字字符串（样本超过 JavaScript 精确整数范围），不转换 double。网络请求固定官网和精确路径，关闭自动跳转；直播态必须含匹配的响应 roomId。
2. 实际下播样本省略 roomId，却包含另一房间的 `nextRoomInfo.pullConfig`。保留 requestedRoomId 与缺失 responseRoomId 的区别；忽略所有推荐、deeplink 预加载流及 replayInfo，避免错误录入其他房间或回放。
3. 仅解析唯一初始状态 script。实际全局配置含裸 `undefined`；有界扫描仅将字符串外的占位 token 转为 null，再由 JSON 解析器验证全部结构。不执行 JS，不在标题/URL 内替换单词，不接受函数、表达式、NaN/Infinity 或重复状态 script。
4. 状态 2 且 liveStatus=success 为平台声明直播，3 且 end 为声明下播；冲突为 schema，其他数值为 unknown。通用 pageStatus=error 分类 api，不凭混合错误文案认定下播、房间删除或访问限制。
5. 媒体仅在 `monetizeType=0` 且 joinLimitTypes 全零/空列表时暴露；付费、群聊、家族、地域以及未知条件不取预览流冒充完整直播，元数据仍保留。字段缺失标 access unknown。
6. 保留 h264/h265、quality_type、quality_type_name、原始 http/https 与完整 query；同 codec/quality/URI 的重复别名归并。当前四 URL 是 HLS 一路、FLV 三路，**一档质量而非四档质量**。没有按全局 width/height 伪造逐档分辨率。
7. URL 校验 xhscdn 子域、默认端口、精确 `/live/{roomId}.m3u8` 或 `.flv`，排除跨房间、userinfo、fragment 和外部地址；未观察的后缀路径仍待补充合同，未主动猜测 CDN。
8. 共享 Dio/请求级取消，2 MiB UTF8 字节上限、20 秒总请求/流读取期限；每个 codec 最多 32 源、pullConfig 64 Ki 字符上限。HTTP 401/403/406、404、429、5xx 与 transport/schema/api/identity/cancelled 分开。取消与失败只释放本请求，不影响共享 caller token 或兄弟请求。

## 原始观察与单分片验证

忽略目录 `local-artifacts/xiaohongshu-public-20260910/` 保存响应、官方静态源码、请求结果及 `public-contract.json` 哈希索引；原始 HTML/headers 包含平台全局配置与签名图片参数，不进入 Git。夹具仅保留直播状态子树，移除 deeplink/追踪参数并替换昵称、标题和图片。

| 层级 | 实测 | 尚未证明 |
| --- | --- | --- |
| 下播分享页 | status=3/end，响应 roomId 缺失，含别房推荐 | 跨开播持久主播身份 |
| 当前直播分享页 | status=2/success，roomId 匹配，public，4 URL / h264:HD | 目录分页、关键词搜索、账号态 |
| 生产 Dio 探针 | 19:15:10 UTC 开始；两次 HTTP 200，Referer/禁跳转符合；两个房间状态分别 false/true | 原生播放/录制 |
| 当前 HLS | 200 / 426 B，三个 2 秒 TS 条目；无 ENDLIST | 全线路、长时持续性或刷新恢复 |
| 首个完整 TS | 序号 1788902456；HTTP 200 / **1,567,168 B** | 其余分片和完整直播内容 |
| 外部 FFprobe/FFmpeg | **2.062 秒、H.264 1920×1080 / 50 视频包、AAC / 93 音频包**；严格 decode exit=0、stderr=0 B | 应用 relay、停止排空、封装收尾、双端 GUI |

分片 SHA256：`DCDB956FA6F3A97C9AA01458E3388BC018FA517A57C3A94CCFBFFBB574508BDF`。媒体核验时间 19:16:50 UTC；命令使用本机既有 FFmpeg，`-v error -i media-segment.ts -xerror -fps_mode passthrough -enc_time_base demux -f null -`。未把单分片证据写回生产探针的 mediaValidated 字段。

## 回归、失败保留与资源

检查脚本和日志：`local-artifacts/xiaohongshu-share-20260910/`。均通过重型资源守卫串行运行；每次结束活跃重型进程数 0。

| build-records 记录 | 结果 / 解释 | 耗时；峰值 CPU / 工作集 |
| --- | --- | --- |
| `20260909T191358423Z-xiaohongshu-share-first.json` | 117 PASS / 1 FAIL：真实 SSR 全局 undefined 导致初版 JSON 失败，未进入 analyze | 37.990 s；8.53% / 10,584,637,440 B |
| `20260909T191545969Z-xiaohongshu-share-final.json` | 补扫描及 7 回归后 **125/125**，含在线 1/1；analyze 报探针一处多行 if 缺大括号 | 51.169 s；9.51% / 10,567,532,544 B |
| `20260909T191652362Z-xiaohongshu-share-verified.json` | 大括号修正后五文件严格分析 PASS；单 TS 探测及严格解码 PASS；未重跑不变在线请求 | 19.139 s；8.86% / 10,033,094,656 B |
| `20260909T191818402Z-xiaohongshu-share-acceptance.json` | 将通用页面错误从 access 改为 api，最终 **124/124 + 在线 1 skip**、五文件严格分析 PASS | 50.983 s；9.24% / 10,604,195,840 B |

64 项专项覆盖真实直播/下播、推荐污染、身份、结构/访问/URL边界、hydration 非执行解析、UTF8 容量、超时和取消；60 项共享生命周期继续覆盖八站点的实际 Dio 流关闭、兄弟请求隔离与持续小块总期限。最终五文件哈希与 acceptance-source.json 逐项相符后提交。在线证据来自成功/下播路径，之后仅改变页面错误分类，不假称重新在线验收了错误路径。

reverse-api-engineer 0.13.0/schema1 仅完成 dry-run；run_id/har_path/script_path 均 null，未启动 SDK 代理或生成客户端。本批客户端是经审查的本仓库实现。

## 下一阶段与回滚

- 继续应用接线：精确分享导入、房间号搜索与能力说明、收藏/分享身份、设置迁移、导航及播放器/录制解析；目录和跨开播主播跟随需要另取公开合同，禁止将一个固定样本或推荐房当作全站目录。
- 验证注册后的生产 HLS/FLV 路由与刷新、真实控制器录制及收尾，再补 Android/Windows GUI 和长时验收；弹幕、账号、特殊房间、短链接、国际站/别名路径独立记账。
- 本批尚未触及注册表、版本或持久化结构；回滚点为 52fd16f9，单独撤销 3abad7a4 即可移除新底层模块及测试，不回退其他功能或用户数据。

汇总见 [当前剩余工作](ACCEPTANCE_STATUS_3_2_0.md)、[完整验收入口](ACCEPTANCE_3_2_0.md)、[参考平台差距](PLATFORM_EXPANSION_AUDIT_2026_09_07.md)。
