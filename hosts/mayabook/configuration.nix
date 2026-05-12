# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  pkgs,
  inputs,
  ...
}:

{
  # Implicitly enables IWD and disables wpa_supplicant
  networking.networkmanager.wifi.backend = "iwd";

  # hardware.apple.touchBar = {
  #   enable = true;
  #   package = pkgs.tiny-dfr;
  # };
}
