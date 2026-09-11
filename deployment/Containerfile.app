# Find eligible builder and runner images on Docker Hub. We use Alpine
# for smaller image sizes and faster builds.
#
# https://hub.docker.com/r/hexpm/elixir
# https://hub.docker.com/_/alpine
# https://pkgs.alpinelinux.org/packages
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir - official Elixir images
#   - https://hub.docker.com/_/alpine - official Alpine Linux base image
#
# NOTE: Chromium runs in a separate container (see docker-compose.yml)

ARG BUILDER_IMAGE="hexpm/elixir:1.20.1-erlang-29.0.1-alpine-3.23.4@sha256:27d06bcda28874e29b32c75d97f2391428e947b2cbd4bcb54fc22a4d4679b19f"
ARG RUNNER_IMAGE="alpine:3.22@sha256:55ae5d250caebc548793f321534bc6a8ef1d116f334f18f4ada1b2daad3251b2"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apk add --no-cache build-base git nodejs npm

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
COPY assets assets
RUN npm ci --prefix assets

# Enable parallel compilation

# MAKEFLAGS: Parallel compilation for NIFs (native code like argon2_elixir)
# MIX_OS_DEPS_COMPILE_PARTITION_COUNT: Parallel compilation across dependencies

# Note: We calculate half of available cores inline in compilation commands

RUN export HALF_CORES=$(($(nproc) / 2)) && \
    export MAKEFLAGS="-j${HALF_CORES}" && \
    export MIX_OS_DEPS_COMPILE_PARTITION_COUNT="${HALF_CORES}" && \
    mix deps.compile

COPY priv priv

COPY lib lib

# Compile the app first (generates phoenix-colocated hooks needed by esbuild)
RUN mix compile

# Download configured locale data before assembling the release.
RUN mix localize.setup

# compile assets (must come after mix compile for phoenix-colocated hooks)
RUN mix assets.sentry.deploy
# Source maps are uploaded separately by CI and must not be shipped in the runtime image.
# This runs after digesting so the deployed JavaScript remains byte-identical to CI's artifact.
RUN npm run sentry:sourcemaps:clean --prefix assets

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix sentry.package_source_code
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# Install runtime dependencies
# Note: Chromium is NOT installed here - it runs in a separate container
RUN apk add --no-cache \
  openssl \
  ncurses-libs \
  ca-certificates \
  vips \
  curl \
  qpdf \
  libxslt

# Set the locale (Alpine handles locales differently than Debian)
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/firmowid ./

USER nobody

# Health check to ensure the application is responding
# Uses the /health endpoint which checks database, Oban, and connection pool
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=9s \
  CMD curl --fail --silent --show-error http://127.0.0.1:4000/health || exit 1

CMD ["/app/bin/server"]
