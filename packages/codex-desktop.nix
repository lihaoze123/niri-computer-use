# Patched Codex Desktop with a niri-compatible Linux Computer Use backend.
#
# Everything is built with the nixpkgs pinned by codex-desktop-linux so the
# Rust backend and the Electron package stay binary-compatible with upstream.
{ upstream, system }:
let
  pkgs = import upstream.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  # crates.io API downloads are rate limited/redirected; fetch from the
  # static mirror instead.
  buildRustPackage = pkgs.rustPlatform.buildRustPackage.override {
    importCargoLock = pkgs.rustPlatform.importCargoLock.override {
      fetchurl = args: pkgs.fetchurl (args // {
        url = builtins.replaceStrings
          [ "https://crates.io/api/v1/crates" ]
          [ "https://static.crates.io/crates" ]
          args.url;
      });
    };
  };

  # Patches for the Rust backend (`codex-computer-use-linux`).
  compatibilityPatches = [
    ../patches/codex-niri-window-screenshot.patch
    ../patches/codex-niri-window-coordinates.patch
    ../patches/codex-linux-native-drag.patch
    ../patches/codex-linux-drag-interpolation.patch
    ../patches/codex-niri-scroll-unicode.patch
    # Uses niri's AgentInput/AgentScreenshot IPC when available (see niri-agent-input.patch);
    # falls back to the patches above otherwise.
    ../patches/codex-niri-agent-input.patch
  ];

  backendSource = pkgs.applyPatches {
    name = "codex-desktop-linux-niri-source";
    src = upstream;
    patches = compatibilityPatches;
  };

  # The JavaScript adapter patch is applied on top of the backend patches;
  # it only touches linux-features/computer-use-linux/*.mjs.
  patchedSource = pkgs.applyPatches {
    name = "codex-desktop-linux-native-launch-source";
    src = backendSource;
    patches = [ ../patches/codex-linux-native-launch.patch ];
  };

  backend = buildRustPackage {
    pname = "codex-computer-use-niri";
    version = "0.4.9-linux-alpha1";
    src = backendSource;
    cargoLock.lockFile = backendSource + "/Cargo.lock";
    cargoBuildFlags = [ "-p" "codex-computer-use-linux" "--bin" "codex-computer-use-linux" ];
    cargoTestFlags = [ "-p" "codex-computer-use-linux" "--bin" "codex-computer-use-linux" ];
    doCheck = true;
    COMPUTER_USE_WTYPE_EXECUTABLE = "${pkgs.wtype}/bin/wtype";
  };

  pluginDir = "opt/codex-desktop/resources/plugins/openai-bundled/plugins/unified-computer-use";

  desktop = upstream.packages.${system}.codex-desktop-computer-use-ui.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      install -m755 ${backend}/bin/codex-computer-use-linux \
        "$out/${pluginDir}/bin/codex-computer-use-linux"
      install -m644 ${patchedSource}/linux-features/computer-use-linux/native-client.mjs \
        "$out/${pluginDir}/scripts/native-client.mjs"
      install -m644 ${patchedSource}/linux-features/computer-use-linux/native-service.mjs \
        "$out/${pluginDir}/scripts/native-service.mjs"
      install -m644 ${patchedSource}/linux-features/computer-use-linux/native-backend-service.mjs \
        "$out/${pluginDir}/scripts/native-backend-service.mjs"
      install -m644 ${patchedSource}/linux-features/computer-use-linux/native-protocol.mjs \
        "$out/${pluginDir}/scripts/native-protocol.mjs"
    '';
    passthru = (old.passthru or { }) // { niriBackend = backend; };
  });

  # Stdio entry point for MCP clients such as Claude Code:
  #   codex-computer-use mcp
  # It runs the exact binary bundled into `desktop`, so both share one build.
  wrapper = pkgs.writeShellScriptBin "codex-computer-use" ''
    exec ${desktop}/${pluginDir}/bin/codex-computer-use-linux "$@"
  '';
in
{
  inherit backend desktop wrapper;
}
