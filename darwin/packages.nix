{ pkgs }:

with pkgs;
let common-packages = import ../common/packages.nix { pkgs = pkgs; };
in common-packages ++ [
  dockutil
  skhd
  pkgs.nivApps.cemu
  pkgs.nivApps.flirc
  pkgs.nivApps.skip1s
  pkgs.nivApps.java
]
