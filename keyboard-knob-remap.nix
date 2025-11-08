{
  config,
  pkgs,
  lib,
  ...
}:

# detect volume knob (mute) key presses and remap
# single = play/pause
# double = next track
# triple = previous track
# quadruple = mute/unmute
let
  muteKeyMonitor = pkgs.writeShellScriptBin "mute-key-monitor" ''
    #!/usr/bin/env bash

    LOCKFILE="/tmp/mute_key_double_click_$USER.lock"
    CLICK_COUNT_FILE="/tmp/mute_key_click_count_$USER"
    DOUBLE_CLICK_TIMEOUT=0.3

    KEYBOARD_DEVICE="/dev/input/event4" # idk if this changes?
    echo "Monitoring device: $KEYBOARD_DEVICE"

    ${pkgs.evtest}/bin/evtest "$KEYBOARD_DEVICE" 2>/dev/null | while read line; do
      # detect mute key (code 113) press
      if echo "$line" | ${pkgs.gnugrep}/bin/grep -q "code 113.*value 1"; then
        current_time=$(${pkgs.coreutils}/bin/date +%s.%N)

        # increment click count
        if [ -f "$CLICK_COUNT_FILE" ]; then
          click_count=$(${pkgs.coreutils}/bin/cat "$CLICK_COUNT_FILE")
          click_count=$((click_count + 1))
        else
          click_count=1
        fi
        echo "$click_count" > "$CLICK_COUNT_FILE"
        echo "$current_time" > "$LOCKFILE"

        # reset the timeout handler
        (
          sleep $DOUBLE_CLICK_TIMEOUT
          stored_time=$(${pkgs.coreutils}/bin/cat "$LOCKFILE" 2>/dev/null || echo "0")
          if [ "$stored_time" = "$current_time" ]; then
            click_count=$(${pkgs.coreutils}/bin/cat "$CLICK_COUNT_FILE" 2>/dev/null || echo "0")
            if [ "$click_count" -eq 1 ]; then
              echo "Detected single click - toggling play/pause"
              ${pkgs.playerctl}/bin/playerctl --player=spotify,vlc,%any play-pause
            elif [ "$click_count" -eq 2 ]; then
              echo "Detected double click - skipping to next track"
              ${pkgs.playerctl}/bin/playerctl --player=spotify,vlc,%any next
            elif [ "$click_count" -eq 3 ]; then
              echo "Detected triple click - skipping to previous track"
              ${pkgs.playerctl}/bin/playerctl --player=spotify,vlc,%any previous
            elif [ "$click_count" -eq 4 ]; then
              echo "Detected quadruple click - toggling system volume mute"
              ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
            fi
            ${pkgs.coreutils}/bin/rm -f "$LOCKFILE"
            ${pkgs.coreutils}/bin/rm -f "$CLICK_COUNT_FILE"
          fi
        ) &
      fi

      # detect key_calc (code 140) press
      # if echo "$line" | ${pkgs.gnugrep}/bin/grep -q "code 140.*value 1"; then
      #   # do something, konsole doesnt work lol
      # fi
    done
  '';

in
{
  environment.systemPackages = with pkgs; [
    playerctl
    bc
    evtest
    libinput
  ];

  systemd.user.services.mute-key-handler = {
    description = "Remaps mute key (keyboard volume knob) to media controls";
    wantedBy = [ "default.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${muteKeyMonitor}/bin/mute-key-monitor";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  services.udev.extraRules = ''
    KERNEL=="event*", SUBSYSTEM=="input", MODE="0660", GROUP="input"
  '';
}
