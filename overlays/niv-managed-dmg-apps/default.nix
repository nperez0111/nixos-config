{ nivSources, }:
self: super:
let
  inherit (self) stdenvNoCC lib;
  inherit (lib) isAttrs mapAttrs filterAttrs hasInfix;
  nivManagedDmgs =
    filterAttrs (n: v: (isAttrs v) && (hasInfix ".dmg" v.url)) nivSources;
  dmgInstall = args:
    stdenvNoCC.mkDerivation (args // {
      sourceRoot = ".";
      preferLocalBuild = true;
      phases = [ "installPhase" ];
      installPhase = ''
        echo "Installing $out..."
        mkdir -p mnt $out/Applications
        /usr/bin/hdiutil attach -readonly -mountpoint mnt $src
        # Install any .pkg files in the dmg
        for pkg in mnt/*.pkg; do
          echo /usr/bin/sudo /usr/sbin/installer -pkg "$pkg" -target / >> /tmp/todo
        done
        # Install any .app in the dmg
        for app in *.app; do
          echo "Copying $app..."
          cp -r "$app" $out/Applications/
        done
        /usr/bin/hdiutil detach -force mnt
      '';
    });
  dmgPkgs = mapAttrs (n: v:
    dmgInstall {
      src = v;
      name = n;
      version = v.version;
    }) nivManagedDmgs;
in { nivApps = dmgPkgs; }
