# deploy/local/compose/edge_admin/Dockerfile

# Build netclient with HTTP patches (for local development)
ARG NETCLIENT_VERSION=v1.1.0
FROM golang:1.25-alpine AS netclient-builder

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
    -e 's|fmt\.Sprintf("https://%s/|fmt.Sprintf("http://%s/|g' \
    {} \;

# Build the patched netclient
RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o netclient .

# Main Elixir stage
FROM elixir:1.19.2-otp-28-slim AS elixir-dev-stage

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install apt packages
RUN apt-get update && apt-get install --no-install-recommends -y \
  # dependencies for building
  build-essential \
  git \
  ca-certificates \
  # psycopg dependencies
  libpq-dev \
  # development utilities
  sudo \
  bash-completion \
  nano \
  ssh \
  # postgresql client
  postgresql-client \
  # requests and pings
  curl \
  # file system watching for live reload
  inotify-tools \
  # cleaning up unused files
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/*

# Copy patched netclient binary from builder stage
COPY --from=netclient-builder /build/netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

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

# Copy dependency files first (for Docker layer caching)
COPY edge_admin/mix.exs edge_admin/mix.lock* ./
COPY nexmaker/ /nexmaker/

# Copy config files (needed for dependency compilation)
COPY edge_admin/config ./config

# Install dependencies with smart caching
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,id=edge_admin_deps \
    --mount=type=cache,target=/app/_build,id=edge_admin_build \
    if [ ! -f mix.lock ]; then \
      echo "mix.lock not found, generating from mix.exs..."; \
    else \
      echo "Using existing mix.lock for dependency resolution"; \
    fi && \
    mix deps.get

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,id=edge_admin_deps \
    --mount=type=cache,target=/app/_build,id=edge_admin_build \
    mix deps.compile

# Pre-compile the application (this will speed up startup)
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=/app/deps,id=edge_admin_deps \
    --mount=type=cache,target=/app/_build,id=edge_admin_build \
    mix compile

ENTRYPOINT ["/entrypoint"]
