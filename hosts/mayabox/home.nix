{
  inputs,
  pkgs,
  ...
}:
{

  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager.backupFileExtension = "home-manager.bak";
  home-manager.users.jovannmc = {
    # The home.stateVersion option does not have a default and must be set
    home.stateVersion = "25.05";

    xdg.configFile."openxr/1/active_runtime.json".text = ''
      {
        "file_format_version": "1.0.0",
        "runtime": {
            "name": "Monado",
            "library_path": "${pkgs.wivrn}/lib/wivrn/libopenxr_wivrn.so"
        }
      }
    '';
  };
}
