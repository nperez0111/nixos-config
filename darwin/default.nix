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

  # Disable Spotlight indexing — we use Raycast instead.
  # No built-in nix-darwin module exists, so we use a LaunchDaemon.
  launchd.daemons.disable-spotlight = {
    script = ''
      /usr/bin/mdutil -i off -a
    '';
    serviceConfig = {
      RunAtLoad = true;
      StartOnMount = true;
    };
  };

  # Erase existing Spotlight indexes on activation, and kill unwanted agents.
  system.activationScripts.postActivation.text = ''
    # Enable Remote Login (SSH daemon) so WireGuard peers can SSH in
    /usr/sbin/systemsetup -setremotelogin on >/dev/null 2>&1 || true

    # Spotlight
    /usr/bin/mdutil -i off -a
    /usr/bin/mdutil -E -a 2>/dev/null || true

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
