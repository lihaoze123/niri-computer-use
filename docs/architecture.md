# 架构

## 组件

```
┌────────────────────── Codex Desktop (Electron) ─────────────────────┐
│ unified-computer-use 插件                                           │
│   scripts/native-client.mjs          ← JS 适配层（CUA API → 后端调用）│
│   scripts/native-service.mjs                                        │
│   scripts/native-backend-service.mjs ← 启动 .desktop 应用等          │
│   scripts/native-protocol.mjs                                       │
│   bin/codex-computer-use-linux       ← 补丁版 Rust 后端              │
└─────────────────────────────────────────────────────────────────────┘
                 │                               ▲
                 │ 同一个二进制                   │ stdio MCP
                 ▼                               │
        codex-computer-use (包装脚本) ──── Claude Code (`linux-cua`)

Rust 后端依赖的系统能力：
  截图      niri msg action screenshot-window / GNOME Shell / XDG Portal
  窗口信息  niri IPC（补丁后提供平铺窗口位置）
  可访问性  AT-SPI（at-spi2-core + toolkit-accessibility）
  指针      /dev/uinput 绝对指针设备
  键盘      ydotool 守护进程；非 ASCII 走 wtype（niri 虚拟键盘）
            或 Chromium 的 Ctrl+Shift+U 码点输入
```

## 构建流程（`packages/codex-desktop.nix`）

1. 用 `codex-desktop-linux` 自己锁定的 nixpkgs 实例化 `pkgs`（允许 unfree），保证与上游 Desktop 包二进制兼容。
2. `backendSource` = 上游源码 + 5 个后端补丁（截图、坐标、拖拽、拖拽插值、滚动/Unicode）。
3. `patchedSource` = `backendSource` + `codex-linux-native-launch.patch`（只改 `.mjs`）。
4. `backend` = 从 `backendSource` 构建 `codex-computer-use-linux`，`doCheck = true` 运行完整 Rust 测试；`COMPUTER_USE_WTYPE_EXECUTABLE` 在编译期固定 `wtype` 路径。crates 下载改走 `static.crates.io`。
5. `desktop` = 上游 `codex-desktop-computer-use-ui` 的 `overrideAttrs`，在 `postInstall` 中替换插件的后端二进制和 4 个 `.mjs` 文件。`passthru.niriBackend` 指向 `backend`。
6. `wrapper` = `codex-computer-use`，直接 `exec` Desktop 包里的后端二进制，因此 MCP 与 Desktop 共用一次构建。

## 坐标映射

niri 下窗口相对坐标 → 全局坐标的换算：

```
全局位置 = 输出(output)的逻辑原点
         + tile_pos_in_workspace_view   ← niri 补丁新增
         + window_offset_in_tile
然后按上游的 monitor-scale 逻辑换算为指针坐标
```

任何一项工作区/输出元数据读取失败时，后端丢弃坐标并拒绝操作，而不是点击一个可能无关的全局位置。

## 非 ASCII 文本输入

- 普通 niri 窗口：`wtype` 通过 niri 虚拟键盘输入，不经过剪贴板；输入前先敲一次修饰键，避免丢失首字符。
- Chromium 系浏览器（按 app id / class 识别）：`wtype` 向 contenteditable 注入中文会让 Edge 148 主进程 SIGILL，因此改为每个码点发送 `Ctrl+Shift+U` + 十六进制 + 空格（经 ydotool）。
- 未指定目标的非 ASCII 输入会先解析当前聚焦的 niri 窗口，无法识别时拒绝输入。
