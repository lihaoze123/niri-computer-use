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

带窗口目标（`window_id`、`app_id` 等）的 `screenshot`、`click`、`scroll`、`drag`、`press_key`、`type_text` 不会激活窗口，也不移动你的鼠标；结果消息会写明 "through niri agent input"。若你正在使用目标窗口所在的程序，调用会被拒绝（`target client holds the real pointer/keyboard focus`），这是有意为之：同一客户端无法区分两路输入。建议让 agent 使用单独的浏览器 profile/进程。

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
