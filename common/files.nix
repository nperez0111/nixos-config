{ config, ... }:
{
  # git
  ".config/git/template-message".text = ''

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
  ".config/gh/hosts.yml".text = ''
    github.com:
      users:
        nickthesick:
            oauth_token: "${
              builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile config.age.secrets.github.path)
            }"
      git_protocol: ssh
      oauth_token: "${
        builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile config.age.secrets.github.path)
      }"
      user: nickthesick
  '';
}
