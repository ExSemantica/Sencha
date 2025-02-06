ARG MIX_ENV="prod" # The Mix environment to build, probably should be "prod"

ARG USE_ERLANG="27.2.2" # The Erlang/OTP version to use
ARG USE_ELIXIR="1.18.2" # The Elixir version to use
ARG USE_ALPINE="3.21.2" # The Alpine Linux OS version to use

# === BUILDER =================================================================
FROM hexpm/elixir:${USE_ELIXIR}-erlang-${USE_ERLANG}-alpine-${USE_ALPINE} as build

# Install build dependencies
RUN apk add --no-cache build-base git python3 curl

# Set work directory
WORKDIR /app

# Export Mix environment (dev, prod, test)
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

# Copy Mix dependency data then pull them in
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Make configuration directory then copy the configurations
RUN mkdir config
COPY config/config.exs config/$MIX_ENV.exs config/

# Copy needed migrations
RUN mkdir priv
COPY priv/repo priv/repo

# Compile dependencies
RUN mix deps.compile

# Copy main application data then compile it
COPY lib lib
RUN mix compile

# Copy the runtime configuration and create an OTP release
COPY config/runtime.exs config/
RUN mix release

# === RUNNER ==================================================================
FROM alpine:$USE_ALPINE as deploy

# Export Mix environment (dev, prod, test)
ARG MIX_ENV

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Create a sandbox user
ENV USER="sencha"
WORKDIR "/home/${USER}/deploy"
RUN addgroup -g 1000 -S "${USER}" && \
    adduser -s /bin/sh -u 1000 -G "${USER}" -h "/home/${USER}" -D "${USER}" && \
    su "${USER}"

# Drop into that sandbox user
USER "${USER}"

# Copy the previously built release
COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/sencha ./

# Drop into the release
ENTRYPOINT ["bin/sencha"]
CMD ["start"]
