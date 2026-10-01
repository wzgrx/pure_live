# F.4b WebDAV Digest 认证

- 状态：未开始
- 档位：可以以后；规模：小
- 功能点：F-BAK-04（见 [INVENTORY.md](../INVENTORY.md)）
- 涉及代码：`apps/pure_live/lib/features/web_dav/web_dav_client.dart`
- 依赖：U.11b（WebDAV 界面）合并后
- 来源：M13.10“留给后续”、M13.18 任务说明第 4 项
- 评审页：按授权直接开发
- 记录：[records/F.4b.md](../records/F.4b.md)（开发后）

## 要做的

| 功能点 | v3 | v4 现在 | 要做到 |
|---|---|---|---|
| F-BAK-04 | webdav_client 支持 Basic 和 Digest（`modules/web_dav/web_dav_controller.dart:50`） | 只有 Basic（坚果云、Nextcloud、Alist 都用 Basic） | 服务器回 401 且要 Digest 时按 RFC 7616（MD5、qop=auth）重试 |

## 测试和验证

- 单元测试：本地假服务器要 Digest，测试连接、列目录、上传成功。

## 经过

| 日期 | 内容 |
|---|---|
| 2026-10-02 | 建立（第 1 版清点） |
