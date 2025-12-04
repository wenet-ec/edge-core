# deploy/local/compose/edge_agent/Dockerfile

# Build netclient with HTTP patches (for local development)
ARG NETCLIENT_VERSION=v1.2.0
FROM golang:1.25-alpine AS netclient-builder

# Install git
RUN apk add --no-cache git

# Clone the netclient repository and checkout specific version
WORKDIR /build
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

# Build the patched netclient
RUN go mod download && \
    CGO_ENABLED=0 GOOS=linux go build -o netclient .

# Main Elixir stage
FROM elixir:1.19.4-otp-28-alpine

ARG APP_HOME=/app
ENV MIX_ENV=dev

WORKDIR ${APP_HOME}

# Install only absolute essentials for the edge agent itself
RUN apk add --no-cache \
  # Core build tools (required for Elixir/Erlang native dependencies)
  build-base \
  git \
  ca-certificates \
  # Agent database
  sqlite \
  # Agent shell and basic utilities
  bash \
  bash-completion \
  nano \
  util-linux \
  # Agent networking (for VPN and API calls)
  curl \
  wget \
  # Network discovery
  nmap \
  # SSH server key generation
  openssl \
  # File system watching for live reload (development only)
  inotify-tools \
  # For any native dependencies
  pkgconfig \
  iputils \
  && rm -rf /var/cache/apk/*

# Install node_exporter for metrics collection
ENV NODE_EXPORTER_VERSION="1.10.2"
RUN wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
    && tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz \
    && mv node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/ \
    && rm -rf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64* \
    && chmod +x /usr/local/bin/node_exporter

# Copy patched netclient binary from builder stage
COPY --from=netclient-builder /build/netclient /usr/local/bin/netclient
RUN chmod +x /usr/local/bin/netclient

# Create app user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/bash -D app && \
    mkdir -p /app/data && \
    chown -R app:app /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy entrypoint and utility scripts
COPY ./deploy/local/compose/edge_agent/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

COPY ./deploy/local/compose/edge_agent/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

COPY ./deploy/local/compose/edge_agent/migrate /migrate
RUN sed -i 's/\r$//g' /migrate && \
    chmod +x /migrate

COPY ./deploy/local/compose/edge_agent/hostscript /usr/local/bin/hostscript
RUN sed -i 's/\r$//g' /usr/local/bin/hostscript && \
    chmod +x /usr/local/bin/hostscript

COPY ./deploy/local/compose/edge_agent/edge_bashrc /usr/local/bin/edge_bashrc
RUN sed -i 's/\r$//g' /usr/local/bin/edge_bashrc && \
    chmod +r /usr/local/bin/edge_bashrc

RUN mix deps.get --only hex rebar || true

ENTRYPOINT ["/entrypoint"]
