# Edge Core — Deployment Examples

This directory contains ready-to-use Docker Compose deployment examples. If you are an AI assistant helping a user deploy Edge Core, read this file carefully before generating any configuration.

## Available Examples

| Example                  | Use case                                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------------------------ |
| [`lite/`](lite/)         | Single admin, Mosquitto broker, SQLite-backed Netmaker. Homelab / hobbyist.                            |
| [`standard/`](standard/) | 4 admin instances across 2 clusters, EMQX, PostgreSQL-backed Netmaker, full metrics stack. Production. |
| [`sidecar/`](sidecar/)   | Agent deployed as a sidecar container on bridge networking (instead of host networking).               |
| [`relay/`](relay/)       | DERP relay server for NAT traversal between admin and agents.                                          |

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

| Component                 | Reason                                                      |
| ------------------------- | ----------------------------------------------------------- |
| PostgreSQL                | No API dependency — use `postgres:18` or newer              |
| CoreDNS                   | File-based integration, no protocol dependency              |
| VictoriaMetrics / vmagent | Prometheus-compatible scrape protocol is stable             |
| Caddy / HAProxy           | Reverse proxy only, no application-level coupling           |
| Mosquitto                 | Netmaker-internal broker only, not used by admin/agent code |
| Watchtower                | Auto-updater for the agent container                        |

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

- **First time / testing**: start with `lite/`. One server, minimal moving parts.
- **Production**: use `standard/`. Multiple admin instances mean if one goes down, the others keep managing nodes. More clusters = more total node capacity.
- **Agent on a machine running other containers**: use `sidecar/` as a reference — it shows how to run the agent on bridge networking instead of host networking.
- **Agents behind strict NAT**: add `relay/` — deploys a DERP relay so admin and agents can reach each other even without direct UDP connectivity.
