# deploy/production/compose/edge_agent/Dockerfile
# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.18.4-otp-27-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    sqlite-dev \
    ca-certificates \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# First, build the tailscale library
WORKDIR /tailscale
COPY tailscale/mix.exs tailscale/mix.lock ./
RUN mix deps.get --only $MIX_ENV
COPY tailscale/lib lib/
RUN mix deps.compile && mix compile

# Then build the main application
WORKDIR /app

# Copy mix files and install dependencies
COPY edge_agent/mix.exs edge_agent/mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
COPY edge_agent/config config/
RUN mix deps.compile

# Copy source code and compile
COPY edge_agent/lib lib/
COPY edge_agent/priv priv/
COPY edge_agent/rel rel/
RUN mix compile

# Create release
RUN mix release

# -----------------------------------------------
# Stage: Production runtime image
# -----------------------------------------------
FROM alpine:3.22.0

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    sqlite \
    bash \
    curl \
    wget \
    tailscale \
    libstdc++ \
    libgcc \
    su-exec \
    util-linux \
    && rm -rf /var/cache/apk/*

# Install node_exporter for metrics collection
ENV NODE_EXPORTER_VERSION="1.9.1"
RUN wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
    && tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
    && mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ \
    && rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64* \
    && chmod +x /usr/local/bin/node_exporter

RUN mkdir -p /app/data /var/run/tailscale /var/lib/tailscale /var/cache/tailscale

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_agent /app

RUN chmod +x /app/bin/migrate /app/bin/server

# Copy entrypoint script
COPY ./deploy/production/compose/edge_agent/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

# Copy hostscript utility
COPY ./deploy/production/compose/edge_agent/hostscript /usr/local/bin/hostscript
RUN sed -i 's/\r$//g' /usr/local/bin/hostscript && \
    chmod +x /usr/local/bin/hostscript

COPY ./deploy/production/compose/edge_agent/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

COPY ./deploy/production/compose/edge_agent/start-dev /start-dev
RUN sed -i 's/\r$//g' /start-dev && \
    chmod +x /start-dev

WORKDIR /app

ENTRYPOINT ["/entrypoint"]
