self: super:
let
  inherit (self) stdenv;
in
{
  nivApps = {
    cemu = stdenv.mkDerivation {
      name = "cemu";
      version = "2.0-39";
      src = builtins.fetchurl {
        url = "https://github.com/cemu-project/Cemu/releases/download/v2.0-39/cemu-2.0-39-macos-12-x64.dmg";
        sha256 = "16pqzp16xssk12jz9rqasbpkkdwban5qkznnv5ij0dmn122zlfrm";
      };
      nativeBuildInputs = with self; [ ];
      sourceRoot = ".";
      preferLocalBuild = true;
      allowSubstitutes = false;
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/Applications
        hdiutil attach -readonly -mountpoint mnt $src 2>&1 || true
        cp -r mnt/*.app $out/Applications/ 2>/dev/null || true
        hdiutil detach mnt 2>/dev/null || true
      '';
    };

    flirc = stdenv.mkDerivation {
      name = "flirc";
      version = "3.26.8";
      src = builtins.fetchurl {
        url = "https://flirc.com/software/flirc-usb/GUI/release/mac/Flirc-3.26.8.dmg";
        sha256 = "1jkm8qv423fbyyfl14865amgmflimgvs5yq0zfd8c2y4hasv5chx";
      };
      nativeBuildInputs = with self; [ ];
      sourceRoot = ".";
      preferLocalBuild = true;
      allowSubstitutes = false;
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/Applications
        hdiutil attach -readonly -mountpoint mnt $src 2>&1 || true
        cp -r mnt/*.app $out/Applications/ 2>/dev/null || true
        hdiutil detach mnt 2>/dev/null || true
      '';
    };

    java = stdenv.mkDerivation {
      name = "zulu17";
      version = "17.42.19";
      src = builtins.fetchurl {
        url = "https://cdn.azul.com/zulu/bin/zulu17.42.19-ca-jdk17.0.7-macosx_aarch64.dmg";
        sha256 = "1i85a9a3x61nvh5d9h9ldys51j8y5i6vz3znwyn20l5j3plaqkwq";
      };
      nativeBuildInputs = with self; [ ];
      sourceRoot = ".";
      preferLocalBuild = true;
      allowSubstitutes = false;
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p $out/Applications
        hdiutil attach -readonly -mountpoint mnt $src 2>&1 || true
        for pkg in mnt/*.pkg; do
          echo "Found package: $pkg"
        done
        cp -r mnt/*.app $out/Applications/ 2>/dev/null || true
        hdiutil detach mnt 2>/dev/null || true
      '';
    };
  };
}
