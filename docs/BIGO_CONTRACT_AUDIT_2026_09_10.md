# Bigo 既有元数据合同复验（2026-09-10）

## 结论与基线

基线 `b0f8c7a8`。Bigo 元数据层已由 `cf704d5f` 实现，详见[既有审计](BIGO_METADATA_API_AUDIT_2026_09_09.md)。本批仅追加当前响应夹具与回归测试，生产 `bigo_api.dart` 保持基线内容。没有新增 LiveSite 注册或媒体能力。

本轮开始误将“未注册”当作“没有实现”，重复覆盖了数据层及原测试。Git 核对发现重复后已恢复，舍弃版本保留于忽略目录 `local-artifacts/bigo-contract-20260910/discarded-duplicate/`，不进入提交。该版本的 66 项、40 项测试结果均不计入最终证据；恢复后使用原 API 重新回放。

## 当前响应证据

2026-09-10 00:43–00:44 UTC，通过本机 Clash 7897 对公开元数据做有界请求，未提供账号凭据、改变系统代理或执行下载的脚本。

- 官网 HTML 和其引用的静态 JS HTTP 200；首次静态请求缺少重定向跟随导致空文件，后续依据响应头重取并核对正文，未将 curl 退出 0 等同内容有效。
- 推荐端点返回 HTTP 200、外层 code=0、内层 resCode="0"，共 20 行。fetchNum=10 并不代表响应有分页合同。
- 三个目录房间详情均 HTTP 200、needLogin=true、alive=0，uid 与目录 owner 一致，clientBigoId 有值但 siteId 为空，未返回可播放 HLS。该 alive=0 是门槛响应，不是下播证据。
- 固定[参考实现](https://github.com/biliup/biliup/blob/906e0f6fdb104d65989d12b76c9a6f02205384cb/crates/biliup/src/downloader/live/bigo.rs)仅作比较，未合并上游。其状态判断在这些样本上会落入 Offline；本项目既有层已经区分登录门槛，本批并非新增此修复。

原始 HTML/JS、HTTP 头、20 行目录、三个详情、比较结果与 SHA-256 清单存于忽略目录 `local-artifacts/bigo-contract-20260910/`。原响应含时效图片 URL 和客户端信息，未提交。

## 保留的既有不变量与新增覆盖

[生产 API](../lib/core/site/bigo/bigo_api.dart)先核对预期 owner，再分类登录/密码/付费门槛；门槛下 reportedAlive 保持未知。公共 ID、owner 与 int64 广播 ID 分开保留，别名按返回身份关联。请求保留既有取消作用域、总期限、正文上限与共享 Dio 路由。

[新增夹具说明](../test/fixtures/bigo/README.md)：两行推荐和一个详情保持实际 envelope/字段类型，账号标识、广播 ID、名字和图片替换为合成值，移除客户端 IP 与图片签名。新增两个测试覆盖 int64/身份分离和登录门槛前的 owner 校验。另在忽略目录以生产 API 回放完整 20 行及三个详情；回放只验证解析和请求形态，不代表此次调用默认网络传输。

## 验证

恢复基线后 **44/44** 通过：既有 38 项、新增 2 项夹具回归、完整本机捕获 4 项回放。生产 API、测试及本机回放三文件严格分析通过，生产 API 与 HEAD 内容一致。终态记录为 `local-artifacts/build-records/20260910T010825981Z-bigo-contract-check-restored-baseline-revalidation.json`。本批没有生产行为修改，不重跑无关平台或构建。

## 设备连接补充

本轮显式绑定 192.168.1.2:5555，只读得到型号 25102RKBEC、代号 myron，与用户指定一致。MT MCP initialize 协商协议为 2025-06-18，按该版本读取 tools/list 成功，返回 26 个工具。首次使用旧协议头收到 Invalid MCP-Protocol-Version，随后遵循协商结果修正；未误判为设备断连。

证据在 `local-artifacts/mt-mcp-preflight-20260910-090512/`。只检查设备身份与 MCP 元信息，未调用 APK 编辑/构建/安装、未切换前台或修改转发，未动 Root/LSP、Wi-Fi、调试授权或端口。

## 仍待完成

Bigo 仍缺正常媒体响应及会话合同、媒体身份/续期、导航与注册、播放/录制和原生验收。下一步针对真实缺口推进，不重复实现已存在的数据层。

整体仍为 19 个直播站点加 IPTV、8 组参考平台未注册；历史验收表 42 组未闭环之外仍有平台扩展及发布门禁。未构建、改版本、发布或同步上游；Android 152cf151 / Windows 2fb471d3 候选不变，3.2.0 等完整验收。回滚本批仅移除新增测试、夹具及记录，无数据迁移。
