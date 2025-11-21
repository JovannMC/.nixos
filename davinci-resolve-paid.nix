{
  hexdump,
  replaceDependencies,
  system ? "x86_64-linux",
  ...
}:
let
  oldNixpkgs =
    import
      (builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/2a574fe34c894ef2a343ee006f4228f4e006e5b9.tar.gz";
        sha256 = "1ipqwcpi3s6p0vh5yw7v4127c6774iwwlq6ig1xm9ycmaz5dx8vm";
      })
      {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };

  oldDavinciResolveStudio = oldNixpkgs.davinci-resolve-studio;
  nonFhsOriginalDavici = oldDavinciResolveStudio.passthru.davinci;

  davinciPatched = nonFhsOriginalDavici.overrideAttrs (
    finalAttrs: prevAttrs: {
      # https://stackoverflow.com/a/17168777
      preFixup = ''
        pattern="\x55\x41\x57\x41\x56\x53\x48\x83\xec.\x49\x89\xfe\xc7\x47\x34\xff\xff\xff\xff\x85\xf6\x0f\x84....\x89\xf5\x81\xfe\x13\xfc\xff\xff\x0f\x85"
        offset=23
        file="$out/bin/resolve"
        matches=$(LANG=C grep -obUaP "$pattern" "$file")
        matchcount=$(echo "$matches" | wc -l)
        if [[ -z $matches ]]; then echo "pattern not found";
          elif [[ $matchcount -ne 1 ]]; then echo "pattern returned $matchcount matches instead of 1";
        else
          patternOffset=$(echo $matches | cut -d: -f1)
          instructionOffset=$(($patternOffset + $offset))
          echo "patching byte '0x$(${hexdump}/bin/hexdump -s $instructionOffset -n 1 -e '/1 "%02x"' "$file")' at offset $instructionOffset"
          echo -en "\x85" | dd conv=notrunc of="$file" bs=1 seek=$instructionOffset count=1;
        fi
      '';
    }
  );
in
replaceDependencies {
  drv = oldDavinciResolveStudio;
  replacements = [
    {
      oldDependency = nonFhsOriginalDavici;
      newDependency = davinciPatched;
    }
  ];
}
