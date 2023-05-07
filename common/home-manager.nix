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
    '';
  };

  gh = {
    enable = true;
    enableGitCredentialHelper = true;
    settings = {
      git_protocol = "https";
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
    attributes = [
      "npm-shrinkwrap.json merge=npm-merge-driver"
      "package-lock.json merge=npm-merge-driver"
    ];
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
      commit.gpgsign = true;
      commit.template = "~/.config/git/template-message";
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
      "merge \"npm-merge-driver\"" = {
        name = "automatically merge npm lockfiles";
        driver = "volta run npm exec npm-merge-driver merge %A %O %B %P";
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
