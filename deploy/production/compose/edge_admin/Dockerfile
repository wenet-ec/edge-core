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
    apt-get install -y libstdc++6 openssl libncurses5 locales curl netcat-openbsd && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create app user
RUN useradd --create-home --shell /bin/bash app

# Copy the release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/edge_admin /app

# Switch to app user
USER app
WORKDIR /app
