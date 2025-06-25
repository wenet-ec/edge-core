# deploy/local/compose/edge_metrics_collector/Dockerfile

# Build stage for Go service
FROM golang:1.24-alpine AS go-builder

WORKDIR /app

# Copy Go module files from the edge_metrics_collector directory
COPY edge_metrics_collector/go.mod edge_metrics_collector/go.sum ./
RUN go mod download

# Copy the main.go file
COPY edge_metrics_collector/main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o edge_metrics_collector_wrapper main.go

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
COPY --from=go-builder /app/edge-metrics-collector /usr/local/bin/edge-metrics-collector

# Create directories
RUN mkdir -p /var/lib/tailscale /vmagent-data /etc/prometheus

# Copy scripts
COPY ./deploy/local/compose/edge_metrics_collector/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && \
    chmod +x /entrypoint

COPY ./deploy/local/compose/edge_metrics_collector/start /start
RUN sed -i 's/\r$//g' /start && \
    chmod +x /start

EXPOSE 8429 8430

ENTRYPOINT ["/entrypoint"]
