# 补丁说明

所有 `codex-*` 补丁针对 `ilysenko/codex-desktop-linux` 的固定版本
`9fb575b70b5ecdff51a0c534a5cbd231288e1058`（见 `flake.lock`）。
社区后端版本为 `0.4.9-linux-alpha1`，Desktop 版本 `26.917.61114`。

应用顺序（`packages/codex-desktop.nix`）：

| # | 补丁 | 修改的文件 | 用于 |
| --- | --- | --- | --- |
| 1 | `codex-niri-window-screenshot.patch` | `src/screenshot.rs`, `src/server.rs` | 后端 |
| 2 | `codex-niri-window-coordinates.patch` | `src/windowing/backends/niri.rs`, `src/server.rs` | 后端 |
| 3 | `codex-linux-native-drag.patch` | `src/server.rs`, `native-protocol.mjs`, `native-client.mjs` | 后端 + JS |
| 4 | `codex-linux-drag-interpolation.patch` | `src/abs_pointer.rs` | 后端 |
| 5 | `codex-niri-scroll-unicode.patch` | `src/server.rs` | 后端 |
| 6 | `codex-niri-agent-input.patch` | `src/niri_agent.rs`（新）, `src/server.rs`, `src/screenshot.rs` | 后端 |
| 7 | `codex-linux-native-launch.patch` | `native-client.mjs`, `native-protocol.mjs`, `native-backend-service.mjs` | 仅 JS |
| — | `niri-ipc-tiled-window-position.patch` | niri `src/layout/scrolling.rs` | niri |
| — | `niri-agent-input.patch` | niri `src/agent_input.rs`（新）, IPC, `handlers/` | niri（`agentInput`） |

1–6 构成 `backendSource`，Rust 后端由它构建；7 在其之上生成 `patchedSource`，只从中取 `.mjs` 文件。

## 1. 窗口截图 — `codex-niri-window-screenshot.patch`

**问题**：上游在 niri 下窗口原点为 `None`，portal 全屏截图无法按窗口裁剪。

**做法**：定向截图改用 `niri msg action screenshot-window --id … --path …`。在私有随机临时目录中轮询异步写出的 PNG，校验后删除临时文件。全屏截图和其他合成器路径不变。

**取舍**：
- 原生截图失败即报错，**绝不**退回整张桌面截图。
- 图像仍经过上游的尺寸/格式限制。
- 原生窗口尺寸不会被缓存成桌面尺寸。
- niri 的该命令会顺带把 PNG 放进剪贴板（已知副作用）。

## 2. 窗口坐标 — `codex-niri-window-coordinates.patch` + niri 补丁

**问题**：niri IPC 不报告平铺窗口的位置，窗口相对的点击/拖拽/滚动无法换算成全局指针坐标。

**做法**：
- `niri-ipc-tiled-window-position.patch` 让 niri 通过 `tile_pos_in_workspace_view` 报告平铺窗口当前的渲染位置。
- 后端将其与 `window_offset_in_tile` 相加，再加上窗口所在输出的逻辑原点，最后使用上游的 monitor-scale 换算发送指针输入。混合缩放、多输出布局下也正确。
- 读取不到工作区/输出元数据时丢弃坐标，拒绝操作。

**取舍**：上游 niri 刻意省略该位置数据，以免滚动视图移动时产生级联 IPC 窗口更新。补丁恢复它之后，订阅窗口事件的客户端可能收到更多更新。

## 3. 原生拖拽 — `codex-linux-native-drag.patch`

在原生桌面适配层暴露窗口相对的 `drag(from, to)`，后端实现按下—移动—释放序列，JS 协议与客户端增加对应调用。

## 4. 拖拽插值 — `codex-linux-drag-interpolation.patch`

GTK 应用需要在按键按下**之后**收到移动事件才会进入拖拽状态。补丁在按住按钮期间对 uinput 绝对指针的移动做插值，发出一系列中间点。

## 5. 滚动与 Unicode — `codex-niri-scroll-unicode.patch`

- **滚动**：ydotool 的绝对移动在 niri 下不能让滚轮事件落在目标位置。补丁先用已有的 uinput 绝对指针设备把指针移到目标点，再发送 ydotool 滚轮事件。
- **非 ASCII 输入**：
  - 一般窗口使用 `wtype`（niri 虚拟键盘），不动剪贴板；输入前敲一次修饰键修复首字符丢失。`wtype` 路径在构建时通过 `COMPUTER_USE_WTYPE_EXECUTABLE` 固定。
  - Chromium 系窗口（按 app id/class 识别）改为逐码点 `Ctrl+Shift+U` + 十六进制 + 空格，经 ydotool 发送，避免 Edge 148 在 contenteditable 中被 `wtype` 注入中文时主进程 SIGILL（具体触发的 Chromium 断言未知）。
  - 未指定目标时先解析聚焦的 niri 窗口，无法识别则拒绝输入。

## 6. 应用启动与新版 API — `codex-linux-native-launch.patch`

- `getApp(id)` 找不到运行中的窗口时，从 XDG/NixOS 应用目录解析 `.desktop` 条目，为启动进程重建唯一的 niri Wayland 会话环境，启动后绑定新窗口。接受精确的 desktop app id 或无歧义的显示名；已有窗口按显示名复用。
- 新增 `toggleMaximize()`，按绑定的 niri 窗口 id 切换最大化。
- 适配 Desktop 26.917 的 Linux CUA 接口：
  - `listWindows()`、`getApp({ windowId })`、`computer.launch_app()`；
  - 滚动距离从像素换算成页（`pixels / 500`，至少 1）；
  - 社区清单成功后，移除内置原生清单失败带来的 `Native apps:` 错误。
- 旧的字符串 app id 仍然可用。

## 6. agent 输入 — `codex-niri-agent-input.patch` + `niri-agent-input.patch`

详见 [agent-input.md](agent-input.md)。后端在运行时探测 niri 是否支持 `AgentInput`（发送一个 `window_id: 0` 的请求，补丁版回答 "no window with id 0"），支持时：

- 带窗口目标的 `click` / `scroll` / `drag` / `press_key` / `type_text` 走 `AgentInput`，**不调用** `focus_target_for_input`（它会激活窗口）；
- niri 窗口截图走 `AgentScreenshot`，`screenshot` 不再抬起窗口；
- 截图坐标按 `AgentScreenshot` 返回的缩放与几何偏移换算成窗口内逻辑坐标（顺带修正了 CSD 阴影导致的 16–22px 偏移）。

其余情况（元素索引点击、未知按键名、无窗口目标、未打补丁的 niri、`CODEX_COMPUTER_USE_NIRI_AGENT=0`）沿用补丁 1–5 的原路径。

## 回到上游

在宿主中设置 `programs.codexComputerUse.package = inputs.computer-use.inputs.codex-desktop-linux.packages.${system}.codex-desktop-computer-use-ui;` 即可使用未打补丁的 Desktop；`patchNiri = false` 可恢复原版 niri。
