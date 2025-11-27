# deploy/production/compose/edge_admin/Dockerfile

# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.19.3-otp-28-slim AS builder

# Install build dependencies
RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod
ENV ERL_MAX_PORTS=65536
ENV ELIXIR_MAKE_PARALLEL=true

# First, build the nexmaker library with caching
WORKDIR /nexmaker
COPY nexmaker/mix.exs nexmaker/mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV
COPY nexmaker/lib lib/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile --parallel && mix compile --parallel

# Then build the main application
WORKDIR /app

# Copy mix files and install dependencies with caching
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

# Create release
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix release

# -----------------------------------------------
# Stage: Production runtime image (optimized)
# -----------------------------------------------
FROM debian:stable-20250520-slim

ENV NETCLIENT_VERSION="1.2.0"

# Install runtime dependencies in single layer
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    curl \
    ca-certificates \
    wget && \
    # Install netclient in same layer to reduce image size
    wget -qO /tmp/netclient https://github.com/gravitl/netclient/releases/download/v${NETCLIENT_VERSION}/netclient-linux-amd64 && \
    mv /tmp/netclient /usr/local/bin/netclient && \
    chmod +x /usr/local/bin/netclient && \
    mkdir -p /etc/netclient && \
    # Set locale in same layer
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
    # Clean up in same layer to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Set locale environment variables
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Copy the entrypoint script
COPY ./deploy/production/compose/edge_admin/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint
RUN chmod +x /entrypoint

COPY ./deploy/production/compose/edge_admin/start /start
RUN sed -i 's/\r$//g' /start
RUN chmod +x /start

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/edge_admin /app

RUN chmod +x /app/bin/migrate /app/bin/server

# Switch to app user
WORKDIR /app

ENTRYPOINT ["/entrypoint"]
