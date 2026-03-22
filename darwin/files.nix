{ config, pkgs, lib, ... }:

{
  ".local/share/nix-sudoers".text = lib.concatMapStringsSep "\n"
    (i: "_nixbld${toString i} ALL=(ALL) NOPASSWD:ALL")
    (lib.range 1 config.nix.nrBuildUsers);
}
