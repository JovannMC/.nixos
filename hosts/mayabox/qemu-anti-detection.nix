{
  pkgs,
  ...
}:

let
  patch = pkgs.fetchpatch {
    url = "https://raw.githubusercontent.com/zhaodice/qemu-anti-detection/main/qemu-10.2.2.patch";
    hash = "sha256-mMUtKzkHh8Q1lBu2Lrok6au521mUf4KOj8QJZRPOCOQ=";
  };
in {
  nixpkgs.overlays = [
    (final: prev: {
      qemu = prev.qemu.overrideAttrs (old: {
        version = "10.2.2";
        src = prev.fetchurl {
          url = "https://download.qemu.org/qemu-10.2.2.tar.xz";
          hash = "sha256-eEspb/KcFBeqcjI6vLLS6pq5dxck9Xfc14XDsE8h4XY=";
        };
        patches = (old.patches or []) ++ [ patch ];
      });
    })
  ];
}
