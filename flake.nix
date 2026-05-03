{
  description = "Nick the Sick's nix-darwin configuration";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      flake-utils,
      darwin,
      home-manager,
      nixpkgs,
      agenix,
      ...
    }@inputs:
    {
      # Mac Mini
      darwinConfigurations = {
        "nickthesicks-Mac-mini" = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            ./darwin
            home-manager.darwinModules.home-manager
            agenix.nixosModules.default
          ];
          inputs = {
            inherit
              darwin
              home-manager
              nixpkgs
              agenix
              ;
          };
        };
      };
    };
}
