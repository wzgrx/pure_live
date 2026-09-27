# TTing/FLEX API 数据层审计（2026-09-09）

实现 `260fbfd5689b2665c0942eba50b146fdef0b4d99`，基线 `f4d81f0f6d64a0a2d37eff99724f1e1063d5df8b`。继 [公开合同取证](TTING_PUBLIC_CONTRACT_AUDIT_2026_09_09.md)、[多画面接线](MULTIVIEW_SOURCE_INPUT_AUDIT_2026_09_09.md)，新增可供生产站点层调用的 API、链接解析及脱敏夹具。**尚未注册平台、接入用户入口或取得 native 播放/录制证据。**

## 数据层边界

- 固定 `api.flextv.co.kr` 的主目录、频道 profile、stream 三个 GET 路径。API 带官方 `x-site-code: flex` 及 Origin/Referer；媒体 headers 不带站点 API 头。生产传输复用共享 HttpClient/Dio 路由，不添加失败后直连或旧域名重试。
- room 的 profile→stream 共用一次总时限和独立 CancelToken；结束、取消、超时回收本次 transport，不取消共享调用者令牌。流式响应限制 1 MiB、严格 UTF-8、总 body 时限，拒绝自动重定向；错误枚举不包含签名 URL 或响应原文。
- profile 的频道 ID、owner ID 与 stream 顶层频道、嵌套频道、广播 ID 分别验证。明确离线 profile 跳过 stream；profile 限制先于媒体请求检查。ended/disconnected/finalized 为非当前可播信号，不从所有 400、空 sources 或异常结构推断下播。
- barrier 的锁定、等级、成人、暂停、屏蔽字段及 stream 状态分别检查，缺失或类型异常显式失败；flag 只接受 bool 或 int 0/1。目录只表示主目录快照，count/重复频道检查；不伪造全站分页、搜索或 directory owner 数字 ID。
- 媒体限定观察到的 HTTPS NCP edge 主机与 m3u8，拒绝 userinfo、异常端口、错配 token 和过期来源。保留四个 API resolution 与源族；没有把列表声明当成实际解码画质。expiry 分段解析，拒绝相邻重复 exp 字段。
- 每源持有精确 HlsSourceQueryPolicy，供下一阶段 LiveSite 的 resolution map 接线。链接接受数字频道及两个品牌的精确 `/channels/{id}/live` 路径，不把主播/广播 ID 或任意末尾数字认成频道；编码路径、凭据、非标准端口、仿冒域名被排除。

## 当前公开样本与新增源族

2026-09-09 **05:23:19—05:23:25 UTC**，通过用户本机 Clash `127.0.0.1:7897` 匿名读取目录、profile、stream，均 HTTP 200，未使用 Cookie/账号或改变代理设置。所选公开未锁定频道 **52406**：profile/stream 顶层/嵌套频道一致，owner 均 **55850**，当前广播 **375931**。

当前样本 sourceType 与各源 format 为 **ncp_llh**，此前频道 746608 样本为 ncp。最初 API 仅接受 ncp，读取当前完整响应的实际解析测试失败 `TTing mediaUnavailable`；保留失败记录，未把它当作下播或忽略该频道。新增对 ncp_llh 的明确识别与源族保存，禁止顶层/条目源族不匹配。

随后从本次 API 的 resolution=0 URL 读取 master 和一个同源子列表，均 HTTP 200。master 为版本 10，声明三档视频和独立音轨；媒体清单含 EXT-X-MAP、PART、PRELOAD-HINT、RENDITION-REPORT，也有完整 EXTINF。子请求仅在同 HTTPS authority、源目录内保留 API token。**没有下载本次音轨/媒体分片、没有解码、没有证明低延迟体验或录制成品。** 源族支持目前指 API 合同和输入策略，不是 native 全能力通过。

完整响应与清单仅保存在忽略目录 `local-artifacts/tting-api-20260909/`，current-http.json/llh-http.json 记录 HTTP 结果，contract-hashes.json 记录原件与脱敏夹具哈希。测试中的 101/202/303、图片和 hmac=fixture 均为替换值；原始签名 URL 未进入 Git。

## 验证账本

| 记录 | 结果 | 耗时 / 峰值 CPU / WS |
|---|---|---|
| `20260909T052141785Z-tting-api-green.json` | 41 项测试通过；严格分析因两处多行 if 缺大括号提示退出 1，runner 失败 | 214.425 秒 / 68.41% / 6,490,451,968 B |
| `20260909T052555801Z-tting-api-green.json` | 修订格式并补边界后，44 项与严格分析通过 | 192.71 秒 / 16.84% / 6,499,471,360 B |
| `20260909T052754292Z-tting-api-online.json` | 当前公开响应的生产解析 **0/1**，ncp_llh 未被识别；分析未执行 | 83.01 秒 / 8.62% / 5,807,476,736 B |
| `20260909T053204968Z-tting-api-green.json` | **46/46**；三变更 Dart 文件 `analyze --fatal-infos` **No issues found**，两退出码 0 | 185.51 秒 / 9.80% / 5,891,756,032 B |

最终 46 项 = 39 条 TTing 确定性测试 + 6 条真实本机 HLS 查询传播回归 + 1 条对本次保存的完整官方响应运行生产 API 的测试。最后一项注入保存的 HTTP body；HTTP 请求本身由有界 curl 完成，不声称在该测试内通过生产 Dio 实时访问接口。四次记录结束活跃重型进程均为 0。提交前核对三份源码与最终 green-source.json 完全一致，没有复用变更前哈希。

## 下阶段与交付

继续实现 LiveSite：目录快照说明、按频道精确搜索/收藏/分享、离线与受限展示、质量/源族选择、刷新与录制解析；随后平台注册、设置迁移、双语文案和相关用户入口回归。不要把本次固定 ID 或暂时签名写入生产代码。

版本仍 3.1.8+4121；17 个直播站点 + IPTV、10 组未注册参考平台口径未变，历史 42 项宏观未闭环不减记。没有 ADB/MT、覆盖安装、Root/LSP 修改、重启、清数据、发布或上游合并。稳定 3.2.0 仍等待完整目标验收。回滚本批移除实现提交的七个新增文件，不触及数据迁移。
