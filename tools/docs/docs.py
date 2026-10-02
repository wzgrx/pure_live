"""Generates the docs indexes from docs/tasks.toml and checks the docs.

docs/tasks.toml is the only source of task numbers, states and stages. This
script writes the files derived from it (docs/STATUS.md, docs/TASKS.md,
docs/MAPPING.md, every group's and sub-category's README.md) and checks:
the registry itself, that every task folder under docs/ is registered, that
every relative link in docs/ resolves, and that every docs/ path named in
the code exists.

usage:
  python3 tools/docs/docs.py          write the generated files
  python3 tools/docs/docs.py --check  write nothing; exit 1 if a generated
                                      file is stale or a check fails (gate)
"""

from __future__ import annotations

import os
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs'
REGISTRY = DOCS / 'tasks.toml'
HEADER = '<!-- 由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改 -->\n'

STATUSES = ['未开始', '设计中', '待确认', '已确认', '开发中', '暂停', '受阻', '待真机', '完成', '不做']
TYPES = ['界面', '功能', '平台', '性能', '原生', '验证', '发布', '工程', '文档']
SIZES = {'小': 1, '中': 2, '大': 4}
TIERS = {1: '第一档', 2: '第二档', 3: '第三档'}
# Progress of a task without stages, by state.
STATE_PROGRESS = {
    '未开始': 0.0,
    '设计中': 0.15,
    '待确认': 0.25,
    '已确认': 0.35,
    '开发中': 0.6,
    '暂停': 0.3,
    '受阻': 0.5,
    '待真机': 0.9,
    '完成': 1.0,
}
OPEN = {'未开始', '设计中', '待确认', '已确认', '开发中', '暂停', '受阻'}
BAR = 20

# Old documents and where their content went (MAPPING.md, last section).
OLD_DOCS = [
    ('docs/PLAN.md（模块重构计划）', '[PLAN.md](PLAN.md)；还有效的工程规则在 [specs/ENGINEERING.md](specs/ENGINEERING.md)'),
    ('docs/UPGRADES.md', '[specs/UPGRADES.md](specs/UPGRADES.md)'),
    ('docs/ui/UI_PLAN.md', '[specs/UI.md](specs/UI.md)'),
    ('docs/ui/TASKS.md、docs/features/TASKS.md、docs/4.0.x/TASKS.md', '[TASKS.md](TASKS.md)、[STATUS.md](STATUS.md)（由 tasks.toml 生成）'),
    ('docs/ui/PROCESS.md、docs/features/PROCESS.md、docs/features/FEATURE_PLAN.md', '[PROCESS.md](PROCESS.md)、[PLAN.md](PLAN.md)'),
    ('docs/ui/INVENTORY.md、TASK_FILES.md、V3_UI_INVENTORY.md', '[inventory/](inventory/README.md) 的 UI.md、UI_FILES.md、V3_UI.md'),
    ('docs/features/INVENTORY.md', '[inventory/FEATURES.md](inventory/FEATURES.md)'),
    ('docs/features/TASKS.md 第 5 节（K90 真机清单）', '[T15/T15b/CHECKLIST.md](T15/T15b/CHECKLIST.md)'),
    ('docs/ui/compare/<编号>/、docs/ui/records/<编号>.md', '对应任务的文件夹（`README.md` 设计、`record.md` 记录）'),
    ('docs/features/<编号>/、docs/features/records/', '对应任务的文件夹（`README.md` 说明、`record.md` 记录）'),
    ('docs/modules/<编号>.md', '对应任务的文件夹（`record.md`）'),
    ('docs/4.0.x/tasks/、records/', '对应任务的文件夹（`brief.md` 任务书、`record.md` 记录）'),
    ('docs/4.0.x/audit-2026-10-02.md', '[T15/T15b/audit-2026-10-02.md](T15/T15b/audit-2026-10-02.md)'),
    ('docs/4.0.x/research-smoothness-2026-10-02.md', '[T14/research-2026-10-02.md](T14/research-2026-10-02.md)'),
    ('docs/readme/、docs/releases/', '[T16/T16c/](T16/T16c/README.md) 的 readme/、releases/'),
    ('docs/ui/templates/、docs/features/templates/', '[templates/](templates/README.md)'),
]

GROUP_RX = re.compile(r'T\d\d')
SUB_RX = re.compile(r'T\d\d[a-z]')
TASK_RX = re.compile(r'T\d\d[a-z]\.\d+')


