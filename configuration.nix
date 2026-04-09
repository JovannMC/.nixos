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
  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    optimise.automatic = true;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  imports = [
    ./home.nix
    ./apps/keyboard-knob-remap.nix
  ];

  boot = {
    loader = {
      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiSupport = true;
        minegrub-theme = {
          enable = true;
          splash = "100% Flakes!";
          background = "background_options/1.8  - [Classic Minecraft].png";
          boot-options-count = 2;
        };
      };

      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };

    # for OBS virtual camera
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';

    plymouth = {
      enable = true;
      plymouth-minecraft-theme.enable = true;
    };
  };
  security.polkit.enable = true;

  networking = {
    hostName = "mayabox";
    # Pick only one of the below networking options.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager.enable = true; # Easiest to use and most distros use this by default.
    networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
    nameservers = [
      "1.1.1.1#one.one.one.one"
      "1.0.0.1#one.one.one.one"
    ];
  };

  # Set your time zone.
  time.timeZone = "Asia/Qatar";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  hardware = {
    bluetooth = {
      enable = true; # enables support for Bluetooth
      powerOnBoot = true; # powers up the default Bluetooth controller on boot
      settings = {
        General = {
          Experimental = true;
        };
      };
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jovannmc = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "vboxusers"
      "dialout"
      "libvirtd"
      "input"
    ];
    shell = pkgs.zsh;
    #packages = with pkgs; [
    #];
  };

  virtualisation = {
    libvirtd.enable = true;
    spiceUSBRedirection.enable = true;
    waydroid.enable = true;
    docker.enable = true;
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "olm-3.2.16" ];
  };

  environment = {
    variables = {
      GAY = "maya";
    };
    sessionVariables = {
      # issue with gpu accel on wayland: https://github.com/electron/electron/issues/45862 & https://github.com/NixOS/nixpkgs/issues/382612
      # thanks chromium (https://issues.chromium.org/issues/396434686)
      NIXOS_OZONE_WL = "1"; # force electron apps to run on wayland
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
      ADB_LIBUSB = "0"; # adb broken - see https://github.com/nmeum/android-tools/issues/153

      # nvidia fixes?
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      # __EGL_VENDOR_LIBRARY_FILENAMES = "/run/current-system/sw/share/glvnd/egl_vendor.d/10_nvidia.json";
    };

    etc."libinput/local-overrides.quirks".text = ''
      [Beken 2.4G Wireless Device (Attack Shark X6) scroll fix]
      MatchName=Beken 2.4G Wireless Device*
      MatchUdevType=mouse
      AttrEventCode=-REL_WHEEL_HI_RES;-REL_HWHEEL_HI_RES;
    '';

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    systemPackages = with pkgs; [
      # programming
      python3
      nodejs
      corepack
      bun
      gnumake
      gcc
      undollar
      rust-analyzer
      jetbrains-toolbox
      jdk17

      # editors
      micro
      vscode
      audacity
      blender
      libreoffice
      alcom
      unityhub
      sourcegit
      github-desktop
      inkscape

      # command line utilities
      wget
      git
      tree
      nixfmt
      btop
      fastfetch
      hyfetch
      pciutils # gpu support for hyfetch.. even though it is in hyfetch's nix expression
      scrcpy
      uxplay
      zsh-you-should-use
      (ffmpeg-full.override {
        withOpengl = true;
        withRtmp = true;
      })
      playerctl
      busybox
      xclicker
      yt-dlp
      spotdl
      #wineWowPackages.stable
      #ineWowPackages.waylandFull
      wineWow64Packages.stable
      wineWow64Packages.waylandFull
      winetricks
      docker-compose
      p7zip # for unity hub, actually install support lmao
      exiftool
      libimobiledevice
      ifuse

      # chat
      vesktop
      arrpc
      nheko
      #kdePackages.neochat
      telegram-desktop
      thunderbird
      signal-desktop
      slack

      # games
      prismlauncher
      wayvr
      opencomposite
      bs-manager
      sidequest
      inputs.parsecgaming.packages.x86_64-linux.parsecgaming
      slimevr
      dolphin-emu

      # networking
      qbittorrent
      protonvpn-gui
      android-tools

      # other
      #brave
      # TODO: test ALL!!! the browser engines because why tf not, funny screenshot
      # prob need a windows vm for some - https://en.wikipedia.org/wiki/Browser_engine
      inputs.helium.packages.${system}.default
      inputs.orion-browser.packages.${pkgs.system}.default
      vlc
      filezilla
      spotify
      fahclient
      (pkgs.callPackage ./apps/davinci-resolve-paid.nix { })
      oneko
      nixd
      firefoxpwa

      # utilities
      gparted
      # gwe # no support for wayland
      tuxclocker
      nvidia-vaapi-driver
      recoll
      pinta
      qdirstat
      kdePackages.kalk
      kdePackages.dragon
      kdePackages.krdc
      kdePackages.krfb
      kdePackages.isoimagewriter
      kdePackages.kimageformats
      remmina
      localsend
      moonlight-qt
      yubioath-flutter
      handbrake
      #alsa-utils
      #pkgs.audiorelay
      sonobus
      easyeffects
      losslesscut-bin
      qdirstat
      qpwgraph
      lutris
      persepolis
      netpeek
      tigervnc
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
          # "LIBVA_DRIVER_NAME" fixes VA-API errors on NVIDIA (video recording blank)
          # "LD_LIBRARY_PATH" with tesseract fixes OCR
          wrapProgram $out/bin/spectacle \
            --set QT_QUICK_BACKEND software \
            --set LIBVA_DRIVER_NAME none \
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

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.kdePackages.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal
    ];
  };

  programs = {
    pay-respects.enable = true;
    nix-index.enable = true;
    noisetorch.enable = true;
    ssh.startAgent = true;
    openvpn3.enable = true;
    ladybird.enable = true;
    servo.enable = true;

    firefox = {
      enable = true;
      package = pkgs.librewolf;
      nativeMessagingHosts.packages = [ pkgs.firefoxpwa ];
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      histSize = 10000;

      shellAliases = {
        ll = "ls -l";
        update = "sudo nixos-rebuild switch";
        update-flake = "sudo nixos-rebuild switch --flake .#mayabox";
        upgrade-flake = "nix flake update && sudo nixos-rebuild switch --flake .#mayabox";
        upgrade-nixpkgs = "nix flake update nixpkgs && sudo nixos-rebuild switch --flake .#mayabox";
        upgrade-kernel = "nix flake update nix-cachyos-kernel && sudo nixos-rebuild switch --flake .#mayabox";
      };

      ohMyZsh = {
        enable = true;
        plugins = [
          "git"
          "dirhistory"
          "history"
          "direnv"
          "timer"
        ];
        theme = "robbyrussell";
      };
    };

    git = {
      enable = true;
      lfs.enable = true;
      config = {
        user.name = "JovannMC";
        user.email = "jovannmc@femboyfurry.net";
        commit.gpgsign = true;
        tag.gpgsign = true;
        gpg.format = "ssh";
        user.signingkey = "/home/jovannmc/.ssh/id_rsa.pub";
      };
    };

    spicetify =
      let
        spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
      in
      {
        enable = true;

        enabledExtensions = with spicePkgs.extensions; [
          adblock
          shuffle # shuffle+ (special characters are sanitized out of extension names)
          fullAlbumDate
          skipStats
          songStats
          showQueueDuration
          history
          volumePercentage
          beautifulLyrics
          oneko
        ];
        enabledCustomApps = with spicePkgs.apps; [
          newReleases
          ncsVisualizer
          marketplace
        ];
        enabledSnippets = with spicePkgs.snippets; [
          pointer
          smoothProgressBar
          oneko
        ];

        theme = spicePkgs.themes.catppuccin;
        colorScheme = "mocha";
      };

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = false;
    };

    appimage = {
      enable = true;
      binfmt = true;
    };

    steam = {
      enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
        proton-ge-rtsp-bin
        pkgs.steam-play-none
      ];
    };

    obs-studio = {
      enable = true;

      package = (
        pkgs.obs-studio.override {
          cudaSupport = true;
        }
      );

      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-backgroundremoval
        obs-pipewire-audio-capture
        obs-dvd-screensaver
        obs-freeze-filter
        obs-multi-rtmp
        obs-media-controls
        obs-vkcapture
        waveform
      ];
    };

    gnome-disks.enable = true;
    kdeconnect.enable = true;
    wireshark.enable = true;
    direnv.enable = true;
    virt-manager.enable = true;

    zoom-us.enable = true;
  };

  # List services that you want to enable:
  services = {
    #
    # hardware / system stuff
    #

    # Enable the X11 windowing system.
    xserver.enable = true;

    desktopManager.plasma6.enable = true;
    displayManager = {
      sddm = {
        enable = true;
        theme = "minesddm";
      };
      sddm.wayland.enable = false;
      defaultSession = "plasma";
      autoLogin.enable = true;
      autoLogin.user = "jovannmc";
    };

    # Enable CUPS to print documents.
    printing = {
      enable = true;
      drivers = [
        pkgs.hplipWithPlugin
      ];
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Enable sound.
    pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };

    resolved = {
      enable = true;
      settings.Resolve = {
        DNSSEC = "true";
        Domains = [ "~." ];
        FallbackDNS = [
          "1.1.1.1#one.one.one.one"
          "1.0.0.1#one.one.one.one"
        ];
        DNSOverTLS = "true";
      };
    };
    openssh.enable = true;
    blueman.enable = true;

    #
    # user stuff
    #
    wivrn = {
      enable = true;
      defaultRuntime = true;
      openFirewall = true;
      autoStart = true;
      # thank you LVRA discord for helping me fix my weird issue lmfao
      # "it could be that wivrn is writing an older path for oc and messing it up"
      extraServerFlags = [ "--no-manage-active-runtime" ];

      #       package = pkgs.wivrn.overrideAttrs (old: rec {
      #   version = "1e488a8a9c4be6fefae1fc63d9f23f65ebf53a06";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "WiVRn";
      #     repo = "WiVRn";
      #     rev = version;
      #     hash = "sha256-acsxbb3XKzpCkZUtkL3jfpk7qoBc7LU+VtQ7bA6JMCc=";
      #   };
      # });

      # config = {
      #   enable = true;
      #   json = {
      #     scale = 0.5;
      #     # 100 Mb/s
      #     bitrate = 100000000;
      #     encoders = [
      #       {
      #         encoder = "nvenc";
      #         codec = "h265";
      #         width = 0.5;
      #         height = 1.0;
      #         offset_x = 0.0;
      #         offset_y = 0.0;
      #       }
      #       {
      #         encoder = "nvenc";
      #         codec = "h265";
      #         width = 0.5;
      #         height = 1.0;
      #         offset_x = 0.5;
      #         offset_y = 0.0;
      #       }
      #     ];
      #   };
      # };
    };
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
    # foldingathome = {
    #   enable = true;
    #   team = 1066441;
    #   user = "JovannMC";
    # };
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    tailscale.enable = true;
    # zerotierone.enable = true;
    #logmein-hamachi.enable = true;
    flatpak = {
      enable = true;
      packages = [
        "org.vinegarhq.Sober"
      ];
    };

    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };

    cloudflare-warp = {
      enable = true;
      openFirewall = true;
    };

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

  systemd.packages = with pkgs; [ arrpc ];

  networking.firewall.enable = false;

  nix.settings = {
    substituters = [
      "https://cache.nixos-cuda.org"
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    ];
  };

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
