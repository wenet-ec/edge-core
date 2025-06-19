# deploy/local/compose/edge_agent/Dockerfile
FROM elixir:1.18.4-otp-26-alpine

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install only absolute essentials for the edge agent itself
RUN apk add --no-cache \
  # Core build tools (required for Elixir/Erlang native dependencies)
  build-base \
  git \
  ca-certificates \
  # Agent database
  sqlite \
  # Agent shell and basic utilities
  bash \
  bash-completion \
  nano \
  # Agent networking (for VPN and API calls)
  curl \
  # File system watching for live reload (development only)
  inotify-tools \
  # For any native dependencies
  pkgconfig \
  && rm -rf /var/cache/apk/*

# Install Tailscale (VPN client)
RUN apk add --no-cache tailscale && \
    mkdir -p /var/run/tailscale

# Create app user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/bash -D app && \
    mkdir -p /app/data && \
    chown -R app:app /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy entrypoint and utility scripts
COPY ./deploy/local/compose/edge_agent/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

COPY ./deploy/local/compose/edge_agent/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

COPY ./deploy/local/compose/edge_agent/migrate /migrate
RUN sed -i 's/\r$//g' /migrate && \
    chmod +x /migrate

COPY ./deploy/local/compose/edge_agent/hostscript /usr/local/bin/hostscript
RUN sed -i 's/\r$//g' /usr/local/bin/hostscript && \
    chmod +x /usr/local/bin/hostscript

# Copy ONLY dependency files first (for Docker layer caching)
COPY edge_agent/mix.exs edge_agent/mix.lock ./

# Copy config files (needed for dependency compilation)
COPY edge_agent/config ./config

# Install and compile dependencies (this layer will be cached!)
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=deps \
    --mount=type=cache,target=_build \
    mix deps.compile

ENTRYPOINT ["/entrypoint"]