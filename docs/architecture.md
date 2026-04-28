# Edge Core — Architecture

**Updated: 2026-03-18**

Edge Core is an infrastructure management platform for geographically distributed edge machines. It gives you centralized control over remote nodes through a secure VPN mesh — running commands, accessing machines via SSH, proxying traffic through them, and scraping their metrics — all through a simple HTTP API.

---

## Functionalities and Connectivity

Edge Core is organized around two groups — functional capabilities and connectivity layers.

### Functionalities

**1. Remote Command Execution**

Run shell commands across hundreds of machines from a single API call. Commands are distributed to target nodes, executed in parallel, and results are collected back centrally. Supports both shell and exec modes. Works in real-time over VPN (Layer 1/2) or with eventual consistency when only HTTP polling is available (Layer 3, ~60s latency).

**2. SSH Backdoor**

SSH access to any edge node as a first-class feature. Admin holds centralized SSH usernames, passwords, and public keys. Agents run an embedded SSH server on port 40022. Combined with the admin's forward proxy, you get full tunneled SSH access through the admin to any node in the mesh — without exposing any SSH port to the public internet.

**3. Metrics Aggregation**

Admin instances act as Prometheus-compatible aggregators. Scrapers collect host, agent, and WireGuard metrics from all nodes through the admin's service discovery endpoints — without needing direct network access to each node. Metrics are proxied on demand (Layer 1/2) or served from a local cache pushed by agents (Layer 3).

### Connectivity

**4. Cloud ↔ Edge (Forward Proxy + Proxy Chaining)**

Admin runs HTTP (port 43128) and SOCKS5 (port 41080) forward proxies. Because SOCKS5 supports any TCP connection, this covers any protocol — not just HTTP. Two modes: route directly to a VPN node (Mode 1, username `_`), or chain through a specific agent as the exit node to reach internet or LAN targets from that agent's network location (Mode 2, proxy chaining). No MQTT, no WebSocket — raw TCP over the VPN. In production, a HAProxy instance load-balances proxy traffic across all admin instances.

**5. Edge ↔ Edge (VPN Mesh)**

