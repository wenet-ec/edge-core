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
  # networking utilities
  netcat-traditional \
  # postgresql client
  postgresql-client \
  # health checks and pings
  curl \
  # file system watching for live reload
  inotify-tools \
  # cleaning up unused files
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
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

# Copy mix files to install dependencies
COPY edge_admin/mix.exs edge_admin/mix.lock ./
RUN mix deps.get && mix deps.compile

ENTRYPOINT ["/entrypoint"]