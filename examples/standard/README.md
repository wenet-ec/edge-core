# Edge Core — Standard Setup

A full production-grade deployment of Edge Core with 4 admin instances across 2 clusters, PostgreSQL-backed Netmaker, EMQX broker, and a complete metrics stack.

**What's included:**
- 4 Edge Admin instances — cluster A (a1, a2) + cluster B (b1, b2)
- Netmaker VPN (PostgreSQL-backed, EMQX broker)
- Netmaker UI
- CoreDNS
- VictoriaMetrics (metrics storage)
- vmagent (metrics collector)
- Caddy (reverse proxy / TLS)

## Cluster Layout

```
Cluster A: edge_admin_a1 + edge_admin_a2  →  subnet 100.63.0.0/24
Cluster B: edge_admin_b1 + edge_admin_b2  →  subnet 100.63.1.0/24
```

Each admin instance is a peer — there is no primary/replica or leader/follower relationship. Instances within the same cluster form an Erlang peer mesh over the VPN and share the same PostgreSQL database. Each cluster independently owns and manages its own set of edge nodes. Multiple clusters mean more total capacity and more HA — clusters do not coordinate with each other.

## Requirements

- A Linux server with Docker and Docker Compose installed
- Ports open to the internet:
  - `48081` — Netmaker API
  - `48083` — EMQX WebSocket / MQTT
  - `34000`–`34003` — Admin APIs (one per instance)
- A domain with DNS records pointing to this server (for Caddy TLS)

## Quick Start

**On your server (cloud.yml):**

```bash
# 1. Copy and edit the env file
cp .env.example .env
nano .env   # fill in your domain, secrets, and passwords

# 2. Edit configs/Caddyfile — replace yourdomain.com with your actual domain

# 3. Edit configs/prometheus.yml — replace the metrics key with your METRICS_KEY

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
- Replace all `your-server-ip-or-domain.com` with your actual domain
- Replace all `change-me` with strong random values
- `SECRET_KEY_BASE` — generate with `openssl rand -base64 48`
- `MASTER_KEY` — omnipotent key, fallback for all scoped keys
- `API_KEY` — scoped to REST API clients (optional, defaults to `MASTER_KEY`)
- `METRICS_KEY` — scoped to metrics scrapers (optional, defaults to `MASTER_KEY`)
- `VPN_CLUSTER_COOKIE` — must be the same across all 4 admin instances
- `MQ_PASSWORD` and `EMQX_DASHBOARD_PASSWORD` — must match each other
- Update `configs/Caddyfile` with your actual domain names
- Update `configs/prometheus.yml` with your actual `METRICS_KEY`

## API Docs

Once the admin is running, the API documentation is available at:

- `/api/swaggerui` — Swagger UI (interactive)
- `/api/redoc` — ReDoc

## Upgrading

The edge agent updates itself automatically via Watchtower when a new image is published to `ghcr.io/wenet-ec/edge_agent:stable`.

To update the admin stack:

```bash
docker compose -f cloud.yml pull
docker compose -f cloud.yml up -d
```
