# Edge Core

Make your machines cloud manageable.

Edge Core is an infrastructure management platform for geographically distributed edge nodes. It gives you centralized control over remote machines through a secure WireGuard mesh — run commands, access machines via SSH, proxy traffic through them, and scrape their metrics — all through a simple HTTP API.

## What it does

- **Remote command execution** — run shell commands across hundreds of machines from a single API call
- **SSH backdoor** — SSH into any edge node through the admin, with centralized key management
- **Cloud-edge proxy** — HTTP and SOCKS5 forward proxies tunnel traffic to edge nodes and their local networks
- **Metrics observability** — Prometheus-compatible scraping of host, agent, and WireGuard metrics through admin service discovery
- **Edge mesh networking** — all nodes in the same cluster form a full WireGuard mesh via Netmaker

## Architecture

```
Cloud Server
├── Edge Admin (×N peers)     Elixir/Phoenix, shared PostgreSQL
│   ├── Erlang peer cluster   masterless P2P, no leader election
│   ├── Cluster ownership     one admin owns each edge cluster (sharding)
│   └── Forward proxies       HTTP + SOCKS5, routes traffic to edge nodes
│
└── Netmaker VPN Stack        WireGuard mesh (EMQX/Mosquitto + CoreDNS)

Edge Nodes (one agent per machine)
└── Edge Agent                network_mode: host, privileged
    ├── netclient             WireGuard VPN client (with DERP relay fallback)
    ├── SSH server            port 40022, keys managed centrally by admin
    ├── Forward proxies       HTTP + SOCKS5
    └── Metrics exporters     node exporter + WireGuard metrics
```

**Admin clustering** is masterless peer-to-peer — admins within the same cluster coordinate via Erlang distribution and share a PostgreSQL database. Exactly one admin owns each edge cluster at a time (shard assignment, not replication). HA comes from running additional independent admin clusters.

**Agent↔Admin communication** is HTTP over WireGuard, with graceful fallback: raw WireGuard UDP → DERP relay (transparent, handles symmetric NAT) → HTTP polling (last resort, eventual consistency).

For full detail see [`docs/architecture.md`](docs/architecture.md).

## Components

| Directory            | Description                                              |
| -------------------- | -------------------------------------------------------- |
| `edge_admin/`        | Phoenix admin server (PostgreSQL, Oban, OpenAPI)         |
| `edge_agent/`        | Phoenix agent (SQLite, embedded SSH, Oban)               |
| `nexmaker/`          | Shared Elixir lib — Netmaker API + netclient CLI wrapper |
| `deploy/local/`      | Local development Docker Compose                         |
| `deploy/production/` | Production Docker Compose                                |
| `examples/lite/`     | Single-admin homelab setup                               |
| `examples/standard/` | 4-admin (2-cluster) production setup                     |
| `docs/`              | Architecture docs and API specs                          |

## Getting Started

No local Elixir or Go required. Everything runs through Docker Compose via the `./bin/run` script.

### 1. Start the cloud stack (admin + VPN + DB)

```bash
./bin/run cloud up
```

### 2. Start the edge agents (separate terminal)

```bash
./bin/run edge up
```

### 3. Explore the API

```
Admin API:      http://localhost:44000
Swagger UI:     http://localhost:44000/api/swaggerui
ReDoc:          http://localhost:44000/api/redoc
MCP server:     http://localhost:44000/mcp
Netmaker UI:    http://localhost:48080
```

### 4. Connect an AI assistant (optional)

Edge Admin exposes an MCP server at `/mcp` for AI assistants (Claude Desktop, Cursor, etc.). Point your MCP client at the admin with your `MCP_KEY`:

```json
{
  "mcpServers": {
    "edge-admin": {
      "type": "http",
      "url": "http://localhost:44000/mcp",
      "headers": { "Authorization": "Bearer your-mcp-key" }
    }
  }
}
```

47 tools cover the full management surface — nodes, clusters, commands, SSH, metrics, and health checks. Tools are discovered dynamically via `tools/list` (MCP standard — no static spec file needed).

### Common commands

```bash
./bin/run all up -d          # Start everything detached
./bin/run cloud logs edge_admin
./bin/run cloud admin:shell  # IEx shell inside admin container
./bin/run cloud admin:test   # Run admin tests
./bin/run all format         # Format code
./bin/run all quality        # Lint + dialyzer
```

## Deployment Examples

Ready-to-use Docker Compose setups are in `examples/`:

- **[`examples/lite/`](examples/lite/)** — single admin, Mosquitto broker, no metrics stack. For homelab and hobbyists.
- **[`examples/standard/`](examples/standard/)** — 4 admin instances across 2 clusters, EMQX, full VictoriaMetrics stack. For production.

Both use pre-built images from `ghcr.io/wenet-ec/`.

## VPN Source Reference

To work on anything VPN-related without hallucinating, clone the source locally:

```bash
git clone --branch v1.5.0 https://github.com/gravitl/netmaker edge_vpn/netmaker
git clone --branch v1.5.0-derp https://github.com/wenet-ec/netclient edge_vpn/netclient
```

The Netmaker OpenAPI spec is at [`docs/netmaker-v1.5.0.yml`](docs/netmaker-v1.5.0.yml).
