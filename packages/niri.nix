{ pkgs, agentInput ? true }:

pkgs.niri.overrideAttrs (old: {
  patches = (old.patches or [ ])
    ++ [ ../patches/niri-ipc-tiled-window-position.patch ]
    ++ pkgs.lib.optional agentInput ../patches/niri-agent-input.patch;
})
