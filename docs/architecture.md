# Edge Core — Architecture

**Last Updated: 2026-05-06**

Edge Core is an infrastructure management platform for geographically distributed edge machines. It gives you centralized control over remote nodes through a secure VPN mesh — running commands, accessing machines via SSH, proxying traffic through them, and scraping their metrics — all through a simple HTTP API.

---

## Two principles

Edge Core was born from three years of watching a company hit the same walls trying to ship to edge devices it didn't fully control: deployments were a black box, machines on the same LAN couldn't reliably find each other, and every new product re-implemented the same WebSocket/MQTT sync layer to stay in touch with the cloud. The system is organized around two principles that came out of that experience.

### 1. Control — a fleet you don't physically touch should still be a fleet you can see and operate.

Once devices are geographically distributed, you lose the things you take for granted with a server in a rack: shell access, log tailing, the ability to push a config file, the ability to know whether the machine is even alive. Closing that gap is the entire reason this project exists.

- **Direct execution** — run shell commands across hundreds of machines from a single API call. Commands are distributed to target nodes, executed in parallel, results are collected back centrally. Real-time over VPN, eventually consistent over HTTP polling when the VPN is down.
- **SSH access** — first-class. Admin holds centralized SSH usernames and public keys; agents run an embedded SSH server on port 40022 that calls back to admin to verify each connection. Combined with the forward proxy below, you get tunneled SSH into any node without ever exposing port 22.
- **Observability** — admin instances act as Prometheus-compatible aggregators. Host, agent, and WireGuard metrics are scraped from every node through the admin's service-discovery endpoints — no direct network access to individual nodes required.
- **Self-update** — coordinated agent upgrades across the fleet from a single API call, via Watchtower as a sidecar. Same shape as command execution: one request, fans out to many machines.
- **Async signal back out** — when state changes (a node registers, a command finishes, an SSH session is verified), the system publishes events. Consumers subscribe via webhooks (per-row HTTP delivery, signed) or a message broker (NATS, Kafka, AMQP, Redis, MQTT, AWS SNS, Google Cloud Pub/Sub). No polling required to follow what's happening.

### 2. Connectivity — talking to a specific edge machine should work without anyone configuring IPs, ports, or tunnels in advance.

Once you've decided to operate machines you don't physically touch, the next problem is _reaching_ them. You don't know the LAN, you don't control the firewall, the IPs are dynamic, the hostnames are generic. Every edge product ends up rebuilding the same WebSocket/MQTT sync layer to route around this. We wanted that solved once, in the platform.

