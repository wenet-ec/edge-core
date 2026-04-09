# deploy/local/compose/edge_agent/Dockerfile

# Pull pre-built netclient (DERP fork) — built by wenet-ec/netclient CI
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Main Elixir stage - Use Debian slim (better Elixir/Erlang compatibility than Alpine)
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
  libnss-mdns && \
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

# Install node_exporter for host metrics collection
ENV NODE_EXPORTER_VERSION="1.10.2"
RUN curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz -o node_exporter.tar.gz && \
    tar xzf node_exporter.tar.gz && \
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && \
    chmod +x /usr/local/bin/node_exporter && \
    rm -rf node_exporter.tar.gz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

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

RUN mix deps.get --only hex rebar || true

ENTRYPOINT ["/entrypoint"]

CMD ["/start"]
