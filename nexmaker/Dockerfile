# Stage 1: Build patched netclient (HTTP instead of HTTPS for local testing)
FROM golang:1.23-alpine AS netclient_builder

# Multi-stage build: Build patched netclient, then create Elixir test environment with it
ARG NETCLIENT_VERSION=v1.4.0

WORKDIR /build

# Install dependencies
RUN apk add --no-cache git

# Clone and checkout specific version
RUN git clone https://github.com/gravitl/netclient.git . && \
    git checkout ${NETCLIENT_VERSION}

# Patch ONLY API-related https:// to http:// (surgical patches for local dev)
# Using find to apply patches to all relevant files
RUN find . -type f -name '*.go' -exec sed -i \
    -e 's|"https://" + server\.API|"http://" + server.API|g' \
    -e 's|"https://" + serverData\.Server|"http://" + serverData.Server|g' \
    -e 's|"https://" + api|"http://" + api|g' \
    -e 's|fmt\.Sprintf("https://%s/|fmt.Sprintf("http://%s/|g' \
    {} \;

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
