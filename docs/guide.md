# Edge Core — User Guide

This guide is for operators and integrators using a running Edge Admin. If you want to know **how it's built**, read [`architecture.md`](architecture.md). If you want to know **how to deploy it**, see [`../examples/`](../examples/). This file covers the day-to-day surface — what you click, call, and configure once an admin is up.

---

## 1. API surface and built-in UIs

The admin is **API-first**. Every management operation goes through HTTP — there is no separate web UI to install. The API ships with three built-in browser entry points:

| Path              | What it is                                                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `/swaggerui`      | **Primary UI.** Interactive Swagger UI — browse every endpoint, fill in parameters, hit "Try it out", see live responses.              |
| `/redoc`          | Same OpenAPI spec rendered as ReDoc — better for reading reference docs end-to-end.                                                    |
| `/live_dashboard` | Phoenix LiveDashboard — runtime introspection (BEAM processes, ETS, Oban queues, Ecto stats). Useful for debugging, not for daily ops. |
| `/asyncdoc`       | AsyncAPI viewer for the event catalog (see §7).                                                                                        |
| `/mcp`            | MCP server endpoint for AI assistants (see §4).                                                                                        |

**Day-to-day, you live in `/swaggerui`.** Everything in this guide can be done from there: list nodes, create commands, register webhooks, manage SSH credentials, generate enrollment keys. Anything not on Swagger is intentionally not part of the management API — typically because it's a health/metrics endpoint hit by infrastructure rather than a person.

The OpenAPI spec itself is at `GET /api/openapi` if you want to feed it into your own client generator.

---

## 2. Concepts

Edge Core has two conceptual domains: the **edge domain** (everything you actually manage) and **admin ops** (the control plane managing it). Most of the time you're in the edge domain.

### Edge domain

A linear graph — each resource builds on the previous one:

```
Cluster
  └─ Enrollment Key
       └─ Node
            ├─ Alias
            ├─ Metrics  (host / agent / wireguard)
            ├─ Command Execution  ← Command (one command → many executions)
            ├─ SSH Username / Public Key
            └─ Self-Update Request
```

**Cluster.** A logical group of nodes that form a single WireGuard mesh. Each cluster maps **1:1 to a Netmaker network**. You can supply your own subnet at creation time, or let the system generate one — but once created, the VPN IP plane is abstracted away. You don't deal in IPs; you deal in DNS names and node IDs.

Two opinionated design choices worth knowing up front:

- **No ACLs inside a cluster.** Every cluster is a **full mesh** — every node can reach every other node, period. We deliberately don't expose per-cluster ACLs. ACLs are a bandaid for clusters that grew too big; the right answer is to divide a large cluster into smaller ones along workload boundaries, not to gate traffic inside one. Design your clusters upfront by grouping machines that work together (divide and conquer). You can move a node from one cluster to another later, but think of clusters as your **trust + workload boundary**, not as a flat namespace you'll firewall later.
- **WireGuard mesh is O(n²).** A 100-node mesh is ~5,000 peer connections. We **advise** keeping a cluster at 50–100 nodes and growing horizontally via more clusters; we **don't enforce** a cap. The mesh-explosion ceiling is a physical constraint of WireGuard — you'll be forced to design around it eventually based on your workload, so it's better to plan for it from day one.

**Enrollment key.** A short-lived credential a fresh agent uses to join a specific cluster. You generate the key on the admin, configure it as `ENROLLMENT_TOKEN` on the agent, and the agent enrolls itself on first boot. Keys are cluster-scoped — one key per cluster.

**Node.** A single edge machine that has joined a cluster. Maps **1:1 to a physical machine** (or a VM, container host, etc. — anything running an agent). Once enrolled, every node in the same cluster can reach every other directly over WireGuard.

Nodes are addressed **only by VPN hostname**, never by IP:

```
node-{uuid}.{cluster_name}.<NETMAKER_DEFAULT_DOMAIN>
```

The agent does have a VPN IP underneath — Netmaker has to assign one — but **we do not expose it through the admin API and you should not rely on it**. Tracking IPs and keeping them in sync across enrollments, re-enrollments, cluster moves, and DERP fallbacks is the kind of bookkeeping that's a nightmare to get right; the hostname convention abstracts it away. Use `node-{uuid}.{cluster_name}.<DOMAIN>` (or its alias form, see below) everywhere — in commands, in proxy chaining usernames, in your own scripts.

From any node-A in `cluster-prod`, `ping node-B.cluster-prod.nm.internal` works out of the box. **Exactly one admin owns each cluster at a time** (cluster ownership sharding) — this is invisible to you, but it's why you don't see "which admin is talking to my node" anywhere in the API.

