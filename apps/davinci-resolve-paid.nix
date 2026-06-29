{
  davinci-resolve-studio,
  hexdump,
  replaceDependencies,
  makeWrapper,
  pkgs,
  ...
}:
let
  ffmpeg-encoder-plugin = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "ffmpeg-encoder-plugin";
    version = "1.3.3";

    src = pkgs.fetchFromGitHub {
      owner = "EdvinNilsson";
      repo = "ffmpeg_encoder_plugin";
      tag = "v${finalAttrs.version}";
      hash = "sha256-G677EnV9cob0VyLzuyMeKzrDLZB7NrzmBVBRQ2kN/Gc=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      ffmpeg-full
    ];

    buildInputs = with pkgs; [ ffmpeg ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp ffmpeg_encoder_plugin.dvcp $out/
      runHook postInstall
    '';
  });

  # TODO: update patch for 20.3.3, not working
  davinci-aac-fix = pkgs.stdenv.mkDerivation {
    pname = "davinci-resolve-linux-aac-fix";
    version = "local";

    src = ./davinci-resolve-linux-aac-fix;

    nativeBuildInputs = [ pkgs.gcc ];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      ${pkgs.gcc}/bin/gcc \
        -shared -fPIC -O2 -Wall -Wno-format-truncation \
        -o aac_hybrid_shim.so \
        src/aac_hybrid_shim.c
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin

      install -m755 aac_hybrid_shim.so $out/lib/aac_hybrid_shim.so
      install -m755 tools/resolve-codec-patch $out/bin/resolve-codec-patch

      runHook postInstall
    '';
  };

  nonFhsOriginalDavinci = davinci-resolve-studio.passthru.davinci;

  davinciPatched = nonFhsOriginalDavinci.overrideAttrs (
    finalAttrs: prevAttrs: {
      nativeBuildInputs = (prevAttrs.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

      preFixup = (prevAttrs.preFixup or "") + ''
        pattern="\xff\xe9\x75\x02\x00\x00\x85\xdb\x74\x68\x4d\x8b\x7e\x10\x49\x89"
        offset=8
        file="$out/bin/resolve"
        matches=$(LANG=C grep -obUaP "$pattern" "$file")
        matchcount=$(echo "$matches" | wc -l)
        if [[ -z $matches ]]; then
          echo "pattern not found"
        elif [[ $matchcount -ne 1 ]]; then
          echo "pattern returned $matchcount matches instead of 1"
        else
          patternOffset=$(echo "$matches" | cut -d: -f1)
          instructionOffset=$((patternOffset + offset))
          echo "patching byte '0x$(${hexdump}/bin/hexdump -s "$instructionOffset" -n 1 -e '/1 "%02x"' "$file")' at offset $instructionOffset"
          printf '\x75' | dd conv=notrunc of="$file" bs=1 seek="$instructionOffset" count=1
        fi
      '';

      postInstall = (prevAttrs.postInstall or "") + ''
        mkdir -p $out/IOPlugins/ffmpeg_encoder_plugin.dvcp.bundle/Contents/Linux-x86-64/
        cp ${ffmpeg-encoder-plugin}/ffmpeg_encoder_plugin.dvcp \
          $out/IOPlugins/ffmpeg_encoder_plugin.dvcp.bundle/Contents/Linux-x86-64/

        mkdir -p $out/lib $out/libexec
        cp ${davinci-aac-fix}/lib/aac_hybrid_shim.so $out/lib/aac_hybrid_shim.so
        cp ${davinci-aac-fix}/bin/resolve-codec-patch $out/libexec/resolve-codec-patch
        chmod +x $out/libexec/resolve-codec-patch
      '';

      postFixup = (prevAttrs.postFixup or "") + ''
        wrapProgram $out/bin/resolve \
          --unset SESSION_MANAGER \
          --set GTK_IM_MODULE "" \
          --set QT_IM_MODULE "" \
          --set XMODIFIERS "" \
          --set-default AAC_REDIRECT_CACHE_DIR "''${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac" \
          --set-default ALSA_PLUGIN_DIR "${pkgs.alsa-plugins}/lib/alsa-lib" \
          --prefix LD_LIBRARY_PATH : "${
            pkgs.lib.makeLibraryPath [
              pkgs.alsa-lib
              pkgs.alsa-plugins
            ]
          }" \
          --prefix LD_PRELOAD : "$out/lib/aac_hybrid_shim.so" \
          --prefix PATH : "$out/libexec:${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}"
      '';
    }
  );
in
replaceDependencies {
  drv = davinci-resolve-studio;
  replacements = [
    {
      oldDependency = nonFhsOriginalDavinci;
      newDependency = davinciPatched;
    }
  ];
}
