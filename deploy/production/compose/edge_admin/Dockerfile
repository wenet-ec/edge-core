# deploy/production/compose/edge_admin/Dockerfile

# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.18.4-otp-26-slim AS builder

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

# Copy mix files and install dependencies
COPY edge_admin/mix.exs edge_admin/mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
# Make sure to copy ALL config files
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
    libncurses5 \
    locales \
    curl \
    netcat-openbsd \
    gnupg \
    lsb-release \
    ca-certificates \
    sudo && \
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

# Create app user and add to sudoers for VPN operations
RUN useradd --create-home --shell /bin/bash app \
    && echo "app ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/app \
    && chmod 0440 /etc/sudoers.d/app

# Pre-create Tailscale directories with proper permissions
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale \
    && chown -R app:app /var/run/tailscale /var/cache/tailscale /var/lib/tailscale

# Copy the entrypoint script
COPY ./deploy/production/compose/edge_admin/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint
RUN chmod +x /entrypoint

# Copy the release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/edge_admin /app

# Switch to app user
USER app
WORKDIR /app

ENTRYPOINT ["/entrypoint"]