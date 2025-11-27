# deploy/production/compose/edge_agent/Dockerfile
# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.19.2-otp-28-alpine AS builder

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
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true

# First, build the nexmaker library with caching
WORKDIR /nexmaker
COPY nexmaker/mix.exs nexmaker/mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV
COPY nexmaker/lib lib/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile --parallel && mix compile --parallel

# Then build the main application
WORKDIR /app

# Copy mix files and install dependencies with caching
COPY edge_agent/mix.exs edge_agent/mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
COPY edge_agent/config config/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile --parallel

# Copy source code and compile
COPY edge_agent/lib lib/
COPY edge_agent/priv priv/
COPY edge_agent/rel rel/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix compile --parallel

# Create release
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

# -----------------------------------------------
# Stage: Production runtime image (optimized)
# -----------------------------------------------
FROM alpine:3.22.0

# Install runtime dependencies and node_exporter in single layer
ENV NODE_EXPORTER_VERSION="1.10.2"
ENV NETCLIENT_VERSION="1.2.0"

RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    sqlite \
    bash \
    curl \
    wget \
    libstdc++ \
    libgcc \
    su-exec \
    util-linux && \
    # Install node_exporter in same layer to reduce image size
    wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && \
    chmod +x /usr/local/bin/node_exporter && \
    # Install netclient in same layer to reduce image size
    wget -qO /tmp/netclient https://github.com/gravitl/netclient/releases/download/v${NETCLIENT_VERSION}/netclient-linux-amd64 && \
    mv /tmp/netclient /usr/local/bin/netclient && \
    chmod +x /usr/local/bin/netclient && \
    mkdir -p /app/data /etc/netclient && \
    # Clean up in same layer to reduce image size
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64* /var/cache/apk/* /tmp/* /var/tmp/*

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

WORKDIR /app

ENTRYPOINT ["/entrypoint"]
