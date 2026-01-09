# deploy/local/compose/edge_admin/Dockerfile

# Build netclient with HTTP patches (for local development)
FROM golang:1.25-alpine AS netclient-builder

# Define version inside the build stage
ARG NETCLIENT_VERSION=v1.4.0

# Install git
RUN apk add --no-cache git

# Clone the netclient repository and checkout specific version
WORKDIR /build
RUN git clone https://github.com/gravitl/netclient.git . && \
    git checkout ${NETCLIENT_VERSION}

# Patch ONLY API-related https:// to http:// (surgical patches for local dev)
# Using find to apply patches to all relevant files
RUN find . -type f -name '*.go' -exec sed -i \
    -e 's|"https://" + server\.API|"http://" + server.API|g' \
    -e 's|"https://" + serverData\.Server|"http://" + serverData.Server|g' \
    -e 's|"https://" + api|"http://" + api|g' \
    -e 's|fmt\.Sprintf("https://%s/|fmt.Sprintf("http://%s/|g' \
    {} \;

# Build the patched netclient
RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o netclient .

# Main Elixir stage
FROM elixir:1.19.4-otp-28-slim AS elixir-dev-stage

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
  # Create dummy /sbin/init to suppress netclient init system detection error
  # Netclient checks init type for service installation, not needed in containers
  mkdir -p /sbin && ln -s /bin/true /sbin/init && \
  # Clean up in same layer to reduce image size
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
  rm -rf /var/lib/apt/lists/*

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Copy patched netclient binary from builder stage
COPY --from=netclient-builder /build/netclient /usr/local/bin/netclient
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
