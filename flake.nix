{
  description = "System flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-xr.url = "github:nix-community/nixpkgs-xr";
    # spicetify-nix.url = "github:Gerg-L/spicetify-nix";
    # spicetify-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-xr, # spicetify-nix
    }: {
      nixosConfigurations = {
        joebox = nixpkgs.lib.nixosSystem rec {
          system = "x86_64-linux";
          modules = [
            ./hosts/joebox/configuration.nix
            nixpkgs-xr.nixosModules.nixpkgs-xr
            # spicetify-nix.lib.mkSpicetify
          ];
        };
      };
    };
}
