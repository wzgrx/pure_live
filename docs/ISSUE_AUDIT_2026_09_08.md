# Issue 增量核验（2026-09-08）

## 范围与来源

本轮针对维护分支 `18da9a5fa7a2cc51a55d3adeb224bf63f34632af` 做只读核对，没有合并上游、修改 Issue、设备操作或发布。GitHub connector 使用 `is:issue`、`state:open`、按 updated 降序、上限 100 的搜索，维护仓库返回 0，上游返回 16；这是本次筛选结果，不是本项目剩余 Bug 数。

上游编号为 849、857、855、853、852、851、850、848、846、845、836、819、792、779、767、708。相比 [09-07 审计](ISSUE_AUDIT_2026_09_07.md) 新增 855/857；本轮重点读取这两条及 849 最新评论，其余不重复宣称完成逐条复验。匿名 REST 曾返回 403、配额剩余 0，该失败不用于计数。

原始 connector 响应、直接 HTTP 采样和脚本保存在忽略目录 `local-artifacts/issues/20260908-current/`。评论中的附件签名地址和原始媒体字段不进入版本库。

## #857：YY 的外部打开分支遗漏

[报告](https://github.com/liuchuancong/pure_live/issues/857)于 2026-09-07 14:14 UTC 创建，版本 v3.1.2、Windows 11；从 YY 播放页菜单选择打开直播间，报告者观察到 system32 文件夹。

- 当前分支：`present`。`LivePlayController.openNaviteAPP()` 初始化两种 URL 为空，switch 缺少 `Sites.yySite`，Windows 分支随后把空 webUrl 传给系统启动器。这是源码中第一个错误状态；系统实际打开文件夹的现象本轮尚未原生复现。
- 相邻问题：未知站点同样可能保留空 URL，启动器返回 false 未处理，异常后的浏览器重试也缺少空值防护。后续修复应覆盖这些同链路输入，而不是重写播放器生命周期。
- YY API 已返回 `https://www.yy.com/<roomId>`，可作为网页打开的既有来源；Android 深链尚未取证，不猜测协议。
- 来源类别暂为 `not-reproduced`（三方来源尚未核对）；这不撤销当前源码 `present` 的判断。没有把旧版本报告直接归因于维护分支。
- 下一步：建立调用真实打开路径的行为红测，修补 YY 和无效目标保护，覆盖返回 false/异常及相邻站点，最后使用 Windows 候选验证菜单实际打开行为。本轮没有提交修复或标记 fixed。

## #855：CC 入口迁移，避免把部分返回扩大为全站结论

[报告](https://github.com/liuchuancong/pure_live/issues/855)于 2026-09-07 08:17 UTC 创建，称 CC 已停止运营并建议删除分区。报告未附官方公告，本轮未取得该公告原文。

匿名直连采样（2026-09-07 23:10–23:11 UTC）：

| 路径 | 实测 |
| --- | --- |
| CC 首页、`/category/?format=json` | 均重定向到 `https://ds.163.com/glive/`，200 HTML，21,640 B |
| `/api/category/live/?format=json&start=0&size=10` | 200 JSON，`lives` 返回 10 条，31,485 B |
| 同一公开样本的 anchor lives / channel 详情链 | 200；匹配 channel，`status=1`、`stream_list` 存在；未读取媒体字节 |

当前归类 `external-drift`：旧网页/分类入口确有迁移，但仍有部分旧后台响应。现有 CC 分类解析遇 HTML 时返回四个静态父分类，子分类为空；这避免解析崩溃，并不等于动态分类可用。推荐/详情返回也不证明原生播放、录制或全站运营状态。

后续应核验大神的新分类/房间合同与旧收藏身份兼容，明确呈现不可用的旧入口。此次保留平台及用户收藏，没有按单条报告删除整个平台，也未将四个空父分类记为验收通过。

采样 SHA256：首页/分类 `7d687bcc3f67fe0abf09aa8fab918b7dc13de3ded135da9cf12c3270bbc9769d`；推荐 `4878958aab2f1f46dfa5c24a01c723cc0642585867a39fe487eedf2afe42ba1d`；anchor `4177c95fe4165904dc7503b442e87d5e21c4918126437f95165579509d67a065`；channel `2d39ea9c7ceb53511a759dbd4c8ceae63cbe7673cb033acb8e216d0faede787a`。

## #849：新增一位报告者的运行库恢复证据

[报告及评论](https://github.com/liuchuancong/pure_live/issues/849)现有 7 条评论，更新到 2026-09-07 18:27 UTC。新日志指出 v3.1.2.4100 的 APPCRASH，模块 `MSVCP140.dll 14.0.24215.1`，异常 `c0000005`。同一报告者随后[确认重新安装/修复 VC++ 运行库后恢复启动](https://github.com/liuchuancong/pure_live/issues/849#issuecomment-5574413991)。另一报告者没有同样的恢复确认，Issue 仍 open；这不是所有 Windows 启动问题已解决的证据。单独文本附件本轮未成功读取，结论仅基于已读评论。

对该报告者归类 `environment-or-data`；其他机器仍为 `not-reproduced`。当前分支已有 Release app-local 三个 VC++ DLL 的构建门禁，[实际候选审计](WINDOWS_RELEASE_CPU_AUDIT_2026_09_07.md)已确认从包内加载 14.52.36615.0。复用这项历史措施，不重复改系统运行库，也不将其外推成报告者机器已验证当前包。

## 排序

先完成当前克拉克拉 API 验证收尾，再处理 YY 行为红测/修复及 CC 分类迁移；既有录制原生失败后的累计修订仍需复验。平台扩展、Windows 启动环境和原生验收分别记账。版本仍 3.1.8+4121，3.2.0 待完整验收。
