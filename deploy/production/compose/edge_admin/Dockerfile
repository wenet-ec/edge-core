# deploy/production/compose/edge_admin/Dockerfile

# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.18.4-otp-27-slim AS builder

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

# First, build the tailscale library
WORKDIR /tailscale
COPY tailscale/mix.exs tailscale/mix.lock ./
RUN mix deps.get --only $MIX_ENV
COPY tailscale/lib lib/
RUN mix deps.compile && mix compile

# Then build the main application
WORKDIR /app

# Copy mix files and install dependencies
COPY edge_admin/mix.exs edge_admin/mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
COPY edge_admin/config config/
RUN mix deps.compile

# Copy source code and compile
COPY edge_admin/lib lib/
COPY edge_admin/priv priv/
COPY edge_admin/rel rel/
RUN mix compile

# Create release
RUN mix release

# -----------------------------------------------
# Stage: Production runtime image
# -----------------------------------------------
FROM debian:stable-20250520-slim

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    curl \
    ca-certificates \
    sudo \
    # for tailscale installation
    gnupg \
    lsb-release && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
  && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y tailscale \
  && mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

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
