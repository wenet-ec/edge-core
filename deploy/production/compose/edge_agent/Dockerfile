# deploy/production/compose/edge_agent/Dockerfile

# Stage 0a: Pull pre-built netclient (DERP fork)
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Stage 0b: Pull pre-built node_exporter
FROM quay.io/prometheus/node-exporter:v1.11.1 AS node-exporter-builder

# Stage 1: Build the OTP release
FROM elixir:1.19.5-otp-28-slim AS builder

# Install build dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y build-essential git sqlite3 libsqlite3-dev

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true

# Copy nexmaker (path dependency) so mix deps.get can resolve it and its transitive deps
COPY nexmaker /nexmaker

# Copy mix files and install all dependencies (including nexmaker's transitive deps) with caching
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

# Stage 2: Production runtime image
FROM debian:stable-20260421-slim

# Install runtime dependencies in single layer
# Agent leverages host tools via hostscript (nsenter/chroot to /host)
# So we only install what the AGENT itself needs, not what commands need
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
    # Erlang runtime dependencies
    libstdc++6 \
    openssl \
    libncurses6 \
    ca-certificates \
    # Essential tools (healthcheck, SSH server, capability checks)
    curl \
    libcap2-bin \
    # Process management (pgrep, pkill for netclient cleanup)
    procps \
    # Agent database (SQLite)
    sqlite3 \
    # Agent-specific: WireGuard management (VPN + wireguard_exporter)
    wireguard-tools \
    # Agent-specific: nsenter for hostscript (part of util-linux)
    util-linux \
    # systemd-resolved: provides resolvectl for netclient DNS management on systemd hosts
    systemd-resolved \
    # mDNS resolution: enables .local hostname resolution via nss-mdns
    libnss-mdns \
    # PID 1 zombie reaper for the BEAM
    tini \
    # IANA timezone database — required for timezone-aware Oban/Quantum schedules
    tzdata \
    # Operator debugging — agent is shell-friendly: operators SSH in to troubleshoot
    iproute2 \
    iputils-ping \
    iptables \
    dnsutils \
    netcat-openbsd \
    bash-completion \
    vim-tiny \
    less \
    jq && \
    # Enable mDNS resolution in nsswitch.conf
    sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf && \
    # Create dummies to suppress netclient init system detection errors
    # Netclient checks init type for service installation, not needed in containers
    mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox

# Copy netclient binary from builder stage
COPY --from=netclient-builder /netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go

# Set locale environment variables (C.UTF-8 is built into glibc — no locales pkg needed)
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Disable automatic distribution startup — agent starts it dynamically after detecting LAN IP
ENV RELEASE_DISTRIBUTION=none

# Keep epmd in the 40k port range to avoid colliding with user-deployed Erlang/Elixir apps
ENV ERL_EPMD_PORT=44369

# Copy node_exporter binary from official Docker image
COPY --from=node-exporter-builder /bin/node_exporter /usr/local/bin/node_exporter
RUN chmod +x /usr/local/bin/node_exporter

# Copy wireguard_exporter binary from official Docker image
COPY --from=mindflavor/prometheus-wireguard-exporter:3.6.6 /usr/local/bin/prometheus_wireguard_exporter /usr/local/bin/prometheus_wireguard_exporter
RUN chmod +x /usr/local/bin/prometheus_wireguard_exporter

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_agent /app
RUN chmod +x /app/bin/migrate /app/bin/server

# License text for the embedded Edge Agent + Nexmaker code. Apache 2.0 — see
# /usr/share/doc/edge_agent/LICENSE and /usr/share/doc/nexmaker/LICENSE.
COPY edge_agent/LICENSE /usr/share/doc/edge_agent/LICENSE
COPY nexmaker/LICENSE /usr/share/doc/nexmaker/LICENSE

# Create unified data directory structure with symlink for netclient
RUN mkdir -p /app/data/edge /app/data/vpn /tmp/erl_crash && \
    ln -sfn /app/data/vpn /etc/netclient && \
    chmod -R 755 /app/data /tmp/erl_crash

# Copy entrypoint and utility scripts
COPY ./deploy/production/compose/edge_agent/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

COPY ./deploy/production/compose/edge_agent/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

# hostscript: nsenter/chroot to execute commands on host
# This is how agent leverages host tools instead of bundling them
COPY ./deploy/production/compose/edge_agent/hostscript /usr/local/bin/hostscript
RUN sed -i 's/\r$//g' /usr/local/bin/hostscript && \
    chmod +x /usr/local/bin/hostscript

COPY ./deploy/production/compose/edge_agent/edge_bashrc /usr/local/bin/edge_bashrc
RUN sed -i 's/\r$//g' /usr/local/bin/edge_bashrc && \
    chmod +r /usr/local/bin/edge_bashrc

WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/entrypoint"]

CMD ["/start"]
