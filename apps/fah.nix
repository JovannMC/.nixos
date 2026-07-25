{ pkgs, ... }:

{
  systemd.user.services.foldingathome = {
    description = "Folding@Home Client (user service)";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.fahclient}/bin/fah-client --beta=yes";
      Restart = "always";
      RestartSec = "10";
    };
  };
}
