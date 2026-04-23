# nexmaker/Dockerfile
# Stage 1: Pull pre-built netclient (DERP fork) — built by wenet-ec/netclient CI
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient_builder

# Stage 2: Create Elixir test environment with netclient installed
FROM elixir:1.19-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    git \
    build-base \
    curl \
    wget \
    bash \
    libmnl \
    gcompat \
    openresolv \
    iproute2 \
    wireguard-tools \
    iptables \
    ip6tables \
    ca-certificates && \
    # Netclient checks init system type on startup — override /sbin/init with a no-op
    ln -sf /bin/true /sbin/init

# Copy netclient from builder stage
COPY --from=netclient_builder /netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

# Use HTTP for Netmaker API (local testing — no TLS certs)
ENV NETMAKER_API_SCHEME=http

# Verify netclient is installed
RUN netclient version || echo "netclient installed"

# Copy Elixir project files
COPY mix.exs mix.lock* ./

# Install Elixir dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

# Copy source code and tests
COPY lib ./lib
COPY test ./test
COPY .formatter.exs ./

# Compile
RUN MIX_ENV=test mix compile

# Create netclient data directory
RUN mkdir -p /etc/netclient

CMD ["mix", "test", "--include", "integration"]
