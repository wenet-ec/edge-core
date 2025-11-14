# Multi-stage build: Build patched netclient, then create Elixir test environment with it
ARG NETCLIENT_VERSION=v1.2.0

# Stage 1: Build patched netclient (HTTP instead of HTTPS for local testing)
FROM golang:1.23-alpine AS netclient_builder

ARG NETCLIENT_VERSION
WORKDIR /build

# Install dependencies
RUN apk add --no-cache git grep

# Clone and checkout specific version
RUN git clone https://github.com/gravitl/netclient.git . && \
    git checkout ${NETCLIENT_VERSION}

# Patch API calls from HTTPS to HTTP for local testing
RUN echo "=== Patching netclient for HTTP (local testing) ===" && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' auth/auth.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' config/oldconfig.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/uninstall.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/server.go && \
    sed -i 's|"https://" + serverData\.Server|"http://" + serverData.Server|g' functions/register.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/list.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/mqpublish.go && \
    sed -i 's|fmt\.Sprintf("https://%s/|fmt.Sprintf("http://%s/|g' functions/mqhandlers.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/pull.go && \
    sed -i 's|"https://" + server\.API|"http://" + server.API|g' functions/auto_relay.go && \
    sed -i 's|"https://" + api|"http://" + api|g' ncutils/netclientutils.go

# Build patched netclient
RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o netclient .

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

# Copy patched netclient from builder stage
COPY --from=netclient_builder /build/netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

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
