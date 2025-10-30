{ config, lib, nixpkgs, inputs, outputs, pkgs, ... }: {

  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager.backupFileExtension = ".home-manager.bak";
  home-manager.users.jovannmc = {
    # The home.stateVersion option does not have a default and must be set
    home.stateVersion = "25.05";

    xdg.desktopEntries = {
      wlx-overlay-s = {
        name = "wlx-overlay-s";
        genericName = "VR Overlay";
        exec =
          "LIBMONADO_PATH=${pkgs.wivrn}/lib/wivrn/lib/libmonado_wivrn.so wlx-overlay-s --openxr";
        terminal = true;
        categories = [ "Application" ];
        mimeType = [ ];
      };
    };

    xdg.configFile."openxr/1/active_runtime.json".text = ''
      {
        "file_format_version": "1.0.0",
        "runtime": {
            "name": "Monado",
            "library_path": "${pkgs.wivrn}/lib/wivrn/libopenxr_wivrn.so"
        }
      }
    '';

    xdg.configFile."openvr/openvrpaths.vrpath".text = ''
      {
        "config" :
        [
          "~/.local/share/Steam/config"
        ],
        "external_drivers" : null,
        "jsonid" : "vrpathreg",
        "log" :
        [
          "~/.local/share/Steam/logs"
        ],
        "runtime" :
        [
          "${pkgs.opencomposite}/lib/opencomposite"
        ],
        "version" : 1
      }
    '';
  };
}
