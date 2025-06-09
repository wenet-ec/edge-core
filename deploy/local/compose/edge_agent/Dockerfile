# deploy/local/compose/edge_agent/Dockerfile
FROM elixir:1.18.4-otp-26-alpine AS elixir-dev-stage

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install Alpine packages
RUN apk add --no-cache \
  # Core build tools
  build-base \
  git \
  ca-certificates \
  # PostgreSQL client and dev libraries
  postgresql-client \
  postgresql-dev \
  # Development utilities
  bash \
  bash-completion \
  nano \
  # Networking utilities
  netcat-openbsd \
  # Health checks and monitoring
  curl \
  # File system watching for live reload
  inotify-tools \
  # For any native dependencies
  pkgconfig \
  && rm -rf /var/cache/apk/*

# Create development user
RUN addgroup -g 1000 dev-user \
  && adduser -u 1000 -G dev-user -s /bin/bash -D dev-user

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