**Alias.** A friendly name for a node. Instead of `node-3f8a-…-deadbeef.cluster-prod.nm.internal`, you can give a node the alias `web-1` and reach it as `web-1.cluster-prod.nm.internal`. Pure convenience — aliases are 1:1 with nodes inside a cluster.

**Metrics.** Three families, each scraped from a different exporter on the agent:

- **Host** — CPU, memory, disk, network, load. Most useful, most relatable. From `node_exporter`.
- **Agent** — BEAM, Oban, command throughput, internal Phoenix metrics. From PromEx.
- **WireGuard** — peer endpoint, last handshake, bytes in/out, latency.

The admin exposes both Prometheus-scrape endpoints (raw, for Grafana / Prometheus) and human-friendly JSON endpoints (parsed, for dashboards or quick checks). Full detail in §6.

**Command.** A shell command you want to run on one or more nodes. You create a command with a target filter (`all`, specific cluster, specific node IDs, etc.), and the admin tracks delivery and results asynchronously. Commands are not synchronous — they are jobs.

**Command execution.** The actual unit of work. **One command fans out into one execution per targeted node.** Each execution has its own status (`pending`, `sent`, `completed`, `cancelled`, `expired`), output, exit code, and timing. `completed` is a single terminal status whether the command succeeded or failed — read `exit_code` to distinguish. When you "run a command on 50 nodes," you create 1 command and the system creates 50 executions.

**SSH username + public key.** Centralized SSH credentials. You register a username with one or more public keys on the admin; the agent's embedded SSH server (port 40022) verifies every connection attempt by calling the admin. **No host SSH is involved** — you're SSHing into the agent's own SSH server, not into port 22 on the host. This is normally combined with the proxy servers (§5) when you're outside the VPN: SOCKS5 to the admin, SSH through the tunnel into the agent.

**Self-update request.** A managed agent upgrade. Requires Watchtower running as a sidecar container next to the agent and the agent image pinned to the `:stable` tag. You create a self-update request via the admin; the admin pushes it to the targeted agents; each agent calls its local Watchtower, which pulls the latest `:stable` and recreates the container. The version "stable" is whatever we've most recently promoted — you don't choose specific versions through this path. (If you want pinned-version rollouts, manage your image tags directly.)

**Webhook.** See §7 — these are user-facing subscriptions to lifecycle events.

### Admin ops domain

The admin layer manages itself too: admin instances form peer clusters, share PostgreSQL, deterministically agree on which admin owns which edge cluster. Most of this is invisible to operators — it's described in [`architecture.md`](architecture.md). The day-to-day surface for it is:

- `GET /api/v1/admins/*` — list admins, see each admin's metadata, ownership assignments
- `/live_dashboard` — runtime view of every admin process
- `/health/cluster` — load-balancer-friendly cluster health (see §8)

You generally don't manage admin-side resources through the API — admins are spun up via your deploy system, joined automatically, and converge.

---

## 3. Authentication and keys

The admin uses bearer-token auth. There is one master key and four scoped keys; **all scoped keys default to MASTER_KEY if unset**, so a minimal deployment can start with just `MASTER_KEY` and split keys later as the deployment grows.

```env
# Full admin access — required.
MASTER_KEY=supersecretkey123456789

# Optional scoped keys. All default to MASTER_KEY if unset.
# API_KEY=      # REST API endpoints (nodes, commands, SSH, clusters, webhooks)
# METRICS_KEY=  # Read-only: metrics endpoints
# PROXY_KEY=    # Proxy tunnel endpoints (HTTP + SOCKS5)
# MCP_KEY=      # MCP server endpoint
```

Every API request needs `Authorization: Bearer <key>`. The agent gets its own per-node API token at enrollment — that's a separate identity used only for agent → admin reporting.

**Splitting keys is recommended for production.** A Prometheus scraper only needs `METRICS_KEY`; a CI script only needs `API_KEY`; an AI assistant only needs `MCP_KEY`. If any of those leak, you rotate just that key without touching the others.

---

## 4. MCP — AI assistant access

