# deploy/production/compose/edge_metrics_collector/Dockerfile

# Build stage for Go service
FROM golang:1.25-alpine AS go-builder

# Set Go environment for better caching and performance
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/go/pkg/mod

WORKDIR /app

# Copy Go module files from the edge_metrics_collector directory
COPY edge_metrics_collector/go.mod edge_metrics_collector/go.sum ./

# Download dependencies with cache mount
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Copy collector wrapper source code
COPY edge_metrics_collector/ ./

# Build with cache mounts for faster builds
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -o edge_metrics_collector_wrapper main.go

# Final stage
FROM alpine:latest

# Define VictoriaMetrics version
ARG VICTORIA_METRICS_VERSION=v1.120.0

# Install runtime dependencies
RUN apk add --no-cache \
    # Core utilities
    ca-certificates \
    curl \
    bash \
    wget \
    # VPN client
    tailscale \
    && rm -rf /var/cache/apk/*

# Download prebuilt vmagent binary
RUN wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/${VICTORIA_METRICS_VERSION}/vmutils-linux-amd64-${VICTORIA_METRICS_VERSION}.tar.gz && \
    tar xzf vmutils-linux-amd64-${VICTORIA_METRICS_VERSION}.tar.gz && \
    mv vmagent-prod /usr/local/bin/vmagent && \
    rm -f vmutils-linux-amd64-${VICTORIA_METRICS_VERSION}.tar.gz vm*

# Create Tailscale directory
RUN mkdir -p /var/run/tailscale

# Copy Go service binary
COPY --from=go-builder /app/edge_metrics_collector_wrapper /usr/local/bin/edge_metrics_collector_wrapper

# Create directories
RUN mkdir -p /var/lib/tailscale /vmagent-data /etc/prometheus

# Copy scripts
COPY ./deploy/production/compose/edge_metrics_collector/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

COPY ./deploy/production/compose/edge_metrics_collector/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

ENTRYPOINT ["/entrypoint"]
