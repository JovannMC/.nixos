{ config, pkgs, ... }:

{
  imports = [ ../../configuration.nix ./hardware-configuration.nix ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver = {
    videoDrivers = [ "nvidia" ];
  };

  hardware.nvidia = {
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
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/5b9cc694-c600-48ae-87ff-558182b7bcc5";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/E044-AFE6";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/5E70E5FD70E5DC31";
    fsType = "ntfs";
  };

  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/C408CF7F08CF6F4C";
    fsType = "ntfs";
  };

  fileSystems."/mnt/editing" = {
    device = "/dev/disk/by-uuid/C6FE0F60FE0F47DF";
    fsType = "ntfs";
  };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/f11168ac-adc5-44d8-b13c-5860e01f703b"; }];
}
