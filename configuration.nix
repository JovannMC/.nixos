# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, inputs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  imports = [ ./home.nix ];

  boot.loader = {
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
      useOSProber = true;
    };

    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
  };

  networking = {
    hostName = "joebox";
    # Pick only one of the below networking options.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager.enable =
      true; # Easiest to use and most distros use this by default.
    nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
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
      settings = { General = { Experimental = true; }; };
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jovannmc = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.zsh;
    #packages = with pkgs; [
    #];
  };

  users.groups.libvirtd.members = [ "jovannmc" ];

  virtualisation = {
    libvirtd.enable = true;
    spiceUSBRedirection.enable = true;
  };

  nixpkgs.config = {
    allowUnfree = true;
    permittedInsecurePackages = [ "olm-3.2.16" ];
    cudaSupport = true;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # programming
    python3Full
    nodejs
    bun
    github-desktop
    gnumake
    gcc
    undollar

    # editors
    micro
    vscode
    audacity
    blender
    libreoffice
    alcom
    unityhub

    # command line utilities
    wget
    git
    tree
    nixfmt
    btop
    hyfetch
    pciutils # gpu support for hyfetch.. even though it is in hyfetch's nix expression
    android-tools
    scrcpy
    uxplay
    zsh-you-should-use

    # chat
    vesktop
    nheko
    #kdePackages.neochat
    telegram-desktop
    thunderbird

    # games
    prismlauncher
    wlx-overlay-s
    opencomposite
    bs-manager
    #also get rdp/vnc working
    sidequest

    # networking
    qbittorrent

    # other
    librewolf
    brave
    obs-studio
    vlc
    filezilla
    spotify
    fahclient
    (pkgs.callPackage ./davinci-resolve-paid.nix { })

    # utilities
    vmware-workstation
    gparted
    xmousepasteblock
    # gwe # no support for wayland
    tuxclocker
    kdePackages.krdc
    nvidia-vaapi-driver
    recoll
    kdePackages.kalk
    pinta
    qdirstat
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      histSize = 10000;

      shellAliases = {
        ll = "ls -l";
        update = "sudo nixos-rebuild switch";
      };

      ohMyZsh = {
        enable = true;
        plugins = [ "git" "thefuck" "dirhistory" "history" ];
        theme = "robbyrussell";
      };
    };
    thefuck.enable = true;

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
      let spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
      in {
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
      enableSSHSupport = true;
    };

    appimage = {
      enable = true;
      binfmt = true;
    };

    steam = {
      enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin proton-ge-rtsp-bin ];
    };

    partition-manager.enable = true;
    kdeconnect.enable = true;
    virt-manager.enable = true;
    java.enable = true;
    wireshark.enable = true;
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
      sddm.enable = true;
      sddm.wayland.enable = false;
      defaultSession = "plasma";
    };

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable sound.
    pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
    };

    resolved = {
      enable = true;
      dnssec = "true";
      domains = [ "~." ];
      fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
      dnsovertls = "true";
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
    foldingathome = {
      enable = true;
      team = 1066441;
      user = "JovannMC";
    };
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    tailscale.enable = true;
    flatpak.enable = true;
  };

  environment = {
    variables = { GAY = "maya"; };
    sessionVariables = {
      # issue with gpu accel on wayland: https://github.com/electron/electron/issues/45862 & https://github.com/NixOS/nixpkgs/issues/382612
      # thanks chromium (https://issues.chromium.org/issues/396434686)
      #NIXOS_OZONE_WL = "1"; # force electron apps to run on wayland
      STEAM_EXTRA_COMPAT_TOOLS_PATHS =
        "\${HOME}/.steam/root/compatibilitytools.d";
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 3389 ];
  networking.firewall.allowedUDPPorts = [ 3389 ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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
  system.stateVersion = "24.11"; # Did you read the comment?

}

