# deploy/production/compose/edge_relay/Dockerfile

# -----------------------------------------------
# Stage 1: Build derper from tailscale source
# -----------------------------------------------
FROM golang:1.26.3-alpine AS builder

ARG TAILSCALE_REPO=https://github.com/tailscale/tailscale.git
ARG TAILSCALE_VERSION=v1.98.1

WORKDIR /build

RUN apk add --no-cache git ca-certificates

RUN git clone --depth 1 --branch ${TAILSCALE_VERSION} ${TAILSCALE_REPO} .

RUN go mod download

RUN CGO_ENABLED=0 GOOS=linux go build \
    -o /derper \
    -ldflags="-s -w" \
    ./cmd/derper

# -----------------------------------------------
# Stage 2: Production runtime image
# -----------------------------------------------
# Alpine instead of scratch: the entrypoint is a shell script (bash → sh here),
# and derper needs ca-certificates for Let's Encrypt + TLS outbound. Both are
# included in alpine:latest. If you ever replace the entrypoint with a compiled
# binary, you can drop to scratch and just COPY ca-certificates.crt.
FROM alpine:latest

RUN apk add --no-cache ca-certificates

COPY --from=builder /derper /usr/local/bin/derper

# Upstream license + patent grant for the embedded derper binary.
# Tailscale source is BSD-3-Clause; the PATENTS file is a separate patent
# grant. Both are required for binary distribution of derived works.
COPY --from=builder /build/LICENSE /usr/share/doc/tailscale/LICENSE
COPY --from=builder /build/PATENTS /usr/share/doc/tailscale/PATENTS

COPY ./deploy/production/compose/edge_relay/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint && chmod +x /entrypoint

VOLUME ["/var/lib/derper"]

# HTTPS/DERP
EXPOSE 443
# HTTP (ACME challenge + redirect)
EXPOSE 80
# STUN
EXPOSE 3478/udp

ENTRYPOINT ["/entrypoint"]
