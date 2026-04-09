# deploy/local/compose/edge_admin/Dockerfile

# Pull pre-built netclient (DERP fork) — built by wenet-ec/netclient CI
ARG NETCLIENT_VERSION=v1.5.1-derp
FROM ghcr.io/wenet-ec/netclient:${NETCLIENT_VERSION} AS netclient-builder

# Main Elixir stage
FROM elixir:1.19.5-otp-28-slim AS elixir-dev-stage

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install apt packages in single layer
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
  # PostgreSQL dependencies
  libpq-dev \
  postgresql-client \
  # Development utilities
  sudo \
  bash-completion \
  nano \
  ssh \
  # Essential tools (healthcheck, troubleshooting, capability checks)
  curl \
  iputils-ping \
  libcap2-bin \
  # File system watching for live reload (dev only)
  inotify-tools \
  # Network debugging (comprehensive set for development)
  iproute2 \
  dnsutils \
  netcat-openbsd \
  tcpdump \
  iptables && \
  # Set locale in same layer
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
  # Create dummies to suppress netclient init system detection errors
  # Netclient checks init type for service installation, not needed in containers
  mkdir -p /sbin /bin && ln -s /bin/true /sbin/init && ln -s /bin/true /bin/busybox && \
  # Clean up in same layer to reduce image size
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
  rm -rf /var/lib/apt/lists/*

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Use HTTP for Netmaker API (local dev — no TLS certs)
ENV NETMAKER_API_SCHEME=http

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

# Create devcontainer user and add it to sudoers
RUN groupadd --gid 1000 dev-user \
  && useradd --uid 1000 --gid dev-user --shell /bin/bash --create-home dev-user \
  && echo dev-user ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/dev-user \
  && chmod 0440 /etc/sudoers.d/dev-user

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy entrypoint and utility scripts
COPY ./deploy/local/compose/edge_admin/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint
RUN chmod +x /entrypoint

COPY ./deploy/local/compose/edge_admin/start /start
RUN sed -i 's/\r$//g' /start
RUN chmod +x /start

COPY ./deploy/local/compose/edge_admin/migrate /migrate
RUN sed -i 's/\r$//g' /migrate
RUN chmod +x /migrate

RUN mix deps.get --only hex rebar || true

ENTRYPOINT ["/entrypoint"]

CMD ["/start"]
