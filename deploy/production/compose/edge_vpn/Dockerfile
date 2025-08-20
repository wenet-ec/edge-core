# deploy/production/compose/edge_vpn/Dockerfile
FROM golang:1.25-alpine AS go-builder

# Define headscale version
ARG HEADSCALE_VERSION=v0.26.1

# Install build dependencies
RUN apk add --no-cache git make

# Set Go environment for better caching and performance
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/go/pkg/mod

WORKDIR /build

# Clone headscale repository
RUN git clone https://github.com/juanfont/headscale.git
WORKDIR /build/headscale

# Checkout the specific version we want
RUN git checkout ${HEADSCALE_VERSION}

# Download dependencies first for better layer caching
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

# Build headscale with cache mounts for faster builds
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags="-s -w -X github.com/juanfont/headscale/hscontrol/types.Version=${HEADSCALE_VERSION}" -o headscale ./cmd/headscale

# Build our Go wrapper
WORKDIR /app
COPY edge_vpn/go.mod edge_vpn/go.sum ./

# Download wrapper dependencies with cache
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY edge_vpn/ .

# Build wrapper with cache mounts
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o edge_vpn_wrapper .

# Final stage - Alpine with both binaries
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache bash ca-certificates curl

# Create app directory
WORKDIR /app

# Copy headscale binary and make it executable
COPY --from=go-builder /build/headscale/headscale /usr/local/bin/headscale
RUN chmod +x /usr/local/bin/headscale

# Copy our wrapper binary and make it executable
COPY --from=go-builder /app/edge_vpn_wrapper /app/edge_vpn_wrapper
RUN chmod +x /app/edge_vpn_wrapper

# Copy the start script
COPY ./deploy/production/compose/edge_vpn/start /start
RUN sed -i 's/\r$//g' /start
RUN chmod +x /start
