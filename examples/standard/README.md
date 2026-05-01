# Edge Core — Standard Setup

A multi-admin deployment of Edge Core with 4 admin instances across 2 clusters, PostgreSQL-backed Netmaker, EMQX broker, and a complete metrics stack. Use this when you need resilience (if one admin goes down the others keep running) or more node capacity.

**What's included:**

- 4 Edge Admin instances — cluster A (a1, a2) + cluster B (b1, b2)
- Netmaker VPN (PostgreSQL-backed, EMQX broker)
- Netmaker UI
- Prometheus (metrics)
- Caddy (reverse proxy / TLS)

## Cluster Layout

```
Cluster A: edge_admin_a1 + edge_admin_a2  →  subnet 100.63.0.0/24
Cluster B: edge_admin_b1 + edge_admin_b2  →  subnet 100.63.1.0/24
```

Each admin instance is a peer — there is no primary/replica or leader/follower relationship. Instances within the same cluster form an Erlang peer mesh over the VPN and share the same PostgreSQL database. Each cluster independently owns and manages its own set of edge nodes. Multiple clusters mean more total capacity — clusters do not coordinate with each other.

## Requirements

- A Linux server with Docker and Docker Compose installed
- Three ports reachable from every agent machine (private IP or public — either works):
  - `48081` — Netmaker VPN API
  - `48083` — EMQX WebSocket / MQTT
  - `34000`–`34003` — Admin APIs (one per instance)
- Optional: a domain name if you want TLS (Caddy handles certs automatically)

## Quick Start

**On your server (cloud.yml):**

```bash
# 1. Copy and edit the env file
cp .env.example .env
nano .env   # fill in your server address, secrets, and passwords

# 2. If using a domain with TLS: edit configs/Caddyfile — replace yourdomain.com

# 3. Edit configs/prometheus.yml — replace change-me-your-metrics-key with your METRICS_KEY

# 4. Start the cloud stack
docker compose -f cloud.yml up -d

# 5. Check everything is healthy
docker compose -f cloud.yml ps
```

**On each edge node (edge.yml):**

```bash
# 1. Copy and edit the env file
cp .env.example .env
nano .env   # set PUBLIC_ENROLLMENT_KEY_URL to your admin's address

# 2. Start the agent
docker compose -f edge.yml up -d
```

## Configuration

All configuration lives in a single `.env` file. Copy `.env.example` to `.env` and fill in the values marked `REQUIRED`.

Key things to configure:

- Replace all `your-server-ip-or-domain.com` with your actual server address (private IP or public domain, both work)
- Replace all `change-me` with strong random values
- `SECRET_KEY_BASE` — generate with `openssl rand -base64 48`
- `MASTER_KEY` — omnipotent key, fallback for all scoped keys
- `API_KEY` — scoped to REST API clients (optional, defaults to `MASTER_KEY`)
- `METRICS_KEY` — scoped to metrics scrapers (optional, defaults to `MASTER_KEY`)
- `VPN_CLUSTER_COOKIE` — must be the same across all 4 admin instances
- `MQ_PASSWORD` and `EMQX_DASHBOARD_PASSWORD` — must match each other
- Update `configs/prometheus.yml` — replace `change-me-your-metrics-key` with your actual `METRICS_KEY`
- If using a domain with TLS: update `configs/Caddyfile` with your domain names

### Private network (no TLS)?

If you're using a plain IP address without TLS, add this to your `.env`:

```env
NETMAKER_API_SCHEME=http
```

Set this on **both** the server (`.env` used by `cloud.yml`) and the agent (`.env` used by `edge.yml`). Without it, netclient will try HTTPS and fail even though the server is running plain HTTP.

A plain IP address works fine for `SERVER_HOST`, `SERVER_HTTP_HOST`, and `SERVER_API_CONN_STRING` when using HTTP. If you're using HTTPS (Caddy with a TLS cert), these must be a proper hostname — the TLS cert won't match a bare IP.

## Event Broker (optional)

Edge Core can publish lifecycle events (node registered, command completed, etc.) to a message broker. Disabled by default — broker is deployed separately.

```bash
# Start with NATS (recommended)
docker compose -f cloud.yml -f ../event_brokers/nats.yml up -d
```

Then add to your `.env`:

```bash
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats
EVENT_BROKER_NATS_URLS=nats://edge_event_broker:4222
# EVENT_BROKER_NATS_JETSTREAM=true   # enable durable log (default: false)
```

See `examples/event_brokers/` for all supported brokers (NATS, Redpanda, Kafka, RabbitMQ, Redis).

## API Docs

Once the admin is running, the API documentation is available at:

- `/swaggerui` — Swagger UI (interactive)
- `/redoc` — ReDoc
- `/asyncdoc` — AsyncAPI (event broker schema)

## Upgrading

The edge agent updates itself automatically via Watchtower when a new image is published to `ghcr.io/wenet-ec/edge_agent:stable`.

To update the admin stack:

```bash
docker compose -f cloud.yml pull
docker compose -f cloud.yml up -d
```
