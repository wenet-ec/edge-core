# Edge Core — Architecture

**Updated: 2026-03-11**

Edge Core is an infrastructure management platform for geographically distributed edge machines. It gives you centralized control over remote nodes through a secure VPN mesh — running commands, accessing machines via SSH, proxying traffic through them, and scraping their metrics — all through a simple HTTP API.

---

## The Five Operating Principles

Everything Edge Core does flows from five core capabilities:

1. **Edge Mesh Network** — All nodes in the same edge cluster form a full WireGuard mesh. Every node can reach every other node directly, without routing through a central gateway.

2. **Remote Command Execution** — Run shell commands across hundreds of machines from a single API call. Commands are distributed, executed in parallel, and results are collected back centrally.

3. **SSH Backdoor** — SSH access to any edge node as a first-class feature. Admin holds centralized SSH keys and usernames; agents run an embedded SSH server. Combined with the proxy layer, you get full tunneled SSH access through the admin.

4. **Metrics Observability** — Admin instances act as aggregators. Prometheus-compatible scrapers can collect host, agent, and WireGuard metrics from all nodes through the admin's service discovery endpoints — without needing direct access to each node.

5. **Cloud-Edge Connectivity** — Admin runs HTTP and SOCKS5 forward proxies. Any TCP connection can be tunneled from the cloud side through an agent to reach the agent's local network. No MQTT brokers, no WebSocket — raw TCP proxy over the VPN.

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
│  │  Netmaker API + EMQX/Mosquitto + CoreDNS      │   │
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

Netmaker manages the WireGuard mesh. Each edge cluster maps to a dedicated Netmaker network named `cluster-{cluster_id}`. Admin instances join multiple networks: their own admin cluster network plus every edge cluster they manage.

DNS identities follow a consistent pattern:

- Admin: `admin-{id}.admin-cluster-{name}.nm.internal`
- Node: `node-{id}.cluster-{cluster_id}.nm.internal`

Cluster sizing is intentionally limited. WireGuard mesh is O(n²) — 100 nodes means ~5,000 peer connections. Clusters are capped at 50–100 nodes; horizontal scale comes from more clusters, not bigger ones.

### Broker: EMQX (standard) / Mosquitto (lite)

The MQTT broker is Netmaker infrastructure — it handles communication between the Netmaker server and netclient agents running inside each Edge Agent container. It is not part of Edge Admin or Edge Agent application code. EMQX is recommended for production (supports clustering); Mosquitto is simpler and sufficient for small deployments.

### CoreDNS

CoreDNS resolves `.nm.internal` VPN hostnames. Netmaker writes its node table to a shared volume that CoreDNS reads automatically. Admin and agent communicate using these DNS names over the WireGuard interface.

### netclient

netclient is the WireGuard client bundled inside the Edge Agent container. It handles VPN enrollment, peer management, and — critically — transparent DERP relay fallback when direct UDP is blocked. Edge Agent is built on top of our fork of netclient (`github.com/wenet-ec/netclient`, branch `v1.4.0-derp`) which adds DERP relay support and an HTTP scheme override for local development.

---

## Nexmaker

Nexmaker is the shared Elixir library that abstracts all interaction with the Netmaker/netclient layer. Both Edge Admin and Edge Agent depend on it as a local path dependency (`{:nexmaker, path: "../nexmaker"}`). Neither Admin nor Agent ever call Netmaker or netclient directly — everything goes through Nexmaker.

It has two distinct interfaces:

### `Nexmaker.Api.*` — Netmaker REST API

HTTP client built on `Req`. All requests use MASTER_KEY bearer token auth. Covers the full Netmaker API surface:

| Module                        | Responsibility                                         |
| ----------------------------- | ------------------------------------------------------ |
| `Nexmaker.Api.Networks`       | Create/delete/list VPN networks (one per edge cluster) |
| `Nexmaker.Api.EnrollmentKeys` | Create enrollment keys for agent bootstrapping         |
| `Nexmaker.Api.Hosts`          | Manage physical host registrations                     |
| `Nexmaker.Api.Nodes`          | Manage node memberships within networks                |
| `Nexmaker.Api.DNS`            | Create/delete DNS entries (`.nm.internal`)             |
| `Nexmaker.Api.Superadmin`     | Bootstrap Netmaker admin account on first run          |
| `Nexmaker.Api.Gateways.*`     | Ingress, egress, relay gateway management              |
| `Nexmaker.Api.EMQX`           | EMQX broker provisioning (Netmaker-internal use)       |

Config is read from application env or passed per-call:

