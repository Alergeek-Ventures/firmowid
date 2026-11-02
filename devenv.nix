{ pkgs, config, ... }:

let
  # Owner of the Hex version; version-sync-check.yml keeps CI and Containerfile.app in sync.
  hex-version = "2.5.3";

  # Security-only overrides keep the remaining nixpkgs packages on the 7-day cooldown.
  # https://github.com/elixir-lang/elixir/releases/tag/v1.20.5
  elixir = pkgs.beam29Packages.elixir_1_20.overrideAttrs {
    version = "1.20.5";
    src = pkgs.fetchFromGitHub {
      owner = "elixir-lang";
      repo = "elixir";
      rev = "v1.20.5";
      hash = "sha256-MsRNaWAQ05ysL3hOqpfhm//tRNL0Z4Ia/NfEWEQfEWE=";
    };
  };

  # https://github.com/pnpm/pnpm/releases/tag/v11.28.9 (GHSA-xjj6-f33q-929c).
  pnpm = pkgs.pnpm_11.override {
    version = "11.28.9";
    hash = "sha256-5UsH5WNLe/Q1IVPgyMJbzvKTCinj0b3EKp6vL/1ENt8=";
    nodejs-slim = pkgs.nodejs-slim_26;
  };

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
  # https://github.com/openai/tunnel-client/releases/download/v0.0.18/SHA256SUMS.txt
  tunnel-client-platforms = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-PIIwcxas2TyIo4S2KvHYHT9MsO+pdfnAv675IoZqBMQ=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-pfPXDvx19eZqtcZ8RNJyqoCyc2+T+HXxZRQFF3UOwDU=";
    };
  };
  tunnel-client-system = pkgs.stdenv.hostPlatform.system;
  tunnel-client-platform =
    assert pkgs.lib.assertMsg (builtins.hasAttr tunnel-client-system tunnel-client-platforms)
      "OpenAI tunnel-client 0.0.18 is pinned only for x86_64-linux and aarch64-linux; other platforms need separately verified official release archives.";
    tunnel-client-platforms.${tunnel-client-system};

  tunnel-client = pkgs.stdenvNoCC.mkDerivation {
    pname = "tunnel-client";
    version = "0.0.18";
    src = pkgs.fetchurl {
      url = "https://github.com/openai/tunnel-client/releases/download/v0.0.18/tunnel-client-v0.0.18-linux-${tunnel-client-platform.arch}.zip";
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
    pnpm
    accent-cli
    elixir
    beam29Packages.erlang
    infisical
    worktrunk
    betterleaks
    bash
    curl
    jq

    # Build and native-library dependencies used by the application and npm tools.
    gcc
    gnumake
    pkg-config
    vips
    qpdf
    libxslt
    cacert

    # For dev.up.
    openssl
    postgresql
    tmux

    # For oxc.
    oxfmt
    oxlint
    tsgolint

    podman
    podman-compose
  ]
  ++ lib.optionals stdenv.isLinux [
    tunnel-client
    glibcLocales
    # Linux-only file watching.
    inotify-tools
  ];

  # npm-distributed native binaries expect libstdc++ in the conventional location.
  env.LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];

  # A versioned archive directory installs the pinned Hex instead of using ~/.mix.
  env.MIX_ARCHIVES = "${config.devenv.state}/mix-archives/hex-${hex-version}";
  enterShell = ''
    mix local.hex ${hex-version} --force --if-missing
  '';

}