def load() -> dict:
    with REGISTRY.open('rb') as f:
        return tomllib.load(f)


def progress(task: dict) -> float:
    status = task['status']
    if status in ('完成', '待真机'):
        return STATE_PROGRESS[status]
    stages = task.get('stages')
    if stages:
        return 0.9 * min(task.get('done', 0), len(stages)) / len(stages)
    return STATE_PROGRESS[status]


def weight(task: dict) -> int:
    return SIZES.get(task.get('size', '中'), 2)


def counted(tasks: list[dict]) -> list[dict]:
    return [t for t in tasks if t['status'] != '不做']


def ratio(tasks: list[dict]) -> float:
    tasks = counted(tasks)
    total = sum(weight(t) for t in tasks)
    return sum(weight(t) * progress(t) for t in tasks) / total if total else 0.0


def bar(value: float) -> str:
    filled = round(value * BAR)
    return '`' + '█' * filled + '░' * (BAR - filled) + f'` {round(value * 100)}%'


def stage_text(task: dict) -> str:
    stages = task.get('stages')
    if not stages:
        return '—'
    done = min(task.get('done', 0), len(stages))
    if task['status'] in ('完成', '待真机'):
        done = len(stages)
    if done >= len(stages):
        return f'{done}/{len(stages)}'
    return f'{done}/{len(stages)}：下一阶段“{stages[done]}”'


