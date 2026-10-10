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

  # Full official client archives, pinned to the release's SHA256SUMS.txt:
  # https://github.com/openai/tunnel-client/releases/download/v0.0.15/SHA256SUMS.txt
  tunnel-client-platforms = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-jINtxdaNaLZj2aXFso/5+ngNn3o//7HDBogLjzL6tfE=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-xRv9iD/CLjRFSUoDwBeYdRdlZL3kcGYbMI/YOvXQGrs=";
    };
  };
  tunnel-client-system = pkgs.stdenv.hostPlatform.system;
  tunnel-client-platform =
    assert pkgs.lib.assertMsg (builtins.hasAttr tunnel-client-system tunnel-client-platforms)
      "OpenAI tunnel-client 0.0.15 is pinned only for x86_64-linux and aarch64-linux; other platforms need separately verified official release archives.";
    tunnel-client-platforms.${tunnel-client-system};

  tunnel-client = pkgs.stdenvNoCC.mkDerivation {
    pname = "tunnel-client";
    version = "0.0.15";
    src = pkgs.fetchurl {
      url = "https://github.com/openai/tunnel-client/releases/download/v0.0.15/tunnel-client-v0.0.15-linux-${tunnel-client-platform.arch}.zip";
      inherit (tunnel-client-platform) hash;
    };
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    unpackPhase = ''
      runHook preUnpack
      unzip "$src"
      runHook postUnpack
    '';
    dontBuild = true;
    # Preserve the official static binaries rather than patching or stripping them.
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec/tunnel-client" "$out/bin"
      cp -r ./* "$out/libexec/tunnel-client/"
      chmod +x "$out/libexec/tunnel-client/tunnel-client" "$out/libexec/tunnel-client/cloudflared"
      ln -s "$out/libexec/tunnel-client/tunnel-client" "$out/bin/tunnel-client"
      runHook postInstall
    '';
    # Keep the matching companion and manifest adjacent, as upstream expects.
    # Only tunnel-client is on PATH; bundling does not enable Cloudflare or start a tunnel.
    meta = {
      description = "Official OpenAI Secure MCP Tunnel client";
      homepage = "https://github.com/openai/tunnel-client";
      license = pkgs.lib.licenses.asl20;
      platforms = builtins.attrNames tunnel-client-platforms;
      mainProgram = "tunnel-client";
    };
  };
in
{
  packages = with pkgs; [
    nodejs_26
    accent-cli
    tunnel-client
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
