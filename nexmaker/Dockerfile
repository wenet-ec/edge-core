# Stage 1: Build netclient from our fork (DERP support + NETMAKER_API_SCHEME)
FROM golang:1.25-bookworm AS netclient_builder

ARG NETCLIENT_REPO=https://github.com/wenet-ec/netclient.git
ARG NETCLIENT_VERSION=v1.4.0-derp

WORKDIR /build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${NETCLIENT_VERSION} ${NETCLIENT_REPO} .

RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o netclient -ldflags="-s -w" .

# Stage 2: Create Elixir test environment with netclient installed
FROM elixir:1.19-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    git \
    build-base \
    curl \
    wget \
    bash \
    libmnl \
    gcompat \
    openresolv \
    iproute2 \
    wireguard-tools \
    iptables \
    ip6tables \
    ca-certificates

# Copy netclient from builder stage
COPY --from=netclient_builder /build/netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

# Use HTTP for Netmaker API (local testing — no TLS certs)
ENV NETMAKER_API_SCHEME=http

# Verify netclient is installed
RUN netclient version || echo "netclient installed"

# Copy Elixir project files
COPY mix.exs mix.lock* ./

# Install Elixir dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

# Copy source code and tests
COPY lib ./lib
COPY test ./test
COPY .formatter.exs ./

# Compile
RUN MIX_ENV=test mix compile

# Create netclient data directory
RUN mkdir -p /etc/netclient

CMD ["mix", "test", "--include", "integration"]
