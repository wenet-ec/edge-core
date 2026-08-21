# deploy/production/compose/edge_admin/Dockerfile

ARG NETCLIENT_VERSION=v1.6.0-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

FROM elixir:1.20.3-otp-29-slim AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y build-essential cmake git

WORKDIR /app

ENV MIX_ENV=prod
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true
# Skip emqtt's optional QUIC NIF — our MQTT adapter uses TCP/TLS only, so the
# `quicer` build (compiles Microsoft's msquic from source) is pure overhead.
ENV BUILD_WITHOUT_QUIC=1

# Relocate Mix's home to a normal image path so hex/rebar archives survive across
# RUN steps. The default /root/.mix gets overlaid by the cache mount below,
# which would otherwise hide a pre-install and make every subsequent mix step
# prompt for hex.
ENV MIX_HOME=/opt/mix
RUN mix local.hex --force && mix local.rebar --force

COPY nexmaker /nexmaker

COPY edge_admin/mix.exs edge_admin/mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV

COPY edge_admin/config config/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile --parallel

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

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

FROM debian:stable-20260803-slim

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
    # Erlang runtime dependencies
    libstdc++6 \
    openssl \
    libncurses6 \
    # OTP 29 dynamically probes SCTP at startup; include this to avoid a warning
    libsctp1 \
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
    # Netclient checks init type for service installation, which containers do not use.
    mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Admin always runs userspace WireGuard
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go

# Erlang distribution settings
# Admins always use dynamic clustering (started after VPN join)
ENV RELEASE_DISTRIBUTION=none

COPY --from=netclient-builder /netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient && \
    mkdir -p /etc/netclient && \
    chmod 0775 /etc/netclient

RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

COPY ./deploy/production/compose/edge_admin/entrypoint /entrypoint
COPY ./deploy/production/compose/edge_admin/start /start
COPY ./deploy/production/compose/edge_admin/migrate /migrate
COPY ./deploy/production/compose/edge_admin/rotate_encryption_key /rotate_encryption_key
COPY ./deploy/production/compose/edge_admin/console /console
RUN sed -i 's/\r$//g' /entrypoint /start /migrate /rotate_encryption_key /console && \
    chmod +x /entrypoint /start /migrate /rotate_encryption_key /console

COPY --from=builder /app/_build/prod/rel/edge_admin /app
RUN chmod +x /app/bin/console /app/bin/migrate /app/bin/rotate_encryption_key /app/bin/server /app/bin/bootstrap_edge_vpn_admin /app/bin/create_default_cluster && \
    chown -R app:app /app

# License text for the embedded Edge Admin release. ELv2 — see /usr/share/doc/edge_admin/LICENSE.
COPY edge_admin/LICENSE /usr/share/doc/edge_admin/LICENSE

RUN mkdir -p /app/data /tmp/erl_crash && \
    chown -R app:app /app/data /tmp/erl_crash

WORKDIR /app

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint"]

CMD ["/start"]
