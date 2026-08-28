self: super:
let
  inherit (self) stdenv fetchurl;
  # iCloud Photos -> S3 backup CLI. https://github.com/tijs/attic
  #
  # Attribute is `attic-photos`, NOT `attic`: nixpkgs already ships an
  # unrelated `attic` (Zhaofeng Li's Nix binary cache server) and shadowing it
  # here would be silent and confusing.
  #
  # To upgrade:
  #   1. Update `version` to the new tag (without the leading "v")
  #   2. Run: nix-prefetch-url <new release tarball URL>   (NOT --unpack)
  #   3. Update `sha256` below with the output
  #   4. IMPORTANT: the release binary is ad-hoc, linker-signed, so its keychain
  #      Designated Requirement is derived from its content hash. A new version
  #      looks like a different application and the existing keychain ACL will
  #      refuse access until re-trusted. After deploying an upgrade, run:
  #        launchctl kickstart -k gui/$(id -u)/org.nixos.attic-prime
  #      from a GUI session and click "Always Allow" on both keychain prompts.
  #      Skipping this makes the nightly backup fail with
  #      "Failed to read keychain item" and upload nothing.
  #   5. The Photos TCC grant is keyed on the BINARY PATH, which is this store
  #      path - so a version bump also drops Photos access. The same prime
  #      kickstart re-prompts for it; click "Allow". Verified 2026-08-28:
  #      TCC.db held `.../attic-photos-1.0.0-beta.25/bin/attic|2`.
  #
  # KNOWN GAP: beta.25 (newest release) has no --on-failure/--on-success and no
  # --json on backup or status, despite upstream's docs describing all three -
  # they exist only on unreleased `main`. darwin/attic/attic-backup-run.sh works
  # around this. Re-check on the next release and simplify if they have landed.
  version = "1.0.0-beta.25";
  platform =
    if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then "aarch64-apple-darwin"
    else throw "attic-photos: unsupported platform (upstream ships aarch64-apple-darwin only)";
in
{
  attic-photos = stdenv.mkDerivation {
    pname = "attic-photos";
    inherit version;
    src = fetchurl {
      url = "https://github.com/tijs/attic/releases/download/v${version}/attic-${version}-${platform}.tar.gz";
      sha256 = "sha256-3nc76q50gIRoFC4HbPbzBOnVoQuR7CwpTh4g6Y5EsJY=";
    };
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out/bin
      cp attic $out/bin/attic
      chmod +x $out/bin/attic
    '';
  };
}
