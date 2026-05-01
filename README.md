# Edge Core

**Turn your machines into managed nodes.**

Edge Core is an open-source infrastructure management platform for geographically distributed machines. It gives you centralized control over remote nodes through a secure WireGuard mesh — run commands, SSH into any machine, proxy traffic through them, and scrape their metrics — all through a simple HTTP API.

Works on any Linux machine: on-premises servers, IoT devices, factory floor equipment, Raspberry Pis, cloud VMs, home lab nodes, remote POS terminals, bare metal, containers. No vendor lock-in. Self-hosted.

## What it does

**Functionalities**

- **Remote command execution** — run shell commands across hundreds of machines from a single API call, results collected centrally
- **SSH backdoor** — SSH into any node through the admin proxy with centralized key and username management, no exposed SSH ports
- **Metrics aggregation** — Prometheus-compatible scraping of host, agent, and WireGuard metrics via admin service discovery
- **Self-update** — roll out agent updates across the fleet from a single API call, coordinated via Watchtower

**Connectivity**

- **Cloud ↔ Edge (forward proxy + proxy chaining)** — HTTP and SOCKS5 forward proxies tunnel any TCP traffic from the cloud through any agent to its local network or the internet
- **Edge ↔ Edge (VPN mesh)** — full WireGuard P2P mesh per cluster, automatic peer discovery, netclient-local DNS for `.nm.internal` hostnames, DERP/TURN relay fallback for NAT
- **Edge ↔ Local devices (mDNS)** — agents advertise themselves via mDNS for zero-config discovery by devices on the same LAN; full LAN DNS control is a future direction (see [`docs/architecture.md`](docs/architecture.md))

**Plus:** Event streaming (lifecycle events to NATS, Kafka/Redpanda, RabbitMQ, or Redis), and an MCP server for AI assistant integration (Claude, Cursor, and any MCP-compatible client).

## Who is this for

**If you are looking for:**

- An open-source alternative to Balena that works for general Linux machines, not just IoT
- A way to manage remote machines without exposing SSH ports to the internet
- Fleet management that works on-prem, air-gapped, or across multiple clouds simultaneously
- Remote access to machines behind strict NAT or firewalls (DERP/TURN relay handles symmetric NAT automatically)
- A self-hosted alternative to Headscale (self-hosted Tailscale) + fleet management, where you own all the infrastructure
- HTTP-first edge communication without needing to run MQTT brokers (like EMQX or Mosquitto) in your own application code
- Something that scales to tens of thousands of nodes without a single point of failure

**Concrete use cases:**

- Manage a fleet of Raspberry Pis or embedded Linux devices from a central dashboard
- Remote command execution across factory floor machines or industrial controllers
- SSH access to machines in remote offices or data centers through a single proxy
- Collect Prometheus metrics from edge nodes without VPN client on the monitoring server
- Roll out updates to hundreds of edge nodes with a single API call
- IoT device management where you need real shell access, not just telemetry

## Compared to alternatives

|                                  | Edge Core    | Balena      | Ansible¹ | Tailscale / Headscale | FleetDM |
| -------------------------------- | ------------ | ----------- | -------- | --------------------- | ------- |
| Self-hosted                      | ✅           | Partial     | ✅       | Partial / ✅          | ✅      |
| Works for general Linux          | ✅           | ❌ IoT-only | ✅       | ✅                    | ✅      |
| Built-in VPN mesh                | ✅           | ✅          | ❌       | ✅                    | ❌      |
| SSH proxy (no VPN client needed) | ✅           | ❌          | ❌       | ✅                    | ❌      |
| HTTP forward proxy to edge       | ✅           | ❌          | ❌       | ❌                    | ❌      |
| Remote command execution         | ✅           | ✅          | ✅       | ❌                    | Partial |
| Prometheus metrics via admin     | ✅           | Partial     | ❌       | ❌                    | ❌      |
| Works behind symmetric NAT       | ✅ DERP/TURN | ✅          | ❌       | ✅ DERP/TURN          | ❌      |
| Scales to 50k+ nodes             | ✅           | Limited     | Limited  | ✅                    | Limited |
| No vendor lock-in                | ✅           | ❌          | ✅       | ❌ / ✅               | ✅      |

