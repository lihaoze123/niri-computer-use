# NixOS module: Codex Desktop Computer Use on niri.
{ self, codex-desktop-linux }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.codexComputerUse;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  pluginDir = "opt/codex-desktop/resources/plugins/openai-bundled/plugins/unified-computer-use";
in
{
  imports = [ codex-desktop-linux.nixosModules.default ];

  options.programs.codexComputerUse = {
    enable = mkEnableOption "Codex Desktop with the niri-compatible Linux Computer Use backend";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.codex-desktop;
      defaultText = lib.literalExpression "computer-use.packages.\${system}.codex-desktop";
      description = "Patched Codex Desktop package passed to programs.codexDesktopLinux.";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "alice" ];
      description = ''
        Users allowed to drive input. They are added to the `ydotool` group,
        which owns both the ydotool daemon socket and /dev/uinput.
      '';
    };

    patchNiri = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Patch programs.niri.package so niri IPC reports tiled-window positions.
        Without it, window-relative clicks on tiled windows are refused.
        Requires a full logout/login after switching.
      '';
    };

    mcpWrapper.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install `codex-computer-use`, a wrapper around the bundled backend
        binary. `codex-computer-use mcp` serves the backend over stdio MCP.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      programs.codexDesktopLinux = {
        enable = true;
        package = cfg.package;
        linuxFeatures = [ "computer-use-linux" ];
      };

      # Keyboard input goes through the ydotool daemon socket.
      programs.ydotool.enable = true;

      # Native pointer input writes to /dev/uinput directly.
      boot.kernelModules = [ "uinput" ];
      services.udev.extraRules = ''
        KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="ydotool", MODE="0660"
      '';

      # AT-SPI accessibility tree for get_app_state / element actions.
      services.gnome.at-spi2-core.enable = true;
      programs.dconf.enable = true;
      programs.dconf.profiles.user.databases = [{
        settings."org/gnome/desktop/interface".toolkit-accessibility = true;
      }];

      users.users = lib.genAttrs cfg.users (_: { extraGroups = [ "ydotool" ]; });
    }

    (mkIf cfg.patchNiri {
      programs.niri.package = pkgs.niri.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ../patches/niri-ipc-tiled-window-position.patch ];
      });
    })

    (mkIf cfg.mcpWrapper.enable {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "codex-computer-use" ''
          exec ${cfg.package}/${pluginDir}/bin/codex-computer-use-linux "$@"
        '')
      ];
    })
  ]);
}
