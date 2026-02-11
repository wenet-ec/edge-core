# deploy/production/compose/edge_admin/Dockerfile

# -----------------------------------------------
# Stage 0: Build netclient with DERP support
# -----------------------------------------------
FROM golang:1.25-bookworm AS netclient-builder

ARG NETCLIENT_REPO=https://github.com/wenet-ec/netclient.git
ARG NETCLIENT_VERSION=v1.4.0-derp

WORKDIR /build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${NETCLIENT_VERSION} ${NETCLIENT_REPO} .
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o netclient -ldflags="-s -w" .

# -----------------------------------------------
# Stage 1: Build the OTP release
# -----------------------------------------------
FROM elixir:1.19.5-otp-28-slim AS builder

# Install build dependencies
RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

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
COPY edge_admin/mix.exs edge_admin/mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
COPY edge_admin/config config/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile --parallel

# Copy source code and compile
COPY edge_admin/lib lib/
COPY edge_admin/priv priv/
COPY edge_admin/rel rel/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix compile --parallel

# Create release
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

# -----------------------------------------------
# Stage 2: Production runtime image (optimized)
# -----------------------------------------------
FROM debian:stable-20250520-slim

# Install runtime dependencies in single layer
# Grouped by purpose for maintainability
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    # Erlang runtime dependencies
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    # Essential tools (healthcheck, troubleshooting, netclient download, capability checks)
    curl \
    wget \
    libcap2-bin \
    procps \
    # Network debugging (minimal set for production troubleshooting)
    iproute2 \
    iputils-ping \
    iptables \
    # WireGuard management (wg show, wg showconf)
    wireguard-tools \
    # Proxy troubleshooting
    netcat-openbsd && \
    # Set locale in same layer
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
    # Create dummies to suppress netclient init system detection errors
    # Netclient checks init type for service installation, not needed in containers
    mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox && \
    # Clean up in same layer to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Erlang distribution settings
# Admins always use dynamic clustering (started after VPN join)
ENV RELEASE_DISTRIBUTION=none

# Copy netclient built from source
COPY --from=netclient-builder /build/netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient && \
    mkdir -p /etc/netclient && \
    chmod 0775 /etc/netclient

# Create app user (non-root)
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

# Copy the entrypoint and start scripts
COPY ./deploy/production/compose/edge_admin/entrypoint /entrypoint
COPY ./deploy/production/compose/edge_admin/start /start
RUN sed -i 's/\r$//g' /entrypoint /start && \
    chmod +x /entrypoint /start

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_admin /app
RUN chmod +x /app/bin/migrate /app/bin/server /app/bin/create_netmaker_superadmin /app/bin/create_default_cluster && \
    chown -R app:app /app

# Create directories with proper permissions
RUN mkdir -p /app/data /tmp/erl_crash && \
    chown -R app:app /app/data /tmp/erl_crash

# Switch to app user for security
# NOTE: Will run as root at runtime due to NET_ADMIN capability requirements
# But the release files are owned by app user
WORKDIR /app

ENTRYPOINT ["/entrypoint"]

CMD ["/start"]
