# NixOS 模块：`programs.codexComputerUse`

`nixosModules.default` 会自动导入上游的 `codex-desktop-linux.nixosModules.default`，使用方无需再单独添加 `codex-desktop-linux` 输入。

## 选项

| 选项 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `enable` | bool | `false` | 启用整套配置 |
| `package` | package | `computer-use.packages.${system}.codex-desktop` | 传给 `programs.codexDesktopLinux.package` 的 Desktop 包 |
| `users` | list of str | `[ ]` | 加入 `ydotool` 组的用户（可访问 ydotool socket 与 `/dev/uinput`） |
| `patchNiri` | bool | `true` | 用补丁覆盖 `programs.niri.package` |
| `mcpWrapper.enable` | bool | `true` | 安装 `codex-computer-use` 到 `environment.systemPackages` |

## 启用后实际设置的内容

```nix
programs.codexDesktopLinux = {
  enable = true;
  package = cfg.package;
  linuxFeatures = [ "computer-use-linux" ];
};

programs.ydotool.enable = true;                 # 键盘输入
boot.kernelModules = [ "uinput" ];              # 原生指针输入
services.udev.extraRules = ''
  KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="ydotool", MODE="0660"
'';

services.gnome.at-spi2-core.enable = true;      # 可访问性树
programs.dconf.profiles.user.databases = [{
  settings."org/gnome/desktop/interface".toolkit-accessibility = true;
}];

users.users.<name>.extraGroups = [ "ydotool" ]; # 对 cfg.users 中每个用户

# patchNiri = true
programs.niri.package = pkgs.niri.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./patches/niri-ipc-tiled-window-position.patch ];
});

# mcpWrapper.enable = true
environment.systemPackages = [ codex-computer-use ];  # 指向 cfg.package 内的后端
```

说明：

- niri 补丁作用于**宿主系统**的 `pkgs.niri`（而不是 codex-desktop-linux 的 nixpkgs），所以 niri 版本跟随你的系统 nixpkgs。若补丁与新版 niri 冲突，可暂时设 `patchNiri = false`，代价是平铺窗口上的窗口相对输入会被拒绝。
- `toolkit-accessibility` 写入 dconf 的**系统默认数据库**；若用户数据库（例如 Home Manager 的 `dconf.settings`）中显式设为 `false`，用户值优先。
- 模块本身不启用 `programs.niri`，由宿主配置决定。
- 包装脚本基于 `cfg.package` 生成，所以自定义 `package` 时 MCP 与 Desktop 仍然使用同一个后端。

## 示例

```nix
{ inputs, ... }:
{
  imports = [ inputs.computer-use.nixosModules.default ];

  programs.codexComputerUse = {
    enable = true;
    users = [ "alice" ];
  };
}
```

## 生效条件

- 切换后需要**完整注销再登录**：新的 niri 合成器才会加载补丁；新的 `ydotool` 组成员资格也只在新会话中生效。
- 仅重启 Codex Desktop 不会替换已在运行的合成器。
