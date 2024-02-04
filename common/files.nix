{ config, ... }:
let
  home = builtins.getEnv "HOME";
  xdg_configHome = "${home}/.config";
  xdg_dataHome = "${home}/.local/share";
  xdg_stateHome = "${home}/.local/state";
in {

  # git
  "${xdg_configHome}/git/template-message".text = ''
      
    # Commit message is imperative. Should complete the sentence
    # If applied, this commit will "$COMMIT_MSG"
    # Commit Types:
    # feat, fix, chore, refactor, perf, style, test, docs, build
    #
    # <type>(scope): <short description>
    #
    # [optional body]
    #
    # [optional footer]
    #
    # BREAKING CHANGE: <description>
    #
  '';
  "${xdg_configHome}/gh/hosts.yml".text = ''
    github.com:
      users:
        nperez0111:
            oauth_token: "${
              builtins.replaceStrings [ "\n" ] [ "" ]
              (builtins.readFile config.age.secrets.github.path)
            }"
      git_protocol: ssh
      oauth_token: "${
        builtins.replaceStrings [ "\n" ] [ "" ]
        (builtins.readFile config.age.secrets.github.path)
      }"
      user: nperez0111
  '';
}
