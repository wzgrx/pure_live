# 发给云端的提示词

在 Claude 桌面应用的 Code 标签页新建会话并选 **Cloud**（或打开 claude.ai/code），仓库选 `wzgrx/pure_live`，然后发下面的提示词。**一个任务开一个会话**，互不影响，可以同时开几个；先开哪些、哪些不能同时开，看 [TASKS.md](TASKS.md) 的“建议顺序”和“哪些能同时开”。

## 单个任务（最常用）

把 `<编号>` 换成任务编号（例如 `B01`）：

```text
你在 GitHub 仓库 wzgrx/pure_live 上工作。先完整读 docs/cloud/RULES.md（共同规则），再读 docs/cloud/tasks/<编号>.md（你的任务单），严格照做。
从最新的 master 新建分支 cloud/<编号>，只提交到这个分支，不要推送到 master，也不要合并 PR。
完成后：写 docs/cloud/records/<编号>.md，推送分支，开一个草稿 PR 到 master，最后用中文告诉我分支名、PR 链接、每条做到没有、测试结果和需要我决定的事。
```

## 一个会话连做几个小任务

只用于互不依赖、不在同一组的小任务（例如 B01 和 F02）；同一组有先后的任务（例如 B02 → B05）要等前一个合并进 master 再开：

```text
你在 GitHub 仓库 wzgrx/pure_live 上工作。先完整读 docs/cloud/RULES.md，再依次读 docs/cloud/tasks/<编号1>.md、<编号2>.md、<编号3>.md。
按顺序做，每个任务一个分支（cloud/<编号>，都从最新的 master 新建）、一份记录、一个草稿 PR；一个做完、推送、开好 PR 后再做下一个。不要推送到 master，也不要合并 PR。
全部做完后用中文汇总：每个任务的分支、PR 链接、做到没有、测试结果、需要我决定的事。
```

## 修改上一次的结果

维护者看过 PR 后有意见时，在同一个会话里接着发：

```text
按下面的意见修改分支 cloud/<编号>（不要新开分支），改完更新记录、推送，并回复改了什么：
<意见>
```

## 合并（维护者在本地做）

云端推送分支后，维护者在本地：

```bash
git fetch origin cloud/<编号> && git merge --no-ff origin/cloud/<编号>
```

然后跑 `bash tools/gate/gate.sh --all`，在 K90 上按记录里的步骤看，通过后推送 master，在 `docs/cloud/TASKS.md` 里把状态改成“完成”。
