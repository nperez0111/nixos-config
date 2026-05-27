{ config, pkgs, lib, ... }:

{
  ".ssh/authorized_keys" = {
    text = ''
      ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDCtdTNTuGahi60FJjFir3pxJ/hwIYFraqnzCgkGQ9u/6t68gH6UhV2gKxhi6amHql2rkeUYc3QES/1JjTWUipHVzC94/zglMVuR/NhpGjDEFpnm5Y5qC4Wjz4EA7gBJyovMnjHPon6z5DaEWm3uKiVHADBn1IVGBT3Evr+jzJ60EFOL4wHVJMycliP/AyvVNCrsYtyxd0zIUOxVbEQlkHFJ24SGrNZLr2BqUdJDBGSAtUfeEINWyyqOkyEeYx0VJ4+BA0vGbq2j/o6L4xM+y/BhvSz9IiboW1pQCoOIqNk9x7aHKS+tI9CusSTDms7YSRzc77V6xWHBQOGAuptojWEO9miXDV0ZICZMQL5sAUl1Z++IbLT2Pg7D/2/0GCV+GZAfVimEdOycFhfoTEDUGG5UWYh6GD/k+MyjxVZyzCB49HJqdji7clNenGj1nAE2regl0JvofGPvkP+SdzdkHqibxGbm9GD77Gd6PBpzaR6+4Wv5sb5C3FVYu/kAYmuihS6mVII8XKjwsGd9BbfeWWzAUD9k61fdw5KNzfdTpos5H6I26eoYb+Zk4ncy2MXnEc4VkWt4nTe4qZVDH7LHbYi3PIelPnXb9Vn3Rv4RrfXT48zm1vIi48EKZCeVx4k9V/EoMwrvzNQAXpXtI9rsV+csnEklQE6taitkG3//u3M8w== nperez0111@gmail.com
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINv/m8MJSWIPfqYqole/8e69PpMndNf2bowRbUpH5TuM nicholas.perez@tiptap.dev
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILkiB20On2DzTW2E66x/dHvqbj5CDfT/qcVlj7Md2uHI computers@nickthesick.com
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFvcYFSxJeE8+X9p7+fWVASrLR/DqRfw3RPHQ4TarAxf computers@nickthesick.com
    '';
    force = true;
  };
  ".local/share/nix-sudoers".text = lib.concatMapStringsSep "\n"
    (i: "_nixbld${toString i} ALL=(ALL) NOPASSWD:ALL")
    (lib.range 1 config.nix.nrBuildUsers);

  ".gnupg/gpg-agent.conf".text = ''
    pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
    default-cache-ttl 10000
    max-cache-ttl 120000
    default-cache-ttl-ssh 10000
    max-cache-ttl-ssh 10000
  '';

  # skhd hotkey configuration (skhd installed via Homebrew for stable binary path)
  ".skhdrc".text = ''
    # Youtube Brave
    cmd + shift + alt - z : osascript -e 'set bravePath to "/Applications/Brave Browser.app"' -e 'tell application "System Events"' -e 'if not (exists process "Brave Browser") then' -e 'do shell script "open -a " & quoted form of bravePath' -e 'delay 3' -e 'end if' -e 'tell application "Brave Browser" to open location "https://youtube.com/tv"' -e 'delay 1' -e 'tell process "Brave Browser"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
    # Youtube Orion
    cmd + shift + alt - y : osascript -e 'set orionPath to "/Applications/Orion.app"' -e 'tell application "System Events"' -e 'if not (exists process "Brave Browser") then' -e 'do shell script "open -a " & quoted form of orionPath' -e 'delay 3' -e 'end if' -e 'tell application "Orion" to open location "https://youtube.com/tv"' -e 'delay 1' -e 'tell process "Orion"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
    # Open Stremio
    cmd + shift + alt - s : osascript -e 'set stremioPath to "/Applications/Stremio.app"' -e 'tell application "System Events"' -e 'if not (exists process "Stremio") then' -e 'do shell script "open -a " & quoted form of stremioPath' -e 'delay 3' -e 'end if' -e 'delay 1' -e 'tell process "stremio"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
    # Open Ryujinx
    cmd + shift + alt - r : osascript -e 'set ryujinxPath to "/Applications/Ryujinx.app"' -e 'tell application "System Events"' -e 'if not (exists process "Ryujinx") then' -e 'do shell script "open -a " & quoted form of ryujinxPath' -e 'delay 3' -e 'end if' -e 'delay 1' -e 'tell process "Ryujinx"' -e 'set value of attribute "AXFullScreen" of window 1 to true' -e 'end tell' -e 'end tell'
    # Send space if youtube, enter everywhere else
    cmd + shift + alt - e : osascript -e 'set currentURL to ""' -e 'tell application "System Events"' -e 'set frontAppName to name of first application process whose frontmost is true' -e 'if frontAppName is "Orion" then' -e 'tell application "Orion" to set currentURL to URL of current tab of front window' -e 'else if frontAppName is "Brave Browser" then' -e 'tell application "Brave Browser" to set currentURL to URL of active tab of front window' -e 'end if' -e 'if currentURL contains "youtube.com" then' -e 'tell process frontAppName to keystroke space' -e 'else' -e 'tell process frontAppName to keystroke return' -e 'end if' -e 'end tell'
  '';
}
