# Edge Core

[![CI](https://github.com/wenet-ec/edge-core/actions/workflows/local.yml/badge.svg?branch=develop)](https://github.com/wenet-ec/edge-core/actions/workflows/local.yml)
[![Build](https://github.com/wenet-ec/edge-core/actions/workflows/production.yml/badge.svg?branch=main)](https://github.com/wenet-ec/edge-core/actions/workflows/production.yml)
[![Docs](https://github.com/wenet-ec/edge-core/actions/workflows/docs.yml/badge.svg?branch=main)](https://github.com/wenet-ec/edge-core/actions/workflows/docs.yml)

**Open-source self-hostable control plane for distributed Linux and Edge fleets — WireGuard mesh, SSH proxy, remote execution, Prometheus metrics, all over one REST API/MCP.**

📖 **Docs:** [wenet-ec.github.io/edge-core](https://wenet-ec.github.io/edge-core/)

Edge Core is an infrastructure management platform for fleets of Linux machines you don't physically touch. Cloud VMs across providers, on-premises servers, factory-floor equipment, Raspberry Pis, homelab boxes, IoT devices — anywhere you have N machines and want a single HTTP API to operate them. You get a secure WireGuard mesh, remote command execution, SSH without exposing port 22, HTTP/SOCKS5 forward proxying through any node, and Prometheus metrics aggregation.

We named the project "Edge Core" because the founding pain came from edge devices, but **"edge" here means *any machine you don't physically touch right now*** — a cloud VM in Frankfurt, a bare-metal box in a colo, or a Raspberry Pi in a factory. The control plane doesn't care; it's all the same problem.

Runs on standard Linux hosts (glibc + systemd, kernel ≥ 5.6 for built-in WireGuard). Tested on Ubuntu 22.04 / 24.04 and Debian 12 (x86_64 + ARM64); other glibc/systemd distros should work — see [Host compatibility](#host-compatibility) below. Self-hosted, no vendor lock-in.

The **agent** that runs on your machines and the **Nexmaker** shared library are open-source under Apache 2.0. The **admin** server is source-available under the Elastic License 2.0 — you can self-host, modify, and use it commercially. The one thing we reserve is the right to offer Edge Admin as a hosted service to the public; we hope you respect that decision so we can keep the rest of Edge Core fully free, with no future feature gates or surprise relicensing. See [License](#license) below for details.

## What it does

**Functionalities**

- **Remote command execution** — run shell commands across hundreds of machines from a single API call, results collected centrally
- **SSH backdoor** — SSH into any node through the admin proxy with centralized key and username management, no exposed SSH ports
- **Metrics aggregation** — Prometheus-compatible scraping of host, agent, and WireGuard metrics via admin service discovery
- **Self-update** — roll out agent updates across the fleet from a single API call, coordinated via Watchtower

**Connectivity**

- **Cloud ↔ Edge (forward proxy + proxy chaining)** — HTTP and SOCKS5 forward proxies tunnel any TCP traffic from the cloud through any agent to its local network or the internet
- **Edge ↔ Edge (VPN mesh)** — full WireGuard P2P mesh per cluster, automatic peer discovery, netclient-local DNS for `.nm.internal` hostnames, DERP relay fallback for NAT
- **Edge ↔ Local devices (mDNS)** — agents advertise themselves via mDNS for zero-config discovery by devices on the same LAN; full LAN DNS control is a future direction (see [`docs/architecture.md`](https://github.com/wenet-ec/edge-core/blob/main/docs/architecture.md))

**Async events**

- **Lifecycle events** — every state change (node registered, command finished, SSH verified, self-update completed) is published as a CloudEvents envelope. Subscribe via webhooks or a message broker (NATS, Kafka/Redpanda, RabbitMQ, Redis, MQTT, AWS SNS, Google Cloud Pub/Sub). No polling required.

**AI-driveable by default**

- **MCP server** — Edge Admin exposes the **same surface as the REST API** as MCP tools, with no separate integration work. Anything you can do over HTTP, an AI assistant (Claude, Cursor, any MCP-compatible client) can do through `/mcp` with a bearer token.
- **Closed loop** — combine MCP tools (act), lifecycle events (observe), and the forward proxy (reach the long tail of services on any node), and an AI agent has every primitive it needs to run your fleet end-to-end. Patch a CVE across hundreds of nodes, follow rollout state in real time, debug a crash by SSH'ing through the proxy — none of it requires a human in the loop. The architecture happens to be the right shape; we didn't bolt anything on.

## Who is this for

**If you are looking for:**

- A self-hostable alternative to Balena that works for general Linux machines, not just IoT
- A way to manage remote machines without exposing SSH ports to the internet
- Fleet management that works on-prem, air-gapped, or across multiple clouds simultaneously
- Remote access to machines behind strict NAT or firewalls (DERP relay handles symmetric NAT automatically)
- A self-hosted alternative to Headscale (self-hosted Tailscale) + fleet management, where you own all the infrastructure
- HTTP-first edge communication without needing to run MQTT brokers (like EMQX or Mosquitto) in your own application code
- A control plane with no single point of failure — masterless admins, horizontal scale-out via independent admin clusters

**Concrete use cases:**

- Manage a fleet of Raspberry Pis or embedded Linux devices from a central dashboard
- Remote command execution across factory floor machines or industrial controllers
- SSH access to machines in remote offices or data centers through a single proxy
- Collect Prometheus metrics from edge nodes without VPN client on the monitoring server
- Roll out updates to hundreds of edge nodes with a single API call
- IoT device management where you need real shell access, not just telemetry

## Compared to alternatives

|                                  | Edge Core    | Balena                     | Ansible¹ | Tailscale / Headscale | FleetDM |
| -------------------------------- | ------------ | -------------------------- | -------- | --------------------- | ------- |
| Self-hosted                      | ✅           | Partial                    | ✅       | Partial / ✅          | ✅      |
| Works for general Linux          | ✅           | ❌ IoT-only                | ✅       | ✅                    | ✅      |
| Built-in VPN mesh                | ✅           | ❌ hub-and-spoke (OpenVPN) | ❌       | ✅                    | ❌      |
| SSH proxy (no VPN client needed) | ✅           | ❌                         | ❌       | ✅                    | ❌      |
| HTTP forward proxy to edge       | ✅           | ❌                         | ❌       | ❌                    | ❌      |
| Remote command execution         | ✅           | ✅                         | ✅       | ❌                    | Partial |
| Prometheus metrics via admin     | ✅           | Partial                    | ❌       | ❌                    | ❌      |
| Works behind symmetric NAT       | ✅ DERP     | ✅                         | ❌       | ✅ DERP               | ❌      |
| No vendor lock-in                | ✅           | ❌                         | ✅       | ❌ / ✅               | ✅      |

*¹ Ansible is a complement, not a competitor — see below.*

**vs Balena:** Balena is optimized for IoT and requires their cloud or their OS. Edge Core is designed to run on general-purpose Linux (see [Host compatibility](#host-compatibility) for tested distros), any cloud or on-prem. You own everything.

**vs Tailscale / Headscale:** Tailscale (and its self-hosted equivalent Headscale) is a polished, opinionated mesh networking product — VPN, identity, SSH, ACLs, MagicDNS, exit nodes. We use Tailscale's [DERP](https://tailscale.com/blog/how-nat-traversal-works) relay protocol for our own NAT-traversal fallback, so this isn't really a head-to-head comparison. Edge Core sits one layer up: the network plumbing is solved (via Netmaker + DERP), and the product is the fleet-management layer on top — command execution, centralized SSH credentials, HTTP/SOCKS5 forward proxying, metrics aggregation, MCP. If your need is "give my team SSH'd access to my fleet over a VPN", Tailscale is probably what you want. If you also need to *operate* the fleet from a control plane, that's where Edge Core fits.

**Works alongside Ansible:** Edge Core is not an Ansible replacement — it's the network layer that makes Ansible work on unreachable machines. Nodes behind NAT or firewalls are normally inaccessible to Ansible. With Edge Core, you SSH through the admin proxy tunnel to reach them, then run your playbooks as normal. No changes to your Ansible setup needed — just configure `ProxyCommand` in your SSH config to route through the admin's SOCKS5 proxy and Ansible works as if the nodes were on your local network.

**vs running EMQX/Mosquitto yourself:** If you want edge-to-cloud communication and don't need a message bus, Edge Core gives you command delivery, result collection, SSH access, and full TCP tunneling (via HTTP and SOCKS5 forward proxy) without ever touching an MQTT broker. The broker in this repo (EMQX/Mosquitto) is internal Netmaker infrastructure — your application code never sees it.

## Scaling

Edge Core has a masterless control plane. Within an admin cluster there is no leader election, no Raft consensus, no primary/replica — all admin instances run the same deterministic ownership algorithm against shared PostgreSQL state and converge on identical cluster assignments. This means:

- No single point of failure in the control plane
- Adding admins is a linear capacity increase, not coordination overhead
- Network partitions don't cause split-brain — both sides continue operating, assignments reconcile on reconnect
- Adding more admin clusters is horizontal scale-out — admin clusters share only PostgreSQL and are otherwise independent

WireGuard mesh is O(n²), so edge clusters are capped at 50–100 nodes each. Scale comes from more clusters, not bigger ones. Tunables live in the env files of each example setup.

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
    ├── netclient             WireGuard VPN client (DERP relay fallback for symmetric NAT)
    ├── SSH server            port 40022, keys managed centrally by admin
    ├── Forward proxies       HTTP + SOCKS5
    └── Metrics exporters     node exporter + WireGuard metrics
```

**Admin clustering** is masterless peer-to-peer — admins coordinate via Erlang distribution and share a PostgreSQL database. Exactly one admin owns each edge cluster at a time (shard assignment, not replication). HA and horizontal scale come from running additional independent admin clusters.

**Agent↔Admin communication** is HTTP over WireGuard, with graceful fallback: raw WireGuard UDP → DERP relay (transparent, handles symmetric NAT) → HTTP polling (last resort, eventual consistency).

For full detail see [`docs/architecture.md`](https://github.com/wenet-ec/edge-core/blob/main/docs/architecture.md).

## Getting started

Everything runs in Docker Compose — no Elixir or Go required on the host.

Pick the setup that fits your needs and follow its README:

| Setup        | Description                                                                                             | Start here                                          |
| ------------ | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **Lite**     | Single admin, Mosquitto broker, no metrics stack. Good for homelab, small fleets, or first deployments. | [`examples/lite/`](https://github.com/wenet-ec/edge-core/blob/main/examples/lite/README.md)         |
| **Standard** | 4 admin instances across 2 clusters, EMQX, full Prometheus metrics. Production-ready HA setup.          | [`examples/standard/`](https://github.com/wenet-ec/edge-core/blob/main/examples/standard/README.md) |

Each README covers: server requirements, configuration, enrolling your first node, and upgrading. Once your admin is running, the **[user guide](https://github.com/wenet-ec/edge-core/blob/main/docs/guide.md)** walks through the day-to-day surface (Swagger, MCP, proxy, metrics, events).

## Compatibility

### Admin deployment matrix

The admin is always a containerized deployment target. We do not support running it directly as a bare Linux host process.

| Deployment surface | Status | Notes |
| ------------------ | ------ | ----- |
| Docker Compose on Linux | Supported | Canonical deployment path today |
| Docker on Linux | Supported | Same containerized runtime model |
| Kubernetes | Planned / not yet shipped | `examples/k8s` is still TODO |
| Bare Linux host process | Unsupported | Not a supported runtime shape |

The admin is much less host-sensitive than the agent: it runs containerized and uses `wireguard-go` (userspace) inside its own container, so it does not depend on host WireGuard kernel support.

### Agent platform matrix

Edge Agent ships as a Debian-slim container, so the agent process itself is portable. The real constraints come from what it does to the **host**: it runs `network_mode: host` + `privileged`, manages WireGuard interfaces, writes `/etc/resolv.conf`, and (when present) talks to `systemd-resolved` over D-Bus.

| Platform | Architectures | Status | Notes |
| -------- | ------------- | ------ | ----- |
| Ubuntu 22.04 | `amd64`, `arm64` | Tested | Regularly used baseline |
| Ubuntu 24.04 | `amd64`, `arm64` | Tested | Regularly used baseline |
| Debian 12 | `amd64`, `arm64` | Tested | Regularly used baseline |
| Fedora, Rocky, Alma, openSUSE Leap, recent CentOS Stream | `amd64`, `arm64` | Should work, not regularly tested | glibc + systemd shape expected |
| Older Linux with kernel `< 5.6` | varies | Caveat | Needs WireGuard DKMS or `wireguard-go` userspace fallback |
| Alpine and other musl-based hosts | varies | Caveat | Container may run, but host-network integration can be rough |
| Immutable / atomic distros (Fedora CoreOS, Flatcar, Bottlerocket, Talos, NixOS) | varies | Caveat | Expect extra integration work around persistence and service management |
| SELinux-enforcing hosts | `amd64`, `arm64` | Caveat | May need custom policy or `--security-opt label=disabled` |
| `riscv64`, `ppc64le`, `s390x` | those architectures | Unsupported today | Not currently built or tested |

## Using a running admin

Once an admin is up, the day-to-day surface — Swagger UI, MCP, proxy servers, metrics, events/webhooks, health checks, concepts — is documented in the **[user guide](https://github.com/wenet-ec/edge-core/blob/main/docs/guide.md)**.

Other useful pointers:

- Configuration reference: `.env.example` in [`examples/lite/`](https://github.com/wenet-ec/edge-core/tree/main/examples/lite) or [`examples/standard/`](https://github.com/wenet-ec/edge-core/tree/main/examples/standard), and the full annotated env files in [`deploy/production/.envs/`](https://github.com/wenet-ec/edge-core/tree/main/deploy/production/.envs)
- Grafana dashboards: [`edge_admin/priv/grafana_dashboards/`](https://github.com/wenet-ec/edge-core/tree/main/edge_admin/priv/grafana_dashboards)
- Event catalog: `/asyncdoc` on a running admin, or [`docs/admin-asyncapi-v0.2.0.md`](https://github.com/wenet-ec/edge-core/blob/main/docs/admin-asyncapi-v0.2.0.md)
- MCP tool catalog: [`docs/admin-mcp-v0.2.0.md`](https://github.com/wenet-ec/edge-core/blob/main/docs/admin-mcp-v0.2.0.md) — MCP has no static-spec standard yet, so this is hand-maintained alongside `EdgeAdminMcp.Server`

## Components

| Directory                 | Description                                                                                                     |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `edge_admin/`             | Phoenix admin server — REST API, OpenAPI, AsyncAPI, MCP server, HTTP/SOCKS5 proxies (PostgreSQL, Oban)          |
| `edge_agent/`             | Phoenix agent — embedded SSH server, HTTP/SOCKS5 proxies, metrics exporters (SQLite, Oban)                      |
| `nexmaker/`               | Shared Elixir lib — Netmaker API + netclient CLI wrapper                                                        |
| `examples/lite/`          | Single admin, Mosquitto, no metrics — good for small fleets or resource-constrained servers                     |
| `examples/standard/`      | 4 admins across 2 clusters, EMQX, Prometheus — when you need HA or more node capacity                           |
| `examples/relay/`         | Self-hosted DERP relay node — optional, for agents behind strict NAT                                           |
| `examples/sidecar/`       | Agent as a sidecar container (bridge networking) rather than host-networked                                     |
| `examples/event_brokers/` | NATS, Redpanda, Kafka, RabbitMQ, Redis, and MQTT compose files (AWS SNS is managed — provisioning notes inline) |
| `docs/`                   | Architecture docs and API specs                                                                                 |

## Built on

Edge Core stands on a stack of much larger projects, and we're grateful for them:

| Layer                | Project                                                                           | Why                                                                                                |
| -------------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| WireGuard mesh       | [Netmaker](https://github.com/gravitl/netmaker) (v1.6.0)                          | Mature mesh control plane with proper network segmentation                                         |
| Relay fallback       | [DERP](https://tailscale.com/blog/how-nat-traversal-works) (Tailscale)            | Best-in-class WireGuard-over-HTTPS for symmetric NAT                                               |
| Runtime              | [Elixir](https://elixir-lang.org/) / [Phoenix](https://www.phoenixframework.org/) | BEAM concurrency model fits a coordination plane naturally                                         |
| Distributed registry | [`:syn`](https://github.com/ostinelli/syn)                                        | Availability-over-consistency, scoped registries with metadata                                     |
| Background jobs      | [Oban](https://github.com/oban-bg/oban)                                           | Same-process job runner that works on Postgres or SQLite — exactly what our two-binary shape needs |

The Netmaker OpenAPI spec we target is included at [`docs/netmaker-openapi-v1.6.0.yml`](https://github.com/wenet-ec/edge-core/blob/main/docs/netmaker-openapi-v1.6.0.yml) for reference.

We didn't build any of these — we glued them together in a way that solved the specific problem in front of us.

## License

Edge Core ships under multiple licenses depending on the component. See [`LICENSE`](https://github.com/wenet-ec/edge-core/blob/main/LICENSE) at the repository root for the full overview.

| Component                           | Path          | License                                                      | Posture          |
| ----------------------------------- | ------------- | ------------------------------------------------------------ | ---------------- |
| Edge Agent                          | `edge_agent/` | [Apache License 2.0](https://github.com/wenet-ec/edge-core/blob/main/edge_agent/LICENSE)                     | Open source      |
| Nexmaker                            | `nexmaker/`   | [Apache License 2.0](https://github.com/wenet-ec/edge-core/blob/main/nexmaker/LICENSE)                       | Open source      |
| Edge Admin                          | `edge_admin/` | [Elastic License 2.0](https://github.com/wenet-ec/edge-core/blob/main/edge_admin/LICENSE)                    | Source available |
| Examples, docs, deploy, bin scripts | other         | Apache License 2.0 unless a file explicitly states otherwise | Open source      |

**Open source vs. source available — what the difference means here**

The agent and Nexmaker are **open source** under Apache 2.0. You can do anything you want with them — fork, modify, embed in commercial products, redistribute — as long as you preserve the copyright and license notices.

The admin server is **source available** under the Elastic License 2.0. The full source is published, you can read, modify, self-host, run it for your own organization, run it as part of how you deliver services to your own customers, and use it commercially. The license carves out only one significant restriction: you may not offer Edge Admin itself (or its substantial functionality) to third parties as a hosted or managed service. That clause is what makes a hosted Edge Admin tier viable as a commercial product without a hyperscaler reselling it the next day.

What this means in practice:

- **Allowed without asking us:** self-hosting for your own company, using it internally to manage your own fleet, using it as a tool while delivering services to your clients (MSP / consulting / IoT vendor patterns), modifying it, redistributing modified versions under ELv2, building products on top of it that aren't themselves "Edge Admin in the cloud."
- **Requires a commercial license from us:** offering Edge Admin (or a thin wrapper around it) as a hosted SaaS that customers sign up for and use directly.

Email **<licensing@wenet-ec.com>** if your use case needs a commercial license, or if you're not sure whether what you want to build falls inside or outside ELv2 — we'll tell you, and we're not looking to be difficult about it.

Contributions are welcome. See [`CONTRIBUTING.md`](https://github.com/wenet-ec/edge-core/blob/main/CONTRIBUTING.md) for the contribution flow and the Developer Certificate of Origin (DCO) sign-off we require on every commit.

Copyright © 2026 WENET VIETNAM JOINT STOCK COMPANY. "Edge Core", "Edge Admin", "Edge Agent", "Nexmaker", "Wenet", and "Wenetec" are trademarks of WENET VIETNAM JOINT STOCK COMPANY. The licenses above grant rights to the software only — not to the trademarks.