All nodes in the same cluster form a full WireGuard mesh via Netmaker. Every node can reach every other node directly, P2P, without routing through a central gateway. This is the transport layer that everything else runs on. Three-layer fallback handles adverse network conditions: raw WireGuard UDP → DERP relay (symmetric NAT) → HTTP polling (last resort). See [Admin ↔ Agent Communication](#admin--agent-communication) for detail.

**6. Edge ↔ Local Devices / End Users (Local Network Discovery)**

This covers how edge nodes make themselves discoverable and accessible to devices on the same LAN — without requiring those devices to join the VPN.

**What is supported today:** Agents advertise themselves via mDNS (Multicast DNS). A node's `mdns_hostname` is resolved by any device on the same local network using standard zero-conf discovery (Bonjour/Avahi). No configuration needed on the local device side.

**What is not in scope (and why):** Full LAN DNS control — running a DNS server that authoritative-answers for local devices, intercepting local traffic, or acting as a LAN gateway — is architecturally feasible but deliberately out of scope for now. LAN networks are heterogeneous and largely outside our control: corporate networks have existing DNS policies, home routers have varying DNS behavior, and managing DNS conflicts across different environments is a reliability problem we are not ready to take on responsibly. We would rather support mDNS well and expand carefully than break existing LAN setups. If you need full LAN DNS integration, the agent's local IP and mDNS hostname are stable enough to configure your own DNS server to point at.

**Future direction:** A managed in-agent DNS server that resolves `.edge.local` names for local clients is a natural next step, gated on having a reliable way to co-exist with existing LAN DNS without conflict.

---

## Component Overview

```
┌─────────────────────────────────────────────────────┐
│                   Cloud Server                       │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐                   │
│  │  Edge Admin │  │  Edge Admin │  ← peer cluster A  │
│  │     (a1)    │  │     (a2)    │                   │
│  └──────┬──────┘  └──────┬──────┘                   │
│         └────────────────┘                          │
│              Erlang distribution                     │
│              Shared PostgreSQL                       │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │           Netmaker VPN Stack                  │   │
│  │       Netmaker API + EMQX/Mosquitto           │   │
│  └──────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────┘
                         │ WireGuard mesh (via netclient)
              ┌──────────┴──────────┐
              │                     │
   ┌──────────▼──────────┐  ┌──────▼────────────┐
   │     Edge Agent       │  │    Edge Agent      │
   │   (edge node 1)      │  │  (edge node 2)     │
   │  network_mode: host  │  │ network_mode: host │
   └──────────────────────┘  └────────────────────┘
```

---

## VPN Layer

The VPN is the foundation everything else is built on. It creates a secure mesh between all components — admins and agents — so they can communicate using stable internal DNS names without exposing ports to the public internet.

### Netmaker

Netmaker manages the WireGuard mesh. Each edge cluster maps to a dedicated Netmaker network named `cluster-{cluster_name}`. Admin instances join multiple networks: their own admin cluster network plus every edge cluster they manage.

DNS identities follow a consistent pattern:

- Admin: `admin-{id}.admin-cluster-{admin_cluster_name}.nm.internal`
- Node: `node-{id}.cluster-{cluster_name}.nm.internal`

Cluster sizing is intentionally limited. WireGuard mesh is O(n²) — 100 nodes means ~5,000 peer connections. Clusters are capped at 50–100 nodes; horizontal scale comes from more clusters, not bigger ones.

### Broker: EMQX (standard) / Mosquitto (lite)

The MQTT broker is Netmaker infrastructure — it handles communication between the Netmaker server and netclient agents running inside each Edge Agent container. It is not part of Edge Admin or Edge Agent application code. EMQX is recommended for production (supports clustering); Mosquitto is simpler and sufficient for small deployments.

### DNS (netclient-local, post-CoreDNS)

`.nm.internal` VPN hostnames are resolved by netclient itself, not by a separate CoreDNS container. Starting in Netmaker `v1.5.1` (rebuilt upstream 2026-04-23), the server-side CoreDNS helper was removed — Netmaker no longer writes `Corefile` / `netmaker.hosts` to a shared volume. Instead, nameserver records live in Netmaker's `schema.Nameserver` table and are pushed to each host in the `DnsNameservers` field of the `HostPeerUpdate` / `HostPull` payloads (MQTT + HTTP pull).

Each netclient daemon binds a UDP DNS listener on its own VPN IP, port 53, and configures the host's resolver (via `systemd-resolved`, `resolvconf`, or direct `/etc/resolv.conf` writes depending on flavor) to point at itself. Admin-to-admin clustering (Erlang distribution using FQDNs like `admin-<id>.admin-cluster-a.nm.internal`) and admin-to-node HTTP (`node-<id>.cluster-<name>.nm.internal`) both flow through this local resolver.

This is gated on `ManageDNS=true` in the Netmaker server config, which is enabled by setting `DNS_MODE=on` in `.edge_vpn`. Leave it on — flipping it off disables the listener and breaks VPN hostname resolution entirely.

### netclient

netclient is the WireGuard client bundled inside the Edge Agent container. It handles VPN enrollment, peer management, the local DNS listener described above, and — critically — transparent DERP relay fallback when direct UDP is blocked. Edge Agent is built on top of our fork of netclient (`github.com/wenet-ec/netclient`, branch `v1.5.1-derp`) which adds DERP relay support and an HTTP scheme override for local development.

---

## Nexmaker

Nexmaker is the shared Elixir library that abstracts all interaction with the Netmaker/netclient layer. Both Edge Admin and Edge Agent depend on it as a local path dependency (`{:nexmaker, path: "../nexmaker"}`). Neither Admin nor Agent ever call Netmaker or netclient directly — everything goes through Nexmaker.

It has two distinct interfaces:

### `Nexmaker.Api.*` — Netmaker REST API

HTTP client built on `Req`. All requests use MASTER_KEY bearer token auth. Covers the full Netmaker API surface:

| Module                         | Responsibility                                         |
| ------------------------------ | ------------------------------------------------------ |
| `Nexmaker.Api.Networks`        | Create/delete/list VPN networks (one per edge cluster) |
| `Nexmaker.Api.EnrollmentKeys`  | Create enrollment keys for agent bootstrapping         |
| `Nexmaker.Api.Hosts`           | Manage physical host registrations                     |
| `Nexmaker.Api.Nodes`           | Manage node memberships within networks                |
| `Nexmaker.Api.DNS`             | Create/delete DNS entries (`.nm.internal`)             |
| `Nexmaker.Api.Superadmin`      | Bootstrap Netmaker admin account on first run          |
| `Nexmaker.Api.Server`          | Server status, info, public IP, log retrieval          |
| `Nexmaker.Api.Gateways.*`      | Ingress, egress, relay gateway management              |
| `Nexmaker.Api.Acls`            | ACL policy management                                  |
| `Nexmaker.Api.AdvancedEgress`  | Advanced egress gateway configuration                  |
| `Nexmaker.Api.InternetGateway` | Internet gateway management                            |
| `Nexmaker.Api.ExternalClients` | External (non-netclient) WireGuard client management   |
| `Nexmaker.Api.EMQX`            | EMQX broker provisioning (Netmaker-internal use)       |

Config is read from application env or passed per-call:

```elixir
config :nexmaker,
  base_url: System.get_env("NETMAKER_API_URL"),
  master_key: System.get_env("NETMAKER_MASTER_KEY")
```

### `Nexmaker.Cli` — netclient CLI wrapper

Thin wrapper around the `netclient` binary (which must be present in the container). Handles VPN lifecycle operations by shelling out to the CLI:

| Function                    | What it does                                                                                                    |
| --------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `join_network/1`            | Enroll this host into a VPN network using an enrollment token                                                   |
| `leave_network/1`           | Remove this host from a network                                                                                 |
| `list_networks/0`           | List all networks this host is joined to (shells out to `netclient list`)                                       |
| `read_nodes/0`              | Read network state directly from `/etc/netclient/nodes.json` — fast, no subprocess                              |
| `check_connection/1`        | Check connection status for a specific network                                                                  |
| `wireguard_interface_up?/0` | Check whether the `netmaker` WireGuard interface exists in `/proc/net/dev`                                      |
| `health_check/0`            | Health check via `read_nodes/0` + `wireguard_interface_up?/0`: returns `:healthy`, `:degraded`, or `:unhealthy` |
| `pull/0`                    | Force-pull latest config from Netmaker server (triggers full WireGuard interface restart)                       |
| `list_peers/1`              | List WireGuard peer details                                                                                     |
| `ping_peers/1`              | Ping peers through WireGuard tunnel, check connectivity and latency                                             |

---

## Edge Admin

Edge Admin is an Elixir/Phoenix application. It is the control plane — it owns the database, orchestrates command execution, manages SSH credentials, and runs the forward proxy.

### Deployment

Admin runs containerized, always. It uses `wireguard-go` (userspace WireGuard) inside the container. Kernel-mode WireGuard is not supported in the containerized admin — `wireguard-go` is required. Bare-metal admin is untested and not a supported path.

### Erlang Peer Clustering

Multiple admin instances within the same admin cluster connect to each other via Erlang distribution, using their VPN DNS names as Erlang node names:

```
admin@admin-abc123.admin-cluster-a.nm.internal
```

This is **peer-to-peer, masterless**. There is no leader election, no primary, no replica. Every admin instance is equal. They coordinate through:

- **`:syn` distributed registry** — two scopes: `:admin_scope` (who is in the cluster, what capacity) and `:cluster_scope` (which admin's Gateway GenServer owns which edge cluster)
- **ETS** — local in-memory cache of topology, intentionally ephemeral. Dies with the process, forcing clean recomputation from PostgreSQL on restart. Mnesia is explicitly avoided — its persistence creates split-brain complications.
- **PostgreSQL** — the only source of truth. All persistent state lives here.

Erlang distribution is **intra-cluster only** (admins within the same peer cluster). Different admin clusters do not connect to each other via Erlang distribution at all — they only share the PostgreSQL database.

### Cluster Ownership Sharding

WireGuard mesh overhead makes it expensive for multiple admins to all join the same edge cluster. The one-admin-per-cluster algorithm ensures exactly one admin manages each edge cluster at any time.

How it works:

- Each admin maintains a local ETS table of the current topology (who owns what, remaining capacity)
- When topology changes (admin joins or leaves, node counts shift), every admin independently runs the **same deterministic algorithm** on the same inputs — no coordination round needed
- Assignment is computed from scratch each time, with one continuity hint: clusters sorted by size descending, each assigned to the best available admin scored by (fewest clusters managed, then highest remaining capacity, then previous owner wins at ties, then admin ID as final tiebreaker). The previous-owner key keeps reassignment rate near the theoretical minimum on topology change without overriding load balance or capacity
- Clusters that exceed total system capacity become orphaned (tracked separately, not assigned to any admin)
- On admin failure: surviving peers detect the disconnect via `:syn`, recompute assignments from scratch, and pick up the orphaned or previously-assigned clusters naturally through the same algorithm

Replication is achieved not by replicating state within a cluster, but by **spinning up a second independent admin cluster** sharing the same PostgreSQL database. The two clusters are completely independent federations — no Erlang distribution between them, no `:syn` visibility across the boundary.

### Scaling Dimensions

```
Same admin cluster (A1 + A2):
  → More sharding capacity, more WireGuard partitioning
  → Share :syn state, Erlang distribution, coordinate via one-admin-per-cluster
  → Heals if one peer goes down

Multiple admin clusters (cluster A + cluster B):
  → More HA, geographic separation
  → Completely independent — share only PostgreSQL
  → No coordination between clusters
```

### Forward Proxy

Admin runs two Ranch-based forward proxies — HTTP (port 43128) and SOCKS5 (port 41080). Both converge to raw bidirectional TCP streaming after their protocol handshake.

Two proxy modes:

- **Mode 1** (username `_`): Admin routes directly to a VPN node. Used to reach services inside the mesh.
- **Mode 2** (username = node DNS hostname): Admin chains through a specific agent as the exit node. The agent opens the final TCP connection. Used to reach internet targets via an agent's network location.

Cross-admin routing is transparent: a client connecting to any admin proxy gets correctly routed to the agent it wants, regardless of which admin owns that cluster. `Gateway.lookup/1` uses `:syn.lookup` to resolve the Gateway PID for the owning admin — Erlang distribution then routes the subsequent `GenServer.call` transparently to whichever node that PID lives on. Local connections (Gateway on same node as caller) use zero-copy socket ownership transfer via `:gen_tcp.controlling_process/2`; remote connections spawn a `RemoteTunnel` proxy process on the Gateway node that forwards data back to the caller via Erlang distribution messages.

Admin never acts as an exit node — only agents can. This prevents SSRF.

---

## Edge Agent

Edge Agent is a standalone binary that runs on each edge machine. The primary deployment model is one agent per physical machine using `network_mode: host`.

The standard deployment requires:

- `network_mode: host` — agent shares the host network namespace; required so netclient can manage WireGuard interfaces on the host, and so the proxy and SSH server are reachable without port mapping
- `pid: host` — agent shares the host PID namespace; required for certain Linux system tools and commands that do not function correctly inside an isolated PID namespace
- `privileged: true` — required for WireGuard interface creation, routing rule manipulation (`ip rule`), and kernel module management (`rmmod wireguard`)
- `/etc/resolv.conf:/etc/resolv.conf:rw` — netclient modifies the host's `resolv.conf` to inject VPN DNS on join and restores it on clean shutdown; needs write access to the host file, not a copy
- `/:/host:ro` — mounts the host filesystem read-only so the Prometheus node exporter can read host proc/sys stats rather than container-scoped ones
- `/run/dbus/system_bus_socket:/run/dbus/system_bus_socket:ro` — required on systems running `systemd-resolved`; netclient communicates with `systemd-resolved` over D-Bus to configure VPN DNS correctly

### Sidecar deployment

The agent also works as a sidecar container on bridge networking (no `network_mode: host`). In this mode it runs in the pod's or container's network namespace rather than the host's. This was not the original design intent but has been tested and works.

What you get from a sidecar agent:

- **VPN mesh access** — the pod/container joins the WireGuard mesh
- **Proxy servers** — HTTP/SOCKS5 proxy accessible at `localhost` from other containers in the same pod
- **SSH access** — SSH into the pod's network namespace

What doesn't apply in sidecar mode:

- **Command execution** — commands run inside the agent container, not the application container
- **Host metrics** — reflects the container's view, not the host machine

Requirements for sidecar mode (same as host mode minus `network_mode: host`):

- `USE_RANDOM_ID=true` — avoids identity collisions when multiple sidecars run on the same node (host-derived identity is not meaningful in a container)
- `cap_add: [NET_ADMIN, SYS_MODULE]`
- `sysctls: net.ipv4.ip_forward=1, net.ipv4.conf.all.src_valid_mark=1, net.ipv6.conf.all.forwarding=1`
- `/dev/net/tun:/dev/net/tun` — required for wireguard-go to create a TUN interface

See `examples/sidecar/` for a ready-to-use Docker Compose example.

### What the Agent Contains

The agent is more than a process runner. It bundles:

- **Elixir/Phoenix HTTP API** — receives commands from admin, reports results and health
- **netclient** — WireGuard VPN client, handles mesh enrollment and connectivity
- **Prometheus node exporter** — exposes host metrics (CPU, memory, disk, network) on port 49100
- **WireGuard metrics exporter** — exposes peer/interface metrics on port 49586
- **Embedded SSH server** — Erlang `:ssh` server on port 40022, with centralized key management via admin
- **HTTP + SOCKS5 forward proxy** — same dual-protocol proxy as admin (ports 43128 / 41080)
- **Oban background workers** — async job processing for commands, health reporting, polling

The agent is currently implemented in Elixir but the interface is purely HTTP — it could be reimplemented in any language.

### Self-Updates

Agents update themselves via Watchtower. Two delivery paths, mirroring the broader Layer 1/2 vs Layer 3 split:

**Push (VPN up):** Admin creates a self-update request; `SelfUpdateTriggerWorker` pushes it directly to each targeted agent's HTTP API over VPN; the agent calls Watchtower's HTTP API to pull the new image and recreate the container.

**Pull (VPN down, HTTP fallback):** `CheckSelfUpdateWorker` runs every 2 hours and polls the admin's HTTP fallback URL for pending self-update requests. Only activates when VPN discovery returns no admins, a fallback URL is configured, and self-update is enabled — same guard pattern as the other Layer 3 workers.

Watchtower tracks the `:stable` tag — this is why the agent image is always pinned to `stable`, not a version tag.

---

## Admin ↔ Agent Communication

Communication between admin and agent is **HTTP over the VPN**. The VPN DNS name and a per-node API token are all that's needed. There is no Erlang distribution to agents — agents are not Erlang nodes.

```
Admin → Agent:  POST  http://node-{id}.cluster-{cluster_name}.nm.internal:44000/api/command_executions
Agent → Admin:  PATCH http://admin-{id}.cluster-{cluster_name}.nm.internal:44000/api/agents/command_executions/:id
                POST  http://admin-{id}.cluster-{cluster_name}.nm.internal:44000/api/agents/nodes/me/health_check
```

### Connectivity Fallback Layers

The system degrades gracefully when network conditions deteriorate:

```
Layer 1: Raw WireGuard UDP     ← Direct P2P, lowest latency        ✅ Production
    ↓ UDP blocked / symmetric NAT
Layer 2: DERP Relay            ← WireGuard over relay, transparent  ✅ Production
    ↓ Netmaker/WireGuard stack completely down
Layer 3: HTTP Polling          ← Agent polls admin, eventual        ✅ Production
```

**Layer 1 — Raw WireGuard:** Standard operation. Admin pushes to agent, scrapes metrics, opens proxy and SSH connections. Full feature support, sub-100ms latency.

**Layer 2 — DERP/TURN Relay:** When direct UDP fails (symmetric NAT, ISP UDP blocking), netclient transparently routes WireGuard packets through a relay server. The relay protocol is DERP (Designated Encrypted Relay for Packets) — Tailscale's open-source relay protocol, conceptually similar to TURN/coturn but designed specifically for WireGuard tunnels and operating over HTTPS/TCP port 443. This is entirely inside the netclient binary — the Elixir application sees no difference. VPN DNS names, IPs, and HTTP communication are all unchanged. Proxy and SSH continue to work. For HA, self-hosted DERP nodes can be added alongside Tailscale's public DERP servers; DERP is stateless and cheap to run.

Only `wireguard-go` (userspace) supports DERP relay. Kernel-mode WireGuard does not. Admin always uses `wireguard-go`. Agent can use kernel-mode WireGuard for maximum performance, but this disables DERP fallback.

**Layer 3 — HTTP Polling:** When the VPN is completely down, agents poll the admin HTTP API directly via `FALLBACK_ADMIN_URLS`. This is unidirectional (agent → admin only) and eventually consistent. Commands are fetched every 2 minutes, health and metrics pushed on the same interval.

| Feature           | Layer 1 + 2  | Layer 3 (HTTP polling)     |
| ----------------- | ------------ | -------------------------- |
| Command execution | ✅ real-time | ✅ 0–120s latency          |
| Health reporting  | ✅ real-time | ✅ 0–120s latency          |
| Metrics           | ✅ real-time | ✅ cached, ~5min staleness |
| Proxy servers     | ✅           | ❌ requires VPN            |
| SSH access        | ✅           | ❌ requires VPN            |

Proxy and SSH have no fallback below Layer 2. Both require raw TCP streaming — the correct answer for better availability is more DERP nodes, not a new relay mechanism.

---

## Event Broker

Edge Admin can publish lifecycle events to an external message broker — opt-in, disabled by default, broker deployed separately.

Events span three domains: node lifecycle (registered, status changed, deleted, etc.), command execution lifecycle (created → sent → completed/cancelled/expired), and self-update request lifecycle. All events follow [CloudEvents 1.0](https://cloudevents.io) and carry a full object snapshot in `data`.

Four adapters: `nats` (NATS — pub/sub by default, set `EVENT_BROKER_NATS_JETSTREAM=true` for durable log), `kafka` (any Kafka-compatible broker — Redpanda, Kafka, Confluent Cloud, etc.), `rabbitmq` (topic exchange, routing key = event type), and `redis` (fire-and-forget pub/sub, no persistence). Pick the broker that matches your semantics — there is no recommended default.

The `type` field in the envelope doubles as the NATS subject, RabbitMQ routing key, and Redis channel (`edge.node.status_changed`, `edge.execution.completed`, etc.) — no parsing needed for broker-level filtering.

Duplicate events are possible for `edge.node.status_changed` — the health check runs on every admin instance independently (masterless design). Each duplicate carries a different `id` (UUID4 generated per enqueue), so `id` is not a dedup key here. Consumers dedup by comparing `(node_id, previous_status, status)` and discarding events whose `time` is not newer than the last processed event for that node.

For the full event schema and subject/topic reference see [`docs/admin-asyncapi-v0.2.0.md`](admin-asyncapi-v0.2.0.md). Interactive viewer at `/asyncdoc` on a running admin.

---

## AI / MCP Interface

Edge Admin exposes a [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server at `POST /mcp` alongside the REST API. This gives AI assistants (Claude, Cursor, etc.) direct, structured access to the full infrastructure management surface — the same operations available through the REST API, but designed for AI consumption rather than human HTTP clients.

### Transport

Streamable HTTP (MCP standard). Any MCP-compatible client connects by pointing at the admin's `/mcp` endpoint with an `Authorization: Bearer` header.

### Authentication

Accepts `MCP_KEY` bearer token or falls back to `MASTER_KEY`. Auth is handled by `EdgeAdminWeb.Plugs.McpAuth` before Anubis processes the request.

### Tool Discovery

MCP clients discover available tools dynamically via the standard `tools/list` method — no static spec file. This is the MCP equivalent of `/api/openapi`. Call `POST /mcp` with `{"method": "tools/list"}` to get the full tool list with input schemas.

### Tool Surface

The MCP tool surface mirrors the REST API — anything you can do via the REST API you can do via MCP. Tools are grouped by domain: admin info, clusters, nodes, aliases, enrollment keys, commands, command executions, SSH credentials, self-updates, and metrics. `check_admin_health` is MCP-only: it runs all subsystem checks (Database, Membership, Metadata, Netmaker API, Netclient VPN, Proxy Servers) in parallel and returns a structured pass/fail per component — useful for diagnosing enrollment or connectivity failures from an AI assistant.

For the current tool list with full input schemas, call `tools/list` on a running admin — that is always authoritative.

### Proxy Access

The admin's HTTP proxy (port 43128) and SOCKS5 proxy (port 41080) are independent of MCP but complement it. An AI client configured to route its own HTTP requests through the proxy can reach any service on any VPN-connected node or its local network — without any MCP tool call. Configure the proxy URL once at the client level using the `PROXY_KEY` credential; the AI then has unrestricted HTTP access to the entire edge mesh.

---

## Authentication

| Path                     | Mechanism                                                                       |
| ------------------------ | ------------------------------------------------------------------------------- |
| Admin API (full access)  | `MASTER_KEY` bearer token                                                       |
| Admin API (REST only)    | `API_KEY` bearer token (defaults to `MASTER_KEY`)                               |
| Admin API (metrics only) | `METRICS_KEY` bearer token (defaults to `MASTER_KEY`)                           |
| Admin API (proxy only)   | `PROXY_KEY` bearer token (defaults to `MASTER_KEY`)                             |
| Admin API (MCP only)     | `MCP_KEY` bearer token (defaults to `MASTER_KEY`)                               |
| Admin → Netmaker         | `MASTER_KEY` bearer token                                                       |
| Agent → Admin            | Per-node API token (issued at enrollment)                                       |
| Admin → Agent            | Per-node API token (same token, stored in admin DB)                             |
| Admin ↔ Admin (Erlang)   | Shared `VPN_CLUSTER_COOKIE` + connection verified against PostgreSQL + Netmaker |
| SSH                      | Username/password or public key, verified by admin on each connection attempt   |

---

## Port Reference

| Service                 | Port    | Notes                                        |
| ----------------------- | ------- | -------------------------------------------- |
| Admin HTTP API          | `44000` | External: `34000`, `34001`, ... per instance |
| Admin HTTP proxy        | `43128` |                                              |
| Admin SOCKS5 proxy      | `41080` |                                              |
| Agent HTTP API          | `44000` |                                              |
| Agent SSH server        | `40022` |                                              |
| Agent HTTP proxy        | `43128` |                                              |
| Agent SOCKS5 proxy      | `41080` |                                              |
| Agent host metrics      | `49100` | Prometheus node exporter                     |
| Agent WireGuard metrics | `49586` |                                              |

---

## Key Design Decisions

**PostgreSQL as the only source of truth.** Admins cache topology in ETS for fast reads but all persistent state is in PostgreSQL. ETS is intentionally ephemeral — it dies with the process and forces clean recomputation on restart. This eliminates the split-brain persistence problems that Mnesia creates.

**Deterministic coordination without a strong leader.** All admins run the same algorithm on the same PostgreSQL-sourced inputs and converge to identical cluster assignments independently. No leader election, no consensus round, no Raft. If a network partition splits admins, both partitions continue operating; duplicate work accumulates in PostgreSQL (idempotent, not corrupting); assignments reconcile on reconnect.

**Weak leader for LocalScheduler deduplication.** The LocalScheduler (Quantum) runs periodic jobs on every admin instance — that is its design. Some jobs (e.g. zombie admin cleanup) would produce wasteful duplicate work if every admin ran them. A **weak leader** is elected deterministically: the admin with the alphabetically first admin ID in the current topology. All admins compute this independently and agree without coordination. The weak leader runs the job; others skip it. Duplicate work is still possible during split brain and is acceptable — these jobs are idempotent. This is explicitly not a strong leader: no exactly-once guarantee, no consensus. If stronger semantics are ever needed, a `:strong_leader` concept can be introduced separately.

**HTTP for agent-admin, Erlang distribution for admin-admin.** Agents are simple HTTP services — no Erlang cookie, no epmd, no Node.connect. Erlang distribution complexity is justified only for admin coordination, where cross-admin proxy routing requires transparent process-to-process calls that would be awkward over HTTP.

**Ranch for the proxy, not Phoenix/Plug.** The proxy is raw TCP. Phoenix is HTTP-only. Ranch gives direct socket control with a clean acceptor pool model — exactly what bidirectional byte streaming needs.

**`:syn` over `:pg` for distributed registry.** Both are global process registries, but `:pg` (OTP's built-in) chooses consistency over availability and can become a bottleneck at scale. `:syn` chooses availability over consistency (strong eventual consistency), which is acceptable here since registration keys are unique by construction (one Gateway per cluster, one admin per name) and write throughput matters more than linearizability. `:syn` also supports scoped registries (`:admin_scope`, `:cluster_scope`), metadata attached to registrations, and cluster-wide callbacks on net splits — none of which `:pg` provides.

**DERP over custom WebSocket relay.** A scalable custom WebSocket relay for proxy/SSH would need relay nodes to mesh and forward between each other for any agent connected to a different node. That is DERP. DERP already solves this at the network layer, transparently, for all TCP streams. More DERP nodes for HA is the right answer.
