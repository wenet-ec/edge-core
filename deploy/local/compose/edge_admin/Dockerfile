# deploy/local/compose/edge_admin/Dockerfile

ARG NETCLIENT_VERSION=v1.7.0-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

FROM elixir:1.20.4-otp-29-slim AS elixir-dev-stage

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

RUN apt-get update && apt-get install --no-install-recommends -y \
  # Erlang runtime dependencies
  libstdc++6 \
  openssl \
  libncurses6 \
  # OTP 29 dynamically probes SCTP at startup; include this to avoid a warning
  libsctp1 \
  locales \
  ca-certificates \
  # Build dependencies (dev only)
  build-essential \
  cmake \
  git \
  # Essential tools (healthcheck, troubleshooting, capability checks)
  curl \
  libcap2-bin \
  # File system watching for live reload (dev only)
  inotify-tools \
  # Network debugging (comprehensive set for development)
  iproute2 \
  iptables \
  # PID 1 zombie reaper for the BEAM
  tini && \
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
  # Netclient checks init type for service installation, which containers do not use.
  mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox && \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
  rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Use HTTP for Edge VPN API (local dev — no TLS certs)
ENV EDGE_VPN_API_SCHEME=http

# Admin always runs userspace WireGuard
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go

# Erlang distribution settings
# Admins always use dynamic clustering (started after VPN join)
ENV RELEASE_DISTRIBUTION=none

# Skip emqtt's optional QUIC NIF — our MQTT adapter uses TCP/TLS only, so the
# `quicer` build (compiles Microsoft's msquic from source) is pure overhead.
ENV BUILD_WITHOUT_QUIC=1

COPY --from=netclient-builder --chmod=0755 /netclient /usr/local/bin/netclient
RUN mkdir -p /etc/netclient && \
    chmod 0775 /etc/netclient

RUN mix local.hex --force && \
    mix local.rebar --force

COPY ./deploy/local/compose/edge_admin/entrypoint /entrypoint
COPY ./deploy/local/compose/edge_admin/start /start
COPY ./deploy/local/compose/edge_admin/migrate /migrate
COPY ./deploy/local/compose/edge_admin/console /console
COPY ./deploy/local/compose/edge_admin/rotate_encryption_key /rotate_encryption_key
RUN sed -i 's/\r$//g' /entrypoint /start /migrate /console /rotate_encryption_key && \
    chmod +x /entrypoint /start /migrate /console /rotate_encryption_key

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint"]

CMD ["/start"]