class Project:
    def __init__(self, data: dict) -> None:
        self.groups = data.get('group', [])
        self.subs = data.get('sub', [])
        self.tasks = data.get('task', [])
        self.problems: list[str] = []
        self.group_by = {g['id']: g for g in self.groups}
        self.sub_by = {s['id']: s for s in self.subs}
        self.tasks_of_sub: dict[str, list[dict]] = {s['id']: [] for s in self.subs}
        self.validate()

    def validate(self) -> None:
        seen: set[str] = set()
        for g in self.groups:
            if not GROUP_RX.fullmatch(g['id']):
                self.problems.append(f'组编号不对：{g["id"]}')
        for s in self.subs:
            if not SUB_RX.fullmatch(s['id']) or s['id'][:3] not in self.group_by:
                self.problems.append(f'子分类编号不对或组不存在：{s["id"]}')
        for t in self.tasks:
            tid = t.get('id', '?')
            if tid in seen:
                self.problems.append(f'任务编号重复：{tid}')
            seen.add(tid)
            if not TASK_RX.fullmatch(tid) or tid[:4] not in self.sub_by:
                self.problems.append(f'任务编号不对或子分类不存在：{tid}')
                continue
            self.tasks_of_sub[tid[:4]].append(t)
            if t.get('status') not in STATUSES:
                self.problems.append(f'{tid} 的状态不在 {"、".join(STATUSES)} 里：{t.get("status")}')
            if t.get('type') not in TYPES:
                self.problems.append(f'{tid} 的类型不在 {"、".join(TYPES)} 里：{t.get("type")}')
            if 'size' in t and t['size'] not in SIZES:
                self.problems.append(f'{tid} 的规模只能是小、中、大：{t["size"]}')
            if 'tier' in t and t['tier'] not in TIERS:
                self.problems.append(f'{tid} 的档位只能是 1、2、3：{t["tier"]}')
            if t.get('status') in OPEN and t.get('status') != '受阻' and 'tier' not in t:
                self.problems.append(f'{tid} 还没完成，要写档位（tier）')
            if t.get('status') in ('完成', '待真机') and 'date' not in t:
                self.problems.append(f'{tid} 已完成或待真机，要写日期（date）')
            if t.get('status') == '暂停' and not t.get('next'):
                self.problems.append(f'{tid} 暂停了，要写接手说明（next）')
            stages = t.get('stages')
            if stages is not None and not 0 <= t.get('done', 0) <= len(stages):
                self.problems.append(f'{tid} 的 done 超出了阶段数')
        for tasks in self.tasks_of_sub.values():
            tasks.sort(key=lambda t: int(t['id'].split('.')[1]))
        # Task folders on disk must be registered.
        for path in DOCS.glob('T??/T???/*'):
            if path.is_dir() and TASK_RX.fullmatch(path.name) and path.name not in seen:
                self.problems.append(f'没登记的任务文件夹：{path.relative_to(ROOT)}')

    def group_tasks(self, gid: str) -> list[dict]:
        return [t for s in self.subs if s['id'][:3] == gid for t in self.tasks_of_sub[s['id']]]

    # ---- paths and links
    @staticmethod
    def task_dir(tid: str) -> Path:
        return DOCS / tid[:3] / tid[:4] / tid

    def materials(self, tid: str, base: Path) -> str:
        folder = self.task_dir(tid)
        if not folder.is_dir():
            return '—'
        names = [
            ('README.md', '设计或说明'),
            ('brief.md', '任务书'),
            ('record.md', '记录'),
            ('record-2.md', '记录 2'),
            ('verify.md', '真机验证'),
            ('review.md', '合并审查'),
        ]
        links = [
            f'[{label}]({os.path.relpath(folder / name, base)})' for name, label in names if (folder / name).exists()
        ]
        if (folder / 'page').is_dir():
            first = sorted((folder / 'page').iterdir())
            if first:
                links.append(f'[评审页]({os.path.relpath(first[0], base)})')
        return '、'.join(links) or '—'

    def task_link(self, tid: str, base: Path) -> str:
        folder = self.task_dir(tid)
        target = folder / 'README.md' if (folder / 'README.md').exists() else DOCS / tid[:3] / tid[:4] / 'README.md'
        return f'[{tid}]({os.path.relpath(target, base)})'

    # ---- generated files
    def status_md(self) -> str:
        base = DOCS
        tasks = counted(self.tasks)
        counts = {s: sum(1 for t in self.tasks if t['status'] == s) for s in STATUSES}
        summary = ' · '.join(f'{s} {n}' for s, n in counts.items() if n)
        out = [HEADER, '# 总进度\n']
        out.append(
            '进度按登记表 [tasks.toml](tasks.toml) 计算：每个任务按规模加权（小 1、中 2、大 4，没写按中），'
            '有阶段的按做完的阶段算，没有阶段的按状态算（[PROCESS.md](PROCESS.md) 第 3 节）。'
            '新任务加进来，百分比会下降，这是正常的。\n'
        )
        out.append(f'## 全项目\n\n{bar(ratio(tasks))}\n\n{len(self.tasks)} 个任务：{summary}\n')
        out.append('## 按档位（还没完成的任务）\n')
        out.append('| 档位 | 进度 | 还剩 | 说明 |\n|---|---|---:|---|')
        notes = {1: '马上做：影响已发布的版本或天天用的功能', 2: '应该做：把这一轮收尾', 3: '以后：新客户端、冷门和增强'}
        for tier, name in TIERS.items():
            group = [t for t in tasks if t.get('tier') == tier]
            left = sum(1 for t in group if t['status'] in OPEN or t['status'] == '待真机')
            out.append(f'| {name} | {bar(ratio(group))} | {left} | {notes[tier]} |')
        out.append('')
        out.append('## 按组\n')
        out.append('| 组 | 进度 | 完成 / 全部 | 进行中 | 下一个 |\n|---|---|---:|---|---|')
        for g in self.groups:
            gt = counted(self.group_tasks(g['id']))
            done = sum(1 for t in gt if t['status'] == '完成')
            doing = [t['id'] for t in gt if t['status'] in ('设计中', '待确认', '开发中')]
            nxt = sorted(
                (t for t in gt if t['status'] in ('未开始', '已确认')),
                key=lambda t: (t.get('tier', 9), t['id']),
            )
            link = f'[{g["id"]} {g["title"]}]({g["id"]}/README.md)'
            out.append(
                f'| {link} | {bar(ratio(gt))} | {done} / {len(gt)} | {"、".join(doing) or "—"} | '
                f'{nxt[0]["id"] + " " + nxt[0]["title"] if nxt else "—"} |'
            )
        out.append('')
        sections = [
            ('正在做', ('设计中', '待确认', '开发中'), '这些任务做到一半，按阶段接着做。'),
            ('暂停', ('暂停',), '额度或时间不够时停下的任务；接手的人（或其他 AI）照“怎么接着做”继续。'),
        ]
        for title, states, intro in sections:
            rows = [t for t in self.tasks if t['status'] in states]
            out.append(f'## {title}（{len(rows)}）\n\n{intro}\n')
            if rows:
                out.append('| 任务 | 状态 | 阶段 | 停在哪、怎么接着做 |\n|---|---|---|---|')
                for t in rows:
                    where = '；'.join(x for x in (t.get('next', ''), ('分支：' + t['branch']) if t.get('branch') else '') if x)
                    out.append(
                        f'| {self.task_link(t["id"], base)} {t["title"]} | {t["status"]} | {stage_text(t)} | {where or "—"} |'
                    )
                out.append('')
        rows = [t for t in self.tasks if t['status'] == '待真机']
        out.append(f'## 待真机（{len(rows)}）\n\n代码已经合并，还没在真机上逐项看过。看过后改成“完成”。\n')
        out.append('| 任务 | 合并日期 | 提交 |\n|---|---|---|')
        for t in rows:
            out.append(f'| {self.task_link(t["id"], base)} {t["title"]} | {t.get("date", "—")} | {t.get("commit", "—")} |')
        out.append('')
        rows = sorted((t for t in self.tasks if t['status'] in ('未开始', '已确认') and t.get('tier') == 1), key=lambda t: t['id'])
        out.append(f'## 下一步：第一档里还没开始的（{len(rows)}）\n')
        out.append('| 任务 | 类型 | 规模 | 阶段 |\n|---|---|---|---|')
        for t in rows:
            out.append(
                f'| {self.task_link(t["id"], base)} {t["title"]} | {t["type"]} | {t.get("size", "—")} | '
                f'{"、".join(t.get("stages", [])) or "—"} |'
            )
        out.append('')
        rows = [t for t in self.tasks if t['status'] == '受阻']
        out.append(f'## 受阻（{len(rows)}）\n')
        for t in rows:
            out.append(f'- {self.task_link(t["id"], base)} {t["title"]}：{t.get("note", "—")}')
        out.append('')
        rows = sorted((t for t in self.tasks if t['status'] in ('完成', '待真机')), key=lambda t: (t.get('date', ''), t['id']), reverse=True)[:15]
        out.append('## 最近完成\n')
        out.append('| 日期 | 任务 | 状态 |\n|---|---|---|')
        for t in rows:
            out.append(f'| {t.get("date", "—")} | {self.task_link(t["id"], base)} {t["title"]} | {t["status"]} |')
        return '\n'.join(out) + '\n'

    def tasks_md(self) -> str:
        base = DOCS
        out = [HEADER, '# 任务清单\n']
        out.append(
            f'共 {len(self.groups)} 组、{len(self.subs)} 个子分类、{len(self.tasks)} 个任务。'
            '编号规则见 [PROCESS.md](PROCESS.md) 第 1 节，进度见 [STATUS.md](STATUS.md)，旧编号对照见 [MAPPING.md](MAPPING.md)。\n'
        )
        for g in self.groups:
            out.append(f'## {g["id"]} {g["title"]}\n\n{g["scope"]}\n\n{bar(ratio(self.group_tasks(g["id"])))}\n')
            for s in (s for s in self.subs if s['id'][:3] == g['id']):
                tasks = self.tasks_of_sub[s['id']]
                out.append(f'### [{s["id"]} {s["title"]}]({s["id"][:3]}/{s["id"]}/README.md)\n')
                if not tasks:
                    out.append('还没有任务。\n')
                    continue
                out.append('| 编号 | 任务 | 类型 | 档位 | 状态 | 阶段 | 资料 |\n|---|---|---|---|---|---|---|')
                for t in tasks:
                    out.append(
                        f'| {t["id"]} | {t["title"]} | {t["type"]} | {TIERS.get(t.get("tier"), "—")} | {t["status"]} | '
                        f'{stage_text(t)} | {self.materials(t["id"], base)} |'
                    )
                out.append('')
        return '\n'.join(out) + '\n'

    def mapping_md(self) -> str:
        out = [HEADER, '# 旧编号对照\n']
        out.append(
            '2026-10-02 之前用过五套编号：模块 M、界面 U、功能 F，以及 4.0.0 更新时的 B、P、U01、U02、F01、F02。'
            '提交信息和代码注释里还会看到它们，按下表找到新任务。旧文档的全文在 git 标签 `docs-archive-2026-10-02`。\n'
        )
        rows = []
        for t in self.tasks:
            for old in t.get('old', []):
                rows.append((old, t['id'], t['title']))

        def key(row: tuple[str, str, str]) -> tuple:
            old = row[0]
            kind = {'M': 0, 'U': 1, 'F': 2, 'B': 3, 'P': 4}.get(old[0], 5)
            if re.fullmatch(r'(U0|F0)\d', old):
                kind = 3
            nums = [int(n) for n in re.findall(r'\d+', old)]
            return (kind, nums, old)

        out.append('| 旧编号 | 新编号 | 任务 |\n|---|---|---|')
        for old, new, title in sorted(rows, key=key):
            out.append(f'| {old} | {self.task_link(new, DOCS)} | {title} |')
        out.append('\n## 旧的组编号\n')
        out.append('| 旧 | 新 |\n|---|---|')
        for old, new in [
            ('U.1 设计系统', 'T01'), ('U.2 直播间', 'T05（飞行弹幕、弹幕列表、本地互动在 T06）'), ('U.3、U.4、U.5 首页、浏览、搜索和历史', 'T07'),
            ('U.6 设置', 'T09a'), ('U.7 录制', 'T08'), ('U.10 账号', 'T10'), ('U.11 备份和同步', 'T09'), ('U.12 其他页面', 'T07（弹幕屏蔽在 T06b）'),
            ('U.15 电视', 'T18'), ('U.17 苹果平台', 'T19'), ('M4 各直播平台', 'T02'), ('M5 弹幕', 'T06a'), ('M7 播放', 'T04'), ('M13 各页面', '各页面所在的组'),
            ('M14 电视', 'T18'), ('M15 发布', 'T16a'), ('F.9 K90 验证', 'T15b'),
        ]:
            out.append(f'| {old} | {new} |')
        out.append('\n## 旧文档去了哪里\n')
        out.append('| 旧文档 | 现在 |\n|---|---|')
        for old, new in OLD_DOCS:
            out.append(f'| {old} | {new} |')
        return '\n'.join(out) + '\n'

    def group_md(self, g: dict) -> str:
        base = DOCS / g['id']
        tasks = self.group_tasks(g['id'])
        out = [HEADER, f'# {g["id"]} {g["title"]}\n', f'{g["scope"]}\n', f'{bar(ratio(tasks))}\n']
        out.append('| 子分类 | 范围 | 进度 | 完成 / 全部 |\n|---|---|---|---:|')
        for s in (s for s in self.subs if s['id'][:3] == g['id']):
            st = counted(self.tasks_of_sub[s['id']])
            done = sum(1 for t in st if t['status'] == '完成')
            out.append(f'| [{s["id"]} {s["title"]}]({s["id"]}/README.md) | {s["scope"]} | {bar(ratio(st)) if st else "—"} | {done} / {len(st)} |')
        out.append('')
        left = [t for t in tasks if t['status'] in OPEN or t['status'] == '待真机']
        out.append(f'## 还没完成的（{len(left)}）\n')
        if left:
            out.append('| 任务 | 状态 | 档位 | 阶段 |\n|---|---|---|---|')
            for t in sorted(left, key=lambda t: (t.get('tier', 9), t['id'])):
                out.append(f'| {self.task_link(t["id"], base)} {t["title"]} | {t["status"]} | {TIERS.get(t.get("tier"), "—")} | {stage_text(t)} |')
        else:
            out.append('没有。')
        extra = sorted(p for p in base.iterdir() if p.is_file() and p.name != 'README.md')
        if extra:
            out.append('\n## 资料\n')
            out += [f'- [{p.name}]({p.name})' for p in extra]
        out.append(f'\n决定见 [DECISIONS.md](../DECISIONS.md)，做法见 [PROCESS.md](../PROCESS.md)。')
        return '\n'.join(out) + '\n'

    def sub_md(self, s: dict) -> str:
        g = self.group_by[s['id'][:3]]
        base = DOCS / g['id'] / s['id']
        tasks = self.tasks_of_sub[s['id']]
        out = [HEADER, f'# {s["id"]} {s["title"]}\n', f'属于 [{g["id"]} {g["title"]}](../README.md)。{s["scope"]}\n']
        out.append(f'- 代码：{s["code"]}')
        out.append(f'- 进度：{bar(ratio(tasks)) if counted(tasks) else "还没有任务"}\n')
        out.append('## 任务\n')
        if tasks:
            out.append('| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |\n|---|---|---|---|---|---|---|')
            for t in tasks:
                out.append(
                    f'| {t["id"]} | {t["title"]} | {t["type"]} | {t["status"]} | {t.get("date", "—")} | '
                    f'{t.get("commit", "—")} | {self.materials(t["id"], base)} |'
                )
        else:
            out.append('还没有任务。')
        left = [t for t in tasks if t['status'] in OPEN]
        if left:
            out.append('\n## 还没完成的\n')
            for t in left:
                lines = [f'- **{t["id"]} {t["title"]}**（{t["status"]}，{TIERS.get(t.get("tier"), "—")}，规模 {t.get("size", "中")}）']
                if t.get('stages'):
                    marks = [('✓ ' if i < t.get('done', 0) else '') + st for i, st in enumerate(t['stages'])]
                    lines.append(f'  - 阶段：{" → ".join(marks)}')
                if t.get('next'):
                    lines.append(f'  - 接着做：{t["next"]}')
                if t.get('branch'):
                    lines.append(f'  - 分支：{t["branch"]}')
                if t.get('note'):
                    lines.append(f'  - 说明：{t["note"]}')
                out += lines
        extra = sorted(p for p in base.iterdir() if p.name != 'README.md' and not TASK_RX.fullmatch(p.name)) if base.is_dir() else []
        if extra:
            out.append('\n## 资料\n')
            for p in extra:
                target = p / 'README.md' if p.is_dir() and (p / 'README.md').exists() else p
                out.append(f'- [{p.name}{"/" if p.is_dir() else ""}]({os.path.relpath(target, base)})')
        return '\n'.join(out) + '\n'

    def generated(self) -> dict[Path, str]:
        files = {
            DOCS / 'STATUS.md': self.status_md(),
            DOCS / 'TASKS.md': self.tasks_md(),
            DOCS / 'MAPPING.md': self.mapping_md(),
        }
        for g in self.groups:
            files[DOCS / g['id'] / 'README.md'] = self.group_md(g)
        for s in self.subs:
            files[DOCS / s['id'][:3] / s['id'] / 'README.md'] = self.sub_md(s)
        return files


