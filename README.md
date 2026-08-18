# Edge Core

[![CI](https://github.com/wenet-ec/edge-core/actions/workflows/local.yml/badge.svg?branch=develop)](https://github.com/wenet-ec/edge-core/actions/workflows/local.yml)
[![Build](https://github.com/wenet-ec/edge-core/actions/workflows/production.yml/badge.svg?branch=main)](https://github.com/wenet-ec/edge-core/actions/workflows/production.yml)
[![Docs](https://github.com/wenet-ec/edge-core/actions/workflows/docs.yml/badge.svg?branch=main)](https://github.com/wenet-ec/edge-core/actions/workflows/docs.yml)

**Self-hostable control plane for distributed Linux and Edge fleets — WireGuard mesh, SSH proxy, remote execution, Prometheus metrics, events, and MCP over one API.**

📖 **Docs:** [wenet-ec.github.io/edge-core](https://wenet-ec.github.io/edge-core/)

Edge Core manages Linux machines you do not physically touch: cloud VMs, on-premises servers, factory equipment, Raspberry Pis, homelab boxes, and IoT devices. It gives operators one place to connect to, observe, and operate those machines without exposing every host to the public internet.

Edge Admin coordinates the fleet as an operational hub-and-spoke system. It
owns the control-plane metadata and assigns each edge cluster to one Admin;
the owning Admin starts one in-process `VirtualGateway` for that cluster.
Agents in a cluster still communicate over their direct full-mesh WireGuard
network, while commands, metrics, SSH verification, and proxy operations are
coordinated through the responsible virtual gateway.

The name comes from our original edge-device use case, but **edge means any machine that is remote from the operator**. A VM in Frankfurt and a Raspberry Pi in a factory present the same control-plane problem; the difference is how hostile and unreliable the surrounding network can be.

## The edge version of a cloud control plane

Cloud providers made centralized machine management familiar: private networking, metrics, remote execution, SSH, updates, events, and automation APIs. Edge Core applies those same control-plane ideas to machines distributed across sites the operator does not fully control.

| Concern | Typical cloud environment | Edge Core |
| --- | --- | --- |
| Private connectivity | VPC or provider network | WireGuard mesh per cluster, with DERP and HTTP fallback |
| Remote operations | Provider API or automation runner | Per-node command executions from one API request |
| Interactive access | Provider console or reachable SSH | Centralized credentials plus HTTP/SOCKS5 proxy |
| Observability | Central metrics and service discovery | Host, Agent, and WireGuard metrics through Admin |
| Local network access | Usually inside the provider boundary | Proxy chaining through an Agent's LAN or internet path |
| Fleet updates and feedback | Image workflows, webhooks, job status | Agent self-updates, CloudEvents, webhooks, and brokers |
| Autonomous operations | API- and increasingly AI-driven | REST and MCP expose the same control surface |

The edge difference is the network and failure model: NAT, firewalls, UDP filtering, intermittent links, changing addresses, local-only services, and power outages. Edge Core treats resilient connectivity as part of the control plane instead of assuming it already exists.

Edge Core manages machines that already exist; it is not a general-purpose compute, storage, or region provider. The self-hostable Core is platform-agnostic. A hosted platform can add provisioning, deployment packages, tenancy, billing, and other cloud-style services above it without changing the Core contract.

## What it does

- **Remote command execution** — run shell commands across selected nodes and collect each result independently.
- **Centralized SSH** — manage usernames and public keys centrally, then reach nodes through the Admin proxy without exposing port 22.
- **Metrics aggregation** — collect host, Agent, and WireGuard metrics through Prometheus-compatible discovery and endpoints.
- **Self-updates** — coordinate Agent updates across a fleet from one API request.
- **VPN connectivity** — create isolated WireGuard meshes per cluster, with relay fallback for difficult NAT paths.
- **Proxying** — tunnel HTTP or arbitrary TCP traffic through a node, including access to that node's local network.
- **Lifecycle events** — publish CloudEvents through signed webhooks or a message broker instead of polling.
- **AI operations** — expose the REST management surface through MCP for compatible assistants and automation.

## Who is it for?

Edge Core is a good fit when you need to:

- manage Linux machines across factories, stores, offices, vehicles, homes, or multiple clouds;
- operate hosts behind NAT or firewalls without exposing SSH and application ports;
- collect metrics centrally without giving the monitoring system direct access to every node;
- automate fleet work while retaining per-node output, status, and lifecycle events; or
- self-host the control plane and build higher-level workflows on its API.

It is intentionally general Linux infrastructure management, not an operating system or device-management lock-in layer. Ansible, Tailscale/Headscale, cloud providers, and existing monitoring systems can complement it; Edge Core focuses on the connectivity and operational control plane between them.

## Architecture

```text
Cloud or self-hosted control plane
├── Edge Admin (one or more peers)
│   ├── REST API, OpenAPI, MCP, events, and metrics
│   ├── Cluster ownership and background operations
│   ├── One VirtualGateway per owned edge cluster
│   └── HTTP + SOCKS5 forward proxies
├── PostgreSQL (standard) or SQLite (lite)
└── Netmaker VPN stack

Distributed machines
└── Edge Agent (one per machine)
    ├── WireGuard netclient
    ├── Embedded SSH server and command execution
    ├── HTTP + SOCKS5 proxy
    └── Metrics exporters and diagnostics
```

Admin and Agent communicate over WireGuard when possible, fall back to DERP relay when direct UDP paths fail, and retain HTTP polling for eventual control during VPN outages. For the full design, see [`docs/architecture.md`](docs/architecture.md).

## Getting started

Everything runs through Docker Compose; no Elixir or Go installation is required on the host.

| Setup | Use it for | Start here |
| --- | --- | --- |
| **Lite** | Single admin, SQLite/Mosquitto, homelabs and small fleets | [`examples/lite/`](examples/lite/README.md) |
| **Standard** | PostgreSQL, multiple Admin peers, Prometheus, production HA | [`examples/standard/`](examples/standard/README.md) |

Each setup guide covers requirements, configuration, first enrollment, and upgrades. After starting Admin, use the [operator guide](docs/guide.md), the live `/` guide, and `/swaggerui` for day-to-day work.

## Compatibility and deployment notes

Admin is a containerized deployment target. Agent is a privileged, host-networked container and therefore depends on the host's networking, resolver, container runtime, and WireGuard support. Tested Agent hosts currently include Ubuntu 24.04/26.04, Debian 13, Rocky Linux 10 and RHEL-family hosts, and Alpine 3.24.

See the [operator guide](docs/guide.md) for host-specific notes, including `firewalld`, and the example guides for deployment requirements. The full architecture and operational contracts live in [`docs/architecture.md`](docs/architecture.md).

## Useful references

- [User and operator guide](docs/guide.md)
- [Architecture](docs/architecture.md)
- [OpenAPI reference](docs/openapi.md)
- [AsyncAPI event catalog](docs/admin-asyncapi-v0.2.0.md)
- [MCP tool catalog](docs/admin-mcp-v0.2.0.md)
- [Lite deployment](examples/lite/README.md)
- [Standard deployment](examples/standard/README.md)
- [Relay deployment](examples/relay/README.md)
- [Sidecar deployment](examples/sidecar/README.md)
- [Contributing](CONTRIBUTING.md)

## Components

| Directory | Description |
| --- | --- |
| `edge_admin/` | Phoenix control plane: REST, OpenAPI, AsyncAPI, MCP, proxies, and PostgreSQL/Oban operations |
| `edge_agent/` | Agent runtime: VPN, SSH, commands, proxies, metrics, diagnostics, and SQLite/Oban state |
| `nexmaker/` | Shared Netmaker API and netclient CLI library |
| `deploy/` | Local and production Docker Compose infrastructure |
| `examples/` | Lite, Standard, relay, sidecar, and event-broker deployments |

## License

Edge Core ships under multiple licenses; see [`LICENSE`](LICENSE) for the complete terms.

| Component | License | Posture |
| --- | --- | --- |
| Edge Agent | [Apache License 2.0](edge_agent/LICENSE) | Open source |
| Nexmaker | [Apache License 2.0](nexmaker/LICENSE) | Open source |
| Edge Admin | [Elastic License 2.0](edge_admin/LICENSE) | Source available |
| Examples, docs, deploy, and scripts | Apache License 2.0 unless otherwise stated | Open source |

You may self-host, modify, and use Edge Core internally or as part of your own services. The Elastic License restricts offering Edge Admin itself, or a thin wrapper around it, as a hosted service to third parties. Contact **<licensing@wenet-ec.com>** if your use case needs clarification or a commercial license.

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution flow and DCO requirements.
