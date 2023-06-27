{ config, pkgs, lib, ... }:

let
  home = builtins.getEnv "HOME";
  xdg_configHome = "${home}/.config";
  xdg_dataHome = "${home}/.local/share";
  xdg_stateHome = "${home}/.local/state";
in {
  "${xdg_dataHome}/nix-sudoers".text = lib.concatMapStringsSep "\n"
    (i: "_nixbld${toString i} ALL=(ALL) NOPASSWD:ALL")
    (lib.range 1 config.nix.nrBuildUsers);
}
