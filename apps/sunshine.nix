{
  pkgs,
  ...
}:


# this is so fucking scuffed but it WORKS lol
let
  sunshine-switch = pkgs.writeShellScriptBin "sunshine-switch" ''
    set -euo pipefail

    TARGET="$1"
    CONF="''${HOME}/.config/sunshine/sunshine.conf"
    SERVICE="sunshine.service"

    current="$(grep -E '^output_name\s*=' "$CONF" 2>/dev/null | sed -E 's/.*=\s*//' || true)"

    if [ "$current" = "$TARGET" ]; then
      exit 0
    fi

    if grep -qE '^output_name\s*=' "$CONF" 2>/dev/null; then
      sed -i -E "s/^output_name\s*=.*/output_name = ''${TARGET}/" "$CONF"
    else
      printf '\noutput_name = %s\n' "$TARGET" >> "$CONF"
    fi

    systemctl --user restart "$SERVICE"
  '';
in
{
  # using sunshine-switch within webui config rather than nixos module because modifying the modulle
  # would not make the script work (changing config location)
  environment.systemPackages = [ sunshine-switch ];
  services.sunshine.package = pkgs.sunshine.override { cudaSupport = true; };
}
