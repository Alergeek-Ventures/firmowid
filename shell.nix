{
  pkgs ? import <nixpkgs> {},
  withPodman ? true,
}: let
  linuxOnlyInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
    pkgs.inotify-tools # hot reload in elixir
  ];
  podmanInputs = pkgs.lib.optionals withPodman [
    pkgs.podman
    pkgs.podman-compose
  ];
in
  pkgs.mkShell {
    buildInputs =
      (with pkgs; [
        nodejs_26
        beam29Packages.elixir_1_20
        infisical
        worktrunk

        # for dev.up
        openssl
        postgresql
        tmux

        # for oxc
        oxfmt
        oxlint
        tsgolint
      ])
      ++ linuxOnlyInputs ++ podmanInputs;
  }