```elixir
config :nexmaker,
  base_url: System.get_env("NETMAKER_API_URL"),
  master_key: System.get_env("NETMAKER_MASTER_KEY")
```

### `Nexmaker.Cli` — netclient CLI wrapper

Thin wrapper around the `netclient` binary (which must be present in the container). Handles VPN lifecycle operations by shelling out to the CLI:

| Function             | What it does                                                                       |
| -------------------- | ---------------------------------------------------------------------------------- |
| `join_network/1`     | Enroll this host into a VPN network using an enrollment token                      |
| `leave_network/1`    | Remove this host from a network                                                    |
| `list_networks/0`    | List all networks this host is currently joined to (reads local file, no API call) |
| `check_connection/1` | Check connection status for a specific network                                     |
| `health_check/1`     | Multi-layer health check: network membership → peer reachability                   |
| `pull/0`             | Force-pull latest config from Netmaker server                                      |
| `list_peers/1`       | List WireGuard peer details                                                        |
| `ping_peers/1`       | Ping peers through WireGuard tunnel, check connectivity and latency                |

**Known quirk — TOCTOU race condition:** netclient v1.4.0 has a race condition in `WriteJSONAtomic` where `/etc/netclient/` can be deleted between a directory check and file write. Nexmaker mitigates this with `ensure_netclient_dir/0` (pre-creates the dir before each call) and `run_with_retry/3` (exponential backoff retry on detection). This is handled transparently — callers don't need to worry about it.

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
- Assignment strategy: new clusters go to the admin with the most remaining capacity; overloaded admins shed their smallest clusters
- On admin failure: surviving peers detect the disconnect via `:syn`, recompute assignments, and absorb the orphaned clusters using greedy bin-packing (largest clusters first)

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

Cross-admin routing is transparent: a client connecting to any admin proxy gets correctly routed to the agent it wants, regardless of which admin owns that cluster. `:syn.call` routes the request to the correct Gateway GenServer, which may be on a different admin node. Local connections use zero-copy socket transfer; remote connections stream via Erlang distribution messages.

Admin never acts as an exit node — only agents can. This prevents SSRF.

---

## Edge Agent

Edge Agent is a standalone binary that runs on each edge machine. **One agent per machine** — this is the only supported deployment pattern. Multiple agents on the same machine is used for testing only.

The official deployment is `network_mode: host` with `privileged: true`, giving it full access to the host network interfaces — required for WireGuard tunnel management. It runs as a real infrastructure tool, not a sandboxed application.

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

Agents update themselves via Watchtower. Admin creates a self-update request; its `SelfUpdateTriggerWorker` calls each targeted agent's HTTP API; the agent calls Watchtower's HTTP API to pull the new image and recreate the container. Watchtower tracks the `:stable` tag — this is why the agent image is always pinned to `stable`, not a version tag.

---

## Admin ↔ Agent Communication

Communication between admin and agent is **HTTP over the VPN**. The VPN DNS name and a per-node API token are all that's needed. There is no Erlang distribution to agents — agents are not Erlang nodes.

