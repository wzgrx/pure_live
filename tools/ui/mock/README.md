# 效果图工具

界面重构用的效果图、按钮编号示意图和对比评审页，都从这里生成。做法见 [docs/ui/PROCESS.md](../../../docs/ui/PROCESS.md)。

## 准备（每台机器一次）

```bash
flutter pub get                 # remixicon 字体从 pub 缓存取
bash tools/ui/mock/fetch.sh     # 字体（Material Icons、Geist）和示意图片下载到缓存，链接到 .cache/
```

还需要：Playwright 的 `chrome-headless-shell`（`npx playwright install chromium-headless-shell`）、`ffmpeg`、系统字体 Noto Sans CJK SC（Debian/Ubuntu 装 `fonts-noto-cjk`）。字体和图片不进仓库。

## 文件

| 文件 | 作用 |
|---|---|
| `kit/kit.css` | v3 的颜色角色（浅色、深色）、字体、图标字体，以及常用组件：手机框 `.ph`、横屏框 `.fs`、窗口 `.win`、状态栏、顶栏、画面和上下栏、信息行、标签、弹幕行、小菜单 `.menu`、对话框 `.dlg`、面板 `.sheet` / `.side`、按钮、开关、滑块、提示条 |
| `kit/annotate.js` | 按钮编号示意图：给控件加 `data-n` |
| `kit/page.css` | 对比评审页的样式 |
| `render.py` | HTML → JPEG |
| `page.py` | `page.json` → 对比评审页 |
| `fetch.sh`、`fonts.txt`、`images.txt` | 下载字体和示意图片 |
| `../strings.py` | 列出 v3 文件用到的文字（中文） |
| `../inventory.py` | 界面统计和逐项清单 |
| `../export_compare.py` | 对比页按章节导出图片 |

## 写一张效果图

`docs/ui/compare/<编号>/src/v4-phone.html`：

```html
<!doctype html><html><head><meta charset="utf-8">
<meta name="mock-size" content="393x852@3">
<link rel="stylesheet" href="kit/kit.css">
</head><body><div class="ph">
  <div class="status"><span>21:36</span><span class="r"><span class="mi">wifi</span><span class="mi">battery_full</span></span></div>
  <div class="appbar">
    <div class="back" data-n="1"><span class="mi">arrow_back</span></div>
    ...
  </div>
  <div class="video" style="background-image:url(.cache/img/158.jpg)"></div>
  <div class="gesture"></div>
</div></body></html>
```

- 路径相对 `tools/ui/mock/`（渲染时自动加 `<base href>`）：样式 `kit/kit.css`，示意图片 `.cache/img/<编号>.jpg`。
- 尺寸：`393x852@3` 手机竖屏，`852x393@2` 横屏，`740x360@2` 窄横屏，`1280x800@1.5` 宽屏，`1920x1080@1` 电脑或电视；长面板写 `393x2400@2 crop`，裁到内容末尾。横屏和窗口用 `.fs` / `.win`，在 style 里设 `--w`、`--h`。
- 图标：`<span class="mi">名字</span>`（Material）、`<span class="mr">名字</span>`（Material Round）、`<span class="rx">&#xea42;</span>`（Remix，码位查 `remixicon` 包）、`<span class="ci">&#xe806;</span>`（v3 的 CustomIcons）、`<span class="dmk open"></span>`（v3 的弹幕图标：open、close、set）。
- 编号：可点的控件加 `data-n="3"`，可选 `data-tag="chg|add|keep|prob"`（颜色）、`data-at="tc|tl|tr|bl|br|c"`（编号位置）。
- 深色：渲染时加 `--dark`，用 kit 里的深色角色。

## 生成

```bash
python3 tools/ui/mock/render.py docs/ui/compare/U.2c/src/                 # 整个目录
python3 tools/ui/mock/render.py docs/ui/compare/U.2c/src/v4-phone.html --annotate --dark
python3 tools/ui/mock/page.py docs/ui/compare/U.2c/page.json              # → ~/ref/design/compare/U.2c.html
python3 tools/ui/export_compare.py ~/ref/design/compare/U.2c.html docs/ui/compare/U.2c/page
```

`render.py` 把图写到 `src/` 的上一级（任务文件夹）：`v4-phone.jpg`，加 `--annotate` 多一张 `v4-phone-n.jpg`，加 `--dark` 多一张 `v4-phone-dark.jpg`。

## 评审页

`page.py` 生成的页面发布成 claude.ai 页面时声明 `db` 能力。页面上每条改动有“满意 / 不满意 / 再想想”和意见框，每个选择有“选 A / 选 B”，最后有整体意见；数据存在页面的 `review` 集合（每条一个文档：`verdict` 或 `pick`、`note`、`ver` 版本号、`at` 时间）。新版本发布到同一个地址后，旧版的表态显示为“第 N 版：……”，供对照。导出图片时这些按钮不显示。
