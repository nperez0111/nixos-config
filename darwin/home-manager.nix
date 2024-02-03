{ config, pkgs, lib, ... }:

let
  common-programs = import ../common/home-manager.nix {
    config = config;
    pkgs = pkgs;
    lib = lib;
  };
  common-files = import ../common/files.nix { config = config; };
  user = "nickthesick";
in {
  imports = [ <home-manager/nix-darwin> ./dock ];

  # It me
  users.users.${user} = {
    name = "${user}";
    home = "/Users/${user}";
    isHidden = false;
    shell = pkgs.zsh;
  };

  # Fully declarative dock using the latest from Nix Store
  local.dock.enable = true;
  local.dock.entries = [
    { path = "${pkgs.vscode}/Applications/Visual Studio Code.app/"; }
    { path = "/System/Applications/System Settings.app/"; }
    { path = "/Applications/Orion.app/"; }
    { path = "/Applications/Brave Browser.app/"; }
    { path = "/Applications/Ryujinx.app"; }
    { path = "/Applications/Stremio.app"; }
    {
      path = "/Applications";
      section = "others";
      options = "--sort name --view grid --display stack";
    }
    {
      path =
        "${config.users.users.${user}.home}/Applications/Home Manager Apps";
      options = "--sort name --view grid --display stack";
    }
    {
      path = "${config.users.users.${user}.home}/Downloads";
      section = "others";
      options = "--sort name --view grid --display folder";
    }
    # {
    #   path = "${config.users.users.${user}.home}/.local/share/downloads";
    #   section = "others";
    #   options = "--sort name --view grid --display stack";
    # }
  ];

  # We use Homebrew to install impure software only (Mac Apps)
  homebrew.enable = true;
  homebrew.onActivation = {
    autoUpdate = true;
    cleanup = "zap";
    upgrade = true;
  };
  homebrew.brewPrefix = "/opt/homebrew/bin";
  homebrew.brews = pkgs.callPackage ./brews.nix { };
  homebrew.taps = [ "homebrew/cask-versions" "cantino/mcfly" ];
  homebrew.casks = pkgs.callPackage ./casks.nix { };
  # These app IDs are from using the mas CLI app
  # mas = mac app store
  # https://github.com/mas-cli/mas
  #
  # $ mas search <app name>
  #
  homebrew.masApps = {
    "Amphetamine" = 937984704;
    "Ferromagnetic" = 1546537151;
    "Tailscale" = 1475387142;
  };

  # Enable home-manager to manage the XDG standard
  home-manager = {
    useGlobalPkgs = true;
    users.${user} = {
      home.enableNixpkgsReleaseCheck = false;
      home.packages = pkgs.callPackage ./packages.nix { };
      home.file = common-files // import ./files.nix {
        config = config;
        pkgs = pkgs;
        lib = lib;
      };
      home.stateVersion = "21.05";
      programs = common-programs // { };

      # https://github.com/nix-community/home-manager/issues/3344
      # Marked broken Oct 20, 2022 check later to remove this
      # Confirmed still broken, Mar 5, 2023
      manual.manpages.enable = false;
    };
  };
}