Edge Admin exposes a [Model Context Protocol](https://modelcontextprotocol.io) server at `POST /mcp`. **Every REST API operation has a corresponding MCP tool.** If you can do it on Swagger, you can do it from Claude Desktop, Cursor, or any MCP-compatible client.

Configure your client to point at:

```json
{
  "mcpServers": {
    "edge-admin": {
      "type": "http",
      "url": "http://your-server:<API_PORT>/mcp",
      "headers": { "Authorization": "Bearer <MCP_KEY>" }
    }
  }
}
```

Tools are discovered dynamically (`tools/list`) — no static spec to maintain. A few extras worth knowing:

- `check_admin_health` — runs every subsystem check (DB, membership, metadata, Netmaker, netclient, proxies, broker) in parallel and returns a structured pass/fail. Use when an AI assistant needs to diagnose enrollment or connectivity issues.
- `get_node_metrics` / `get_host_metrics` / `get_agent_metrics` / `get_admin_metrics` — human-friendly parsed metrics. Pair with the proxy (§5) if the assistant needs raw scrape access too.

---

## 5. Proxy servers

The admin runs two forward proxies on dedicated ports:

| Proxy  | Port    | Use                                   |
| ------ | ------- | ------------------------------------- |
| HTTP   | `43128` | Plain HTTP CONNECT proxy              |
| SOCKS5 | `41080` | Any TCP — HTTP, SSH, custom protocols |

Both authenticate with `username:password` where password is `PROXY_KEY`. The username determines the **mode**:

### Forward proxy (username `_`)

Routes traffic directly to a service on a VPN-connected node. Use this to reach anything running on any node in any cluster — node DNS is the destination.

```bash
# HTTP proxy
curl -x http://_:PROXY_KEY@admin-host:43128 http://node-abc.cluster-prod.nm.internal:8080/api/status

# SOCKS5
curl --socks5 _:PROXY_KEY@admin-host:41080 http://node-abc.cluster-prod.nm.internal:8080/

# SSH through SOCKS5 (requires ncat)
ssh -o ProxyCommand="ncat --proxy admin-host:41080 --proxy-type socks5 --proxy-auth _:PROXY_KEY %h %p" \
    admin@node-abc.cluster-prod.nm.internal -p 40022

# Set globally for all requests
export http_proxy=http://_:PROXY_KEY@admin-host:43128
```

Node DNS format: `node-{id}.cluster-{cluster_name}.<NETMAKER_DEFAULT_DOMAIN>`. List nodes via the API (or `list_nodes` MCP tool) to discover IDs and clusters.

### Proxy chaining (username = node DNS hostname)

Routes traffic through a specific agent as the **exit node**. Use this to reach an agent's local network (LAN devices behind it) or to reach the public internet from that agent's network location.

```bash
# Reach a device on the agent's LAN (e.g. a router at 192.168.1.1)
curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 http://192.168.1.1/

# Reach the internet via the agent's IP
curl -x http://node-abc.cluster-prod.nm.internal:PROXY_KEY@admin-host:43128 https://ifconfig.me
```

The admin itself never acts as an exit node — only agents can. This prevents the admin from being used as an open SSRF surface.

---

## 6. Metrics

The admin is a Prometheus-compatible aggregator: scrapers point at the admin, the admin handles service discovery and per-node fan-out. Auth: `METRICS_KEY` (or `MASTER_KEY`) bearer token on every endpoint.

### Service discovery (returns Prometheus HTTP SD targets, grouped per cluster)

```
GET /api/v1/nodes/metrics/host/discovery       — node_exporter targets (CPU, memory, disk, network)
GET /api/v1/nodes/metrics/agent/discovery      — agent PromEx targets (BEAM, Oban, command throughput)
GET /api/v1/nodes/metrics/wireguard/discovery  — WireGuard exporter targets (peer stats, handshakes, bytes)
```

Wire these into your Prometheus `scrape_configs` as `http_sd_configs` — Prometheus will discover all eligible nodes per cluster automatically.

### Per-node raw metrics proxy (Prometheus text format)

```
GET /api/v1/nodes/:node_id/metrics/host/raw
GET /api/v1/nodes/:node_id/metrics/agent/raw
GET /api/v1/nodes/:node_id/metrics/wireguard/raw
```

Useful for direct scraping of a single node, or for debugging — `curl` one of these and you'll see the raw Prometheus exposition exactly as it came off the node.

### Admin self-metrics

```
GET /api/v1/admins/me/metrics/raw
```

Each admin exposes its own metrics (BEAM, Phoenix, Oban, etc.). Add every admin instance as a Prometheus static target.

### Human-friendly JSON

```
GET /api/v1/nodes/:node_id/metrics             — unified (host + agent)
GET /api/v1/nodes/:node_id/metrics/host
GET /api/v1/nodes/:node_id/metrics/agent
GET /api/v1/admins/me/metrics
```

Parsed JSON, ready to feed into a dashboard or AI assistant. Same data the MCP `get_*_metrics` tools return.

A working `prometheus.yml` example lives at `deploy/production/compose/edge_metrics/prometheus.yml`.

---

## 7. Events — webhooks and brokers

Plenty of state changes in Edge Core happen asynchronously: a node finishes enrolling, a command execution completes, an SSH login is verified, a self-update finishes. Polling the API for these is wasteful — events let you subscribe instead.

**Start at `/asyncdoc`** on a running admin to see the full event catalog: every event type, its envelope, and example payloads. Events are CloudEvents 1.0.

You have **two delivery channels**, used independently:

### Webhooks (always available)

The simplest path. Register a webhook through the API:

```http
POST /api/v1/webhooks
{
  "url": "https://your-receiver.example.com/edge",
  "secret": "<random 32+ chars>",
  "subscribed_events": ["edge.node.registered", "edge.command_execution.completed"],
  "headers": { "X-Tenant": "prod" }
}
```

Each webhook is **immutable after create** — to change anything, delete and recreate. Each delivery is a `POST` with the CloudEvents envelope as the JSON body, signed with `X-Edge-Signature: sha256=<hex>` so receivers can verify integrity. Failures are retried up to `WEBHOOK_MAX_ATTEMPTS` (default 3) with exponential backoff, then dropped.

`subscribed_events` is an explicit allowlist — no wildcards, unknown event types are rejected at create time. This is intentional: adding new event types to the catalog never auto-expands existing subscriptions.

URLs are SSRF-checked at create time (loopback, RFC1918, link-local, cloud metadata IPs are blocked). Opt out per deployment with `WEBHOOK_ALLOW_PRIVATE_IPS=true` if you're on a homelab or dev network where receivers legitimately live on private IPs.

### Event broker (opt-in)

For higher-throughput or message-bus integration. Pick the broker that matches your stack, point the admin at it, and every event is published as a CloudEvents envelope on a subject/topic matching its `type` field (`edge.node.registered`, `edge.command_execution.completed`, etc.).

Supported adapters: NATS, Kafka/Redpanda, AMQP 0-9-1 (RabbitMQ / LavinMQ / etc.), Redis, MQTT, AWS SNS, Google Cloud Pub/Sub.

Configuration is two env vars plus an adapter-specific endpoint:

```env
EVENT_BROKER_ENABLED=true
EVENT_BROKER_ADAPTER=nats     # or: kafka, amqp091, redis, mqtt, aws_sns, google_pubsub
EVENT_BROKER_NATS_URLS=nats://your-broker:4222
```

Ready-to-use compose files for each broker live in [`../examples/event_brokers/`](../examples/event_brokers/).

**Webhooks and the broker run independently.** A broker outage doesn't affect webhook delivery and vice versa. You can use either, both, or neither.

---

## 8. Health checks

Three endpoints, all unauthenticated, served on the same port as the API. They are **not in the OpenAPI spec** — they exist for infrastructure (Kubernetes probes, load balancers) rather than humans.

| Endpoint          | Use                                                                                       |
| ----------------- | ----------------------------------------------------------------------------------------- |
| `/healthz`        | General health. 200 if every subsystem check passes, 503 otherwise.                       |
| `/readyz`         | Alias of `/healthz` — Kubernetes readiness probe.                                         |
| `/health/cluster` | Cluster-level health — used by load balancers to stop routing to degraded admin clusters. |
| `/health`         | Alias of `/healthz`.                                                                      |

Subsystem checks run on every call: database, peer membership, ownership metadata, Netmaker API, netclient VPN, proxy servers, event broker. Only the Netmaker check retries internally — the rest are single-shot with a 5-second timeout.

The cluster health endpoint is the right thing to point HAProxy / nginx / a cloud load balancer at — it returns degraded specifically when the admin cluster (not just one admin) is in trouble.

---

## A note on packaging

**The admin is not a standalone binary.** It always runs inside the published Docker image. This is partly about reproducibility — the image bundles netclient, the right WireGuard userspace implementation, locale data, and the OTP release — and partly about how we solve the WireGuard quadratic-scaling problem (the admin runs `wireguard-go` inside its container so kernel-mode constraints on the host don't matter).

**The agent is technically a standalone binary** — it's an OTP release that runs as a supervision tree — but it's better thought of as **an "edge OS" packaged as a container**. The agent image bundles everything an edge machine needs to be remotely controllable: the agent process itself, netclient (WireGuard), an SSH server, Prometheus exporters, forward proxies, and the supervision tree wiring it all together. For devices that can't run Docker / Compose today, this is what you'd burn to disk if Edge Core shipped a flashable OS image — and that's a plausible future direction. For now, shipping the kit as a container is the most portable, reproducible thing we can do.

The takeaway: when you deploy an agent, you're not deploying "an Elixir app" — you're deploying a small edge OS that happens to live inside a container.