_¹ Ansible is a complement, not a competitor — see below._

**vs Balena:** Balena is optimized for IoT and requires their cloud or their OS. Edge Core works on any Linux machine, any OS, any cloud or on-prem. You own everything.

**vs Tailscale / Headscale:** Tailscale and its self-hosted equivalent Headscale are networking-first — they give you a VPN and SSH access. Edge Core is application-first — networking just works out of the box (WireGuard + DERP/TURN relay), but the product is the fleet management layer on top: command execution, centralized SSH credential management, HTTP proxying, metrics aggregation, MCP AI interface.

**Works alongside Ansible:** Edge Core is not an Ansible replacement — it's the network layer that makes Ansible work on unreachable machines. Nodes behind NAT or firewalls are normally inaccessible to Ansible. With Edge Core, you SSH through the admin proxy tunnel to reach them, then run your playbooks as normal. No changes to your Ansible setup needed — just configure `ProxyCommand` in your SSH config to route through the admin's SOCKS5 proxy and Ansible works as if the nodes were on your local network.

**vs running EMQX/Mosquitto yourself:** If you want edge-to-cloud communication and don't need a message bus, Edge Core gives you command delivery, result collection, SSH access, and full TCP tunneling (via HTTP and SOCKS5 forward proxy) without ever touching an MQTT broker. The broker in this repo (EMQX/Mosquitto) is internal Netmaker infrastructure — your application code never sees it.

## Scaling

Edge Core is designed to scale to ~50,000 edge nodes on commodity hardware with proper tuning.

The key is the **masterless P2P architecture**. There is no leader election, no Raft consensus, no primary/replica. All admin instances independently run the same deterministic algorithm on shared PostgreSQL state and converge to identical cluster assignments — similar in spirit to CRDTs (Conflict-free Replicated Data Types). This means:

- No single point of failure in the control plane
- Adding more admins is linear capacity increase, not coordination overhead
- Network partitions don't cause split-brain — both sides continue operating, assignments reconcile on reconnect

WireGuard mesh is O(n²), so clusters are capped at 50–100 nodes each. Scale comes from **more clusters**, not bigger ones. Each admin cluster handles ~200 nodes (configurable). Multiple admin clusters share one PostgreSQL database.

For fine-tuning to high node counts, see the env files in your chosen setup's directory — all tunables are documented there.

## Architecture

```text
Cloud Server
├── Edge Admin (×N peers)     Elixir/Phoenix, shared PostgreSQL
│   ├── Erlang peer cluster   masterless P2P, no leader election, no Raft
│   ├── Cluster ownership     one admin owns each edge cluster (sharding)
│   └── Forward proxies       HTTP + SOCKS5, routes traffic to edge nodes
│
├── HAProxy                   TCP load balancer for proxy ports
│
└── Netmaker VPN Stack        WireGuard mesh control plane (EMQX/Mosquitto; DNS is netclient-local)

Edge Nodes (one agent per machine)
└── Edge Agent                network_mode: host, privileged
    ├── netclient             WireGuard VPN client (DERP/TURN relay fallback for symmetric NAT)
    ├── SSH server            port 40022, keys managed centrally by admin
    ├── Forward proxies       HTTP + SOCKS5
    └── Metrics exporters     node exporter + WireGuard metrics
```

**Admin clustering** is masterless peer-to-peer — admins coordinate via Erlang distribution and share a PostgreSQL database. Exactly one admin owns each edge cluster at a time (shard assignment, not replication). HA comes from running additional independent admin clusters.

**Agent↔Admin communication** is HTTP over WireGuard, with graceful fallback: raw WireGuard UDP → DERP/TURN relay (transparent, handles symmetric NAT) → HTTP polling (last resort, eventual consistency).

For full detail see [`docs/architecture.md`](docs/architecture.md).

## Getting started

Everything runs in Docker Compose — no Elixir or Go required on the host.

Pick the setup that fits your needs and follow its README:

