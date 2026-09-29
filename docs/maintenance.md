# 维护与排障

## 升级上游 codex-desktop-linux

补丁针对固定版本编写，升级需逐个验证：

```bash
cd ~/computer-use
nix flake update codex-desktop-linux
nix build .#codex-computer-use-niri -L   # 应用补丁并运行 Rust 测试
nix build .#codex-desktop -L
```

补丁应用失败时：

1. 克隆上游到新版本，按 `docs/patches.md` 中的顺序 `git apply` 1–5，然后 6；
2. 解决冲突后用 `git diff` 重新生成对应补丁覆盖到 `patches/`；
3. 如果上游已合并某项修复，从 `packages/codex-desktop.nix` 的列表中删掉该补丁；
4. 重建后在实机上按 `docs/validation.md` 的场景回归（截图、点击、拖拽、滚动、中文输入、启动应用）。

更新 `docs/patches.md` 顶部记录的上游 rev 与 Desktop 版本。

## 升级 niri

niri 补丁作用于宿主系统的 nixpkgs。宿主 `nix flake update` 后若 niri 构建失败，基于新版 `src/layout/scrolling.rs` 重新生成 `niri-ipc-tiled-window-position.patch`，或临时 `patchNiri = false`。

## 在系统配置中更新本仓库

```bash
cd /path/to/your-nixos-config
nix flake update computer-use
nixos-rebuild build --flake .#myhost
```

使用本地 `git+file://` 输入时，只有**已提交**的改动会被读取。

## 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 窗口相对点击被拒绝，提示缺少坐标 | 当前运行的 niri 不是补丁版：确认 `patchNiri = true`，然后注销重新登录 |
| 重建后行为没变 | 上游插件版本号未变，旧插件进程/缓存仍在；退出 Codex Desktop 并结束残留的 `codex-computer-use-linux` 进程，Claude Code 中 `/mcp` 重连 |
| 键盘/指针输入无效或权限错误 | 用户不在 `ydotool` 组或会话未刷新：检查 `id`，重新登录；确认 `ls -l /dev/uinput` 属组为 `ydotool` |
| `get_app_state` 没有可访问性树 | 应用未开启 AT-SPI：运行 `doctor`，必要时 `setup_accessibility`；确认 `gsettings get org.gnome.desktop.interface toolkit-accessibility` 为 `true` |
| Edge/Chrome 中输入中文崩溃 | 应走 Ctrl+Shift+U 路径；若浏览器 app id 未被识别为 Chromium，检查 `niri msg windows` 中的 app id |
| `e.list_apps is not a function` | JS 适配层不是补丁版（Desktop 26.917 的 API 变化），确认 Desktop 使用的是本仓库的 `codex-desktop` |
| 截图意外进入剪贴板 | `niri msg action screenshot-window` 的已知副作用 |
