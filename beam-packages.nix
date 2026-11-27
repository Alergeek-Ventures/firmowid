# The pinned nixpkgs ships Erlang/OTP 29.1.2, without the 29.1.3 security fixes
# (binary_to_term crashes and six other CVEs). Elixir is rebuilt on it; CI requires
# .tool-versions and the Containerfile.app builder image to pin the same release.
# https://github.com/erlang/otp/releases/tag/OTP-29.1.3
{ pkgs }:

pkgs.beam29Packages.overrideScope (
  _: prev: {
    erlang = prev.erlang.overrideAttrs (
      finalAttrs: _: {
        version = "29.1.3";
        src = pkgs.fetchFromGitHub {
          owner = "erlang";
          repo = "otp";
          tag = "OTP-${finalAttrs.version}";
          hash = "sha256-4iE84PlRkdVoZVNBOmGc+/kNINGipY4TEyGqJ4PiIFc=";
        };
      }
    );
  }
)
