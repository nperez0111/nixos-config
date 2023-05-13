{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.local.dock;
  stdenv = pkgs.stdenv;
  dockutil = pkgs.dockutil;
in {
  options = {
    local.dock.enable = mkOption {
      description = "Enable dock";
      default = stdenv.isDarwin;
      example = false;
    };

    local.dock.entries = mkOption {
      description = "Entries on the Dock";
      type = with types;
        listOf (submodule {
          options = {
            path = lib.mkOption { type = str; };
            section = lib.mkOption {
              type = str;
              default = "apps";
            };
            options = lib.mkOption {
              type = str;
              default = "";
            };
          };
        });
      readOnly = true;
    };
  };

  config = mkIf (cfg.enable) (let
    normalize = path: if hasSuffix ".app" path then path + "/" else path;
    entryURI = path:
      "file://"
      + (builtins.replaceStrings [ " " "!" ''"'' "#" "$" "%" "&" "'" "(" ")" ] [
        "%20"
        "%21"
        "%22"
        "%23"
        "%24"
        "%25"
        "%26"
        "%27"
        "%28"
        "%29"
      ] (normalize path));
    wantURIs = concatMapStrings (entry: ''
      ${entryURI entry.path}
    '') cfg.entries;
    createEntries = concatMapStrings (entry: ''
      ${dockutil}/bin/dockutil --no-restart --add '${entry.path}' --section ${entry.section} ${entry.options}
    '') cfg.entries;
  in {
    # TODO figure out how to use stdenvNoCC.mkDerivation to do this installing of the dock & other side-effects like the scripts below
    system.activationScripts.postActivation.text = mkAfter ''
      echo >&2 "Setting up the Dock..."
      haveURIs="$(${dockutil}/bin/dockutil --list | ${pkgs.coreutils}/bin/cut -f2)"
      if ! diff -wu <(echo -n "$haveURIs") <(echo -n '${wantURIs}') >&2 ; then
        echo >&2 "Resetting Dock..."
        ${dockutil}/bin/dockutil --no-restart --remove all
        ${createEntries}
        killall Dock
      else
        echo >&2 "Dock setup complete."
      fi

      echo >&2 "Setting up system preferences..."
      # Set remote ssh server to be on
      sudo /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1

      # Don't allow the computer to sleep
      sudo /usr/sbin/systemsetup -setcomputersleep off >/dev/null 2>&1

      # Only allow the display to sleep for 6 hours
      sudo /usr/sbin/systemsetup -setdisplaysleep 360 >/dev/null 2>&1

      # Following line should allow us to avoid a logout/login cycle
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';
  });
}
