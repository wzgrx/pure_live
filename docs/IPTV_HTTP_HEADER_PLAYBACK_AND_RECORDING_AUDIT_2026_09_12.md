# IPTV 频道 HTTP 请求头、播放与录制链路审计（2026-09-12）

## 结论

本批次补齐受请求头保护的 IPTV 频道：M3U 中的 User-Agent、Referer、Cookie、Authorization、Origin 与自定义字段现可从多种常见写法进入同一规范化策略，经播放列表刷新和数据库 schema 9 持久化，再传到主播放器、多画面、纯音频模式与录制 FFmpeg。媒体 URL 与 `|...` 请求头后缀分离，播放器不再把头部参数当作地址正文；频道头优先于全局 IPTV User-Agent，播放和录制使用同一份最终字段。

源码基线为 `f18c76882909649af8641bdfe931e058360624b7`。冻结的上游比较对象为 `c6c9bd70aedc503c003110dae10a83ad0bb891d8`；其 M3U 解析器同样未保留这些字段，因此本批次判为 `upstream-existing`。本轮没有 fetch、merge 或 cherry-pick，维护仓库继续作为唯一工作线。

## 外部格式依据

- [Kodi PVR IPTV Simple 的 M3U 元素与 HTTP header 说明](https://github.com/kodi-pvr/pvr.iptvsimple/blob/Piers/README.md#supported-m3u-and-xmltv-elements)明确记录 `#EXTVLCOPT:key=value`、`http-user-agent` / `http-referrer`、URL 后缀 `|name1=val1&name2=val2` 与 `!` 自定义字段；URL 值优先于 VLC 属性。
- [Kodi inputstream.adaptive 的属性声明](https://github.com/xbmc/inputstream.adaptive/blob/Piers/inputstream.adaptive/addon.xml.in)列出 `manifest_headers` 与 `stream_headers`；本实现只提取这两类传输字段，不处理 DRM、license 或解密配置。
- [OTT Navigator 官方 changelog](https://github.com/ottnav/ottnav.github.io/blob/main/changelog.md)记录 `#EXTHTTP` 与 JSON header 对象支持；[AuthoIPTV provider guide](https://github.com/glitport/AuthoIPTV/discussions/6)给出 `#EXTHTTP:key=value` 与 `#KODIPROP` 示例。它们用于补齐跨播放器兼容样本，不替代 Kodi 的核心 URL/VLC 规则。

## 修订前的确定性问题

1. `M3uParser` 把 `#EXTVLCOPT`、`#EXTHTTP` 和 `#KODIPROP` 当作未知扩展行跳过。
2. 带 `|user-agent=...&referer=...` 的媒体行会连同后缀一起进入播放器，既污染 URL，也丢失原本的请求头语义。
3. `Channel`、Drift `channels` 表与 `LiveRoom` 没有频道级 header 字段，刷新订阅源后也没有稳定持久化位置。
4. 主播放器只读取平台/全局 header；多画面、纯音频和录制没有频道字段可复用。
5. 播放与录制各自构造字段时缺少统一的名称归一化、控制字符清理和确定性编码边界。

首轮先加入解析与持久化断言；旧代码在编译阶段稳定报出 `Channel.httpHeaders` 不存在，形成第一处有效红测，而非以网络波动判断修复方向。

## 实现范围

### 解析、优先级与错误语义

- 支持播放列表头部和 `#EXTINF` 属性中的 `http-user-agent`、`http-referrer` 及常用 HTTP 字段。
- 支持 stanza 内或下一个 `#EXTINF` 之前的 `#EXTVLCOPT:http-user-agent=...` / `http-referrer=...`。
- 支持 `#EXTHTTP:{"Cookie":"..."}` JSON 对象及 `#EXTHTTP:name=value&name2=value2`。
- 支持 `#KODIPROP:inputstream.adaptive.stream_headers=...` 与 `manifest_headers=...`；其他 adaptive/DRM 属性保持原有忽略语义。
- 支持 URL 后缀 `|name=value&!custom=value`，按 query 规则解码 `%xx` 与 `+`，同时保留 `%2B` 代表的字面加号。
- Kodi 的 `seekable`、`reconnect_*` 与 `icy*` 传输选项不会误发成 HTTP 字段；它们从清洁媒体 URL 中移除。
- 同一字段的确定性优先级为：播放列表头部默认值 < `#EXTINF` 属性 < stanza 指令 < URL 后缀；同级后出现的值覆盖先出现的值。
- 指令只归属一个频道，不泄漏到下一 stanza。畸形 JSON、非字符串 JSON 值、空键值或破损的 URL 选项会标记该播放列表快照有误；导入事务保留旧数据库与旧缓存。

### 规范化与持久化

- 新增 `HttpHeaderPolicy` 作为解析、房间 JSON、平台播放与 FFmpeg 的单一规范化边界。
- 名称统一为小写；`http-user-agent` 归并到 `user-agent`，`http-referrer` / `referrer` 归并到 `referer`，`cookies` 归并到 `cookie`，URL 自定义字段移除前导 `!`。
- 字段名限制为小写字母、数字和连字符；ASCII 控制字符与 DEL 在跨原生边界前替换为空格，空字段丢弃。
- 输出按字段名排序并设为只读；JSON 编码因此稳定，播放列表刷新不会因 Map 遍历顺序制造变化。
- 数据库 schema 从 8 升至 **9**，新增 nullable `channels.http_headers_json`。迁移先读取 `PRAGMA table_info(channels)`，正常升级和已加列但版本号仍为 8 的回放都保持幂等；旧行为空。
- 损坏的历史 JSON 降级为空 header map；`LiveRoom.toString()` 不输出 header 内容，避免诊断日志携带 Cookie 或 Authorization。

### 播放、多画面、纯音频与录制

- `IptvRepository` 与 `IptvSite` 的分类、详情、推荐和搜索房间都恢复数据库中的频道字段。
- `PlayerController.resolvePlaybackHeaders` 把权威 `LiveRoom.httpHeaders` 传入共享 resolver；全局 IPTV User-Agent 先作为默认值写入，再由频道值覆盖。
- 主播放器和多画面共用同一入口；多画面初始解析及后续画质切换都保留频道字段。
- 纯音频模式沿用当前播放器的同一 source/header 快照；FFmpeg 音频 relay 入口也接受频道字段，避免模式切换改变鉴权语义。
- `StreamResolverService` 把录制专用详情中的字段绑定到所选 URL、线路和租约，`RecorderController` 再通过 `FFmpegHeaderFactory` 生成与播放一致的字段。
- 自有输入 recipe 继续由其私有传输实现负责鉴权，外层 FFmpeg header 保持为空，避免重复注入。

## 验证证据

| 层级 | 结果 |
| --- | --- |
| 稳定红测 | 旧模型缺少 `Channel.httpHeaders`，目标测试在编译阶段失败 |
| 直接六文件回归 | **152/152 PASS** |
| 多画面定向 | **53/53 PASS** |
| 最终 focused CI（19 文件） | **426/426 PASS** |
| 静态分析 | 最终 `flutter analyze`：**No issues found**（42.6 秒） |
| 格式门禁 | 23 个 Dart 文件，0 个待格式化 |
| 质量记录 | `local-artifacts/build-records/20260912T082549957Z-quality-focused.json` |
| 仓库审计 | errors 0；保留 2 项既有预期警告：测试 TLS key 与 33 项空 catch inventory |

重点回归覆盖 M3U 优先级、header 泄漏、`+`/`%2B` 解码、混合类型 JSON、稳定刷新与清空、schema 1..8 升级及迁移回放、损坏 JSON、全局 UA 覆盖、实际播放器 resolver、多画面、录制详情、FFmpeg 参数、纯音频切换、回看事务和 IPTV 设置页。

## 本批次边界与后续

- 本批次没有操作 ADB、手机、Windows GUI、真实 IPTV 提供方、真实解码器、构建安装包或发布版本。
- 本批次没有使用 Astra Light；该资源继续只保留给确需 Windows Computer Use 的单个 GUI 验收任务。
- DRM/license 解析、提供方专用非 HTTP 播放选项与真实服务器行为不在本批次结论中。
- 下一步需在 Android/Windows 最终候选中使用真实受保护样本分别核对直播、回看、多画面、纯音频、录制及应用重启后的 schema 9 升级。
- A1-05/A3-04 保持 RUN；宏观状态仍为 **20 PASS / 33 RUN / 9 NR**，共 **42 组**未闭环。
