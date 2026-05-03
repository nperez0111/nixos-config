{ config, pkgs, lib, ... }:

{
  ".local/share/nix-sudoers".text = lib.concatMapStringsSep "\n"
    (i: "_nixbld${toString i} ALL=(ALL) NOPASSWD:ALL")
    (lib.range 1 config.nix.nrBuildUsers);

  ".gnupg/gpg-agent.conf".text = ''
    pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
    default-cache-ttl 10000
    max-cache-ttl 120000
    default-cache-ttl-ssh 10000
    max-cache-ttl-ssh 10000
  '';
}
