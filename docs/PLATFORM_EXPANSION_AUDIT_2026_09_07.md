# 参考平台扩展差距与 Picarto 输入样本（2026-09-07）

本轮以 d509bd8d 源码注册表为准，重新读取参考仓库远程HEAD、完整Git树（truncated=false）、README与实际注册入口，不合并或运行参考代码。

- [biliup 固定入口](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/mod.rs)：19个站点，另有Twitch录像分支与通用适配器；辅助wbi/huya_wup模块不是独立平台。
- [bililive-go 固定入口](https://github.com/bililive-go/bililive-go/blob/ef71711a7c573b013d82fec01ee8d0609ee36aca/src/cmd/bililive/internal/init.go)：20个站点，system不计站点；README表只列17项，漏列源码已导入的快手、Twitch和小红书。源码存在/注册不保证这些参考接口现在仍可用。
- 两个HEAD与09-05相同，之前“Picarto文件504未读”的缺口本轮已补上。
- Pure Live `lib/core/sites.dart` 为10个直播站点加IPTV，共11适配器。快手已使用增量评论feed，CC/AcFun仍是EmptyDanmaku；兼容性文档旧的快手“未接入”及AcFun候选描述已更正。

本地原始证据：`local-artifacts/reference/platform-inventory-20260907/`，包含HEAD时间、完整树、README、注册入口、选定适配器源码及匿名网络结果。没有用户Cookie或令牌注入。

## 全量差距分组

下表按站点品牌合并KilaKila/红豆FM、SOOP/AfreecaTV。Pure Live的SOOP使用`sooplive.co.kr`，参考还出现`afreecatv.com`与`play.sooplive.com`；品牌合并只用于计数，旧/新域名及区域接口兼容并未因此证明。Twitch录像与通用解析单列能力，不增加直播站点数。

| 已注册的10个直播站点 | 参考对应 | 当前缺口口径 |
| --- | --- | --- |
| 哔哩哔哩、斗鱼、虎牙、抖音、快手、网易CC、YY、AcFun、Twitch | 两个参考均有 | 现有功能按各自源码/接口/原生证据分层；注册不代表全部通过 |
| SOOP / AfreecaTV | biliup AfreecaTV；bililive-go SOOP | 本项目韩国接口已接入；跨旧域名/区域合同另验 |

**还有17个未注册的平台候选分组**。它们是用户要求的平台扩展范围，不包含在历史62行/42未闭环大项中，不得悄悄以已有十个平台替代完成标准。

| 候选 | 参考 | 当前状态与具体下一步 |
| --- | --- | --- |
| Picarto | biliup | 本轮目录/详情/HLS取得200；下一步生产适配器、状态分类、分房间HLS质量及恢复夹具 |
| OPENREC | bililive-go | 前批代理样本403；保留可达性/区域条件缺口，先结构化页面与响应分类，不直接移植正则 |
| 小红书 | bililive-go | 对应Issue819；源码通过分享信息接口读取房间，本项目尚未接入，先公开分享链接与房间状态样本 |
| 映客 | biliup | 未接入；核验公开房间ID、状态、媒资及失效类型 |
| 猫耳FM | 两者 | 未接入；核验音频直播、房间/录音模式、声音文件收尾，避免强制视频轨 |
| KilaKila / 红豆FM / 克拉克拉 | 两者 | 未接入；先核验别名/域名、音频与视频房间状态 |
| TTingLive | biliup | 未接入；核验公开入口、房间身份和媒体协议 |
| YouTube | biliup | 未接入；参考依赖yt-dlp/Streamlink的部分不是现成Dart移动端能力；需处理直播/录像/账号边界 |
| TwitCasting | biliup | 未接入；核验公开频道、状态、HLS和弹幕身份 |
| niconico | biliup | 未接入；核验账号依赖、会话续期与外部工具依赖 |
| Bigo Live | biliup | 未接入；核验频道ID、可达性和实际画质列表 |
| 战旗 | bililive-go | 未接入；先确认当前站点/接口生命周期与公开在播样本，源码留存不等于现网可用 |
| 一直播 | bililive-go | 未接入；核验直播链接、房间状态和媒资 |
| 企鹅电竞 | bililive-go | 未接入；先核验站点/接口生命周期，不据参考README宣称可用 |
| 浪live | bililive-go | 未接入；核验多个域名与直播身份、区域访问条件 |
| 花椒 | bililive-go | 未接入；核验公开目录/分享、房间状态与流 |
| 微博直播 | bililive-go | 未接入；区分直播、回放和分享页，核验账号与短链接 |

其他差距：参考的通用适配器调用桌面外部工具，不能直接等同于本项目IPTV支持任意网页；历史审计提及TikTok，本次固定内置注册表没有单独TikTok适配器，应按通用解析/独立候选核验而非计为参考内置支持。定时/批量检测、音频站点、弹幕留档及后处理等功能也需逐合同对照，不机械复制服务端录播器的默认行为。

## Picarto：从源码未读推进到公开输入实证

参考 [Picarto适配器](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/picarto.rs)。在本机确认Clash 7897监听后，仅为本次HTTP请求指定代理，没有改变应用/系统代理设置或操作手机。

| 请求 | 本轮实测 |
| --- | --- |
| `ptvintern.picarto.tv/api/explore` | HTTP200，10条，第1/6页、total51；显式adult=false，未复制参考的adult=true默认 |
| 公开频道详情 | HTTP200；选定目录中公开、在线且无标签的绘画频道，channel ID15237 |
| 多播房间映射 | getMultiStreams含4条；目标是第二条，以channelId匹配15237而非错误选第一条 |
| HLS主列表 | HTTP200 / 140B / EXTM3U；1个variant，声明1280×720、60fps、3,661,056带宽、H.264+AAC |

最后HLS结果时间05:58:43Z。该信息是播放列表声明，**不是实测解码码率、音视频播放或录制通过**；没有获取整个直播视频。当前应用仍未注册Picarto。

### 下一实施合同

1. URI解析验证精确主机和频道段，拒绝搜索/分类/相似域名；不采用未锚定的参考正则。
2. 公开目录读取有界分页、原始在线/观看含义和图片字段；分类/搜索缺公开证据时明确能力，不伪造搜索结果。
3. private、401/403、429、5xx、字段缺失与明确下播分开。参考将private及缺少loadbalancer都映射Offline，这会让监控误判，不能照搬。
4. 详情的多播流按channelId配对；验证origin主机片段，解析标准HLS属性与相对URI；稳定质量ID、多个线路与续期重新取详情。
5. 建立公开在线、明确离线、私有、限流、损坏结构、多播顺序和取消/迟到夹具，再接入导航/分享/平台能力与严格录制解析。
6. 后续串行执行代理媒体探针、Android/Windows播放、短录封装/完整解码、停止清理与长时验证。CC/AcFun弹幕缺口另外保留。

本轮只更新来源/接口证据和文档，没有应用改动、Flutter重测、构建或发布。原整体目标继续；17个扩展分组仍未实现，不因本次接口200而减少为16个。
