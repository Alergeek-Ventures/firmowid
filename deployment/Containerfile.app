# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE="hexpm/elixir:1.20.4-erlang-29.1.1-alpine-3.23.6@sha256:21271f75be4cbc2d893611f3a04ab19e8399c81baf6595c21fcbdd9e9950b6c0"
ARG RUNNER_IMAGE="alpine:3.22@sha256:55ae5d250caebc548793f321534bc6a8ef1d116f334f18f4ada1b2daad3251b2"

FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

# Keep in sync with hex-version in devenv.nix (checked by version-sync-check.yml).
ARG HEX_VERSION="2.5.3"

RUN mix local.hex "${HEX_VERSION}" --force && \
  mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/

# Keep expensive dependency compilation independent of npm and asset changes.
RUN export HALF_CORES=$(($(nproc) / 2)) && \
    export MAKEFLAGS="-j${HALF_CORES}" && \
    export MIX_OS_DEPS_COMPILE_PARTITION_COUNT="${HALF_CORES}" && \
    mix deps.compile

COPY assets/package.json assets/package-lock.json assets/
COPY assets/.npmrc assets/.npmrc
RUN npm ci --prefix assets
RUN npm install --global accent-cli@0.19.0

COPY priv priv

COPY lib lib
COPY accent.json ./accent.json
COPY scripts/accent.exs scripts/accent.exs

ARG SOURCE_COMMIT
ARG ACCENT_API_KEY
RUN test -s priv/gettext/pl/LC_MESSAGES/default.po || elixir scripts/accent.exs export --version "$SOURCE_COMMIT"

# Dependencies compile before fetching translations; app compile follows the fetch.
RUN mix compile

RUN mix localize.setup

# Copy source assets late so JS/CSS changes preserve BEAM compilation layers.
COPY assets assets
RUN mix assets.sentry.deploy
# Keep CI-uploaded source maps out of the runtime image after asset digesting.
RUN npm run sentry:sourcemaps:clean --prefix assets

COPY config/runtime.exs config/

COPY rel rel
RUN mix sentry.package_source_code
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apk add --no-cache \
  openssl \
  ncurses-libs \
  ca-certificates \
  vips \
  curl \
  qpdf \
  libxslt

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/firmowid ./

USER nobody

# The health endpoint checks database, Oban, and the connection pool.
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=9s \
  CMD curl --fail --silent --show-error http://127.0.0.1:4000/health || exit 1

CMD ["/app/bin/server"]
