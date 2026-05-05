# Edge Core

**Your machines, meshed, proxied, observed, and remotely controlled.**

Edge Core is an infrastructure management platform for geographically distributed machines. It gives you centralized control over remote nodes through a secure WireGuard mesh — run commands, SSH into any machine, proxy traffic through them, and scrape their metrics — all through a simple HTTP API.

Designed to run on Linux machines of all shapes: on-premises servers, IoT devices, factory floor equipment, Raspberry Pis, cloud VMs, home lab nodes, remote POS terminals, bare metal, containers. No vendor lock-in. Self-hosted. (Tested host distros: see [Host compatibility](#host-compatibility) below.)

The **agent** that runs on your machines and the **Nexmaker** shared library are open-source under Apache 2.0. The **admin** server is source-available under the Elastic License 2.0 — free to self-host, modify, and use commercially, but you may not offer it to third parties as a hosted or managed service without a commercial license from us. See [License](#license) below for details.

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

**Plus:** Event streaming (lifecycle events to NATS, Kafka/Redpanda, RabbitMQ, Redis, MQTT, AWS SNS, or Google Cloud Pub/Sub), and an MCP server for AI assistant integration (Claude, Cursor, and any MCP-compatible client).

## Who is this for

**If you are looking for:**

- A self-hostable alternative to Balena that works for general Linux machines, not just IoT
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

**vs Balena:** Balena is optimized for IoT and requires their cloud or their OS. Edge Core is designed to run on general-purpose Linux (see [Host compatibility](#host-compatibility) for tested distros), any cloud or on-prem. You own everything.

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

## Host compatibility

Edge Agent ships as a Debian-slim container, so the agent process itself is portable. The real constraints come from what it does to the **host**: it runs `network_mode: host` + `privileged`, manages WireGuard interfaces, writes `/etc/resolv.conf`, and (when present) talks to `systemd-resolved` over D-Bus.

**Tested:** Ubuntu 22.04 / 24.04 and Debian 12, on x86_64 and ARM64, with kernel ≥ 5.15 (built-in WireGuard).

**Should work, not regularly tested:** Other glibc-based, systemd-based distros with kernel ≥ 5.6 (Fedora, Rocky, Alma, openSUSE Leap, recent CentOS Stream). If you run agents on these and hit something, please [open an issue](https://github.com/wenet-ec/edge-core/issues) — fixes are usually small.

**Known caveats:**

- **Older kernels (< 5.6)** — RHEL/CentOS 7, old Debian/Ubuntu LTS — need the WireGuard DKMS module. netclient also has a userspace fallback (`wireguard-go`), but it is slower and less commonly tested in this codebase.
- **Alpine and other musl-based hosts** — works for the agent (it runs in its own container), but if the host network stack expects musl-specific behavior, edge cases may surface.
- **Immutable / atomic distros** (Fedora CoreOS, Flatcar, Bottlerocket, Talos, NixOS) — the privileged-host-container model still applies, but persistent paths, package layout, and service management differ; expect some integration work.
- **SELinux enforcing** (RHEL/Fedora/Rocky/Alma defaults) — privileged containers with host networking and raw socket access often need a custom policy or `--security-opt label=disabled`.
- **Architectures other than x86_64 / ARM64** (RISC-V, ppc64le, s390x) — not currently built or tested.

The admin server is host-distro-agnostic: it runs containerized and uses `wireguard-go` (userspace) inside its container, so it does not depend on the host's WireGuard support.

## Connect an AI assistant

Edge Admin exposes an MCP server at `/mcp`. Point any MCP-compatible client (Claude Desktop, Cursor, etc.) at your admin's public address:

```json
{
  "mcpServers": {
    "edge-admin": {
      "type": "http",
      "url": "http://your-server:<API_PORT>/mcp",
      "headers": { "Authorization": "Bearer your-mcp-key" }
    }
  }
}
```

Tools are discovered dynamically via `tools/list` — no static spec file needed. Covers the full management surface: nodes, clusters, commands, SSH, metrics, and health checks.

## Events

Edge Admin publishes lifecycle events to two independent delivery channels: a message broker (opt-in) and HTTP webhooks (always-on, configured per-row via the API). Both channels receive the same CloudEvents 1.0 envelope; events cover node lifecycle, command execution lifecycle, enrollment-key verification, SSH credential verification, and self-update lifecycle.

### Broker

Disabled by default — opt in by setting `EVENT_BROKER_ENABLED=true` and the adapter-specific endpoint env var. Supported brokers: NATS, Kafka/Redpanda, AMQP 0-9-1 (RabbitMQ / LavinMQ / etc.), Redis, MQTT, AWS SNS, and Google Cloud Pub/Sub.

```bash
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats                   # or: kafka, amqp091, redis, mqtt, aws_sns, google_pubsub
EVENT_BROKER_NATS_URLS=nats://your-broker:4222   # endpoint var is namespaced per adapter
```

Ready-to-use broker compose files are in [`examples/event_brokers/`](examples/event_brokers/). Full event schema: [`docs/admin-asyncapi-v0.2.0.md`](docs/admin-asyncapi-v0.2.0.md) or browse `/asyncdoc` on a running admin.

### Webhooks

Register webhook subscriptions through the REST API at `POST /api/v1/webhooks`. Each webhook stores an HTTPS URL, an HMAC-SHA256 `secret`, optional static `headers`, and an explicit list of `subscribed_events` — literal event-type strings from the catalog (e.g. `edge.node.registered`, `edge.command_execution.completed`). No wildcards; unknown event types are rejected at create time. Webhooks are immutable after create — to change anything, delete and recreate. Retry budget per event is `WEBHOOK_MAX_ATTEMPTS` (default 3).

Sensitive columns (`secret`, `headers`) are encrypted at rest via Cloak — `CLOAK_KEY` and `CLOAK_TAG` are required at boot. Destination URLs are SSRF-checked at create time (loopback, RFC1918, link-local, cloud metadata IPs/hostnames denied; opt out with `WEBHOOK_ALLOW_PRIVATE_IPS=true` for homelab/dev). Each delivery is signed with `X-Edge-Signature: sha256=<hex>`. Each event is retried up to `WEBHOOK_MAX_ATTEMPTS` and then dropped; there is no row-level failure counter or auto-disable.

## Configuration reference

All environment variables are documented in the `.env.example` file of your chosen setup. For the full list of tunables (cluster sizing, VPN config, DB connection pooling, etc.) see:

- [`examples/lite/`](examples/lite/) — `.env.example`
- [`examples/standard/`](examples/standard/) — `.env.example`

## Grafana dashboards

Dashboard JSON files are in [`edge_admin/priv/grafana_dashboards/`](edge_admin/priv/grafana_dashboards/). See the [README there](edge_admin/priv/grafana_dashboards/README.md) for what each dashboard covers.

To import: in Grafana go to **Dashboards → Import**, upload the JSON file, and select your Prometheus datasource.

## Components

| Directory                 | Description                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `edge_admin/`             | Phoenix admin server — REST API, OpenAPI, AsyncAPI, MCP server, HTTP/SOCKS5 proxies (PostgreSQL, Oban)          |
| `edge_agent/`             | Phoenix agent — embedded SSH server, HTTP/SOCKS5 proxies, metrics exporters (SQLite, Oban)                      |
| `nexmaker/`               | Shared Elixir lib — Netmaker API + netclient CLI wrapper                                                        |
| `examples/lite/`          | Single admin, Mosquitto, no metrics — good for small fleets or resource-constrained servers                     |
| `examples/standard/`      | 4 admins across 2 clusters, EMQX, Prometheus — when you need HA or more node capacity                           |
| `examples/relay/`         | Self-hosted DERP/TURN relay node — optional, for agents behind strict NAT                                       |
| `examples/sidecar/`       | Agent as a sidecar container (bridge networking) rather than host-networked                                     |
| `examples/event_brokers/` | NATS, Redpanda, Kafka, RabbitMQ, Redis, and MQTT compose files (AWS SNS is managed — provisioning notes inline) |
| `docs/`                   | Architecture docs and API specs                                                                                 |

## VPN internals

Edge Core uses [Netmaker](https://github.com/gravitl/netmaker) (v1.5.1) as its WireGuard mesh control plane. The Netmaker OpenAPI spec is included at [`docs/netmaker-openapi-v1.5.1.yml`](docs/netmaker-openapi-v1.5.1.yml) for reference.

## License

Edge Core ships under multiple licenses depending on the component. See [`LICENSE`](LICENSE) at the repository root for the full overview.

| Component                           | Path          | License                                                      | Posture          |
| ----------------------------------- | ------------- | ------------------------------------------------------------ | ---------------- |
| Edge Agent                          | `edge_agent/` | [Apache License 2.0](edge_agent/LICENSE)                     | Open source      |
| Nexmaker                            | `nexmaker/`   | [Apache License 2.0](nexmaker/LICENSE)                       | Open source      |
| Edge Admin                          | `edge_admin/` | [Elastic License 2.0](edge_admin/LICENSE)                    | Source available |
| Examples, docs, deploy, bin scripts | other         | Apache License 2.0 unless a file explicitly states otherwise | Open source      |

**Open source vs. source available — what the difference means here**

The agent and Nexmaker are **open source** under Apache 2.0. You can do anything you want with them — fork, modify, embed in commercial products, redistribute — as long as you preserve the copyright and license notices.

The admin server is **source available** under the Elastic License 2.0. The full source is published, you can read, modify, self-host, run it for your own organization, run it as part of how you deliver services to your own customers, and use it commercially. The license carves out only one significant restriction: you may not offer Edge Admin itself (or its substantial functionality) to third parties as a hosted or managed service. That clause is what makes a hosted Edge Admin tier viable as a commercial product without a hyperscaler reselling it the next day.

What this means in practice:

- **Allowed without asking us:** self-hosting for your own company, using it internally to manage your own fleet, using it as a tool while delivering services to your clients (MSP / consulting / IoT vendor patterns), modifying it, redistributing modified versions under ELv2, building products on top of it that aren't themselves "Edge Admin in the cloud."
- **Requires a commercial license from us:** offering Edge Admin (or a thin wrapper around it) as a hosted SaaS that customers sign up for and use directly.

Email **licensing@wenetec.com** if your use case needs a commercial license, or if you're not sure whether what you want to build falls inside or outside ELv2 — we'll tell you, and we're not looking to be difficult about it.

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution flow and the Developer Certificate of Origin (DCO) sign-off we require on every commit.

Copyright © 2026 WENET VIETNAM JOINT STOCK COMPANY. "Edge Core", "Edge Admin", "Edge Agent", "Nexmaker", "Wenet", and "Wenetec" are trademarks of WENET VIETNAM JOINT STOCK COMPANY. The licenses above grant rights to the software only — not to the trademarks.
