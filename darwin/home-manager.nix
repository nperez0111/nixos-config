{
  config,
  pkgs,
  lib,
  ...
}:

let
  common-programs = import ../common/home-manager.nix {
    config = config;
    pkgs = pkgs;
    lib = lib;
  };
  common-files = import ../common/files.nix { config = config; };
  user = "nickthesick";
in
{
  imports = [ ./dock ];

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
      path = "${config.users.users.${user}.home}/Applications/Home Manager Apps";
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
  homebrew.prefix = "/opt/homebrew";
  homebrew.brews = pkgs.callPackage ./brews.nix { };
  homebrew.taps = [
    "anomalyco/tap"
    "oven-sh/bun"
  ];
  homebrew.casks = pkgs.callPackage ./casks.nix { };
  # masApps disabled — nix-darwin's mas integration uses `mas get`
  # which was removed in mas 1.8.6+. Install these manually from
  # the App Store if needed:
  # - Amphetamine (937984704)
  # - Ferromagnetic (1546537151)
  # - Tailscale (1475387142)

  # Enable home-manager to manage the XDG standard
  home-manager = {
    useGlobalPkgs = true;
    backupFileExtension = "bak";
    users.${user} = {
      # Disable buggy modules and replace with fixed versions
      # https://github.com/nix-community/home-manager/pull/8164
      disabledModules = [
        "targets/darwin/linkapps.nix"
        "targets/darwin/fonts.nix"
      ];
      home.enableNixpkgsReleaseCheck = false;
      home.packages = pkgs.callPackage ./packages.nix { };
      home.file =
        common-files
        // import ./files.nix {
          config = config;
          pkgs = pkgs;
          lib = lib;
        }
        // (
          let
            # Workaround for home-manager pathsToLink bug
            # https://github.com/nix-community/home-manager/pull/8164
            hmPackages = config.home-manager.users.${user}.home.packages;
            appsEnv = pkgs.buildEnv {
              name = "home-manager-applications";
              paths = hmPackages;
              pathsToLink = [ "/Applications" ];
            };
            fontsEnv = pkgs.buildEnv {
              name = "home-manager-fonts";
              paths = hmPackages;
              pathsToLink = [ "/share/fonts" ];
            };
            homeDir = config.users.users.${user}.home;
            installDir = "${homeDir}/Library/Fonts/HomeManager";
          in
          {
            "Applications/Home Manager Apps".source = lib.mkForce "${appsEnv}/Applications";
            "Library/Fonts/.home-manager-fonts-version" = {
              text = lib.mkForce "${fontsEnv}";
              onChange = lib.mkForce ''
                run mkdir -p ${lib.escapeShellArg installDir}
                run ${pkgs.rsync}/bin/rsync $VERBOSE_ARG -acL --chmod=u+w --delete \
                  ${lib.escapeShellArgs [
                    "${fontsEnv}/share/fonts/"
                    installDir
                  ]}
              '';
            };
          }
        );
      home.stateVersion = "24.11";
      programs = common-programs // { };

      # https://github.com/nix-community/home-manager/issues/3344
      # Marked broken Oct 20, 2022 check later to remove this
      # Confirmed still broken, Mar 5, 2023
      manual.manpages.enable = false;
    };
  };
}
