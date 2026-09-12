{ pkgs, ... }:

{
  packages = with pkgs; [
    nodejs_26
    beam29Packages.elixir_1_20
    beam29Packages.erlang
    infisical
    worktrunk

    # Build and native-library dependencies used by the application and npm tools.
    gcc
    gnumake
    pkg-config
    vips
    qpdf
    cacert
    glibcLocales

    # For dev.up.
    openssl
    postgresql
    tmux

    # For oxc.
    oxfmt
    oxlint
    tsgolint

    # Linux-only file watching and local containers.
    inotify-tools
    podman
    podman-compose
  ];

  # npm-distributed native binaries expect libstdc++ in the conventional location.
  env.LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
}
