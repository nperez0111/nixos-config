{ config, ... }:
let
  home = builtins.getEnv "HOME";
  xdg_configHome = "${home}/.config";
  xdg_dataHome = "${home}/.local/share";
  xdg_stateHome = "${home}/.local/state";
in {

  # For some reason could not copy the files in?
  "${xdg_configHome}/git/template-message".text =
    builtins.readFile ./config/git/template-message;
  "${xdg_configHome}/gh/hosts.yml".text = ''
    github.com:
      oauth_token: "${
        builtins.replaceStrings [ "\n" ] [ "" ]
        (builtins.readFile config.age.secrets.github.path)
      }"
      user: nperez0111
  '';
}
