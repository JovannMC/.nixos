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
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [
        "https://cache.nixos-cuda.org"
        "https://attic.xuyh0120.win/lantian"
      ];
      trusted-public-keys = [
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      ];
    };

    optimise.automatic = true;
  };

  boot = {
    loader.efi.efiSysMountPoint = "/boot";

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
    graphics.enable32Bit = false;
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

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [
      "olm-3.2.16"
      "openssl-1.1.1w"
    ];
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
    };

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
      vscode
      audacity
      github-desktop

      # command line utilities
      wget
      git
      nixfmt
      btop
      fastfetch
      hyfetch
      pciutils # gpu support for hyfetch.. even though it is in hyfetch's nix expression
      scrcpy
      zsh-you-should-use
      (ffmpeg-full.override {
        withOpengl = true;
        withRtmp = true;
      })
      busybox
      yt-dlp
      spotdl
      #wineWowPackages.stable
      #ineWowPackages.waylandFull
      wineWow64Packages.stable
      wineWow64Packages.waylandFull
      winetricks
      p7zip # for unity hub, actually install support lmao
      exiftool
      unrar

      # chat
      vesktop
      arrpc
      telegram-desktop
      signal-desktop
      slack

      # networking
      qbittorrent
      proton-vpn
      android-tools

      # other
      inputs.helium.packages.${system}.default
      vlc
      filezilla
      spotify
      (pkgs.callPackage ./apps/davinci-resolve-paid.nix { })
      nixd
      firefoxpwa

      # utilities
      gparted
      recoll
      pinta
      qdirstat
      kdePackages.kalk
      kdePackages.dragon
      kdePackages.gwenview
      kdePackages.kimageformats
      (kdePackages.spectacle.override {
        tesseractLanguages = [ "eng" ];
      })
      remmina
      localsend
      moonlight-qt
      yubioath-flutter
      handbrake
      easyeffects
      losslesscut-bin
      qpwgraph
      netpeek
      tigervnc
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

    nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--delete-older-than 30d --keep";
      flake = "/home/jovannmc/.nixos"; # sets NH_OS_FLAKE variable for you
    };

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
        update-flake = "sudo nixos-rebuild switch";
        upgrade-flake = "nix flake update && sudo nixos-rebuild switch";
        upgrade-nixpkgs = "nix flake update nixpkgs && sudo nixos-rebuild switch --flake .#mayabox";
        upgrade-all-but-kernel = "nix flake update nixpkgs nixpkgs-xr home-manager spicetify-nix parsecgaming nix-flatpak minecraft-plymouth minegrub-theme minseddm helium orion-browser ngi && sudo nixos-rebuild switch";
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
    wireshark.enable = true;
    direnv.enable = true;

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
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
    joycond.enable = true;

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
  };

  systemd.packages = with pkgs; [ arrpc ];

  networking.firewall.enable = false;
}
