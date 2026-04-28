# deploy/local/compose/edge_agent/Dockerfile

# Stage 0a: Pull pre-built netclient (DERP fork)
# The fork's CI publishes a new image on every v*-derp tag push.
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Stage 0b: Pull pre-built node_exporter
FROM quay.io/prometheus/node-exporter:v1.11.1 AS node-exporter-builder

# Debug alternative: build from source in-Dockerfile. Uncomment this block (and
# comment out the two lines above) when iterating on the netclient fork locally,
# so you don't need a tag push + CI round-trip per fix. Pair with --no-cache:
#   docker compose -f deploy/local/edge.yml build --no-cache edge_agent
#
# ARG NETCLIENT_VERSION=v1.5.1-derp
# FROM golang:1.26-bookworm AS netclient-builder
# ARG NETCLIENT_VERSION
# RUN apt-get update && apt-get install --no-install-recommends -y git ca-certificates && rm -rf /var/lib/apt/lists/*
# WORKDIR /build
# RUN git clone --depth 1 --branch "${NETCLIENT_VERSION}" https://github.com/wenet-ec/netclient.git . && \
#     echo "netclient cloned at $(git rev-parse HEAD)"
# RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /netclient -ldflags="-s -w" .

# Stage 1: Devcontainer (live reload, source bind-mounted at runtime)
FROM elixir:1.19.5-otp-28-slim AS elixir-dev-stage

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install packages in single layer
# Agent leverages host tools via hostscript (nsenter/chroot to /host)
# So we only install what the AGENT itself needs, not what commands need
RUN apt-get update && apt-get install --no-install-recommends -y \
  # Erlang runtime dependencies
  libstdc++6 \
  openssl \
  libncurses6 \
  locales \
  ca-certificates \
  # Build dependencies (dev only)
  build-essential \
  git \
  # Agent database (SQLite)
  sqlite3 \
  libsqlite3-dev \
  # Development utilities
  sudo \
  bash-completion \
  nano \
  # Essential tools (healthcheck, metrics, SSH server, capability checks)
  curl \
  iputils-ping \
  libcap2-bin \
  # Process management (pgrep, pkill for netclient cleanup)
  procps \
  # File system watching for live reload (dev only)
  inotify-tools \
  # Agent-specific: WireGuard management tools (for VPN and wireguard_exporter)
  wireguard-tools \
  # Agent-specific: nsenter for hostscript (part of util-linux)
  util-linux \
  # systemd-resolved: provides resolvectl for netclient DNS management on systemd hosts
  systemd-resolved \
  # mDNS resolution: enables .local hostname resolution via nss-mdns
  libnss-mdns \
  # PID 1 zombie reaper for the BEAM (matches production for parity)
  tini && \
  # Enable mDNS resolution in nsswitch.conf
  sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf && \
  # Set locale in same layer
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
  # Create dummies to suppress netclient init system detection errors
  # Netclient checks init type for service installation, not needed in containers
  mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox && \
  # Clean up in same layer
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
  rm -rf /var/lib/apt/lists/*

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Copy node_exporter binary from official Docker image
COPY --from=node-exporter-builder /bin/node_exporter /usr/local/bin/node_exporter
RUN chmod +x /usr/local/bin/node_exporter

# Use HTTP for Netmaker API (local dev — no TLS certs)
ENV NETMAKER_API_SCHEME=http

# Agent defaults to userspace WireGuard; override to unset for kernel mode on bare metal
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go

# Disable automatic distribution startup — agent starts it dynamically after detecting LAN IP
ENV RELEASE_DISTRIBUTION=none

# Keep epmd in the 40k port range to avoid colliding with user-deployed Erlang/Elixir apps
ENV ERL_EPMD_PORT=44369

# Copy netclient binary from builder stage
COPY --from=netclient-builder /netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

# Copy wireguard_exporter binary from official Docker image
COPY --from=mindflavor/prometheus-wireguard-exporter:3.6.6 /usr/local/bin/prometheus_wireguard_exporter /usr/local/bin/prometheus_wireguard_exporter
RUN chmod +x /usr/local/bin/prometheus_wireguard_exporter

# Create app user and unified data directory structure with symlink for netclient
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app && \
    mkdir -p /app/data/edge /app/data/vpn && \
    ln -sfn /app/data/vpn /etc/netclient && \
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

# hostscript: nsenter/chroot to execute commands on host
# This is how agent leverages host tools instead of bundling them
COPY ./deploy/local/compose/edge_agent/hostscript /usr/local/bin/hostscript
RUN sed -i 's/\r$//g' /usr/local/bin/hostscript && \
    chmod +x /usr/local/bin/hostscript

COPY ./deploy/local/compose/edge_agent/edge_bashrc /usr/local/bin/edge_bashrc
RUN sed -i 's/\r$//g' /usr/local/bin/edge_bashrc && \
    chmod +r /usr/local/bin/edge_bashrc

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/entrypoint"]

CMD ["/start"]