| Setup        | Description                                                                                             | Start here                                          |
| ------------ | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **Lite**     | Single admin, Mosquitto broker, no metrics stack. Good for homelab, small fleets, or first deployments. | [`examples/lite/`](examples/lite/README.md)         |
| **Standard** | 4 admin instances across 2 clusters, EMQX, full Prometheus metrics. Production-ready HA setup.          | [`examples/standard/`](examples/standard/README.md) |

Each README covers: server requirements, configuration, enrolling your first node, and upgrading.

## Connect an AI assistant

Edge Admin exposes an MCP server at `/mcp`. Point any MCP-compatible client (Claude Desktop, Cursor, etc.) at your admin's public address:

```json
{
  "mcpServers": {
    "edge-admin": {
      "type": "http",
      "url": "http://your-server:34000/mcp",
      "headers": { "Authorization": "Bearer your-mcp-key" }
    }
  }
}
```

Tools are discovered dynamically via `tools/list` — no static spec file needed. Covers the full management surface: nodes, clusters, commands, SSH, metrics, and health checks.

## Event streaming

Edge Admin can publish lifecycle events to a message broker. Disabled by default — opt in by setting `EVENT_BROKER_ENABLED=true` and the adapter-specific endpoint env var.

Events cover node lifecycle, command execution lifecycle, and self-update lifecycle. All follow the [CloudEvents 1.0](https://cloudevents.io) spec. Supported brokers: NATS, Kafka/Redpanda, RabbitMQ, Redis, and MQTT — pick whichever fits your stack.

```bash
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats                   # or: kafka, rabbitmq, redis, mqtt
EVENT_BROKER_NATS_URLS=nats://your-broker:4222   # endpoint var is namespaced per adapter
```

Ready-to-use broker compose files are in [`examples/event_brokers/`](examples/event_brokers/). Full event schema: [`docs/admin-asyncapi-v0.2.0.md`](docs/admin-asyncapi-v0.2.0.md) or browse `/asyncdoc` on a running admin.

## Configuration reference

All environment variables are documented in the `.env.example` file of your chosen setup. For the full list of tunables (cluster sizing, VPN config, DB connection pooling, etc.) see:

- [`examples/lite/`](examples/lite/) — `.env.example`
- [`examples/standard/`](examples/standard/) — `.env.example`

## Grafana dashboards

Dashboard JSON files are in [`edge_admin/priv/grafana_dashboards/`](edge_admin/priv/grafana_dashboards/). See the [README there](edge_admin/priv/grafana_dashboards/README.md) for what each dashboard covers.

To import: in Grafana go to **Dashboards → Import**, upload the JSON file, and select your Prometheus datasource.

## Components

| Directory                 | Description                                                                                            |
| ------------------------- | ------------------------------------------------------------------------------------------------------ |
| `edge_admin/`             | Phoenix admin server — REST API, OpenAPI, AsyncAPI, MCP server, HTTP/SOCKS5 proxies (PostgreSQL, Oban) |
| `edge_agent/`             | Phoenix agent — embedded SSH server, HTTP/SOCKS5 proxies, metrics exporters (SQLite, Oban)             |
| `nexmaker/`               | Shared Elixir lib — Netmaker API + netclient CLI wrapper                                               |
| `examples/lite/`          | Single admin, Mosquitto, no metrics — good for small fleets or resource-constrained servers            |
| `examples/standard/`      | 4 admins across 2 clusters, EMQX, Prometheus — when you need HA or more node capacity                  |
| `examples/relay/`         | Self-hosted DERP/TURN relay node — optional, for agents behind strict NAT                              |
| `examples/sidecar/`       | Agent as a sidecar container (bridge networking) rather than host-networked                            |
| `examples/event_brokers/` | NATS, Redpanda, Kafka, RabbitMQ, Redis, and MQTT compose files                                         |
| `docs/`                   | Architecture docs and API specs                                                                        |

## VPN internals

Edge Core uses [Netmaker](https://github.com/gravitl/netmaker) (v1.5.1) as its WireGuard mesh control plane. The Netmaker OpenAPI spec is included at [`docs/netmaker-openapi-v1.5.1.yml`](docs/netmaker-openapi-v1.5.1.yml) for reference.
