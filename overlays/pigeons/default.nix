self: super:
let
  inherit (self) stdenv fetchurl;
  # To upgrade:
  #   1. Update `version` to the new tag (e.g. "0.2.0")
  #   2. Run: nix-prefetch-url --unpack <new release tarball URL>
  #   3. Update `sha256` below with the output
  version = "0.1.1";
  platform =
    if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then "darwin-aarch64"
    else if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64 then "darwin-x86_64"
    else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then "linux-x86_64"
    else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64 then "linux-aarch64"
    else throw "pigeons: unsupported platform";
in
{
  pigeons = stdenv.mkDerivation {
    pname = "pigeons";
    inherit version;
    src = fetchurl {
      url = "https://github.com/n0-computer/pigeons/releases/download/v${version}/pigeons-v${version}-${platform}.tar.gz";
      sha256 = "sha256-pDQ61iUNP3B3y1fLEn6WtGOXgjJ6PzwP+4VSvBbSGpo=";
    };
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out/bin
      cp pigeons $out/bin/pigeons
      chmod +x $out/bin/pigeons
    '';
  };
}
