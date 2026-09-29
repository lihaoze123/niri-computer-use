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
- 整理为独立 flake 后，`codex-desktop` 的输出路径与原配置中的构建完全一致
  （`/nix/store/ri5b24d20g0f9b8l25m0nzgpprvllhjz-codex-desktop-computer-use-linux-26.917.61114`）。
