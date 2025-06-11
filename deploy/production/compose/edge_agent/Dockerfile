# deploy/production/compose/edge_agent/Dockerfile
# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.18.4-otp-26-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    sqlite-dev \
    ca-certificates \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Copy mix files and install dependencies
COPY edge_agent/mix.exs edge_agent/mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy config files (needed for compilation)
COPY edge_agent/config config/
RUN mix deps.compile

# Copy source code and compile
COPY edge_agent/lib lib/
COPY edge_agent/priv priv/
COPY edge_agent/rel rel/
RUN mix compile

# Create release
RUN mix release

# -----------------------------------------------
# Stage: Production runtime image
# -----------------------------------------------
FROM alpine:3.22.0

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    sqlite \
    bash \
    curl \
    tailscale \
    libstdc++ \
    libgcc \
    su-exec \
    && rm -rf /var/cache/apk/*

# Create app user and setup directories
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/bash -D app && \
    mkdir -p /app/data /var/run/tailscale /var/lib/tailscale /var/cache/tailscale && \
    chown -R app:app /app /var/lib/tailscale /var/cache/tailscale

# Copy the release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/edge_agent /app

# Copy entrypoint script
COPY ./deploy/production/compose/edge_agent/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

WORKDIR /app

ENTRYPOINT ["/entrypoint"]