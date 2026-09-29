# 验证记录

以下为作者在自己机器上的实机验证记录，环境为 NixOS + niri，笔记本内屏 2× 缩放输出。

## 2026-09-11 / 2026-09-12

- Rust 截图相关测试：22 通过，0 失败。
- 实机 `cua.getApp(...).getScreenshot()` 返回正确的 ChatGPT 窗口。
- 实机 `getAXStateAndScreenshot` 返回 960 像素宽的图像，无错误。
- 带坐标的后端构建成功。启用重建后的 niri 合成器后验证实机坐标输入：niri 返回非空的平铺窗口位置，后端在 2× 输出上报告全局边界，窗口相对的点击和文本输入成功。
- 原生桌面适配层暴露窗口相对的 `drag`；在 2× niri 输出上的实机拖拽产生了预期的文本选区，随后通过点击清除。
- 按住按钮期间对拖拽移动做插值（GTK 需要按下后的移动事件）。Computer Use 完整 Rust 测试通过（281 项）。在实机 Inkscape 中，Computer Use 用形状拖拽创建了 11 个对象的机器人、编组、整体移动并从角点缩放。

## 2026-09-22

- `getApp(id)` 找不到运行窗口时启动已安装的 `.desktop` 应用：从 XDG/NixOS 应用目录解析条目，重建 niri Wayland 会话后绑定新窗口。
  - `cua.getApp('neovide')` 启动 Neovide 并返回其聚焦的 niri 窗口；
  - `cua.getApp('org.inkscape.Inkscape')` 启动了 Inkscape；
  - 已有 Inkscape 窗口按显示名复用，新启动的窗口在 Computer Use 会话重置后仍可用；
  - 系统中有一个过时的 `gvim.desktop`，其 `TryExec=gvim` 未安装，不能用于验证。
- `toggleMaximize()` 针对绑定的 niri 窗口 id；实机调用把 Neovide 从 756×963 扩展到 1560×995。
- 滚动：在 niri 实机中，同一个本地 Edge 页面用 ydotool 绝对移动时无法滚动，打补丁后可正确上下滚动。
- 非 ASCII 输入经 `wtype`：最初漏掉首字符，输入前敲一次修饰键后修复。Neovide 缓冲区截图显示完整的 `中文首字完整测试`。合并后端通过全部 281 项 Rust 测试。
- Edge 148 在 `wtype` 向 contenteditable 注入中文时主进程 SIGILL（Chromium 同一 `ud2` 偏移）；ASCII 输入稳定。改为 Chromium 窗口逐码点 `Ctrl+Shift+U` 输入后：
  - 实机 Edge 输入 `中文🙂` 无崩溃，不触碰剪贴板；
  - `cua.getApp('microsoft-edge').typeText('修复验证中文🙂abc123')` 完整显示，主进程存活；
  - 最终系统构建通过，全新会话在 Edge 中显示 `最终验证：中文🙂abc123`，无新崩溃；
  - 未定向的非 ASCII 输入先解析聚焦窗口，无法识别则拒绝。

## 2026-09-28

- Desktop 26.917 把 Linux CUA 公共接口改为 `listWindows()`、`getApp({ windowId })`、`computer.launch_app()` 和像素滚动距离。社区适配层只提供旧的字符串 app id，导致调用失败并报 `e.list_apps is not a function`，尽管 niri host socket 和 Rust 后端都正常。
- 适配层改为同时接受 `{ windowId }` 与旧 app id，提供 `listWindows()` 和 `computer.launch_app()`，换算像素滚动距离，并在社区清单成功后移除内置原生清单的失败错误。实机 26.917 会话枚举了 niri 窗口、按数字窗口 id 绑定 Edge、截取其窗口并成功滚动。完整 NixOS 系统构建通过。

## 2026-09-29

- 后端通过 `codex-computer-use mcp` 以 stdio MCP 形式接入 Claude Code（`linux-cua`）。
- 在嵌套 niri（winit 后端）中验证 agent 输入原型（`niri-agent-input.patch`），用 `wtype`/`wlrctl` 模拟用户、IPC 或 MCP 驱动 agent：
  - 两个 kitty 同时各输入 15 行：内容无串扰，真实焦点始终在"用户"窗口；期间 agent 窗口收到 46 次由 `wtype` 触发的 keymap 切换，agent 仍全部正确（每次按键前补发 seat keymap）。
  - GTK4（zenity）：未激活窗口中点击输入框、输入、点击确定，输出 `gtk agent ok`；前后截图光标位置一致。
  - Edge 148（独立 profile）：点击 textarea 并输入，页面事件为 mousedown/focus/keydown×N，无 blur。首次测试发现 Chromium 用 agent 点击的 serial 申请 xdg-activation 抢走焦点，改为降级为 urgent 后通过。
  - `<select>` 下拉（xdg_popup）：保持打开、键盘 ↓↓Enter 选中、直接点击选项、点击外部关闭均通过；`window.open` 新窗口不获得焦点。
  - 真实指针经过 agent 窗口后，agent 状态失效导致点击无效；改为检测真实焦点变化后重新 enter，复测通过。
  - `AgentScreenshot`：D-Bus 上无 `Notify` 调用，剪贴板保持不变。
  - `Text`：kitty 中 ASCII、中文、emoji 经临时 per-client keymap 完整输入；Edge 中中文/emoji 经 Ctrl+Shift+U 输入，无崩溃。
  - 补丁版后端经 stdio MCP：`screenshot`（来源 `niri-agent-window`）、相对坐标 `click`、`type_text`、`press_key` 均不改变真实焦点，无通知。
- 实机（重新登录后的补丁版 niri）经 Claude Code `linux-cua`：对后台 kitty/ghostty 的 `screenshot`、`type_text`（含中文、emoji）、`press_key` 均成功，焦点始终在用户的 ghostty，无通知、剪贴板不变。同一 ghostty 进程的另一窗口被拒绝（同一客户端），独立进程（`--gtk-single-instance=false`）的窗口可用。
- 发现屏幕外窗口在输入后立即截图得到旧画面（niri 对不可见窗口约 1 Hz 发帧回调）。加入帧泵与"等待无新提交"后，在嵌套 niri 中对屏幕外 kitty 输入后立即截图即显示新内容，截图耗时约 270 ms（debug 构建，空闲截图约 200 ms）。
- `NIRI_AGENT_LAUNCH=1`：嵌套 niri 中带标记直接启动的 kitty、经 `sh` 子进程启动的 kitty 均不获得焦点，无标记的对照组照常获得焦点。
- 整理为独立 flake 后，`codex-desktop` 的输出路径与原配置中的构建完全一致
  （`/nix/store/ri5b24d20g0f9b8l25m0nzgpprvllhjz-codex-desktop-computer-use-linux-26.917.61114`）。
