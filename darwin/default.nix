{
  config,
  pkgs,
  nixpkgs,
  home-manager,
  lib,
  ...
}:

let
  user = "nickthesick";

  # attic - iCloud Photos -> S3 backup. See overlays/attic/default.nix for the
  # pinned version and the post-upgrade keychain re-trust ritual.
  attic = "${pkgs.attic-photos}/bin/attic";

  # Failure + staleness mailer, sharing backrest's single SMTP credential.
  # nounset only: errexit in a notifier is actively harmful, since a benign
  # non-zero (e.g. a `[ -f ]` miss) would abort the script before it mails.
  attic-notify = pkgs.writeShellApplication {
    name = "attic-notify";
    runtimeInputs = [ pkgs.jq pkgs.curl pkgs.coreutils ];
    bashOptions = [ "nounset" ];
    text = builtins.readFile ./attic/attic-notify.sh;
  };

  # /usr/local/bin holds the OrbStack `docker` shim, which attic-notify needs
  # to read the SMTP credential out of the backrest container.
  atticPath = "${pkgs.attic-photos}/bin:${attic-notify}/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  atticLogDir = "/Users/${user}/Library/Logs/attic";

  # Shared launchd shape for every attic job. Background/LowPriorityIO/Nice so a
  # multi-hour iCloud drain never competes with anything interactive.
  atticJob = name: extra: {
    serviceConfig = {
      EnvironmentVariables.PATH = atticPath;
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "${atticLogDir}/${name}.log";
      StandardErrorPath = "${atticLogDir}/${name}.log";
    } // extra;
  };
