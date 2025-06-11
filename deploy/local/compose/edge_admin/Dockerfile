# deploy/local/compose/edge_admin/Dockerfile
FROM elixir:1.18.4-otp-26-slim AS elixir-dev-stage

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
  # for tailscale installation
  gnupg \
  lsb-release \
  # cleaning up unused files
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
  && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y tailscale \
  && mkdir -p /var/run/tailscale \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

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

# Copy ONLY dependency files first (for Docker layer caching)
COPY edge_admin/mix.exs edge_admin/mix.lock ./

# Copy config files (needed for dependency compilation)
COPY edge_admin/config ./config

# Install and compile dependencies (this layer will be cached!)
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    --mount=type=cache,target=deps \
    --mount=type=cache,target=_build \
    mix deps.compile

ENTRYPOINT ["/entrypoint"]
