# niri-computer-use

在 **NixOS + niri (Wayland)** 上运行 Codex Desktop 的 Linux Computer Use，并把同一个后端以 stdio MCP 的形式提供给 Claude Code 等客户端。

本仓库整理自一份在日常使用中的 NixOS 配置，以独立 flake 的形式提供，包含：

- 基于 [`ilysenko/codex-desktop-linux`](https://github.com/ilysenko/codex-desktop-linux) 的补丁版 Codex Desktop（Rust 后端 `codex-computer-use-linux` + JS 适配层）；
- 让 niri IPC 报告平铺窗口位置的 niri 补丁；
- **agent 输入补丁**（默认开启）：niri 新增 `AgentInput` / `AgentScreenshot` IPC，Computer Use 直接向目标窗口的客户端投递输入、离屏渲染截图——**不移动你的鼠标、不抢键盘焦点、不切换活动窗口，截图不弹通知、不覆盖剪贴板**；
- 一个 NixOS 模块，一次性配置好 ydotool、`/dev/uinput`、AT-SPI、dconf 与 niri；
- `codex-computer-use` 包装脚本，`codex-computer-use mcp` 即为 stdio MCP 服务器。

## 为什么需要这些补丁

上游社区后端在 niri 下把窗口原点设为 `None`，因为 niri 不对外暴露平铺窗口的屏幕坐标。结果是：针对单个窗口的截图裁剪失败、窗口相对坐标的点击/拖拽无法映射到全局坐标。另外还存在 GTK 拖拽不生效、滚轮不跟随指针、非 ASCII 输入丢首字符或让 Chromium 崩溃、新版 Desktop（26.917）API 变化等问题。详见 [docs/patches.md](docs/patches.md)。

## 快速开始

在你的系统 flake 中：

```nix
{
  inputs.computer-use.url = "github:lihaoze123/niri-computer-use";
  # 本地克隆也可以："git+file:///path/to/niri-computer-use"

  outputs = { nixpkgs, computer-use, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        computer-use.nixosModules.default
        {
          programs.niri.enable = true;
          programs.codexComputerUse = {
            enable = true;
            users = [ "alice" ];
          };
        }
      ];
    };
  };
}
```

`sudo nixos-rebuild switch` 之后**注销并重新登录**（niri 补丁只有在新的合成器进程中才生效，`ydotool` 组成员资格也需要新会话）。

然后注册到 Claude Code：

```bash
claude mcp add --scope user linux-cua -- codex-computer-use mcp
```

## 仓库结构

```
niri-computer-use/
├── flake.nix                 # 输出 packages / nixosModules / formatter
├── flake.lock                # codex-desktop-linux 固定在补丁对应的版本
├── packages/
│   └── codex-desktop.nix     # 补丁源码、Rust 后端、Desktop 覆盖、包装脚本
├── modules/
│   └── nixos.nix             # programs.codexComputerUse 模块
├── patches/                  # 7 个后端补丁 + 2 个 niri 补丁
└── docs/
```

## Flake 输出

| 输出 | 说明 |
| --- | --- |
| `packages.x86_64-linux.codex-desktop`（`default`） | 替换了后端二进制和 `.mjs` 适配层的 Codex Desktop |
| `packages.x86_64-linux.codex-computer-use-niri` | 单独的补丁版 Rust 后端（构建时运行测试） |
| `packages.x86_64-linux.codex-computer-use` | 指向 Desktop 内置后端的包装脚本 |
| `nixosModules.default` | `programs.codexComputerUse` 模块，已导入上游 `codexDesktopLinux` 模块 |

## 文档

- [docs/architecture.md](docs/architecture.md) — 组件与数据流
- [docs/nixos-module.md](docs/nixos-module.md) — 模块选项与它实际做了什么
- [docs/patches.md](docs/patches.md) — 每个补丁解决的问题与设计取舍
- [docs/agent-input.md](docs/agent-input.md) — 不抢焦点的 agent 输入：原理、协议、限制
- [docs/mcp.md](docs/mcp.md) — 作为 MCP 服务器接入 Claude Code
- [docs/maintenance.md](docs/maintenance.md) — 升级上游、排障
- [docs/validation.md](docs/validation.md) — 实机验证记录

## 已知限制

- 仅支持 `x86_64-linux`，主要针对 niri；其他合成器走上游原有路径。
- niri 窗口截图命令会顺带把 PNG 放进剪贴板。
- 上游插件版本号未变，重建后可能需要结束旧的插件进程/缓存。

## 许可证

[MIT](LICENSE)。

例外：`patches/niri-ipc-tiled-window-position.patch` 与 `patches/niri-agent-input.patch` 是对 [niri](https://github.com/YaLTeR/niri) 的修改，遵循 niri 的 GPL-3.0-or-later 许可证。`codex-*` 补丁修改的上游 [codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) 同为 MIT。Codex Desktop 本身是 OpenAI 的非自由软件，不包含在本仓库中。
