{
  config,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../../configuration.nix
    ./hardware-configuration.nix

    ./home.nix
    ../../apps/keyboard-knob-remap.nix
  ];

  networking.hostName = "mayabox";

  boot = {
    loader = {
      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        minegrub-theme = {
          enable = true;
          splash = "100% Orange Juice!";
          background = "background_options/1.8  - [Classic Minecraft].png";
          boot-options-count = 2;
        };
      };

      efi.canTouchEfiVariables = true;
    };
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

      # Optionally, you may need to select the appropriate driver version for your specific GPU.
      package = config.boot.kernelPackages.nvidiaPackages.beta;
    };
  };

  virtualisation = {
    libvirtd.enable = true;
    spiceUSBRedirection.enable = true;
    docker.enable = true;
  };

  environment = {
    sessionVariables = {
      # nvidia fixes?
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      # __EGL_VENDOR_LIBRARY_FILENAMES = "/run/current-system/sw/share/glvnd/egl_vendor.d/10_nvidia.json";
    };

    etc."libinput/local-overrides.quirks" = {
      # please work
      text = ''
        [KillHighResScroll]
        MatchName=*
        AttrEventCode=-REL_WHEEL_HI_RES;-REL_HWHEEL_HI_RES;
      '';
    };

    systemPackages = with pkgs; [
      # editors
      micro
      blender
      libreoffice
      alcom
      unityhub
      sourcegit
      inkscape

      # command line utilities
      uxplay
      playerctl
      #wineWowPackages.stable
      #ineWowPackages.waylandFull
      wineWow64Packages.stable
      wineWow64Packages.waylandFull
      spotdl
      yt-dlp
      docker-compose
      libimobiledevice
      ifuse

      # games
      prismlauncher
      wayvr
      opencomposite
      bs-manager
      sidequest
      inputs.parsecgaming.packages.x86_64-linux.parsecgaming
      slimevr
      dolphin-emu
      osu-lazer-bin
      ryubing

      # chat
      slack

      # other
      brave
      # TODO: test ALL!!! the browser engines because why tf not, funny screenshot
      # prob need a windows vm for some - https://en.wikipedia.org/wiki/Browser_engine
      inputs.orion-browser.packages.${pkgs.system}.default
      (pkgs.callPackage ../../apps/davinci-resolve-paid.nix { })
      fahclient

      # utilities
      # gwe # no support for wayland
      # tuxclocker # broken - see https://github.com/NixOS/nixpkgs/issues/504637 & https://github.com/Lurkki14/tuxclocker/pull/107
      nvidia-vaapi-driver
      #alsa-utils
      #pkgs.audiorelay
      sonobus
      #lutris # broken due to openldap, don't need anyways - see https://github.com/NixOS/nixpkgs/issues/513245
      (symlinkJoin {
        name = "spectacle";
        paths = [
          (kdePackages.spectacle.override {
            tesseractLanguages = [ "eng" ];
          })
        ];
        buildInputs = [ makeWrapper ];
        postBuild = ''
          # "QT_QUICK_BACKEND" fixes EGL context errors on NVIDIA wayland (crashing on having heavy GPU apps open)
          # "LD_LIBRARY_PATH" with tesseract fixes OCR
          wrapProgram $out/bin/spectacle \
            --set QT_QUICK_BACKEND software \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ tesseract ]} \
        '';
      })

      # currently broken, discord_krisp moved?
      # -- FileNotFoundError: [Errno 2] No such file or directory: '/home/jovannmc/.config/discordcanary/0.0.871/modules/discord_krisp/discord_krisp.node'
      # discord lol
      # (
      #   let
      #     patch-krisp = writers.writePython3 "krisp-patcher" {
      #       libraries = with python3Packages; [
      #         capstone
      #         pyelftools
      #       ];
      #       flakeIgnore = [
      #         "E501"
      #         "F403"
      #         "F405"
      #       ];
      #     } (builtins.readFile ./apps/krisp-patcher.py); # thank you https://git.gay/amida/krisp-patcher/ and AnnoyingRains lmao
      #     binaryName = "DiscordCanary";
      #     node_module = "\\$HOME/.config/discordcanary/${discord-canary.version}/modules/discord_krisp/discord_krisp.node";
      #   in
      #   (discord-canary.override {
      #     withVencord = true;
      #     withOpenASAR = true;
      #   }).overrideAttrs
      #     (previousAttrs: {
      #       postInstall = previousAttrs.postInstall + ''
      #         wrapProgramShell $out/opt/${binaryName}/${binaryName} \
      #         --run "${patch-krisp} ${node_module}"
      #       '';
      #       passthru = removeAttrs previousAttrs.passthru [ "updateScript" ];
      #     })
      # )
      discord-canary
    ];
  };

  programs = {
    ladybird.enable = true;
    servo.enable = true;

    steam = {
      enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
        proton-ge-rtsp-bin
        pkgs.steam-play-none
      ];
    };
    joycond-cemuhook.enable = true;

    kdeconnect.enable = true;
    virt-manager.enable = true;
  };

  # List services that you want to enable:
  services = {
    xserver.videoDrivers = [ "nvidia" ];

    #
    # hardware / system stuff
    #

    # Enable CUPS to print documents.
    printing = {
      enable = true;
      drivers = [
        pkgs.hplipWithPlugin
      ];
    };

    pipewire.alsa.support32Bit = true;

    #
    # user stuff
    #
    wivrn = {
      enable = true;
      package = pkgs.wivrn.override { cudaSupport = true; };

      # openFirewall = true;
      # autoStart = true;

      # thank you LVRA discord for helping me fix my weird issue lmfao
      # "it could be that wivrn is writing an older path for oc and messing it up"
      # extraServerFlags = [ "--no-manage-active-runtime" ];

      # package = pkgs.wivrn.overrideAttrs (old: rec {
      #   version = "1e488a8a9c4be6fefae1fc63d9f23f65ebf53a06";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "WiVRn";
      #     repo = "WiVRn";
      #     rev = version;
      #     hash = "sha256-acsxbb3XKzpCkZUtkL3jfpk7qoBc7LU+VtQ7bA6JMCc=";
      #   };
      # });
    };

    # foldingathome = {
    #   enable = true;
    #   team = 1066441;
    #   user = "JovannMC";
    # };

    cloudflared = {
      enable = true;
      tunnels = {
        "79bcf313-5f62-4996-9a29-d36a70461da1" = {
          credentialsFile = "/home/jovannmc/.cloudflared/79bcf313-5f62-4996-9a29-d36a70461da1.json"; # this needs to not be hardcoded lol
          default = "http_status:404";
          ingress = {
            "vertd.jovann.me" = "http://localhost:24153";
          };
        };
      };
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/b1dc858d-6e15-4ae5-ac31-73d9cb9bcaae";
      fsType = "btrfs";
      options = [ "subvol=@" ];
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/EC47-0639";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    "/mnt/storage" = {
      device = "/dev/disk/by-uuid/C408CF7F08CF6F4C";
      fsType = "ntfs";
    };

    "/mnt/editing" = {
      device = "/dev/disk/by-uuid/C6FE0F60FE0F47DF";
      fsType = "ntfs";
    };
  };
  swapDevices = [ { device = "/dev/disk/by-uuid/6766bdd8-c44c-4512-980c-c43087f8a98a"; } ];

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?
}
