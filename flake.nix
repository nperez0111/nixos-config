{
  description = "Nick the Sick's NixOS and MacOS configuration";

  inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/master"; };
    home-manager = { url = "github:nix-community/home-manager"; };
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, flake-utils, darwin, home-manager, nixpkgs, agenix, ... }@inputs: {
      # Mac Mini
      darwinConfigurations = {
        "nickthesicks-Mac-mini" = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [ ./darwin agenix.nixosModules.default ];
          inputs = { inherit darwin home-manager nixpkgs agenix; };
        };
      };
    };
}
