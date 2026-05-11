# deploy/production/compose/edge_admin/Dockerfile

# Stage 0a: Pull pre-built netclient (DERP fork)
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Stage 1: Build the OTP release
FROM elixir:1.19.5-otp-28-slim AS builder

# Install build dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y build-essential cmake git

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true
# Skip emqtt's optional QUIC NIF — our MQTT adapter uses TCP/TLS only, so the
# `quicer` build (compiles Microsoft's msquic from source) is pure overhead.
ENV BUILD_WITHOUT_QUIC=1

# Copy nexmaker (path dependency) so mix deps.get can resolve it and its transitive deps
COPY nexmaker /nexmaker

# Copy mix files and install all dependencies (including nexmaker's transitive deps) with caching
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

# Package source code for Sentry so production stack traces include source context
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix sentry.package_source_code

# Create release
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

# Stage 2: Production runtime image
FROM debian:stable-20260505-slim

# Install runtime dependencies in single layer
# Grouped by purpose for maintainability
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
    # Essential tools (healthcheck, troubleshooting, netclient download, capability checks)
    curl \
    libcap2-bin \
    procps \
    # Network debugging (minimal set for production troubleshooting)
    iproute2 \
    iptables \
    # WireGuard management (wg show, wg showconf)
    wireguard-tools \
    # PID 1 zombie reaper for the BEAM
    tini \
    # IANA timezone database — required for timezone-aware Oban/Quantum schedules
    tzdata && \
    # Create dummies to suppress netclient init system detection errors
    # Netclient checks init type for service installation, not needed in containers
    mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox

# Set locale environment variables (C.UTF-8 is built into glibc — no locales pkg needed)
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Admin always runs userspace WireGuard
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go

# Erlang distribution settings
# Admins always use dynamic clustering (started after VPN join)
ENV RELEASE_DISTRIBUTION=none

# Keep epmd in the 40k port range to avoid colliding with user-deployed Erlang/Elixir apps
ENV ERL_EPMD_PORT=44369

# Copy netclient binary from builder stage
COPY --from=netclient-builder /netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient && \
    mkdir -p /etc/netclient && \
    chmod 0775 /etc/netclient

# Create app user (non-root)
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

# Copy the entrypoint, start, and one-off task scripts
COPY ./deploy/production/compose/edge_admin/entrypoint /entrypoint
COPY ./deploy/production/compose/edge_admin/start /start
COPY ./deploy/production/compose/edge_admin/migrate /migrate
COPY ./deploy/production/compose/edge_admin/rotate_cloak_key /rotate_cloak_key
RUN sed -i 's/\r$//g' /entrypoint /start /migrate /rotate_cloak_key && \
    chmod +x /entrypoint /start /migrate /rotate_cloak_key

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_admin /app
RUN chmod +x /app/bin/migrate /app/bin/rotate_cloak_key /app/bin/server /app/bin/create_netmaker_superadmin /app/bin/create_default_cluster && \
    chown -R app:app /app

# License text for the embedded Edge Admin release. ELv2 — see /usr/share/doc/edge_admin/LICENSE.
COPY edge_admin/LICENSE /usr/share/doc/edge_admin/LICENSE

# Create directories with proper permissions
RUN mkdir -p /app/data /tmp/erl_crash && \
    chown -R app:app /app/data /tmp/erl_crash

# Switch to app user for security
# NOTE: Will run as root at runtime due to NET_ADMIN capability requirements
# But the release files are owned by app user
WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint"]

CMD ["/start"]
