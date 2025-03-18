{
  description = "System flake";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      joebox = nixpkgs.lib.nixosSystem rec {
        system = "x86_64-linux";
        modules = [ ./hosts/joebox/configuration.nix ];
      };
    };

  };
}
