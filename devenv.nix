{ pkgs, ... }:

let
  accent-cli-src = pkgs.fetchgit {
    url = "https://github.com/mirego/accent.git";
    rev = "43872af8578df4121e39ea17c679b5eebb08f3f4";
    hash = "sha256-rRT9GalXELsrU3S3bZyggkL5xwZ27JjE8bgmyj3THjU=";
    sparseCheckout = [ "cli" ];
  };

  accent-cli = pkgs.buildNpmPackage {
    pname = "accent-cli";
    version = "0.19.0";
    src = accent-cli-src;
    sourceRoot = "${accent-cli-src.name}/cli";
    npmDepsHash = "sha256-32Z41J4yR2/196DzNy0JDr6X5h883l4SKMGxRgh6htA=";
    npmBuildScript = "build";
    nodejs = pkgs.nodejs_26;
  };
in
{
  packages = with pkgs; [
    nodejs_26
    accent-cli
    beam29Packages.elixir_1_20
    beam29Packages.erlang
    infisical
    worktrunk
    bash
    curl
    jq

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