in
{

  imports = [
    ../common
    ../common/cachix
    ./home-manager.nix
  ];

  # Set the primary user for nix-darwin
  system.primaryUser = "${user}";

  # skhd installed via Homebrew (stable binary path) to avoid
  # macOS re-prompting for Accessibility permissions on every rebuild.
  # Config is managed via home.file in darwin/files.nix.
  launchd.user.agents.skhd = {
    serviceConfig = {
      ProgramArguments = [ "/opt/homebrew/bin/skhd" ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      EnvironmentVariables.PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    };
  };

  # Launch WireGuard and auto-connect the "macmini" tunnel at login.
  # The App Store WireGuard uses a Network Extension that needs the GUI
  # running, so we open the app first, wait for the extension to register,
  # then activate the tunnel via scutil.
  launchd.user.agents.wireguard-autoconnect = {
    script = ''
      /usr/bin/open -a /Applications/WireGuard.app
      # Wait for the Network Extension to register
      for i in $(seq 1 30); do
        if /usr/sbin/scutil --nc status "macmini" 2>/dev/null | head -1 | grep -q -v "No service"; then
          break
        fi
        sleep 1
      done
      /usr/sbin/scutil --nc start "macmini"
    '';
    serviceConfig = {
      RunAtLoad = true;
    };
  };

  # ---------------------------------------------------------------- attic
  # iCloud Photos -> Backblaze B2. These MUST be user agents, not daemons: a
  # LaunchDaemon runs as root outside any user session, so it has no login
  # keychain (S3 credentials) and no Photos TCC grant, and PhotoKit is
  # unavailable. Upstream documents this - see docs/unattended-backups.md
  # "Why a LaunchAgent and not a Daemon or cron".
  #
  # No `pmset repeat wakeorpoweron` is needed: this mini runs `pmset sleep 0`.

  # 09:00 daily. Every slot nearer "overnight" collides with a backrest plan
  # (03:19, 05:47, 14:13, 17:23, 21:07, 23:37) or nix GC (Sun 02:00); 09:00-14:00
  # is the only genuinely empty window, and the mini is headless so the hour
  # costs nothing.
  #
  # --limit 2000 keeps each run to roughly 1-2h. The cap is per-run, not
  # per-day: attic is idempotent, skips what is already in the manifest, and
  # resumes failures from its retry queue, so the ~9.7k-asset first catch-up
  # just takes several runs. Raise or drop it once caught up.
  launchd.user.agents.attic-backup = atticJob "backup" {
    # attic MUST be launchd's direct program, not wrapped in a shell script.
    # TCC attributes the Photos request to the process launchd started, so a
    # wrapper makes the nix-store bash the "responsible" process and macOS
    # prompts to grant Photos access to *bash* - which hangs the backup
    # indefinitely. Outcome is read afterwards by attic-notify via launchd's
    # own `last exit code`, so no wrapper is needed. Verified 2026-08-28.
    ProgramArguments = [
      attic
      "backup"
      "--limit"
      "2000"
    ];
    StartCalendarInterval = [{
      Hour = 9;
      Minute = 0;
    }];
  };

  # Weekly integrity check: confirms every manifest entry still exists in S3.
  # Sunday 07:00 - clear of nix GC (Sun 02:00) and the monthly backrest prune.
  launchd.user.agents.attic-verify = atticJob "verify" {
    ProgramArguments = [ attic "verify" ];
    StartCalendarInterval = [{
      Weekday = 0;
      Hour = 7;
      Minute = 0;
    }];
  };

  # The failure hook above only fires from inside a run, so it is silent when
  # attic stops running at all. This is the layer that catches that - same gap,
  # and same reasoning, as server/backrest/alert-check.sh. It reads the success
  # reads launchd's `last exit code` for the backup job plus its log mtime.
  launchd.user.agents.attic-check = atticJob "check" {
    ProgramArguments = [ "${attic-notify}/bin/attic-notify" "check" ];
    StartCalendarInterval = [{
      Hour = 12;
      Minute = 0;
    }];
  };

  # Manual only - no StartCalendarInterval. `attic status` touches both the
  # Photos library and both keychain items and returns in seconds, so
  # kickstarting this is how permissions get primed and re-trusted:
  #   launchctl kickstart -k gui/$(id -u)/org.nixos.attic-prime
  #
  # It must be kickstarted rather than run in Terminal. TCC attributes a CLI
  # tool's Photos grant to the *responsible process*; run interactively from
  # Terminal.app the grant can land on Terminal, leaving the launchd-spawned
  # binary without access - which presents only as "0 uploaded, 0 failed".
  # Under launchd, attic itself is the responsible process.
  launchd.user.agents.attic-prime = atticJob "prime" {
    ProgramArguments = [ attic "status" ];
  };

  # Disable Spotlight indexing — we use Raycast instead.
  # No built-in nix-darwin module exists, so we use a LaunchDaemon.
  # Uses ExternalVolumesIgnore (undocumented mds pref found via reverse
  # engineering) to tell mds to ignore all external/USB volumes, plus
  # mdutil -d (stronger than -i off: disables both indexing AND searching).
  launchd.daemons.disable-spotlight = {
    script = ''
      # Tell mds to ignore all external volumes (reads by mds at startup)
      /usr/bin/defaults write /Library/Preferences/com.apple.SpotlightServer.plist \
        ExternalVolumesIgnore -bool true
      /usr/bin/defaults write /Library/Preferences/com.apple.SpotlightServer.plist \
        ExternalVolumesDefaultOff -bool true

      # Disable indexing AND searching on all volumes (stronger than -i off)
      /usr/bin/mdutil -d -a 2>/dev/null || true

      # Time Machine volumes ignore mdutil; remove their indexes directly
      for vol in /Volumes/*; do
        [ -d "$vol/.Spotlight-V100" ] && /bin/rm -rf "$vol/.Spotlight-V100"
      done
      /bin/rm -rf /.Spotlight-V100 2>/dev/null || true

      # Kill Spotlight worker processes so they pick up new prefs
      /usr/bin/killall mdsync mdworker mdworker_shared mds_stores 2>/dev/null || true
    '';
    serviceConfig = {
      RunAtLoad = true;
      StartOnMount = true;
    };
  };

  # Pigeons roost: P2P SSH tunnel via iroh/QUIC.
  # Accepts incoming pigeons connections and proxies them to local sshd.
  # The endpoint ID is persisted across restarts (keys stored in /var/root/.config/pigeons).
  # To get the endpoint ID: sudo pigeons roost (it prints it on startup)
  # or check /var/log/pigeons.log after the service starts.
  launchd.daemons.pigeons-roost = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.pigeons}/bin/pigeons"
        "roost"
        "--ssh-port"
        "22"
      ];
      RunAtLoad = true;
      KeepAlive = {
        SuccessfulExit = false;
      };
      EnvironmentVariables = {
        RUST_LOG = "info";
      };
      WorkingDirectory = "/var/root";
      StandardOutPath = "/var/log/pigeons.log";
      StandardErrorPath = "/var/log/pigeons.log";
    };
  };

  # Gracefully stop OrbStack before system shutdown/reboot.
  # Runs a long-lived process that traps SIGTERM (sent by launchd during
  # shutdown) and calls `orbctl stop` to cleanly shut down Docker containers
  # and the VM, preventing stale NFS bind mounts on next boot.
  launchd.daemons.orbstack-shutdown = {
    script = ''
      cleanup() {
        /opt/homebrew/bin/orbctl stop 2>/dev/null || true
        exit 0
      }
      trap cleanup SIGTERM SIGINT
      # Sleep indefinitely; we only exist to catch the shutdown signal
      while true; do sleep 3600 & wait $!; done
    '';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # Erase existing Spotlight indexes on activation, and kill unwanted agents.
  system.activationScripts.postActivation.text = ''
    # Enable Remote Login (SSH daemon) so WireGuard peers can SSH in
    /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true

    # launchd does not create the parent of StandardOutPath - it silently fails
    # to start the job instead. The attic agents all log into this directory.
    /bin/mkdir -p ${atticLogDir}
    /usr/sbin/chown ${user}:staff ${atticLogDir} 2>/dev/null || true

    # Spotlight: set ExternalVolumesIgnore so mds ignores USB/external drives
    /usr/bin/defaults write /Library/Preferences/com.apple.SpotlightServer.plist \
      ExternalVolumesIgnore -bool true
    /usr/bin/defaults write /Library/Preferences/com.apple.SpotlightServer.plist \
      ExternalVolumesDefaultOff -bool true

    # Disable indexing AND searching on all volumes (mdutil -d is stronger than -i off)
    /usr/bin/mdutil -d -a 2>/dev/null || true
    /usr/bin/mdutil -E -a 2>/dev/null || true
    for vol in /Volumes/*; do
      [ -d "$vol/.Spotlight-V100" ] && /bin/rm -rf "$vol/.Spotlight-V100"
    done
    /bin/rm -rf /.Spotlight-V100 2>/dev/null || true
    /usr/bin/killall mds mdsync mdworker mdworker_shared mds_stores 2>/dev/null || true

    # Kill Siri and proactive suggestion daemons so they pick up the
    # disabled preferences immediately (they'll stay dead since we set
    # the prefs that prevent them from doing real work).
    for proc in assistantd siriknowledged siriinferenced siriactionsd sirittsd \
                suggestd parsecd proactived knowledge-agent knowledgeconstructiond \
                proactiveeventtrackerd duetexpertd biomesyncd BiomeAgent tipsd \
                spotlightknowledged ContinuityCaptureAgent; do
      /usr/bin/killall "$proc" 2>/dev/null || true
    done
  '';

  # Harden SSH: key-based auth only, no passwords
  environment.etc."ssh/sshd_config.d/100-nix-darwin.conf" = {
    text = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      UsePAM no
    '';
  };

  age.secrets.github = {
    file = ../secrets/github;
    owner = "501";
    group = "80";
  };

  age.secrets.opencode = {
    file = ../secrets/opencode;
    owner = "501";
    group = "80";
    path = "/Users/${user}/.config/opencode/opencode.json";
    symlink = true;
  };

  nixpkgs.overlays = [
    (import ../overlays/niv-managed-dmg-apps/default.nix)
    (import ../overlays/pigeons/default.nix)
    (import ../overlays/attic/default.nix)
  ];

  # Allow nickthesick to run any command via sudo without a password prompt
  security.sudo.extraConfig = ''
    nickthesick ALL=(ALL) NOPASSWD: ALL
  '';

  # Setup user, packages, programs
  nix = {
    package = pkgs.nix;
    settings.trusted-users = [
      "@admin"
      "${user}"
    ];

    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };

    settings.sandbox = false;
    # Turn this on to make command line easier
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Load configuration that is shared across systems
  environment.systemPackages = (import ../common/packages.nix { pkgs = pkgs; }) ++ [
    pkgs.obsidian
    pkgs.nivApps.cemu
    pkgs.nivApps.flirc
    pkgs.nivApps.java
    pkgs.pigeons
    pkgs.attic-photos
    attic-notify
  ];

  fonts.packages = with pkgs; [
    fira-code
    hack-font
  ];

  system = {
    stateVersion = 4;

    defaults = {
      LaunchServices = {
        LSQuarantine = false;
      };

      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;

        # "com.apple.mouse.tapBehavior" = 1;
        # "com.apple.sound.beep.volume" = 0.0;
        # "com.apple.sound.beep.feedback" = 0;
      };

      dock = {
        autohide = true;
        autohide-delay = 0.0;
        show-recents = false;
        launchanim = false;
        orientation = "bottom";
        tilesize = 48;
      };

      finder = {
        _FXShowPosixPathInTitle = true;
      };

      trackpad = {
        Clicking = true;
        # TrackpadThreeFingerDrag = true;
      };
      loginwindow.autoLoginUser = "${user}";

      CustomUserPreferences = {
        NSGlobalDomain = {
          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
        };
        "com.apple.finder" = {
          ShowExternalHardDrivesOnDesktop = true;
          ShowHardDrivesOnDesktop = true;
          ShowMountedServersOnDesktop = true;
          ShowRemovableMediaOnDesktop = true;
          _FXSortFoldersFirst = true;
          # When performing a search, search the current folder by default
          FXDefaultSearchScope = "SCcf";
        };
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.screensaver" = {
          # Do not require password immediately after sleep or screen saver begins
          askForPassword = 0;
          askForPasswordDelay = 0;
        };
        "com.apple.screencapture" = {
          location = "~/Desktop";
          type = "png";
        };
        "com.apple.Safari" = {
          # Privacy: don’t send search queries to Apple
          UniversalSearchEnabled = false;
          SuppressSearchSuggestions = true;
          # Press Tab to highlight each item on a web page
          WebKitTabToLinksPreferenceKey = true;
          ShowFullURLInSmartSearchField = true;
          # Prevent Safari from opening ‘safe’ files automatically after downloading
          AutoOpenSafeDownloads = false;
          ShowFavoritesBar = false;
          IncludeInternalDebugMenu = true;
          IncludeDevelopMenu = true;
          WebKitDeveloperExtrasEnabledPreferenceKey = true;
          WebContinuousSpellCheckingEnabled = true;
          WebAutomaticSpellingCorrectionEnabled = false;
          AutoFillFromAddressBook = false;
          AutoFillCreditCardData = false;
          AutoFillMiscellaneousForms = false;
          WarnAboutFraudulentWebsites = true;
          WebKitJavaEnabled = false;
          WebKitJavaScriptCanOpenWindowsAutomatically = false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" = true;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" = false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" = false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" = false;
        };
        # Disable Siri entirely
        "com.apple.assistant.support" = {
          "Siri Data Sharing Opt-In Status" = 2;
          "Assistant Enabled" = false;
        };
        "com.apple.Siri" = {
          SiriPrefStashedStatusMenuVisible = false;
          VoiceTriggerUserEnabled = false;
        };
        # Disable proactive suggestions and knowledge agents
        "com.apple.suggestions" = {
          SuggestionsAllowGelato = false;
          SuggestionsAllowSiri = false;
        };
        # Disable Continuity Camera (iPhone as webcam)
        "com.apple.cameracaptured" = {
          "Disabled When Locked" = true;
          doNotDisturb = true;
        };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        "com.apple.print.PrintingPrefs" = {
          # Automatically quit printer app once the print jobs complete
          "Quit When Finished" = true;
        };
        "com.apple.SoftwareUpdate" = {
          AutomaticCheckEnabled = true;
          # Check for software updates daily, not just once per week
          ScheduleFrequency = 1;
          # Download newly available updates in background
          AutomaticDownload = 1;
          # Install System data files & security updates
          CriticalUpdateInstall = 1;
        };
        "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;
        # Turn on app auto-update
        "com.apple.commerce".AutoUpdate = true;
        "com.apple.screensaver".loginWindowIdleTime = 0;
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

  };
}
