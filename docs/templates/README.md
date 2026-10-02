# 模板

模板 v2（2026-10-03）。新任务开工时把需要的模板复制到任务文件夹（`docs/<组>/<子分类>/<任务>/`），按 [PROCESS.md](../PROCESS.md) 填写。

| 模板 | 复制成 | 什么时候用 |
|---|---|---|
| [group.md](group.md) | 组文件夹的 `README.md`（生成区上面） | 组说明 |
| [sub.md](sub.md) | 子分类文件夹的 `README.md`（生成区上面） | 子分类说明 |
| [design.md](design.md) | `README.md` | 界面任务的设计说明 |
| [feature.md](feature.md) | `README.md` | 非界面任务（功能、平台、性能、原生、验证、发布、工程、文档）的说明：目标、3.x 和现状、方案或结果、验证 |
| [brief.md](brief.md) | `brief.md` | 交给执行者（人或任何 AI）的任务书 |
| [record.md](record.md) | `record.md` | 开发记录（分几次做的另写 `record-2.md`） |
| [verify.md](verify.md) | `verify.md` | 真机验证 |
| [review.md](review.md) | `review.md` | 合并审查 |
| [page.json](page.json) | `page.json` | 界面任务的评审页（`python3 tools/ui/mock/page.py <路径>` 生成） |

登记表里新任务的写法见 [PROCESS.md](../PROCESS.md) 第 3.1 节。