- **Edge ↔ Edge (VPN mesh).** All nodes in the same cluster form a full WireGuard mesh via Netmaker. Every node can reach every other node P2P, no central gateway. This is the transport everything else runs on. Three-layer fallback handles adverse network conditions: raw WireGuard UDP → DERP relay (symmetric NAT) → HTTP polling (last resort). See [Admin ↔ Agent Communication](#admin--agent-communication).
- **Cloud ↔ Edge (forward proxy + proxy chaining).** Admin runs HTTP (port 43128) and SOCKS5 (port 41080) forward proxies. Because SOCKS5 supports any TCP connection, this covers any protocol — not just HTTP. Two modes: route directly to a VPN node, or chain through a specific agent as the exit node to reach the internet or its LAN from that agent's network location. Raw TCP over the VPN, no MQTT or WebSocket on the application path. In production, HAProxy load-balances proxy traffic across all admin instances.
- **Network segmentation.** WireGuard mesh is O(n²) — bigger meshes get exponentially more expensive, and a single flat mesh forces every customer's machines to share the same trust boundary. So clusters are kept small (50–100 nodes) and isolated from each other; each customer or workload gets its own mesh, no ACLs to gate traffic inside one. Multiple admin clusters federate via shared PostgreSQL, no Erlang distribution between them.

#### The unsolved one: User ↔ Edge (local).

Some traffic should reach an edge node _without_ going through the cloud admin — when the user is physically near the node and a cloud round-trip is wasteful or unreliable. This is the principle we have not fully solved.

What works today: agents advertise themselves via mDNS, so any device on the same LAN segment can resolve `node-{id}.local`. This covers the small case — a single network, no VLANs, devices that speak Bonjour/Avahi. It does not cover the realistic case of LANs we don't control.

What's missing: trustworthy LAN DNS that the user's resolver actually uses, an HTTPS path to the agent that browsers won't block, and a way to do all of that without colliding with existing LAN DNS (corporate networks, home routers with their own DNS quirks). We don't have a good answer to that combination yet.

What we won't do (yet): require the user to install a client. The whole point of this principle is _no agent on the user side._ If we can't honor that constraint, we'd rather punt than ship a half-thing. R&D continues; it is the focus for v3.

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

### Database Adapter

The admin's database engine is selected at runtime via the `DB_ADAPTER` environment variable. **PostgreSQL is the production default** and the only option that supports multi-admin HA. SQLite is a supported alternative for single-instance hobbyist / homelab deployments.

Both adapters are baked into every compiled binary — no rebuild needed to switch. A dispatcher facade (`EdgeAdmin.Repo`) forwards every Ecto.Repo call to the active impl module (`EdgeAdmin.Repo.Postgres` or `EdgeAdmin.Repo.SQLite`) selected from app env at runtime. Application code never needs to know which adapter is active.

| Concern                       | `DB_ADAPTER=postgres` (default)                                          | `DB_ADAPTER=sqlite`                                                            |
| ----------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Multi-admin HA                | ✅ Required for it                                                       | ❌ Single instance only                                                        |
| Cluster ownership sharding    | ✅                                                                       | ❌                                                                             |
| Cross-admin coordination      | LISTEN/NOTIFY via dedicated notifier repo                                | None — single instance only                                                    |
| Oban engine / peer / notifier | `Engines.Basic` + `Peers.Database` + `Notifiers.Postgres`                | `Engines.Lite` + `Peers.Isolated` + `Notifiers.PG`                             |
| LiveDashboard `ecto_stats`    | Auto-discovered → `EctoPSQLExtras`                                       | Auto-discovered → `EctoSQLite3Extras`                                          |
| Storage location              | External Postgres server (URL or fragment env vars)                      | `SQLITE_DB_PATH` (default `/app/data/edge/edge_admin.db`)                      |
| Schema                        | Same migrations, same Ecto schema                                        | Same migrations, same Ecto schema                                              |
| Recommended for               | Production, anything that might scale, anything you'd be unhappy to lose | Homelab, hobbyist, first-time exploration, fleets that won't exceed ~100 nodes |

See `examples/lite/` for a SQLite single-admin deployment and `examples/standard/` for the production PostgreSQL setup. The general guidance lives in `examples/README.md` ("Choosing an Example").

The rest of this section assumes the production setup (PostgreSQL + multi-admin clustering). Single-admin SQLite mode is functionally a subset — same code paths, just without the peer-cluster and cross-admin coordination layers below.

### Beyond PostgreSQL — future direction

Realistically, Edge Admin is unlikely to outgrow PostgreSQL for most deployments. The data model is bounded (clusters, nodes, SSH credentials are slow-changing; commands and metrics are pruned on a window), and PostgreSQL on a well-tuned host has comfortable headroom for the workload shape Edge Admin produces. CNPG makes in-region HA trivial. The honest assumption is that PostgreSQL is sufficient for the foreseeable future and we are not actively planning around outgrowing it.

That said, the dispatcher pattern leaves the door open. If concrete demand surfaces — typically geo-distributed multi-region admin federation, very high write throughput from agent telemetry, or strict cross-region RPO requirements — **YugabyteDB is the documented future direction**. Yugabyte's YSQL is a fork of PostgreSQL source (not just wire-compatible), which means LISTEN/NOTIFY works, the type system matches, JSONB and transactional DDL behave as expected, and our existing PostgreSQL adapter code path can target it with minimal changes. The core engine is Apache 2.0, which is a meaningful adoption advantage over CockroachDB's CSL — users can self-host the cluster without a paid license. We have not implemented Yugabyte support today and won't without a clear customer ask, but the path is open and shallow.

**MySQL-flavored backends (MySQL, MariaDB, TiDB) are not on the roadmap.** The cost is high and the fit is poor: no LISTEN/NOTIFY (breaks our Oban notifier path and cross-admin coordination), JSON semantics differ from JSONB, no transactional DDL, no native UUID type, and the entire Elixir/Phoenix/Oban ecosystem assumes PostgreSQL semantics deeply enough that a parallel adapter would be ongoing maintenance pain. Users with MySQL-only ops standards are better served by running a small dedicated PostgreSQL instance for Edge Admin alongside their existing MySQL fleet.

**CockroachDB is not on the roadmap either.** It is wire-compatible with PostgreSQL but explicitly does not implement LISTEN/NOTIFY (CRDB issue #41522), which is load-bearing for the multi-admin-cluster federation pattern. It also requires a paid license to operate clusters under the current CSL terms.

### Deployment

Admin runs containerized, always. It uses `wireguard-go` (userspace WireGuard) inside the container. Kernel-mode WireGuard is not supported in the containerized admin — `wireguard-go` is required. Bare-metal admin is untested and not a supported path.

### Erlang Peer Clustering

Multiple admin instances within the same admin cluster connect to each other via Erlang distribution, using their VPN DNS names as Erlang node names:

```
admin@admin-abc123.admin-cluster-a.nm.internal
```

This is **peer-to-peer, masterless**. There is no leader election, no primary, no replica. Every admin instance is equal. They coordinate through:

- **`:syn` distributed registry** — two scopes: `:admin_scope` (who is in the cluster, each admin's WireGuard peer budget) and `:cluster_scope` (which admin's Gateway GenServer owns which edge cluster)
- **ETS** — local in-memory cache of topology, intentionally ephemeral. Dies with the process, forcing clean recomputation from PostgreSQL on restart. Mnesia is explicitly avoided — its persistence creates split-brain complications.
- **PostgreSQL** — the only source of truth. All persistent state lives here.

Erlang distribution is **intra-cluster only** (admins within the same peer cluster). Different admin clusters do not connect to each other via Erlang distribution at all — they only share the PostgreSQL database.

### Cluster Ownership Sharding

WireGuard mesh overhead makes it expensive for multiple admins to all join the same edge cluster. The one-admin-per-cluster algorithm ensures exactly one admin manages each edge cluster at any time.

Capacity is modelled honestly against the WireGuard peer table, not invented as a separate "edge node count":

- Operators set `ADMIN_MAX_WIREGUARD_PEERS` per admin (the physical WG peer budget — admin-mesh peers and edge-node peers both count against it).
- Each admin derives `admin_peer_count = total_admins - 1` (peers in its admin-mesh) and `edge_node_capacity = max_wireguard_peers - admin_peer_count` (slots left for edge nodes). Both are recomputed on every topology change.
- The sharding algorithm sees only `edge_node_capacity` per admin. The cluster-level `total_edge_capacity` is the sum across admins; the system is `degraded` when total enrolled nodes exceed it.

Adding admins to an admin cluster therefore _reduces_ each admin's `edge_node_capacity` by 1 — the cost of admin HA is now visible instead of hidden.

#### `MAX_WIREGUARD_PEERS` is a budgeting unit, not a physical limit

The honest view: WireGuard peer count is a proxy for admin load, not a measurement of it. The actual constraints are multidimensional — encryption CPU per packet, peer table memory, UDP socket throughput, file descriptors, the netclient polling loop, the BEAM scheduler under proxy/SSH/metrics traffic. None of these map cleanly to "peer count." A peer doing nothing costs almost nothing; a peer pushing proxy bytes, holding SSH sessions, and answering metrics scrapes costs orders of magnitude more. So 250 idle peers and 250 busy peers are not the same load — the same number can describe a sleepy fleet at 5% CPU or a fleet pegging the box.

We picked WireGuard peer count anyway because it's the most human-friendly dimension we could find. It maps directly to the thing operators are actually trying to manage (WG mesh size), it's countable, it's bounded by the obvious constraint (you can't have negative peers, and there's a real upper bound from kernel/netclient resources), and it composes cleanly with the admin-mesh accounting that's already required for sharding. Trying to replace it with a multi-knob model (`max_active_proxy_streams` + `max_metrics_qps` + `max_concurrent_ssh_sessions` + ...) trades one wrong-but-tunable number for several wrong-but-tunable numbers, and operators end up worse off.

This is the same shape as token-based budgeting in other distributed systems — Cassandra tokens, Redis Cluster slots, Kafka partition counts. The token count isn't a measurement; it's a budgeting unit operators tune empirically against real telemetry. We do the same: `MAX_WIREGUARD_PEERS` is the quota; CPU, memory, scheduler utilization, peer table size, proxy/SSH/command throughput are the signals operators watch to decide whether the quota is right for their workload.

Until we find a model that's both more accurate and still human-friendly to tune, this is how it works. Pick a number, watch your telemetry, adjust.

How it works:

- Each admin maintains a local ETS table of the current topology (who owns what, remaining capacity)
- When topology changes (admin joins or leaves, node counts shift), every admin independently runs the **same deterministic algorithm** on the same inputs — no coordination round needed
- Assignment is computed from scratch each time, with one continuity hint: clusters sorted by size descending, each assigned to the best available admin scored by (fewest clusters managed, then highest remaining capacity, then previous owner wins at ties, then admin ID as final tiebreaker). The previous-owner key keeps reassignment rate near the theoretical minimum on topology change without overriding load balance or capacity
- Clusters that exceed total system capacity become orphaned (tracked separately, not assigned to any admin)
- On admin failure: surviving peers detect the disconnect via `:syn`, recompute assignments from scratch, and pick up the orphaned or previously-assigned clusters naturally through the same algorithm

Replication is achieved not by replicating state within a cluster, but by **spinning up a second independent admin cluster** sharing the same PostgreSQL database. The two clusters are completely independent federations — no Erlang distribution between them, no `:syn` visibility across the boundary.

### Scaling Dimensions

Edge Admin scales along two axes: vertically by adding admins inside one admin cluster, and horizontally by adding more admin clusters. Admin clusters share the PostgreSQL database but otherwise operate as independent failure domains.

```
Same admin cluster (A1 + A2):
  → More sharding capacity, more WireGuard partitioning
  → Share :syn state, Erlang distribution, coordinate via one-admin-per-cluster
  → Heals if one peer goes down

Multiple admin clusters (cluster A + cluster B):
  → Horizontal scale-out and HA — failure of one cluster does not affect the others
  → Completely independent — share only PostgreSQL
  → No Erlang distribution, no :syn visibility across the boundary
  → Geographic separation is a natural fit (one cluster per region)
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

**Host OS compatibility.** The agent ships as a Debian-slim container, so its own process is portable. The constraints are on the host: kernel WireGuard support (built-in on ≥ 5.6, DKMS or `wireguard-go` userspace fallback otherwise), a writable `/etc/resolv.conf`, and (when applicable) `systemd-resolved` reachable over D-Bus. Regularly tested on Ubuntu 22.04 / 24.04 and Debian 12 (x86_64 and ARM64). Other glibc + systemd distros (Fedora, Rocky, Alma, openSUSE Leap) should work but are not part of the regular test matrix. Alpine / other musl hosts, immutable distros (Fedora CoreOS, Flatcar, Bottlerocket, Talos, NixOS), and SELinux-enforcing hosts may need additional configuration. Architectures beyond x86_64 / ARM64 are not currently built.

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

## Events

Edge Admin publishes lifecycle events through two independent delivery channels: an opt-in message broker and always-on user-configurable HTTP webhooks. Both receive the same CloudEvents 1.0 envelope. Events span node lifecycle, command execution lifecycle, enrollment-key verification, SSH verification, and self-update lifecycle. All events carry a full object snapshot in `data`.

`EdgeAdmin.Events.publish/1` is the single in-process entry point for state-change publication. It builds the envelope and fans out to every channel — broker (if enabled) and webhooks (always). Channels operate independently: a broker outage does not affect webhook delivery, and vice versa.

> Operator-facing usage (subscribing, the broker config matrix, the full adapter list) lives in [`guide.md`](guide.md). The full event catalog is at [`admin-asyncapi-v0.2.0.md`](admin-asyncapi-v0.2.0.md), or browse `/asyncdoc` on a running admin. This section covers the design choices behind the two channels.

### Why two channels

A broker is the right answer when consumers are infrastructure that already speaks message-bus semantics (data pipelines, stream processors, fan-out to many subscribers). It is the wrong answer for a one-off webhook to a SaaS endpoint — that needs HTTPS, HMAC, retries, and SSRF protection, none of which a generic broker provides for free. Rather than force one shape on every consumer, we offer both and let them coexist.

### Broker channel — design notes

- **Adapter shim, not a hub.** The admin publishes; the broker is run separately by the operator. We don't bundle one. Adapters are thin enough that adding a new one is a day's work; the supported list grows on real demand.
- **`type` field doubles as the broker identifier** — NATS subject, AMQP routing key, Redis channel, MQTT topic (`.` rewritten to `/`). This makes broker-level filtering work without parsing the body. AWS SNS and Google Pub/Sub don't support topic-name wildcards, so we promote `type` and `corename` to message attributes for their filter policies/expressions instead.
- **Duplicates are possible** for `edge.node.status_changed` — the health check runs on every admin independently (masterless), and each duplicate carries a different `id`. Consumers dedup by `(node_id, previous_status, status)` plus a monotonic `time` check, not by `id`.

### Webhook channel — design notes

- **Immutable after create.** No partial updates, no soft-disable. Mutability is a footgun for delivery contracts — you delete and recreate. The cost of recreating is trivial; the cost of a partially-updated webhook silently sending to the wrong URL is not.
- **Explicit subscription allowlist, no wildcards.** `subscribed_events` is a literal list of event-type strings, validated at create time against the live catalog. Subscribing to "everything" means listing every type explicitly. This is opt-in by design — adding new event types to the catalog never auto-expands existing subscriptions, so a noisy new event can't accidentally hammer existing receivers.
- **Encryption at rest via Cloak** for `secret` and `headers`. `CLOAK_KEY` and `CLOAK_TAG` are required at admin boot. Rotation is supported via `EdgeAdmin.Release.rotate_cloak_key/0` (see `examples/operations/rotate_cloak_key.yml`).
- **SSRF deny list at create time.** Loopback, RFC1918/ULA, link-local (including the cloud-metadata literals at `169.254.169.254` and `metadata.{google,azure,tencentyun}.internal`), and multicast are all rejected. IPv4-mapped IPv6 (`::ffff:a.b.c.d`) is normalised first so the v6 form can't bypass the v4 deny list. Opt-out is per deployment (`WEBHOOK_ALLOW_PRIVATE_IPS=true`) for homelab/dev — not per-webhook, because per-webhook bypass tends to drift into "everything bypasses by accident."
- **Retry classification with no auto-disable.** `2xx` succeeds; `408 / 429 / 503` and network errors retry with Oban's exponential backoff up to `WEBHOOK_MAX_ATTEMPTS` (default 3), then drop; other `4xx / 5xx` are terminal (`{:cancel, _}`). There is no row-level failure counter and no auto-disable — every event is independent. Auto-disable would create a hidden state machine on top of webhooks; explicit retry-or-drop is easier to reason about.
- **Each delivery is `(webhook × matched event)`** — one HTTP POST per pair, signed with `X-Edge-Signature: sha256=<hex>`.

### Not currently supported

AMQP 1.0 (a different wire protocol from AMQP 0-9-1 despite the name — used by ActiveMQ, Azure Service Bus, IBM MQ, Solace) and Apache Pulsar. Neither is shipped today; the existing `amqp091` adapter does not speak AMQP 1.0, and the `kafka` adapter is not wire-compatible with Pulsar. Adapter additions are tractable — file an issue with a real use case and we'll prioritise.

---

## AI / MCP Interface

Edge Admin exposes a [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server at `POST /mcp` alongside the REST API, giving AI assistants direct, structured access to the same surface human operators get.

> Operator-facing usage (client config, the proxy combo) lives in [`guide.md`](guide.md). This section covers the design choices.

- **Streamable HTTP transport.** Standard MCP. Single endpoint, one bearer token (`MCP_KEY` or `MASTER_KEY`), no separate connection lifecycle to manage.
- **Tools mirror the REST API surface.** Every REST operation has an
  equivalent MCP tool. The tool catalog is **explicitly listed** in
  `EdgeAdminMcp.Server` (each tool registered via `component(...)`),
  not auto-generated from controllers. Adding a REST endpoint does
  not automatically expose it via MCP — you write the matching tool
  module under `edge_admin_mcp/tools/<domain>/` and register it in
  `Server`. Discovery is still dynamic for clients via standard
  `tools/list` once registered.
- **One MCP-only tool: `check_admin_health`.** Runs every subsystem check in parallel and returns structured pass/fail. The motivation is operational: AI assistants are uniquely positioned to triage "why isn't this working" because they can correlate the health output with the user's description, but doing that requires one consolidated health view rather than seven separate REST calls.
- **Auth pre-Anubis.** `EdgeAdminWeb.Plugs.McpAuth` runs before Anubis processes the request, so unauthenticated traffic never reaches the MCP machinery.

The forward proxy (§ Forward Proxy) and MCP are independent but complementary. An AI client configured to route its own HTTP through the admin proxy gets unrestricted access to any service on any VPN-connected node — no MCP tool call needed for arbitrary HTTP. MCP is for _managing_ the fleet; the proxy is for _talking to_ the fleet.

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

**Deterministic coordination without a strong leader.** All admins in an admin cluster run the same algorithm on the same PostgreSQL-sourced inputs and converge to identical cluster assignments independently. No leader election, no consensus round, no Raft. If a network partition splits admins, both partitions continue operating; duplicate work accumulates in PostgreSQL (idempotent, not corrupting); assignments reconcile on reconnect.

**Horizontal scale-out via additional admin clusters.** Beyond a single admin cluster, scale and HA come from running additional independent admin clusters that share only the PostgreSQL database. Admin clusters do not coordinate with each other — no Erlang distribution, no `:syn` visibility across the boundary — which makes an admin cluster the natural unit of failure isolation, geographic placement, and capacity planning.

**Weak leader for LocalScheduler deduplication.** The LocalScheduler (Quantum) runs periodic jobs on every admin instance — that is its design. Some jobs (e.g. zombie admin cleanup) would produce wasteful duplicate work if every admin ran them. A **weak leader** is elected deterministically: the admin with the alphabetically first admin ID in the current topology. All admins compute this independently and agree without coordination. The weak leader runs the job; others skip it. Duplicate work is still possible during split brain and is acceptable — these jobs are idempotent. This is explicitly not a strong leader: no exactly-once guarantee, no consensus. If stronger semantics are ever needed, a `:strong_leader` concept can be introduced separately.

**HTTP for agent-admin, Erlang distribution for admin-admin.** Agents are simple HTTP services — no Erlang cookie, no epmd, no Node.connect. Erlang distribution complexity is justified only for admin coordination, where cross-admin proxy routing requires transparent process-to-process calls that would be awkward over HTTP.

**Ranch for the proxy, not Phoenix/Plug.** The proxy is raw TCP. Phoenix is HTTP-only. Ranch gives direct socket control with a clean acceptor pool model — exactly what bidirectional byte streaming needs.

**`:syn` over `:pg` for distributed registry.** Both are global process registries, but `:pg` (OTP's built-in) chooses consistency over availability and can become a bottleneck at scale. `:syn` chooses availability over consistency (strong eventual consistency), which is acceptable here since registration keys are unique by construction (one Gateway per cluster, one admin per name) and write throughput matters more than linearizability. `:syn` also supports scoped registries (`:admin_scope`, `:cluster_scope`), metadata attached to registrations, and cluster-wide callbacks on net splits — none of which `:pg` provides.

**DERP over custom WebSocket relay.** A scalable custom WebSocket relay for proxy/SSH would need relay nodes to mesh and forward between each other for any agent connected to a different node. That is DERP. DERP already solves this at the network layer, transparently, for all TCP streams. More DERP nodes for HA is the right answer.
