{
  description = "System flake";

  inputs = { 
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
  };

  outputs = { self, nixpkgs, nixpkgs-xr }: {
    nixosConfigurations = {
      joebox = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        modules = [
          ./hosts/joebox/configuration.nix
          nixpkgs-xr.nixosModules.nixpkgs-xr
        ];
      };
    };

  };
}
