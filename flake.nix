{
  description = "RelicOS build environment (FHS, for Buildroot on NixOS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Buildroot requires a real FHS hierarchy (/usr/bin/file, bash at
      # /bin/sh, interpreters in /lib). A plain mkShell cannot provide that
      # on NixOS; buildFHSEnv mounts a namespace that can.
      fhs = pkgs.buildFHSEnv {
        name = "relicos-build";
        targetPkgs = pkgs: with pkgs; [
          # Buildroot mandatory host dependencies
          gcc gnumake binutils bc bison flex perl python3
          wget cpio unzip rsync file which git patch
          gawk gnused gnugrep gnutar gzip bzip2 xz
          diffutils findutils coreutils bash util-linux
          # menuconfig
          ncurses
          # serial console capture on the device
          tio
        ];
      };
    in {
      # `nix develop` drops into the FHS shell interactively.
      devShells.${system}.default = fhs.env;
      # `nix run . -- -c "<cmd>"` runs one command inside the same FHS
      # environment — useful for scripted/non-interactive builds.
      packages.${system}.default = fhs;
    };
}
