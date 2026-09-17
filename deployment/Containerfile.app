# syntax=docker/dockerfile:1

ARG BUILDER_IMAGE="hexpm/elixir:1.20.4-erlang-29.0.6-alpine-3.23.5@sha256:534e1f77442a657c6886f81bba80010355249e31edf6b06750ecc56d21a3f38c"
ARG RUNNER_IMAGE="alpine:3.22@sha256:55ae5d250caebc548793f321534bc6a8ef1d116f334f18f4ada1b2daad3251b2"

FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

RUN mix local.hex --force && \
  mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
COPY assets assets
RUN npm ci --prefix assets
RUN npm install --global accent-cli@0.19.0

RUN export HALF_CORES=$(($(nproc) / 2)) && \
    export MAKEFLAGS="-j${HALF_CORES}" && \
    export MIX_OS_DEPS_COMPILE_PARTITION_COUNT="${HALF_CORES}" && \
    mix deps.compile

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
