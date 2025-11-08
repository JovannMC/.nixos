{
  description = "System flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    spicetify-nix.url = "github:Gerg-L/spicetify-nix";
    spicetify-nix.inputs.nixpkgs.follows = "nixpkgs";
    parsecgaming.url = "github:DarthPJB/parsec-gaming-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-xr,
      home-manager,
      spicetify-nix,
      parsecgaming,
    }@inputs:
    {
      nixosConfigurations = {
        mayabox = nixpkgs.lib.nixosSystem rec {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/mayabox/configuration.nix
            nixpkgs-xr.nixosModules.nixpkgs-xr
            home-manager.nixosModules.home-manager
            spicetify-nix.nixosModules.default
          ];
        };
      };
    };
}
