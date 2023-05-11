{ config, pkgs, nixpkgs, ... }:

let user = "nickthesick";
in {

  imports = [ ../common ../common/cachix ./home-manager.nix ];

  services = {
    # Auto upgrade nix package and the daemon service.
    nix-daemon.enable = true;

    # Setup skhd with configuration
    skhd = {
      enable = true;
      skhdConfig = ''
        # Youtube Brave
        cmd + shift + alt - z : osascript -e 'set bravePath to "/Applications/Brave Browser.app"' -e 'tell application "System Events"' -e 'if not (exists process "Brave Browser") then' -e 'do shell script "open -a " & quoted form of bravePath' -e 'delay 3' -e 'end if' -e 'tell application "Brave Browser" to open location "https://youtube.com/tv"' -e 'delay 1' -e 'tell process "Brave Browser"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
        # Youtube Orion
        cmd + shift + alt - y : osascript -e 'set orionPath to "/Applications/Orion.app"' -e 'tell application "System Events"' -e 'if not (exists process "Brave Browser") then' -e 'do shell script "open -a " & quoted form of orionPath' -e 'delay 3' -e 'end if' -e 'tell application "Orion" to open location "https://youtube.com/tv"' -e 'delay 1' -e 'tell process "Orion"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
        # Open Stremio
        cmd + shift + alt - s : osascript -e 'set stremioPath to "/Applications/Stremio.app"' -e 'tell application "System Events"' -e 'if not (exists process "Stremio") then' -e 'do shell script "open -a " & quoted form of stremioPath' -e 'delay 3' -e 'end if' -e 'delay 1' -e 'tell process "stremio"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
        # Send space if youtube, enter everywhere else
        cmd + shift + alt - e : osascript -e 'set currentURL to ""' -e 'tell application "System Events"' -e 'set frontAppName to name of first application process whose frontmost is true' -e 'if frontAppName is "Orion" then' -e 'tell application "Orion" to set currentURL to URL of current tab of front window' -e 'else if frontAppName is "Brave Browser" then' -e 'tell application "Brave Browser" to set currentURL to URL of active tab of front window' -e 'end if' -e 'if currentURL contains "youtube.com" then' -e 'tell process frontAppName to keystroke space' -e 'else' -e 'tell process frontAppName to keystroke return' -e 'end if' -e 'end tell'
      '';
    };
  };

  age.secrets.github = {
    file = ../secrets/github;
    owner = "501";
    group = "80";
  };

  # Setup user, packages, programs
  nix = {
    package = pkgs.nixUnstable;
    settings.trusted-users = [ "@admin" "${user}" ];

    gc = {
      user = "root";
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };

    # Turn this on to make command line easier
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Turn off NIX_PATH warnings now that we're using flakes
  system.checks.verifyNixPath = false;

  # Load configuration that is shared across systems
  environment.systemPackages = (import ../common/packages.nix { pkgs = pkgs; });

  # Enable fonts dir
  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [ fira-code hack-font ];

  system = {
    stateVersion = 4;

    defaults = {
      LaunchServices = { LSQuarantine = false; };

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

      finder = { _FXShowPosixPathInTitle = true; };

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
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" =
            true;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" =
            true;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" =
            false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" =
            false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" =
            false;
          "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" =
            false;
        };
        "com.apple.AdLib" = { allowApplePersonalizedAdvertising = false; };
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

    activationScripts = {
      # Auto apply system level settings https://medium.com/@zmre/nix-darwin-quick-tip-activate-your-preferences-f69942a93236
      preActivation.text = ''
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

    };
  };
}
