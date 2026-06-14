# deploy/local/compose/edge_agent/Dockerfile

# Stage 0a: Pull pre-built netclient (DERP fork)
# The fork's CI publishes a new image on every v*-derp tag push.
ARG NETCLIENT_VERSION=v1.6.0-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Stage 0b: Pull pre-built node_exporter
FROM quay.io/prometheus/node-exporter:v1.11.1 AS node-exporter-builder

# Debug alternative: build from source in-Dockerfile. Uncomment this block (and
# comment out the two lines above) when iterating on the netclient fork locally,
# so you don't need a tag push + CI round-trip per fix. Pair with --no-cache:
#   docker compose -f deploy/local/edge.yml build --no-cache edge_agent
#
# ARG NETCLIENT_VERSION=v1.6.0-derp
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

# Install packages in single layer. The agent is a gateway: every operator
# command runs on the host via nsenter, so this image only needs what the
# agent process and netclient themselves use, plus dev tooling on local.
RUN apt-get update && apt-get install --no-install-recommends -y \
  # --- BEAM runtime ---
  libstdc++6 \
  openssl \
  libncurses6 \
  locales \
  ca-certificates \
  tini \
  # --- Agent runtime ---
  # SQLite — agent's local store
  sqlite3 \
  # procps — pgrep/pkill used by /start netclient cleanup
  procps \
  # libcap2-bin — getcap/setcap, agent inspects its own capabilities
  libcap2-bin \
  # curl — kept for ad-hoc container-side HTTP probing; no runtime code path
  # uses it directly today (the agent uses Req).
  curl \
  # util-linux — nsenter for hostscript; setns(2) for host_pty_spawn via libc
  util-linux \
  # libnss-mdns — .local hostname resolution from inside the container
  libnss-mdns \
  # --- netclient runtime ---
  # wireguard-tools: wg + wg-quick (WG interface bring-up)
  wireguard-tools \
  # systemd-resolved: provides resolvectl + systemctl, used by netclient to
  # detect and configure systemd-resolved on systemd hosts
  systemd-resolved \
  # iproute2: `ip` — netclient's interface management fallback (no-wg-quick
  # path and the migrate-old-interface path)
  iproute2 \
  # iptables: iptables/ip6tables — netclient's iptables firewall backend
  # shells out via the go-iptables library. The nftables backend uses
  # netlink directly and does NOT need the `nft` binary, but iptables
  # backend does need iptables binaries. netclient prefers iptables when
  # present, so install it to converge on a working backend (and to match
  # prod, which also picks iptables).
  iptables \
  # --- Dev workflow (local only) ---
  # build-essential + git — compile Elixir deps from source (erlexec's C++
  # port, host_pty_spawn helper, sqlite NIF) and fetch git deps
  build-essential \
  git \
  libsqlite3-dev \
  # inotify-tools — Phoenix live-reload file watcher
  inotify-tools \
  # --- Ad-hoc container-side debug probes ---
  # Operator-facing tools (less, vim, nano, bash-completion) are deliberately
  # NOT installed — the SSH shell is the host's, not the container's. Only
  # ad-hoc container-internal probes are kept here, for the rare case of
  # `docker exec local_edge_agent <cmd>` to debug the agent itself.
  jq \
  iputils-ping \
  dnsutils \
  netcat-openbsd && \
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

# erlexec's port program refuses to start unless USER and SHELL are set in
# the environment, even when running as root. Container runtimes don't set
# these by default. The values here just need to be non-empty + match the
# erlexec config (root: true, user: "root").
ENV USER=root
ENV SHELL=/bin/bash

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

# host_pty_spawn: C helper that allocates a PTY in the host's mount namespace
# so the SSH `:shell` channel runs bash on the host. See the source for the why.
COPY ./deploy/local/compose/edge_agent/host_pty_spawn.c /tmp/host_pty_spawn.c
RUN gcc -O2 -Wall -Wextra -o /usr/local/bin/host_pty_spawn /tmp/host_pty_spawn.c -lutil && \
    rm /tmp/host_pty_spawn.c && \
    chmod +x /usr/local/bin/host_pty_spawn

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/entrypoint"]

CMD ["/start"]
