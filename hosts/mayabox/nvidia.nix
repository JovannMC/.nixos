# stolen (& updated) :3
# https://github.com/AnnoyingRain5/dotfiles/blob/f7ca4e42ee12234ddf40ef91755c58a2ea4dca13/hosts/Dragon/nvidia.nix
{
  config,
  pkgs,
  lib,
  ...
}:

let
  package = config.boot.kernelPackages.nvidiaPackages.beta;
in
{
  ### only enable hardware.nvidia on the default specialisation, to allow the nouveau specialisation to exist ###
  options.mayabox.nvidia.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable nvidia proprietary drivers guh";
  };

  config = lib.mkIf config.mayabox.nvidia.enable {
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

    # set 1660 super to 100W and 3060 ti to 160W
    systemd.services.nvidia-power-limit = {
      description = "Set NVIDIA GPU power limits";
      after = [ "nvidia-persistenced.service" ];
      wants = [ "nvidia-persistenced.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # nvidia-smi -i 0 -pl 100
        # nvidia-smi -i 1 -pl 160
        nvidia-smi -pl 160
      '';

      path = [
        config.hardware.nvidia.package
      ];
    };
  };
}