LINK_RX = re.compile(r'\]\(([^)\s]+)\)')
PATH_RX = re.compile(r'(?<![\w/.\-])docs/[A-Za-z0-9_.\-/]*[A-Za-z0-9_\-]')
CODE_DIRS = ['apps', 'packages', 'tools']
CODE_FILES = ['README.md', 'AGENTS.md', 'CLAUDE.md', 'toolchain.env', 'pubspec.yaml']
CODE_EXT = {'.dart', '.py', '.sh', '.kt', '.md', '.yaml', '.json', '.kts', '.xml'}


def check_links(contents: dict[Path, str]) -> list[str]:
    problems = []
    for path in sorted(DOCS.rglob('*.md')):
        if 'templates' in path.relative_to(DOCS).parts:
            continue  # placeholders like v3-xxx.jpg
        text = contents.get(path) if path in contents else path.read_text(encoding='utf-8')
        for target in LINK_RX.findall(text):
            if re.match(r'^[a-z]+:', target) or target.startswith('#'):
                continue
            rel = target.split('#', 1)[0]
            if not (path.parent / rel).exists() and (path.parent / rel) not in contents:
                problems.append(f'{path.relative_to(ROOT)}：链接找不到 {target}')
    return problems


def check_code_paths() -> list[str]:
    problems = []
    files = [ROOT / f for f in CODE_FILES if (ROOT / f).exists()]
    for d in CODE_DIRS:
        for p in (ROOT / d).rglob('*'):
            if p.is_file() and p.suffix in CODE_EXT and 'build' not in p.parts and '.dart_tool' not in p.parts and 'kit' not in p.parts:
                if p != Path(__file__).resolve():  # this file names the old documents on purpose
                    files.append(p)
    for p in files:
        try:
            text = p.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue
        for m in PATH_RX.finditer(text):
            ref = m.group(0)
            if '<' in ref or ref.endswith(('.', '-')):
                continue
            if not (ROOT / ref).exists():
                problems.append(f'{p.relative_to(ROOT)}：提到的 {ref} 不存在')
    return problems


def main() -> int:
    check = '--check' in sys.argv
    project = Project(load())
    files = project.generated()
    problems = list(project.problems)
    stale = []
    for path, text in files.items():
        old = path.read_text(encoding='utf-8') if path.exists() else None
        if old != text:
            if check:
                stale.append(str(path.relative_to(ROOT)))
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8')
    if stale:
        problems.append('生成的文件不是最新的（运行 python3 tools/docs/docs.py）：' + '、'.join(stale))
    problems += check_links(files if check else {})
    problems += check_code_paths()
    for p in problems:
        print(p, file=sys.stderr)
    if not check:
        print(f'docs: {len(files)} 个文件已生成，{len(problems)} 个问题')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
