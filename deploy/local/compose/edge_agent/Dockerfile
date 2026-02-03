# deploy/local/compose/edge_agent/Dockerfile

# Build netclient with HTTP patches (for local development)
FROM golang:1.25-alpine AS netclient-builder

ARG NETCLIENT_VERSION=v1.4.0

RUN apk add --no-cache git

WORKDIR /build
RUN git clone https://github.com/gravitl/netclient.git . && \
    git checkout ${NETCLIENT_VERSION}

# Patch ONLY API-related https:// to http:// (surgical patches for local dev)
RUN find . -type f -name '*.go' -exec sed -i \
    -e 's|"https://" + server\.API|"http://" + server.API|g' \
    -e 's|"https://" + serverData\.Server|"http://" + serverData.Server|g' \
    -e 's|"https://" + api|"http://" + api|g' \
    -e 's|fmt\.Sprintf("https://%s/|fmt.Sprintf("http://%s/|g' \
    {} \;

RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o netclient .

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
  wget \
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
  systemd-resolved && \
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
RUN wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz && \
    mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ && \
    chmod +x /usr/local/bin/node_exporter && \
    rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*

# Copy patched netclient binary from builder stage
COPY --from=netclient-builder /build/netclient /usr/local/bin/netclient
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
