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
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";
    minecraft-plymouth.url = "github:nikp123/minecraft-plymouth-theme";
    minegrub-theme.url = "github:Lxtharia/minegrub-theme";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-xr,
      home-manager,
      spicetify-nix,
      parsecgaming,
      nix-flatpak,
      nix-cachyos-kernel,
      minecraft-plymouth,
      minegrub-theme,
    }@inputs:
    {
      nixosConfigurations = {
        mayabox = nixpkgs.lib.nixosSystem  {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            (
              { pkgs, ... }:
              {
                nixpkgs.overlays = [ nix-cachyos-kernel.overlay ];
                boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-lts-lto;
              }
            )
            ./hosts/mayabox/configuration.nix
            nixpkgs-xr.nixosModules.nixpkgs-xr
            home-manager.nixosModules.home-manager
            spicetify-nix.nixosModules.default
            nix-flatpak.nixosModules.nix-flatpak
            minecraft-plymouth.nixosModules.default
            minegrub-theme.nixosModules.default
          ];
        };
      };
    };
}
