# 作为 MCP 服务器使用

Codex Desktop 插件中的 `codex-computer-use-linux` 本身支持 `mcp` 子命令，以 stdio 方式提供 MCP 服务。模块安装的 `codex-computer-use` 只是指向它的包装脚本，因此 Claude Code 与 Codex Desktop 使用**同一个**补丁版后端。

## 注册到 Claude Code

```bash
claude mcp add --scope user linux-cua -- codex-computer-use mcp
```

等价于 `~/.claude.json` 中：

```json
{
  "mcpServers": {
    "linux-cua": {
      "type": "stdio",
      "command": "codex-computer-use",
      "args": ["mcp"],
      "env": {}
    }
  }
}
```

该注册不由 Nix 管理；`codex-computer-use` 必须在 Claude Code 的 `PATH` 中（`mcpWrapper.enable = true` 时装在系统 profile 里）。

## 注册到 Codex CLI

Codex Desktop 内置的 Computer Use（`unified-computer-use` 插件提供的 `cua_repl`）依赖 Desktop 应用的 native pipe，在终端里运行的 Codex CLI 中会报 `native pipe path unavailable`。CLI 下应改用同一个后端的 MCP：

```bash
codex mcp add codex-computer-use -- codex-computer-use mcp
```

注意 `--` 后要写完整命令；漏掉程序名（如 `codex mcp add codex-computer-use mcp`）会得到 `command = "mcp"`，服务器无法启动，但 `codex mcp list` 仍显示 `enabled`。

然后在 `~/.codex/config.toml` 中补上 `omit_tools_from`：

```toml
[mcp_servers.codex-computer-use]
command = "codex-computer-use"
args = ["mcp"]
startup_timeout_sec = 60.0
omit_tools_from = ["code_mode", "deferred"]
```

Codex 默认延迟加载 MCP 工具，模型须先搜索才能看到；而 `cua_repl` 在插件里设置了同样的 `omit_tools_from`，始终直接可见。不加这一行时，即使 `/mcp` 显示 `codex-computer-use: connected`，模型仍会优先调用 `cua_repl` 并失败。

`unified-computer-use` 插件与 Desktop 共用 `~/.codex/config.toml`，关闭它会影响 Desktop 中的 Computer Use；`-c 'plugins."unified-computer-use@openai-bundled".enabled=false'` 也不会移除 `cua_repl`，因此保留它即可。修改配置后需重新启动 Codex 会话。

不使用 NixOS 模块时，也可以直接运行：

```bash
nix run github:lihaoze123/niri-computer-use#codex-computer-use -- mcp
```

但此时 ydotool、uinput 权限、AT-SPI 等系统前提需自行准备。

## 提供的工具

服务器暴露 `mcp__linux-cua__*` 工具，主要包括：

| 类别 | 工具 |
| --- | --- |
| 诊断/设置 | `doctor`, `setup_accessibility`, `setup_window_targeting` |
| 状态 | `get_app_state`, `list_apps`, `list_windows`, `focused_window`, `screenshot` |
| 窗口 | `activate_window`, `move_window`, `resize_window` |
| 指针 | `click`, `drag`, `scroll` |
| 键盘 | `type_text`, `press_key` |
| 可访问性 | `perform_action`, `set_value` |

## 与 agent 输入配合（`agentInput = true`）

带窗口目标（`window_id`、`app_id` 等）的 `screenshot`、`click`、`scroll`、`drag`、`press_key`、`type_text` 不会激活窗口，也不移动你的鼠标；结果消息会写明 "through niri agent input"。目标窗口有没有焦点都可以操作，定向输入前不需要 `activate_window`。agent 操作不会因为你同时在用该程序而失败，但同一客户端分不清两路输入：你中途在里面打字或拖拽，会和 agent 的输入混在一起。建议让 agent 使用单独的浏览器 profile/进程。

### 让 agent 启动的程序不抢焦点

`codex-computer-use` 已设置 `NIRI_AGENT_LAUNCH=1`。若希望 Claude Code 通过 Bash 启动的程序也不抢焦点，在 `~/.claude/settings.json` 中加入：

```json
{ "env": { "NIRI_AGENT_LAUNCH": "1" } }
```

## 使用建议

- 每轮使用 Computer Use 前先调用 `get_app_state`；诊断报告可访问性关闭时调用 `setup_accessibility`。
- 定向键盘输入前用 `list_windows` / `focused_window` 确认目标，再给 `type_text`/`press_key` 传 `window_id`、`app_id` 等选择器；无法唯一确定目标时后端会拒绝输入。
- 截图可通过 `max_width`、`max_height`、`max_bytes`、`format=jpeg` 控制体积；结果中的 `coordinate_width/coordinate_height` 与 `scale` 用于坐标换算。
- 能修改状态的工具（`readOnlyHint=false`）可能提交、删除、发送数据，客户端应要求确认。
