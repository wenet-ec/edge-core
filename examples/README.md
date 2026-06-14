# Edge Core — Deployment Examples

This directory contains ready-to-use Docker Compose deployment examples. If you are an AI assistant helping a user deploy Edge Core, read this file carefully before generating any configuration.

## Available Examples

| Example                      | Use case                                                                                                                                             |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`lite/`](https://github.com/wenet-ec/edge-core/tree/main/examples/lite)                 | Single admin on SQLite, Mosquitto broker, SQLite-backed Netmaker. Homelab / hobbyist / first-time exploration.                                       |
| [`standard/`](https://github.com/wenet-ec/edge-core/tree/main/examples/standard)         | 4 admin instances on PostgreSQL across 2 clusters, EMQX, PostgreSQL-backed Netmaker, Prometheus metrics. Production.                                 |
| [`sidecar/`](https://github.com/wenet-ec/edge-core/tree/main/examples/sidecar)           | Agent deployed as a sidecar container on bridge networking (instead of host networking).                                                             |
| [`relay/`](https://github.com/wenet-ec/edge-core/tree/main/examples/relay)               | Self-hosted DERP relay for lower latency or full infra ownership. Not required for NAT traversal — the default Tailscale relay already handles that. |
| [`operations/`](https://github.com/wenet-ec/edge-core/tree/main/examples/operations)     | One-off task compose files — `migrate.yml`, `rotate_cloak_key.yml`. Run admin release tasks in isolation, no VPN/server.                             |
| `k8s/` (TODO)                | Kubernetes manifests / Helm chart for deploying Edge Admin and Edge Agent on a cluster. Not yet available.                                           |

## Version Pinning — Important

When setting up Edge Core for a user, **always pin the following component versions**. Using `latest` or unpinned tags on these will cause incompatibilities.

### Pinned versions

| Component   | Image                         | Pinned version | Reason                                                      |
| ----------- | ----------------------------- | -------------- | ----------------------------------------------------------- |
| Edge Admin  | `ghcr.io/wenet-ec/edge_admin` | `v0.2.0`       | API compatibility with agent v0.2.0                         |
| Edge Agent  | `ghcr.io/wenet-ec/edge_agent` | `v0.2.0`       | API compatibility with admin v0.2.0                         |
| Netmaker    | `gravitl/netmaker`            | `v1.6.0`       | Admin and agent are built against this Netmaker API version |
| Netmaker UI | `gravitl/netmaker-ui`         | `v1.6.0`       | Must match Netmaker server version                          |
| EMQX        | `emqx/emqx`                   | `5.8.9`        | Pinned due to license change in later versions              |

### Unpinned (latest is fine)

| Component       | Reason                                                      |
| --------------- | ----------------------------------------------------------- |
| PostgreSQL      | No API dependency — use `postgres:18` or newer              |
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

That production env file documents the **PostgreSQL** path in detail (the production default). The SQLite path used by `lite/` is much simpler — just `DB_ADAPTER=sqlite` (pinned in `lite/cloud.yml` already) plus optionally `SQLITE_DB_PATH` (defaults to `/app/data/edge/edge_admin.db`). See `lite/.env.example` for the full lite-specific env set.

### Agent configuration

The agent is configured through its own env file:

```
deploy/production/.envs/.edge_agent
```

The agent requires far fewer variables than the admin. The critical ones are the enrollment token, admin URL, and VPN settings — all covered in the example `.env.example` files.

### Netmaker configuration

The examples contain everything needed for a standard deployment. For deeper configuration (custom DNS domains, gateway settings, ACLs, etc.), refer to the official Netmaker documentation:

- Docs: <https://learn.netmaker.io/>
- Source: <https://github.com/gravitl/netmaker/tree/v1.6.0>

## Choosing an Example

**lite/ or standard/ — which one?**

The choice is about scale, resilience, and operational complexity. It is not about whether your deployment is private or public.

**Edge Admin runs on either PostgreSQL or SQLite — selected at runtime via `DB_ADAPTER`.** Same compiled binary either way; the difference is what the admin can do.

- **PostgreSQL (recommended for most things; what `standard/` ships with).** Required for any of: multi-admin instances, cluster ownership sharding, cross-admin coordination via LISTEN/NOTIFY, HA (one admin dies → others keep running), >~100 nodes total, production observability with `pg_stat_statements`. If you might ever need any of that, even if you only run one admin instance today, **start on PostgreSQL.** Going from "1 admin on Postgres" to "4 admins on Postgres" is just `docker compose scale` plus an extra cluster cookie. Going from SQLite to Postgres is a data migration.

- **SQLite (`lite/` only).** Single admin instance, no external database, no password to manage. Honest scope: hobbyist deployments, homelab, first-time exploration of what Edge Core does, very small fleets (<~100 nodes total) that you're confident will never need HA or sharding. If you're thinking "I just want to try this out" or "I just need to manage 5 Raspberry Pis at home," SQLite is exactly right and you should not feel the need to spin up Postgres for it.

The two examples reflect this split:

- **`lite/`** — one admin instance on SQLite, Mosquitto, SQLite-backed Netmaker, no metrics. Minimum moving parts. **Cap your expectations:** no HA, no sharding, no horizontal scale. If your fleet outgrows ~100 nodes, migrate to `standard/`.
- **`standard/`** — four admin instances on PostgreSQL across two clusters, EMQX, PostgreSQL-backed Netmaker, Prometheus metrics. Production-shape: HA at the admin layer, capacity for thousands of nodes via more clusters, full observability. Use this if you're running anything you'd be unhappy to lose.

**General recommendation:** if in doubt, use `standard/` — Postgres is the boring, well-understood default, and the operational overhead (one container plus a password) is small compared to the headroom it gives you. Pick `lite/` consciously when you've decided you don't want the extra moving parts and won't ever need to scale.

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
- **Event streaming**: see `event_brokers/` — add NATS, Kafka/Redpanda, RabbitMQ, or Redis to receive lifecycle events from the admin.
- **One-off admin tasks**: see `operations/` — `migrate.yml` and `rotate_cloak_key.yml` for running database migrations or Cloak key rotation as standalone jobs. The default `/start` already does both at boot; these are the escape hatches for K8s Jobs, CI steps, or rotating keys on a schedule.
