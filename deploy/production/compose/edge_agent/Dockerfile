# deploy/production/compose/edge_agent/Dockerfile

# Stage 0a: Pull pre-built netclient (DERP fork)
ARG NETCLIENT_VERSION=v1.6.0-derp
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

ENV MIX_ENV=prod
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true

# Relocate Mix's home to a normal image path so hex/rebar archives survive across
# RUN steps. The default /root/.mix gets overlaid by the cache mount below,
# which would otherwise hide a pre-install and make every subsequent mix step
# prompt for hex.
ENV MIX_HOME=/opt/mix
RUN mix local.hex --force && mix local.rebar --force

# Copy nexmaker (path dependency) so mix deps.get can resolve it and its transitive deps
COPY nexmaker /nexmaker

# Copy mix files and install all dependencies (including nexmaker's transitive deps) with caching.
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

# host_pty_spawn: C helper that allocates a PTY in the host's mount namespace
# so the SSH `:shell` channel runs bash on the host. See the source for the why.
# Compiled here in the builder so the runtime image stays toolchain-free.
COPY deploy/production/compose/edge_agent/host_pty_spawn.c /tmp/host_pty_spawn.c
RUN gcc -O2 -Wall -Wextra -o /usr/local/bin/host_pty_spawn /tmp/host_pty_spawn.c -lutil && \
    rm /tmp/host_pty_spawn.c

# Stage 2: Production runtime image
FROM debian:stable-20260623-slim

# Install runtime dependencies in single layer. The agent is a gateway:
# every operator command runs on the host via nsenter, so this image only
# needs what the agent process and netclient themselves use.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
    # --- BEAM runtime ---
    libstdc++6 \
    openssl \
    libncurses6 \
    ca-certificates \
    tini \
    tzdata \
    # --- Agent runtime ---
    # SQLite — agent's local store
    sqlite3 \
    # procps — pgrep/pkill used by /start netclient cleanup
    procps \
    # libcap2-bin — getcap/setcap, agent inspects its own capabilities
    libcap2-bin \
    # curl — kept for ad-hoc container-side HTTP probing; no runtime code
    # path uses it directly today (the agent uses Req).
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
    # present, so install it to converge on a working backend.
    iptables \
    # --- Ad-hoc container-side debug probes ---
    # Operator-facing tools (less, vim, nano, bash-completion) are deliberately
    # NOT installed — the SSH shell is the host's, not the container's. Only
    # ad-hoc container-internal probes are kept here, for the rare case of
    # `docker exec production_edge_agent <cmd>` to debug the agent itself.
    jq \
    iputils-ping \
    dnsutils \
    netcat-openbsd && \
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

# erlexec's port program refuses to start unless USER and SHELL are set in
# the environment, even when running as root. Container runtimes don't set
# these by default. The values here just need to be non-empty + match the
# erlexec config (root: true, user: "root").
ENV USER=root
ENV SHELL=/bin/bash

# Copy node_exporter binary from official Docker image
COPY --from=node-exporter-builder /bin/node_exporter /usr/local/bin/node_exporter
RUN chmod +x /usr/local/bin/node_exporter

# Copy wireguard_exporter binary from official Docker image
COPY --from=mindflavor/prometheus-wireguard-exporter:3.6.6 /usr/local/bin/prometheus_wireguard_exporter /usr/local/bin/prometheus_wireguard_exporter
RUN chmod +x /usr/local/bin/prometheus_wireguard_exporter

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_agent /app
RUN chmod +x /app/bin/migrate /app/bin/server

COPY --from=builder /usr/local/bin/host_pty_spawn /usr/local/bin/host_pty_spawn
RUN chmod +x /usr/local/bin/host_pty_spawn

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

WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/entrypoint"]

CMD ["/start"]
