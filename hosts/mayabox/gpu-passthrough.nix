# based off https://olai.dev/blog/nvidia-vm-passthrough/
{
  pkgs,
  config,
  lib,
  ...
}:

let
  devices = [
    "10de:21c4" # GTX 1660 Super
    "10de:1aeb" # GTX 1660 Super Audio
  ];
in
{
  # Make the devices bind to VFIO
  boot.kernelParams = [
    "vfio-pci.ids=${lib.concatStringsSep "," devices}"
  ];
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];

  # !! for some reason, these cause my system to freak out a bit
  # !! gpus work as expected with their correct drivers but displays are duplicated, only one is shown in system
  # !! and kde plasma desktop hw accel is ded lol
  # Blacklist the nvidia drivers to make sure they don't get loaded
  # boot.extraModprobeConfig = ''
  #   softdep nvidia pre: vfio-pci
  #   softdep drm pre: vfio-pci
  #   softdep nouveau pre: vfio-pci
  # '';
  # boot.blacklistedKernelModules = [
  #   "nouveau"
  #   "nvidia"
  #   "nvidia_drm"
  #   "nvidia_modeset"
  #   "i2c_nvidia_gpu"
  # ];
  virtualisation.spiceUSBRedirection.enable = true;

  # # Looking glass
  # environment.systemPackages = [ pkgs.looking-glass-client ];
  # systemd.tmpfiles.rules = [
  #   "f /dev/shm/looking-glass 0660 jovannmc libvirtd -"
  # ];
}
