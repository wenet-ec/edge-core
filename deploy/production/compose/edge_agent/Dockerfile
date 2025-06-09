# deploy/production/compose/edge_agent/Dockerfile

# -----------------------------------------------
# Stage: Build the OTP release
# -----------------------------------------------
FROM elixir:1.18.4-otp-26-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    postgresql-dev \
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
    postgresql-client \
    netcat-openbsd \
    tzdata \
    bash \
    && rm -rf /var/cache/apk/*

# Create app user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/bash -D app

# Copy the release from builder stage
COPY --from=builder --chown=app:app /app/_build/prod/rel/edge_agent /app

# Switch to app user
USER app
WORKDIR /app
