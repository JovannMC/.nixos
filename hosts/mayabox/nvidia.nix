# stolen (& updated) :3
# https://github.com/AnnoyingRain5/dotfiles/blob/f7ca4e42ee12234ddf40ef91755c58a2ea4dca13/hosts/Dragon/nvidia.nix
{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # find the latest patchable version here: https://github.com/icewind1991/nvidia-patch-nixos/blob/main/patch.json
  # that list should match 1:1 with the list here: https://github.com/keylase/nvidia-patch
  # if it doesn't... time for a fork!
  package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    version = "595.71.05";

    # Replace with the hashes nix gives you
    sha256_64bit = "sha256-NiA7iWC35JyKQva6H1hjzeNKBek9KyS3mK8G3YRva4I=";
    sha256_aarch64 = lib.fakeHash;
    openSha256 = "sha256-Lfz71QWKM6x/jD2B22SWpUi7/og30HRlXg1kL3EWzEw=";
    settingsSha256 = "sha256-Lfz71QWKM6x/jD2B22SWpUi7/og30HRlXg1kL3EWzEw=";
    persistencedSha256 = lib.fakeHash;
  };
in
{
  ### only enable hardware.nvidia on the default specialisation, to allow the nouveau specialisation to exist ###
  config = lib.mkIf (config.specialisation != { }) {
    # Load nvidia driver for Xorg and Wayland
    services.xserver = {
      videoDrivers = [ "nvidia" ];
    };
    hardware = {
      graphics = {
        enable = true;
        enable32Bit = true;
      };

      nvidia = {

        # Modesetting is required.
        modesetting.enable = true;

        # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
        powerManagement.enable = false;
        # Fine-grained power management. Turns off GPU when not in use.
        # Experimental and only works on modern Nvidia GPUs (Turing or newer).
        powerManagement.finegrained = false;

        # Use the NVidia open source kernel module (not to be confused with the
        # independent third-party "nouveau" open source driver).
        # Support is limited to the Turing and later architectures. Full list of
        # supported GPUs is at:
        # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
        # Only available from driver 515.43.04+
        # Currently alpha-quality/buggy, so false is currently the recommended setting.
        open = true;

        # Enable the Nvidia settings menu,
        # accessible via `nvidia-settings`.
        nvidiaSettings = true;

        # apply some patches!
        package = pkgs.nvidia-patch.patch-nvenc (pkgs.nvidia-patch.patch-fbc package);
        #package = config.boot.kernelPackages.nvidiaPackages.beta;
      };
    };
  };
}
