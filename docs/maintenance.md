# 维护与排障

## 升级 Desktop 应用

应用和 Niri 后端分别锁定。只升级应用时：

```bash
nix flake update codex-desktop-current
nix build .#codex-desktop -L
nix flake check --no-build
```

推送后等待 CI 完成 Desktop、两份 helpers 和 Niri 文档输出的缓存上传，
再更新宿主的 `computer-use` 输入。宿主直接使用本仓库的 `codex-desktop`，
避免另行打包导致缓存路径不同。

## 升级上游 codex-desktop-linux 后端

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

niri 源码由本仓库的 `niri-src` 输入独立锁定；宿主 nixpkgs 提供工具链和系统库。
当前固定到主分支 `4263c9a17f80fc8019bd474f85b1cc1dcbac785c`（2026-10-13），
包含 [niri #4548](https://github.com/niri-wm/niri/pull/4548) 的新虚拟键盘/指针实现。

```bash
nix flake update niri-src
nix build .#niri-patched -L --cores 2 --max-jobs 1
```

更新源码后，需要更新 `packages/niri.nix` 的版本标识与 vendor hash、重新迁移两个
niri 补丁，并验证实际配置：`./result/bin/niri validate`。
构建保留上游测试，并覆盖 agent 在临时 keymap 之后输入、输入法抓取接收 keymap 更新的回归场景。

### #4548 的兼容性

- 虚拟键盘现在经过正常输入处理，快捷键、抓取和按键释放行为会随之改变；ydotool
  的 uinput 路径仍是物理输入。wtype 的临时 keymap 会暂时替换共享 seat keymap。
- agent 输入必须先调用 `restore_configured_keymap()`，再发送目标客户端的 keymap、
  查找字符和计算修饰键，避免拿 wtype 的临时映射解释固定 evdev keycode。
- Fcitx5 抓取键盘期间，Smithay 需要把 keymap 更新同步给输入法，否则 wtype 可能乱码。
  当前额外回移 [Smithay #2213](https://github.com/Smithay/smithay/pull/2213)，
  补丁固定在本仓库，应用到 Cargo vendor 中的 Smithay 0.7.0。
  后续 niri 的 Smithay pin 包含该修复时，应移除这个补丁和 `postPatch` 中的应用步骤。
- 虚拟键盘只通过 `modifiers` 设置的修饰状态仍共享 seat，设备销毁不保证清空这些状态。
  脚本应成对释放按键；不要据此删除 Chromium 的独立 Unicode 输入兼容路径。
- 虚拟指针采用输出变换后的坐标处理；有旋转或混合缩放时需重新检查 VNC 的点击位置。

切换软件包不能替换运行中的 niri。宿主使用图形 greeter 时，按宿主约定部署到下次
启动并重启，或在安全时完整注销再登录；不要在活动桌面中重启 `niri.service`。

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
