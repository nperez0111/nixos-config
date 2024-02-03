{ config, pkgs, lib, ... }:

let
  name = "Nick the Sick";
  email = "nick@nickthesick.com";
in {
  # Shared shell configuration
  zsh = {
    enable = true;
    autocd = false;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "npm" ];
    };
    plugins = [
      {
        name = "syntax-highlighting";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
      {
        name = "autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "spaceship";
        src = pkgs.spaceship-prompt;
        file = "lib/spaceship-prompt/spaceship.zsh";
      }
    ];
    localVariables = {
      CASE_SENSITIVE = "false";
      HISTIGNORE = "pwd:ls:cd";
      SPACESHIP_CHAR_SYMBOL = "❯ ";
    };
    initExtraFirst = ''
      if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
      fi

      # Define a custom history function that defaults to showing the last 1000 entries
      show_history() {
        if [ "$#" -eq 0 ]; then
          history 1000
        else
          history "$@"
        fi
      }
      alias history='show_history'

      # Ripgrep alias
      alias search=rg -p $1 .

      # Micro is my editor
      export ALTERNATE_EDITOR=""
      export EDITOR=$(which micro)
      export VISUAL="code --wait"

      # nix shortcuts
      shell() {
          nix-shell '<nixpkgs>' -A "$1"
      }

      # bat makes cat pretty
      alias cat=bat

      # Always color ls and group directories
      alias ls='ls --color=auto'


      eval "$(gh completion -s zsh)"
      # https://github.com/cantino/mcfly
      eval "$(mcfly init zsh)"
    '';
  };
  vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      arrterian.nix-env-selector
      bbenoist.nix
      brettm12345.nixfmt-vscode
      coolbear.systemd-unit-file
      davidanson.vscode-markdownlint
      dbaeumer.vscode-eslint
      donjayamanne.githistory
      eamodio.gitlens
      editorconfig.editorconfig
      esbenp.prettier-vscode
      formulahendry.auto-rename-tag
      foxundermoon.shell-format
      github.copilot
      golang.go
      gruntfuggly.todo-tree
      jnoortheen.nix-ide
      matthewpi.caddyfile-support
      mechatroner.rainbow-csv
      mikestead.dotenv
      mkhl.direnv
      ms-azuretools.vscode-docker
      ms-vscode-remote.remote-ssh
      redhat.vscode-yaml
      ryu1kn.partial-diff
      streetsidesoftware.code-spell-checker
      tyriar.sort-lines
      vscode-icons-team.vscode-icons
      yzhang.markdown-all-in-one
    ];
    userSettings = {
      "workbench.colorTheme" = "Default Dark+";
      "workbench.iconTheme" = "vscode-icons";
      "workbench.editor.limit.enabled" = true;
      "workbench.editor.limit.value" = 12;
      "workbench.editor.untitled.hint" = "hidden";
      "workbench.sideBar.location" = "right";
      "[dockerfile]" = {
        "editor.defaultFormatter" = "ms-azuretools.vscode-docker";
      };
      "breadcrumbs.enabled" = true;
      "[javascript][javascriptreact][mdx][typescript][typescriptreact][scss][markdown][json][jsonc]" =
        {
          "editor.codeActionsOnSave" = { "source.fixAll" = true; };
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
          "editor.formatOnSave" = true;
        };
      "editor.bracketPairColorization.enabled" = true;
      "editor.codeActionsOnSave" = { "source.fixAll" = true; };
      "editor.fontFamily" =
        "Fira Code, Hack, Menlo, Monaco, 'Courier New', monospace";
      "editor.fontLigatures" = true;
      "editor.fontSize" = 13;
      "editor.formatOnSave" = true;
      "editor.guides.bracketPairs" = true;
      "editor.inlineSuggest.enabled" = true;
      "editor.largeFileOptimizations" = false;
      "editor.minimap.enabled" = false;
      "editor.suggestSelection" = "first";
      "editor.tabSize" = 2;
      "editor.tokenColorCustomizations" = {
        textMateRules = [
          {
            scope = [
              "comment"
              "entity.name.type.class"
              "keyword"
              "storage.modifier"
              "storage.type.class.js"
              "storage.type.function.js"
              "storage.type.js"
              "keyword.control.import.js"
              "keyword.control.from.js"
              "keyword.control.flow.js"
              "keyword.control.conditional.js"
              "keyword.control.loop.js"
              "keyword.operator.new.js"
            ];
            settings = { fontStyle = "italic"; };
          }
          {
            scope = [
              "invalid"
              "keyword.operator"
              "constant.numeric.css"
              "keyword.other.unit.px.css"
              "constant.numeric.decimal.js"
              "constant.numeric.json"
              "entity.name.type.class.js"
            ];
            settings = { fontStyle = ""; };
          }
        ];
      };
      "files.exclude" = {
        "**/.git" = true;
        "**/.svn" = true;
        "**/.hg" = true;
        "**/CVS" = true;
        "**/.DS_Store" = true;
        "**/Thumbs.db" = true;
        "**/node_modules" = true;
        ".tmp-projections/" = true;
      };
      "files.watcherExclude" = {
        "**/.git/objects/**" = true;
        "**/.git/subtree-cache/**" = true;
        "**/node_modules/*/**" = true;
        ".volta/**" = true;
        ".npm/**" = true;
      };
      "git.autofetch" = true;
      "git.confirmSync" = false;
      "git.enableSmartCommit" = true;
      "git.fetchOnPull" = true;
      "gitlens.hovers.currentLine.over" = "line";
      "gitlens.showWelcomeOnInstall" = false;
      "terminal.integrated.scrollback" = 1000001;
      "terminal.integrated.showExitAlert" = false;
      "terminal.integrated.tabs.enabled" = true;
      "vsicons.dontShowNewVersionMessage" = true;
      "workbench.welcomePage.walkthroughs.openOnInstall" = false;
      "window.zoomLevel" = 4;
      # Telemetry
      "code-runner.enableAppInsights" = false;
      "docker-explorer.enableTelemetry" = false;
      "redhat.telemetry.enabled" = false;
      "rpcServer.showStartupMessage" = false;
      "extensions.ignoreRecommendations" = true;
      "telemetry.enableCrashReporter" = false;
      "telemetry.enableTelemetry" = false;
      "telemetry.telemetryLevel" = "off";
      "terraform.telemetry.enabled" = false;
    };
  };

  gh = {
    enable = true;
    gitCredentialHelper = { enable = true; };
    settings = {
      git_protocol = "ssh";
      pager = "${pkgs.bat}/bin/bat";
      prompt = "enabled";
      aliases = {
        branch = "!git pull && git switch -c nick/PRS-$1";
        master = "!git switch master && git pull";
        production = ''
          !echo "What Jira issues are you releasing to production: " && read JIRA_ISSUES && echo "What is the CMRF you created here: https://hq.agilemd.com/cmrf/new" && read CMRF && gh pr create --base production --reviewer zackliston --assignee zackliston --title "Release $(cat package.json | jq -r .version) $JIRA_ISSUES" --body "CMRF: $CMRF"'';
      };
    };
  };
  git = {
    enable = true;
    userName = name;
    userEmail = email;
    attributes = [ "package-lock.json merge=package-lock" ];
    ignores = [ ".tmp-projections/" "node_modules/" ".DS_Store" ];
    aliases = {
      cleanup = "fetch -p";
      co = "checkout";
    };
    signing = {
      key = "0AD7F8215DF25741E7DC79F3420226D226E30AF2";
      signByDefault = true;
    };
    lfs = { enable = true; };
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "${pkgs.micro}/bin/micro";
      commit.template = "~/.config/git/template-message";
      commit.gpgsign = true;
      merge.tool = "vscode";
      pager = {
        diff = "delta";
        log = "delta";
        reflog = "delta";
        show = "delta";
      };
      "mergetool \"vscode\"" = {
        cmd = "code --wait --merge $REMOTE $LOCAL $BASE $MERGED";
      };
      "merge \"package-lock\"" = {
        name = "automatically merge conflicts in package-lock.json files";
        driver = "volta run npm install --package-lock-only";
        recursive = "binary";
      };

      pull.rebase = true;
      fetch.prune = true;
      rebase.autoStash = true;
      rerere = {
        enabled = true;
        autoUpdate = true;
      };
      push.autoSetupRemote = true;
    };

    delta = {
      enable = true;
      options = {
        side-by-side = true;
        plus-color = "#012800";
        minus-color = "#340001";
        syntax-theme = "Monokai Extended";
        colorMoved = "default";
      };
    };
  };
  ssh = { enable = true; };
  gpg = {
    enable = true;
    settings = { default-key = "0AD7F8215DF25741E7DC79F3420226D226E30AF2"; };
  };
  tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      vim-tmux-navigator
      sensible
      yank
      prefix-highlight
      {
        plugin = resurrect; # Used by tmux-continuum

        # Use XDG data directory
        # https://github.com/tmux-plugins/tmux-resurrect/issues/348
        extraConfig = ''
          set -g @resurrect-dir '$HOME/.cache/tmux/resurrect'
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-pane-contents-area 'visible'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '5' # minutes
        '';
      }
    ];
    terminal = "screen-256color";
    prefix = "C-b";
    escapeTime = 10;
    historyLimit = 50000;
    extraConfig = ''
      # Remove Vim mode delays
      set -g focus-events on

      # Enable full mouse support
      set -g mouse on

      # -----------------------------------------------------------------------------
      # Key bindings
      # -----------------------------------------------------------------------------

      # Unbind default keys
      unbind C-b
      unbind '"'
      unbind %

      # Split panes, vertical or horizontal
      bind-key x split-window -v
      bind-key v split-window -h

      # Move around panes with vim-like bindings (h,j,k,l)
      bind-key -n M-k select-pane -U
      bind-key -n M-h select-pane -L
      bind-key -n M-j select-pane -D
      bind-key -n M-l select-pane -R

      # Smart pane switching with awareness of Vim splits.
      # This is copy paste from https://github.com/christoomey/vim-tmux-navigator
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
        | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
      bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h'  'select-pane -L'
      bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j'  'select-pane -D'
      bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k'  'select-pane -U'
      bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l'  'select-pane -R'
      tmux_version='$(tmux -V | sed -En "s/^tmux ([0-9]+(.[0-9]+)?).*/\1/p")'
      if-shell -b '[ "$(echo "$tmux_version < 3.0" | bc)" = 1 ]' \
        "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\'  'select-pane -l'"
      if-shell -b '[ "$(echo "$tmux_version >= 3.0" | bc)" = 1 ]' \
        "bind-key -n 'C-\\' if-shell \"$is_vim\" 'send-keys C-\\\\'  'select-pane -l'"

      bind-key -T copy-mode-vi 'C-h' select-pane -L
      bind-key -T copy-mode-vi 'C-j' select-pane -D
      bind-key -T copy-mode-vi 'C-k' select-pane -U
      bind-key -T copy-mode-vi 'C-l' select-pane -R
      bind-key -T copy-mode-vi 'C-\' select-pane -l
    '';
  };
}
