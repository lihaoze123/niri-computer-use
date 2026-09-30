# 不抢焦点的 agent 输入

目标：agent 操作某个窗口时，**你的鼠标位置、光标形状、键盘焦点和活动窗口都不变**，截图也不弹通知、不动剪贴板。

## 为什么不是 multiseat

- niri 只创建一个 `wl_seat`，维护者明确不做多 seat（[niri#3159](https://github.com/niri-wm/niri/discussions/3159)）。
- Chromium/Electron 只绑定第一个 `wl_seat`（`ui/ozone/platform/wayland/host/wayland_seat.cc`），第二个 seat 对它们无效。
- 嵌套 compositor 无法接管已经打开的窗口：Wayland 客户端不能迁移到另一个合成器。

## 原理：按客户端的虚拟焦点

Wayland 的 `wl_pointer` / `wl_keyboard` 是**每个客户端各有一份**，客户端只看得到发给自己的事件。`niri-agent-input.patch` 让 niri 直接向目标客户端的这些对象发送 `enter`、`motion`、`button`、`axis`、`key`、`modifiers`，而不改 smithay 的 seat 焦点状态。其他客户端（包括你正在用的）什么都收不到。

smithay 公开的 `PointerHandle::client_pointers` / `KeyboardHandle::client_keyboards` 足够实现，不需要改 smithay。

## IPC

```jsonc
// 输入：坐标为窗口几何（不含 CSD 阴影）内的逻辑坐标
{"AgentInput": {"window_id": 4, "events": [
  {"Motion": {"x": 300, "y": 193}},
  {"Button": {"button": 272, "pressed": true}},   // evdev 码
  {"Button": {"button": 272, "pressed": false}},
  {"Axis": {"vertical": 75, "horizontal": 0}},
  {"Key": {"keycode": 30, "pressed": true}},      // evdev 码
  {"Text": {"text": "中文 ok", "unicode_input": "Keymap"}},  // 或 "CtrlShiftU"
  "PointerLeave", "KeyboardLeave"
]}}

// 截图：无通知、不写剪贴板、被遮挡或不在当前工作区的窗口也能截
{"AgentScreenshot": {"window_id": 4, "path": "/abs/path.png", "show_pointer": false}}
// → {"Ok": {"AgentScreenshot": {"width": 776, "height": 1952, "scale": 1.0,
//                               "geometry_x": 16, "geometry_y": 16}}}
// 窗口坐标 = (图像像素 - geometry) / scale
```

## 补丁处理的细节

| 问题 | 处理 |
| --- | --- |
| 目标客户端正持有真实焦点 | 拒绝（`target client holds the real pointer/keyboard focus`）：事件不带 surface，客户端无法区分两路输入 |
| 其他虚拟键盘（wtype、输入法转发）把 keymap 广播给所有客户端 | 发键前只给目标客户端补发 seat keymap |
| Chromium 用 agent 点击的 serial 申请 xdg-activation | niri 记录 agent 发出的 serial，此类请求降级为 urgent |
| 已降级为 urgent 的激活 token 仍让新窗口聚焦（niri 原有问题） | 修正：urgency-only token 不聚焦新窗口 |
| agent 驱动的客户端打开新窗口 | 最近 30 秒收到过 agent 输入、且不是你当前使用的客户端时不聚焦 |
| agent 启动的新程序打开窗口时抢焦点 | 进程环境里有 `NIRI_AGENT_LAUNCH=1`（及其所有子进程，环境变量会继承）时，新窗口不获得焦点。`codex-computer-use` 包装脚本自动设置；也可以在 Claude Code 的 `settings.json` `env` 中设置，覆盖 agent 通过 shell 启动的程序 |
| 菜单/下拉（xdg_popup）grab 被 niri 拒绝 | grab serial 来自 agent 时：保持映射、不做 seat grab；agent 键盘进入 popup；agent 点击 popup 外时关闭 |
| 真实指针/键盘焦点经过 agent 的客户端后，客户端认为焦点已离开 | 检测 `pointer.last_enter()` 变化与键盘 `focus_changed`，下次 agent 操作前重新 enter |
| 键盘布局没有的字符 | `Keymap`：仅对目标客户端临时发送含这些字符的 keymap，输完立即恢复；`CtrlShiftU`：Chromium 使用（临时 keymap 曾让 Edge 在 contenteditable 中 SIGILL） |
| `screenshot-window` 弹通知、覆盖剪贴板 | `AgentScreenshot` 只写文件 |
| 屏幕外的窗口每秒只收到约 1 次帧回调，agent 操作后截图是旧画面 | agent 输入或截图过的窗口在 2 秒内按约 60 Hz 补发帧回调（帧泵）；截图等窗口 50 ms 无新提交（最多 500 ms）再截。空闲窗口立即截图 |

## 观察 agent 在做什么

agent 操作的窗口通常不在你的焦点上，补丁提供两种可见的提示：

- **agent 光标**：agent 指针画成一个靛蓝到紫色的渐变圆点，带白色描边和一圈淡光晕；另有一圈半透明深色细线，保证在浅色页面上也清楚。移动时约 180 ms 缓动滑到新位置，按下按钮时光晕收紧，同时扩散一圈涟漪。它随窗口一起移动和缩放（包括 overview），不会出现在 `AgentScreenshot` 里。
- **`is-agent-driven` 窗口规则**：窗口在 30 秒内收到过 `AgentInput` 或 `AgentScreenshot` 时匹配。超时后光标和规则一起消失。

推荐的规则写法：用同色系的细渐变边框，加一圈柔和的外发光：

```kdl
window-rule {
    match is-agent-driven=true
    border {
        on
        width 2
        active-gradient from="#818cf8" to="#c084fc" angle=135
        inactive-gradient from="#818cf8" to="#c084fc" angle=135
    }
    shadow {
        on
        softness 40
        spread 3
        offset x=0 y=0
        color "#a78bfa70"
    }
}
```

只有窗口可见时才能直接看到这些提示。窗口不在视野里时，可以用窗口投屏（xdg-desktop-portal，例如 OBS）另开一个预览：预览器是另一个客户端，聚焦它不影响 agent。窗口投屏不包含 agent 光标。

## 已知限制

- **同一进程冲突**：你和 agent 不能同时使用同一个客户端的窗口（例如同一个 Edge 进程的两个窗口）。让 agent 使用单独的浏览器 profile。
- agent 窗口里剪贴板不可用（`set_selection` 需要真实键盘焦点），文本请用 `type_text`。
- 不支持 Wayland DnD（`start_drag` 校验 seat grab serial）；应用内部的按住拖拽可用。
- 少数应用若只看 `xdg_toplevel` 的 activated 状态处理输入，可能不响应；kitty、GTK4、Chromium 已验证可用。
- 单实例应用（默认的 ghostty、Edge 同一 profile 等）的新窗口由已有进程创建，读不到 agent 的环境变量，仍会按原规则聚焦。
- 截图最多等待 500 ms；持续动画的窗口会等满 500 ms。
- 嵌套测试中，嵌套 niri 窗口若在宿主上不可见，宿主会把帧回调限到约 1 Hz，所有操作变慢；这是测试环境现象。
