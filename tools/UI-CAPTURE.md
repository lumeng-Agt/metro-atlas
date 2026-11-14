# UI 截图工具

让 agent「看见」界面。两条链路，各自独立。

## 为什么需要

Agent 没有视觉通道：能读源码、跑命令，但看不到渲染结果。CSS/Godot 布局的最终形态由渲染引擎在运行时决定，读代码只能推断意图。截图回流后，agent 用 `read_image` 才能真正审视界面。

## 一、Godot（metro-atlas-desktop）

Godot 4.7.2 已随项目内置，无需安装。

```powershell
# 单场景
powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-ui.ps1 -Scene workbench

# 多场景 + 指定分辨率
powershell -NoProfile -ExecutionPolicy Bypass -File tools\capture-ui.ps1 -Scene menu,workbench,station,saves -Size 1366x768
```

**可用场景**：`menu` / `workbench` / `station` / `saves`

**输出**：`test-artifacts/ui-shots/<时间戳>/ui-<scene>-<WxH>.png`

> 必须非 headless（需要 GPU 渲染）。脚本每次使用独立 `--data-dir`，不会碰真实存档。
> 界面由内部接口驱动到目标状态，**不冒充鼠标键盘试玩**。

### 直接调用引擎

```powershell
.tools\godot-runtime\Godot_v4.7.2-stable_win64_console.exe --path . `
  --script res://tools/capture_ui.gd -- `
  --data-dir=<隔离目录> --scene=workbench --size=1600x980 --out=<输出目录>
```

### 现有测试自带的截图

部分测试已内置截图逻辑，加 `--capture` 即可：

```powershell
.tools\godot-runtime\Godot_v4.7.2-stable_win64_console.exe --path . `
  --script res://tests/story_0202_checks.gd -- "--data-dir=<隔离目录>" "--capture"
```

## 二、Web（metro-atlas-upgrade）

依赖 `playwright-core`（已自动从 `metro-atlas-desktop/.tmp-src` 解析，或自行 `npm install`）。

```powershell
# 先起 dev server
npm run dev

# 另开一个终端截图
node tools/capture-web.mjs -- --url=http://127.0.0.1:5173 --sizes=1440x900,390x844
```

**注意**：`--` 之后才是脚本参数，否则 Node 会吞掉 `--url`。

**输出**：`test-artifacts/web-shots/<时间戳>/`
- `web-<WxH>.png` — 截图
- `diag-<WxH>.json` — 布局诊断：横向溢出、被裁切元素坐标、控制台错误

### 参数

| 参数 | 说明 | 默认 |
|---|---|---|
| `--url=` | 目标地址 | `http://127.0.0.1:5173` |
| `--sizes=` | 视口列表 `WxH,WxH` | `1440x900,1280x800,768x1024,390x844` |
| `--full-page` | 整页截图 | 否 |
| `--wait=` | 导航后等待毫秒 | `1200` |
| `--out=` | 输出目录 | 自动时间戳 |

## 给 agent 的用法

截完图后，把 PNG 路径交给 agent：

```
截图在 test-artifacts/ui-shots/20261113-191801/ui-workbench-1600x980.png，帮我看看布局问题
```

Agent 用 `read_image` 读取即可审视界面。Web 场景可同时提供 `diag-*.json`，让 agent 直接拿到溢出坐标而不必目测。
