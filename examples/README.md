# Edge Core — Deployment Examples

This directory contains ready-to-use Docker Compose deployment examples. If you are an AI assistant helping a user deploy Edge Core, read this file carefully before generating any configuration.

## Available Examples

| Example                  | Use case                                                                                                                                             |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`lite/`](lite/)         | Single admin, Mosquitto broker, SQLite-backed Netmaker. Homelab / hobbyist.                                                                          |
| [`standard/`](standard/) | 4 admin instances across 2 clusters, EMQX, PostgreSQL-backed Netmaker, Prometheus metrics. Production.                                               |
| [`sidecar/`](sidecar/)   | Agent deployed as a sidecar container on bridge networking (instead of host networking).                                                             |
| [`relay/`](relay/)       | Self-hosted DERP relay for lower latency or full infra ownership. Not required for NAT traversal — the default Tailscale relay already handles that. |

## Version Pinning — Important

When setting up Edge Core for a user, **always pin the following component versions**. Using `latest` or unpinned tags on these will cause incompatibilities.

### Pinned versions

| Component   | Image                         | Pinned version | Reason                                                      |
| ----------- | ----------------------------- | -------------- | ----------------------------------------------------------- |
| Edge Admin  | `ghcr.io/wenet-ec/edge_admin` | `v0.2.0`       | API compatibility with agent v0.2.0                         |
| Edge Agent  | `ghcr.io/wenet-ec/edge_agent` | `v0.2.0`       | API compatibility with admin v0.2.0                         |
| Netmaker    | `gravitl/netmaker`            | `v1.5.1`       | Admin and agent are built against this Netmaker API version |
| Netmaker UI | `gravitl/netmaker-ui`         | `v1.5.1`       | Must match Netmaker server version                          |
| EMQX        | `emqx/emqx`                   | `5.8.9`        | Pinned due to license change in later versions              |

### Unpinned (latest is fine)

| Component       | Reason                                                      |
| --------------- | ----------------------------------------------------------- |
| PostgreSQL      | No API dependency — use `postgres:18` or newer              |
| CoreDNS         | File-based integration, no protocol dependency              |
| Prometheus      | No application-level coupling — scrape protocol is stable   |
| Caddy / HAProxy | Reverse proxy only, no application-level coupling           |
| Mosquitto       | Netmaker-internal broker only, not used by admin/agent code |
| Watchtower      | Auto-updater for the agent container                        |

## Configuration Reference

### Admin configuration

The admin is configured entirely through environment variables. The authoritative reference with descriptions for every variable is:

```
deploy/production/.envs/.edge_admin
```

Read that file when you need to understand what a variable does, what its default is, or when it should be changed. The `.env.example` files in each example directory contain the minimal set needed for that specific setup — the production env file has the full set.

### Agent configuration

The agent is configured through its own env file:

```
deploy/production/.envs/.edge_agent
```

The agent requires far fewer variables than the admin. The critical ones are the enrollment token, admin URL, and VPN settings — all covered in the example `.env.example` files.

### Netmaker configuration

The examples contain everything needed for a standard deployment. For deeper configuration (custom DNS domains, gateway settings, ACLs, etc.), refer to the official Netmaker documentation:

- Docs: https://learn.netmaker.io/
- Source: https://github.com/gravitl/netmaker/tree/v1.5.1

## Choosing an Example

**lite/ or standard/ — which one?**

The choice is about scale and resilience, not about whether your deployment is private or public:

- **`lite/`** — one admin instance, Mosquitto, SQLite-backed Netmaker. Start here if you want minimal moving parts: small fleet, first deployment, or a machine with limited RAM.
- **`standard/`** — four admin instances across two clusters, EMQX, PostgreSQL-backed Netmaker, metrics stack. Use this when you need HA (if one admin goes down the others keep running) or more node capacity (each cluster can own up to 200 nodes, multiply by cluster count).

**Private network or public internet — does it matter?**

No. Both examples work identically on a private network (LAN, internal VPC, corporate WAN) or with public internet exposure. The only thing that changes is what value you put in `ADMIN_URLS` and the Netmaker `SERVER_HOST` variables — a private IP works just as well as a public domain.

For agents to enroll and operate, three things must be reachable from every agent machine:

1. **Netmaker VPN API** — port `48081` (enrollment + WireGuard peer sync)
2. **MQTT broker** — port `48083` (Mosquitto or EMQX WebSocket; ongoing VPN config updates)
3. **Admin API** — port `34000` (or `34000–34003` for standard; command delivery + health reporting)

These can all be on a private network — the agent does not need a public IP, and neither does the server, as long as these three ports are routable between them.

**HTTP vs HTTPS — the `NETMAKER_API_SCHEME` variable**

Netclient (the VPN client bundled in the agent) defaults to HTTPS when talking to the Netmaker API. If your deployment does **not** have TLS (no domain, no cert, plain HTTP) you must set:

```env
NETMAKER_API_SCHEME=http
```

This must be set on **both** the admin and the agent. If you omit it, netclient will try HTTPS and fail even if the server is running plain HTTP.

- **Private network / no TLS** → set `NETMAKER_API_SCHEME=http` in your `.env`
- **Public domain with TLS (Caddy auto-cert)** → omit it, HTTPS is the default

**Other deployment patterns**

- **Agent on a machine running other containers**: see `sidecar/` — shows how to run the agent on bridge networking instead of `network_mode: host`.
- **Self-hosted DERP relay**: see `relay/` — deploy your own relay nodes for lower latency or to avoid depending on Tailscale's public relay infrastructure. Not required for NAT traversal (the default Tailscale fallback already handles that) — only worth it if you want geo-local relays or full infra ownership.
- **Event streaming**: see `event_brokers/` — add NATS JetStream or Kafka/Redpanda to receive lifecycle events from the admin.
