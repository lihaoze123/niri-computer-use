{
  description = "Codex Desktop Linux Computer Use on niri: patched backend, NixOS module and MCP wrapper";

  inputs = {
    # Pin independently of Desktop so CI can cache the host's patched niri.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    # The patches are written against a specific upstream revision; see
    # docs/patches.md before running `nix flake update`.
    codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
  };

  outputs = { self, nixpkgs, codex-desktop-linux }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: builtins.listToAttrs (map
        (system: { name = system; value = f system; })
        systems);
    in
    {
      packages = forAllSystems (system:
        let
          built = import ./packages/codex-desktop.nix {
            upstream = codex-desktop-linux;
            inherit system;
          };
        in
        {
          codex-desktop = built.desktop;
          codex-computer-use-niri = built.backend;
          codex-computer-use = built.wrapper;
          niri-patched = import ./packages/niri.nix {
            pkgs = nixpkgs.legacyPackages.${system};
          };
          default = built.desktop;
        });

      nixosModules.default = import ./modules/nixos.nix {
        inherit self codex-desktop-linux;
      };

      formatter = forAllSystems (system:
        codex-desktop-linux.inputs.nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
