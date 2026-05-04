# Edge Core — Lite Setup

A single-admin, SQLite-backed deployment of Edge Core. Good for homelab, hobbyist, first-time exploration, or any small fleet that won't need to scale beyond ~100 nodes total.

**What's included:**

- 1 Edge Admin instance running on **SQLite** (no external database container)
- Netmaker VPN (SQLite-backed, Mosquitto broker)
- Netmaker UI

**What's NOT included (vs standard):**

- No metrics stack (Prometheus)
- No EMQX (uses Mosquitto instead — simpler, less overhead)
- No PostgreSQL containers (Edge Admin and Netmaker both run on SQLite)
- No multiple admin instances (single point of failure, no HA)
- No multi-cluster sharding (one admin owns all nodes; capped by WireGuard mesh O(n²) overhead at ~100 nodes)

**When to upgrade to `standard/`:** if you need any of HA / multi-admin clustering / cluster ownership sharding / >100 nodes / production observability / cross-admin coordination, switch to `standard/`. The Edge Admin binary is identical; the difference is `DB_ADAPTER=postgres` and the supporting infrastructure (Postgres + EMQX + Prometheus + 4 admin instances across 2 clusters). Migrating existing data from SQLite to Postgres is a one-time table-by-table copy, but most users start fresh on `standard/` rather than carrying state forward.

## Requirements

- A Linux server (VPS or bare metal) with Docker and Docker Compose installed
- Three ports reachable from every agent machine (private IP or public — either works):
  - `48081` — Netmaker VPN API
  - `48083` — Mosquitto MQTT/WebSocket
  - `34000` — Admin API
- Optional: a domain name if you want TLS (Caddy handles certs automatically)

## Quick Start

**On your server (cloud.yml):**

```bash
# 1. Copy and edit the env file
cp .env.example .env
nano .env   # fill in your server address and secrets

# 2. Start the cloud stack
docker compose -f cloud.yml up -d

# 3. Check everything is healthy
docker compose -f cloud.yml ps
```

**On each edge node (edge.yml):**

```bash
# 1. Copy and edit the same env file
cp .env.example .env
nano .env   # set PUBLIC_ENROLLMENT_KEY_URL to your admin's address

# 2. Start the agent
docker compose -f edge.yml up -d
```

## Configuration

All configuration lives in a single `.env` file. Copy `.env.example` to `.env` and fill in the values marked `REQUIRED`.

The minimum you must change:

- `your-server-ip-or-domain.com` — replace everywhere with your actual server address (private IP or public domain, both work)
- `change-me` passwords and keys — use strong random values
- `SECRET_KEY_BASE` — generate with `openssl rand -base64 48`
- `CLOAK_KEY` — generate with `openssl rand -base64 32` (encryption-at-rest for sensitive columns; back it up with the rest of your secrets — losing it means losing every encrypted row)

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

To update the admin manually:

```bash
docker compose -f cloud.yml pull
docker compose -f cloud.yml up -d
```