```
Admin → Agent:  POST  http://node-{id}.cluster-{id}.nm.internal:44000/api/command_executions
Agent → Admin:  PATCH http://admin-{id}.cluster-{id}.nm.internal:44000/api/agents/command_executions/:id
                POST  http://admin-{id}.cluster-{id}.nm.internal:44000/api/agents/nodes/me/health_check
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

**Layer 2 — DERP Relay:** When direct UDP fails (symmetric NAT, ISP UDP blocking), netclient transparently routes WireGuard packets through DERP relay servers. This is entirely inside the netclient binary — the Elixir application sees no difference. VPN DNS names, IPs, and HTTP communication are all unchanged. Proxy and SSH continue to work. For HA, self-hosted DERP nodes can be added alongside Tailscale's public DERP servers; DERP is stateless and cheap to run.

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

## AI / MCP Interface

Edge Admin exposes a [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server at `POST /mcp` alongside the REST API. This gives AI assistants (Claude, Cursor, etc.) direct, structured access to the full infrastructure management surface — the same operations available through the REST API, but designed for AI consumption rather than human HTTP clients.

### Transport

Streamable HTTP (MCP standard). Any MCP-compatible client connects by pointing at the admin's `/mcp` endpoint with an `Authorization: Bearer` header.

### Authentication

Accepts `MCP_KEY` bearer token or falls back to `MASTER_KEY`. Auth is handled by `EdgeAdminWeb.Plugs.McpAuth` before Anubis processes the request.

### Tool Discovery

MCP clients discover available tools dynamically via the standard `tools/list` method — no static spec file. This is the MCP equivalent of `/api/openapi`. Call `POST /mcp` with `{"method": "tools/list"}` to get the full tool list with input schemas.

### Tool Surface (47 tools)

| Group              | Tools                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Admin info         | `get_admin`, `get_admin_cluster`, `list_edge_clusters`, `list_orphaned_clusters`, `check_admin_health`                  |
| Clusters           | `list_clusters`, `get_cluster`, `create_cluster`, `update_cluster`, `delete_cluster`                                    |
| Nodes              | `list_nodes`, `get_node`, `delete_node`, `change_node_cluster`                                                          |
| Aliases            | `list_aliases`, `get_alias`, `create_alias`, `delete_alias`                                                             |
| Enrollment keys    | `list_enrollment_keys`, `get_enrollment_key`, `create_enrollment_key`, `update_enrollment_key`, `delete_enrollment_key` |
| Commands           | `list_commands`, `get_command`, `create_command`, `delete_command`                                                      |
| Command executions | `list_command_executions`, `get_command_execution`, `cancel_command_execution`, `delete_command_execution`              |
| SSH usernames      | `list_ssh_usernames`, `get_ssh_username`, `create_ssh_username`, `delete_ssh_username`                                  |
| SSH public keys    | `list_ssh_public_keys`, `get_ssh_public_key`, `create_ssh_public_key`, `delete_ssh_public_key`                          |
| Self-updates       | `list_self_update_requests`, `get_self_update_request`, `create_self_update_request`, `delete_self_update_request`      |
| Metrics            | `get_node_metrics`, `get_host_metrics`, `get_agent_metrics`, `get_admin_metrics`                                        |

`check_admin_health` runs all subsystem checks (Database, Bootstrap, Metadata, Netmaker API, Netclient VPN, Proxy Servers) in parallel and returns a structured pass/fail per component — useful for diagnosing enrollment or command delivery failures.

### Proxy Access

The admin's HTTP proxy (port 43128) and SOCKS5 proxy (port 41080) are independent of MCP but complement it. An AI client configured to route its own HTTP requests through the proxy can reach any service on any VPN-connected node or its local network — without any MCP tool call. Configure the proxy URL once at the client level using the `PROXY_KEY` credential; the AI then has unrestricted HTTP access to the entire edge mesh.

---

## Authentication

| Path                     | Mechanism                                                                     |
| ------------------------ | ----------------------------------------------------------------------------- |
| Admin API (full access)  | `MASTER_KEY` bearer token                                                     |
| Admin API (metrics only) | `METRICS_KEY` bearer token                                                    |
| Admin API (proxy only)   | `PROXY_KEY` bearer token                                                      |
| Admin → Netmaker         | `MASTER_KEY` bearer token                                                     |
| Agent → Admin            | Per-node API token (issued at enrollment)                                     |
| Admin → Agent            | Per-node API token (same token, stored in admin DB)                           |
| Admin ↔ Admin (Erlang)   | Shared `ERLANG_COOKIE` + connection verified against PostgreSQL + Netmaker    |
| SSH                      | Username/password or public key, verified by admin on each connection attempt |

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

**Deterministic coordination without a leader.** All admins run the same algorithm on the same PostgreSQL-sourced inputs and converge to identical cluster assignments independently. No leader election, no consensus round, no Raft. If a network partition splits admins, both partitions continue operating; duplicate work accumulates in PostgreSQL (idempotent, not corrupting); assignments reconcile on reconnect.

**HTTP for agent-admin, Erlang distribution for admin-admin.** Agents are simple HTTP services — no Erlang cookie, no epmd, no Node.connect. Erlang distribution complexity is justified only for admin coordination, where cross-admin proxy routing requires transparent process-to-process calls that would be awkward over HTTP.

**Ranch for the proxy, not Phoenix/Plug.** The proxy is raw TCP. Phoenix is HTTP-only. Ranch gives direct socket control with a clean acceptor pool model — exactly what bidirectional byte streaming needs.

**`:syn` over libcluster.** `:syn` provides scoped distributed registries with built-in `GenServer.call` integration and first-come-first-served conflict resolution. libcluster targets fully-connected mesh clusters; `:syn` fits the selective admin-only distribution topology here.

**DERP over custom WebSocket relay.** A scalable custom WebSocket relay for proxy/SSH would need relay nodes to mesh and forward between each other for any agent connected to a different node. That is DERP. DERP already solves this at the network layer, transparently, for all TCP streams. More DERP nodes for HA is the right answer.
