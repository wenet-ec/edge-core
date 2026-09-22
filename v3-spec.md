# Edge Core v3 — Research Specification

**Status:** Research. This is shared memory for decisions and unresolved product questions. It is not an implementation plan.

**Recording rule:** This document contains only topics, facts, decisions, and
open questions explicitly discussed and agreed in conversation. Do not fill in
missing design details, predict integrations, invent future behavior, or turn
an inference into a decision. Keep an item open until it is actually settled.

```text
Research → Planning → Implementation
```

## Purpose and status

V3 began as a broad review of Edge Core's product boundary, Agent delivery, networking, VPN dependency, and scale. The research record is now concluded. The next phase is implementation planning, beginning with **Ingress Tunneling**: Core-integrated private access through Agent-hosted ingress and a standalone external Tunnel client.

This document records agreed decisions and explicitly retained questions. It does
not authorize filling in those questions during implementation without a new
planning decision.

Two smaller topics remain open when there is a concrete use case:

1. Delegated Agent/proxy access.
2. ACL/policy beyond the existing cluster trust boundary.

## Cross-cutting principles

- Preserve Core's two promises: fleet control and connectivity without manual tunnels.
- The database remains authoritative; networking state is derived and reconcilable.
- Prefer explicit application-level proxying over implicit network routing where both can solve the requirement.
- Treat routes, DNS, firewall policy, MTU, and network interfaces as first-class host state.
- Read checked-in Netmaker and netclient source before making VPN behavior claims.
- Existing implementation, compatibility churn, or migration effort is never a reason to reject a better product or technical direction. Decide first from the desired future behavior, correctness, security, performance, and operability; then plan the migration honestly.
- A research conclusion is not permission to implement. Record only decisions that were explicitly agreed.

## Decisions and boundaries

| Topic | V3 direction |
| --- | --- |
| Hardware rental / Edge OS | Rental is separate commercial and inventory work. Customers control rented hardware and retain root access. Do not build Edge OS, compulsory device tracking, OTA fleet control, or a Balena-like appliance product in Core. Agent installation is optional and transparent. |
| Full Agent platform | Linux only. The canonical Agent is one Docker/OCI image containing its survival kit: Agent, netclient, SSH, metrics, proxy, DNS/VPN tooling, diagnostics, and pinned dependencies. |
| Linux architecture | Publish `linux/amd64` and `linux/arm64`. Support target: Ubuntu 24.04/26.04, Debian 13, Rocky/RHEL-compatible 10, Alpine 3.24, and current 64-bit Raspberry Pi OS Lite. No 32-bit ARM initial target. |
| Windows and macOS Agent | Out of v3. Windows is future/demand-gated; macOS is more plausibly a future Edge Tunnel client platform. Docker Desktop cannot make the Linux Agent control its Windows/macOS host. |
| Agent runtime | Implement V3 Agent-side functionality in Elixir/Phoenix first. Mid-V3, migrate the Agent binary to Go under a separately guided plan. Keep the Debian Docker image, bundled capabilities, SQLite-backed durable command lifecycle, and external Admin/Agent behavior the same; the executable implementation changes, not the product contract. |
| Container base | Keep optimized Debian images. Do not move Admin or Agent to Alpine for image size alone; the Agent's runtime footprint is BEAM-dominant and Alpine adds musl/native/network requalification risk. |
| Bandwidth throttling | Defer beyond v3. Do not silently shape a customer-controlled machine's general traffic. A future feature must be explicit opt-in and limited to Core-owned traffic. |
| Admin clustering | Keep the bundled PostgreSQL-authoritative Erlang-distribution + `:syn` model as the default. The future Admin Router/Worker split is a V3 design track, blocked on an explicit Admin–Netmaker control-plane ownership boundary; do not implement it speculatively. |
| Multiple VPNs / NICs | Split-tunnel VPNs can coexist when ranges, routes, DNS ownership, firewall, and MTU do not conflict. Full-tunnel VPNs are advanced and may conflict. Use configurable non-overlapping ranges and validate real combinations. |
| Gateway model | Keep Core proxying as the explicit default exit model. Netmaker egress/gateway routing is advanced tooling for subnet/protocol/throughput cases, not a replacement for proxy selection. Netmaker ingress is a useful stock-WireGuard reference, not the Edge Tunnel product model. |

### Go Agent persistence and background-work boundary (agreed)

The Go Agent's domain persistence uses GORM: command executions, settings,
identities, results, and all business rules remain ordinary Agent-owned SQLite
state. Goqite is deliberately limited to private background-job governance:
durable wakeups, worker leases, crash retry, and bounded worker concurrency.
It is not a source of truth for commands or any other domain state.

```text
GORM / Agent SQLite state  → authoritative domain records and state machines
Goqite queue table         → durable execution wakeups and leases only
Go scheduler               → stateless periodic work and recovery scans
```

GORM creates and owns the single SQLite `*sql.DB` pool. Goqite receives that
same pool through GORM's `DB()` handle; it does not open a second database or
maintain a competing pool. Goqite uses its own private queue table and raw
`database/sql` operations internally, while all Agent business persistence
remains GORM-owned.

The existing recovery pattern remains intentional: persist a command record,
then enqueue its wakeup; a missed enqueue or exhausted lease is recovered by
the periodic GORM query for recoverable command records. Do not require a
cross-library transaction merely to make queue insertion atomic with the
domain write.
| Netmaker server | Use upstream Netmaker as a pinned VPN substrate. Nexmaker remains the anti-corruption layer. Do not fork the server pre-emptively. |

## Netmaker and DERP direction

The netclient fork is an intentional client-level ownership point. It carries Edge-specific DERP transport plus reliability and host/CLI fixes that cannot wait for upstream. Maintain it as a small, categorized patch stack with deliberate rebases and Core-owned release artifacts.

Fork or replace the Netmaker server only for a concrete incompatibility, a security/reliability fix that cannot arrive in time, untenable upgrade churn, or a required capability that cannot live beside it. Better DERP deployment alone is not a reason to fork the server.

DERP is a separately deployable data-plane service. A Core deployment may bundle Netmaker and DERP relays for convenience, but relay bandwidth, long-lived TCP/TLS connections, and regional capacity must scale and fail independently from enrollment and peer management.

The current netclient model is deliberately coordinator-free:

```text
canonical DERP map
  + symmetric pair rendezvous hashing (HRW)
  → both peers select the same relay region
```

A deliberately local Core map already gives predictable low latency for a geographically colocated deployment. The public Tailscale map is an availability fallback when no configured Core map can be obtained. With several distant regions, HRW remains geographically blind; client-measured relay selection plus published peer/home-relay state is a possible future optimization, not a current server-fork requirement.

## Admin Router / Worker split — open V3 design track

The current bundled Admin intentionally combines public API/domain work, live
Admin coordination, Netmaker membership, and per-cluster virtual gateways. It
is the correct default today. Its constraint is that Admin WireGuard peer
capacity also bounds the number of edge-cluster VPN memberships and therefore
the data-plane work an Admin can own.

```text
Admin Router
  public API, domain state, metadata, logical assignment, scheduling
          ↓ authenticated control and stream protocol
Admin Worker / Gateway Worker
  Netmaker identity and membership, virtual gateways, Agent HTTP and raw streams
```

This is not a leader-election or Partisan proposal. In a split deployment,
PostgreSQL must authoritatively own logical Worker assignment, generation/
fencing, leases, heartbeats, capacity, and reconciliation. `LISTEN/NOTIFY` is
only a wakeup mechanism; `:syn`, ETS, and weak-leader election cannot be the
authority for a detached Worker.

The design is blocked pending one explicit choice: whether Netmaker remains an
external VPN control plane, becomes more deeply integrated with Admin, or is
eventually replaced. Netmaker currently owns effective VPN enrollment and live
membership state; an Admin Worker is not truly live merely because an Admin
database row says so. The final model needs a clear owner and reconciliation
boundary for enrollment, network membership, address allocation, revocation,
and fencing.

Before implementation, define a transport-neutral Worker contract for both
bounded Agent request/response operations and authenticated, long-lived raw
TCP streams. Every Agent-facing operation—including commands, health,
metrics, diagnostics, updates, proxying, and SSH verification—must route
through that contract in split mode. The current bundled Gateway Registry and
raw Admin-to-Admin TCP tunnel are useful implementation references, not the
future distributed contract.

## Ingress Tunneling — primary v3 research track

### Product boundary (agreed)

Ingress Tunneling is a Core private-access capability, not a Netmaker extension. Its
control and protected-side components reuse Core's existing Admin and Agent
lifecycle:

```text
Edge Admin   → `IngressTunneling` domain and control-plane authority
Edge Agent   → Edge Ingress capability on an enrolled Node
edge_tunnel/ → standalone user/device tunnel networking core
```

Edge Tunnel is the technical user/device tunnel endpoint. It is not Edge Agent
and is not a full Netmaker mesh node. `edge_tunnel/` is an Edge Core subrepo.
A user-facing desktop or mobile product name is intentionally not decided yet.

Edge Tunnel is client-only: it attaches through one selected Edge Ingress and
does not become a general mesh participant. Authorization and resource scope
remain part of the Ingress Tunneling design work.

### Connectivity direction (agreed so far)

```text
Edge Tunnel client
  ⇅ direct UDP where possible, DERP when UDP is unavailable/blocked
selected Edge Ingress
  ⇅ protected-side forwarding
target resource
```

- Edge Tunnel must be DERP-aware. DERP requires compatible behavior at both
  Tunnel and Ingress; a stock WireGuard peer cannot use it.
- The requirement is based on a hostile-network test: NAT traversal can overcome NAT, but not an ISP/network that blocks outbound UDP. UDP-only TURN shares that failure; TCP/TLS DERP remains a reachability escape hatch.
- Edge Tunnel and its selected Ingress should prefer a proven direct path (same-LAN interface first, then Internet UDP) and use DERP when direct UDP is unavailable. Always-relayed operation is simpler but would discard valuable local-path performance.
- Firezone is useful reference for the Client ↔ Ingress control/data-plane pattern. Its Portal coordinates authorization and sessions but is not the data path.

#### Verified DERP-first peer coordination

The `ingress_tunneling/` prototype verified that no live Admin/Tower process is
required after a Tunnel Connection has been provisioned. The required initial
material is reciprocal WireGuard public identity, the local private identity,
and a DERP map. The prototype used two static configurations and no Admin
runtime component.

```text
Admin provisions Tunnel Connection material
  → Tunnel and Ingress establish initial WireGuard traffic through DERP
  → each discovers dynamic UDP candidates
  → each exchanges authenticated candidates through DERP
  → direct UDP is used when available
  → DERP continues carrying WireGuard traffic if direct UDP disappears
```

The verified lab used real userspace WireGuard TUN interfaces and the forked
netclient `MagicBind` transport. It completed encrypted ICMP traffic through
public DERP, upgraded it to a sub-millisecond Docker-local UDP path, then
blocked that direct UDP path and verified continued encrypted traffic through
DERP. It also gathered public STUN server-reflexive candidates and delivered
the candidate messages over DERP.

This proves the narrow transport fact, not a finished production protocol.
Candidate validation, Internet NAT behavior, candidate ranking, relay
selection, peer revocation, and configuration rotation remain separate design
work.

### Client platforms and implementation direction (agreed)

Build Edge Tunnel's reusable networking core in Go. It owns the client-side
session, WireGuard packet path, direct-path discovery/probing,
DERP transport, and private DNS/routes. It may reuse or adapt relevant DERP
and path-management concepts/code from the checked-in netclient and Tailscale
sources, while remaining a client-to-selected-Ingress system rather than a
general mesh node.

The Edge Tunnel executable is a thin wrapper around reusable Go packages, not a
second networking implementation. Native applications embed its client
packages rather than spawn the normal executable. Edge Admin is the
control-plane authority; Edge Agent hosts the protected-side Ingress. Neither
is a data path between Tunnel and Ingress.

```text
Edge Tunnel packages   → client transport core and embeddable bindings
Edge Tunnel executable → headless CLI/daemon first
Edge Admin             → IngressTunneling domain and desired-state authority
Edge Agent             → protected-side Edge Ingress capability
```

Platform support is staged: binary first, then desktop, then mobile. Mobile clients use native platform shells:

```text
Swift  → Apple Packet Tunnel / Network Extension (iOS and macOS)
Kotlin → Android VpnService
```

Swift/Kotlin own operating-system VPN permissions, tunnel creation, lifecycle, UI, and packet handoff. The linked Go library owns shared networking behavior. Do not introduce Flutter or React Native into the initial design: neither replaces the required native VPN integration.

### Ingress and mesh behavior

The expected initial data-plane model is source NAT at the selected Edge Ingress:

```text
Edge Tunnel client
→ Edge Ingress
→ source NAT to Ingress protected-side identity
→ target node
```

This suits a client-only user device: protected-side resources do not need temporary user-client routes or addresses, and do not normally initiate new independent connections to phones/laptops. Replies return through Ingress session state.

#### Tunnel address realm and isolation (agreed so far)

Ingress Tunneling is not a second mesh. An Edge Ingress owns an isolated access realm
for its attached Edge Tunnel clients; that realm is never advertised into
the protected-side network. Admin must allocate an address uniquely **within that Ingress**, not
globally across every Ingress. `10.240.0.0/12` is the current candidate
allocation pool; its final size remains open.

For each configured CIDR pool, Admin reserves the **first usable address** for
the Ingress and allocates Tunnel Clients from the following addresses. `.1` and
`::1` are only the usual result when a pool starts at a conventional network
boundary; they are not a separately configured address rule. Core normalizes
each configured pool to its CIDR network boundary at boot.

```text
Ingress A: edgeingress0 = 10.240.0.1/32, fd20:240::1/128
Tunnel A1:               10.240.0.2/32, fd20:240::2/128
Tunnel A2:               10.240.0.3/32, fd20:240::3/128

Ingress B: edgeingress0 = 10.240.0.1/32, fd20:240::1/128
Tunnel B1:               10.240.0.2/32, fd20:240::2/128
```

The repeated addresses are intentional. Ingress A and B have separate
WireGuard key contexts and their clients attach to one Ingress at a time.
Neither ingress realm is routed into the protected-side network, and source
NAT means targets see the selected Ingress's protected-side identity, not a
Tunnel address.
The meaningful session identity is therefore:

```text
Ingress ID + Tunnel public key + session ID/generation
```

not an IP address alone. Every Tunnel peer and the Ingress tunnel interface
receive a `/32` and `/128`; a `/31` is only a two-address point-to-point
prefix and is not the right allocation unit for a many-client Ingress.

The prototype confirmed this existing allocation rule with two simultaneous
Tunnel clients: each active peer must have a distinct IPv4 **and** IPv6
transport address within one Ingress realm. WireGuard selects the encrypted
peer from its `AllowedIPs`; assigning the same destination `/32` or `/128` to
two public keys on one Ingress interface is invalid. This does not make those
addresses globally unique: a different isolated Ingress can intentionally
reuse the same assignments.

The allocation pool is not a connected interface subnet. Assigning the
first usable address with the pool prefix (for example, `10.240.0.1/12`) to
the Ingress would automatically claim a broad
`10.240.0.0/12` host route and could capture unrelated private/VPN traffic.
With that same first usable address as a `/32` (for example, `10.240.0.1/32`),
the Ingress owns only its own address and reconciles
exact per-Tunnel routes/peer mappings such as `10.240.0.2/32 → Tunnel A`.
This is more explicit but avoids broad route interference. Isolation comes
from per-peer WireGuard `AllowedIPs`, explicit routes and forwarding policy,
client-to-client forwarding denial, and source NAT—not from the prefix length
alone.

This model assumes Edge Tunnel remains client-only and has one active Ingress
at a time. It would need reconsidering if protected-side resources must
initiate independent connections to Tunnel devices or Tunnel clients must
communicate with each other.

Firezone is a useful contrast, not an address-model template: it assigns
account-wide unique client and gateway tunnel addresses from its shared
`100.64.0.0/11` tunnel range. That fits its broader account-wide resource and
policy model. It nevertheless normally prevents client-to-client transit;
device-to-device access is separately authorized. Ingress Tunneling's narrower
Ingress-NAT model permits per-Ingress address reuse without making the
addresses globally meaningful. Netmaker external clients are different again:
they receive a globally unique address from the Netmaker network range and are
indirect mesh participants. They peer directly only with an Ingress Gateway,
while other mesh nodes receive a route for that client address through the
Ingress. Ingress Tunneling does not adopt that global-address model.

### Control-plane direction

#### `IngressTunneling` domain: Tunnel clients and connections (agreed so far)

`EdgeAdmin.IngressTunneling` owns the long-lived Tunnel client, the existing
Ingress-capable Node, and their access relationship. There is no standalone
Ingress record: an enrolled Node is the Ingress identity.

```text
tunnel_clients
  long-lived external Tunnel client identity and public key

nodes
  existing enrolled Agent/Ingress identity and `Node.ingress_public_key`

tunnel_connections
  tunnel_client_id + node_id (unique composite key)
  explicit per-connection Ingress and Tunnel transport addresses, plus route scope
```

The Tunnel address belongs to `tunnel_connections`, not `tunnel_clients`, because it
is allocated within the selected Ingress's isolated realm. Every existing
Admin-side Tunnel Connection row is authorized; Admin stores no active flag or
connection-status state. A Tunnel may retain multiple connection records.

The installed Edge Tunnel client chooses exactly one imported connection as its
local active connection. That client-local selection supplies its local Tunnel
address, selected Ingress peer, routes, and path state. Switching Ingress is a
local client selection/state change; it does not change Admin-side
authorization or the existence of another Tunnel Connection row.

This restriction is intentional. Normal WireGuard accepts overlapping
`AllowedIPs` and uses longest-prefix routing; identical peer prefixes do not
create two usable paths—the last configured peer takes ownership of that exact
prefix. Edge Ingress route scopes are expected to overlap, so Ingress Tunneling must not
attempt to activate several such peers on one Tunnel interface. A future
simultaneous-Ingress design would need separate interfaces or network
namespaces per Ingress.

Tunnel creation and connection creation are Admin-provisioned. A Tunnel row
exists before a Tunnel Connection, and the Tunnel owns its WireGuard keypair;
the connection does not. Admin generates and stores that keypair on the Tunnel
row. Generating connection material reuses that stored private key; it does not
silently create or rotate a new identity. The installed Edge Tunnel then holds
the private key in order to operate it.

```text
create Tunnel
→ Admin creates the TunnelClient record and its WireGuard keypair

create tunnel_connection
→ Admin reads the selected TunnelClient and Node records
→ Admin creates the connection and records its Ingress and Tunnel transport-address pair
→ Admin reconciles the new Tunnel peer into the Agent Ingress desired state
→ Admin can generate delivery material for use by the Edge Tunnel client
```

There is no Tunnel self-registration or enrollment-key lifecycle in this
direction. The generated configuration is the access credential for the
already-created Tunnel and Tunnel Connection. It may be delivered as a file,
URL, or QR code; those are delivery forms, not distinct identities.

#### Tunnel Connection artifact delivery (agreed)

The primary delivery mechanism is an expiring download URL. Admin exposes:

```text
POST /api/v1/tunnel_connections/:id/generate
```

It reads the existing Tunnel, Tunnel Connection, selected Node/Ingress, and
cluster configuration, then creates a temporary artifact-download grant. The
response is JSON:

```json
{
  "tunnel_connection_id": "uuid",
  "download_url": "https://admin.example.com/api/v1/tunnel_connection_artifacts/opaque-token/download",
  "expires_at": "2026-09-14T12:30:00Z"
}
```

The `download_url` returns the generated managed Tunnel JSON artifact. A
browser, CLI, or Edge Tunnel itself can download/import it. Generation is a
delivery operation only: it does not alter the connection's authorization,
allocate a new address, rotate the stored Tunnel keypair, or cause a new
Ingress desired-state update.

QR is optional convenience above this API contract. A higher-level client may
render the returned `download_url` as a QR image for Edge Tunnel to scan and
fetch. The QR contains the URL, never the private-key-bearing JSON artifact.
Admin does not need a QR UI or a second QR-specific configuration format.

#### Initial Tunnel Connection artifact (agreed)

The initial artifact is a managed Edge Tunnel configuration, not a stock
WireGuard `.conf` file. Its minimal agreed shape is:

```json
{
  "tunnel_connection_id": "uuid",
  "tunnel_private_key": "…",

  "ingress_public_key": "…",
  "ingress_ipv4_address": "10.240.0.1/32",
  "ingress_ipv6_address": "fd20:240::1/128",
  "tunnel_ipv4_address": "10.240.0.2/32",
  "tunnel_ipv6_address": "fd20:240::2/128",

  "ingress_dns_endpoint": "10.240.0.1:53",
  "vpn_dns_suffix": "cluster-1.nm.internal",
  "vpn_ipv4_range": "100.64.0.0/24",
  "vpn_ipv6_range": "fd7a:…/64",

  "core_derp_map_urls": [
    "https://relay-new.example.com/derpmap/default",
    "https://relay-old.example.com/derpmap/default"
  ],
  "core_stun_servers": [
    "stun1.l.google.com:19302",
    "stun2.l.google.com:19302",
    "stun3.l.google.com:19302",
    "stun4.l.google.com:19302"
  ]
}
```

| Field | Purpose |
| --- | --- |
| `tunnel_connection_id` | Local identity, display, active-selection, and replacement target for this imported connection. It is not a WireGuard field. |
| `tunnel_private_key` | Tunnel's local WireGuard identity; its public key is derivable. |
| `ingress_public_key` | The selected Ingress's `Node.ingress_public_key`: the only remote peer the Tunnel trusts for this connection. |
| `ingress_ipv4_address` | The first usable IPv4 `/32` in this connection's selected Ingress pool. It is stored on the connection so artifact generation does not need to infer it from later deployment configuration. The Tunnel derives a WireGuard peer route for it. |
| `ingress_ipv6_address` | The corresponding first usable IPv6 `/128` in the selected Ingress pool, likewise stored explicitly. |
| `tunnel_ipv4_address` | Tunnel's IPv4 `/32` inside the selected Ingress realm. Required for the inner OS-level VPN routing model even when DERP carries every outer packet. |
| `tunnel_ipv6_address` | Tunnel's distinct `/128` inside the selected Ingress realm. It provides the IPv6 source/return path for protected IPv6 traffic. |
| `ingress_dns_endpoint` | The DNS listener reached through Ingress for this connection's private DNS suffix. |
| `vpn_dns_suffix` | The selected cluster's private DNS suffix. Edge Tunnel installs split DNS only for this suffix. |
| `vpn_ipv4_range` | The selected cluster's Netmaker IPv4 range. Edge Tunnel derives its peer `AllowedIPs` and OS route from it. |
| `vpn_ipv6_range` | The selected cluster's Netmaker IPv6 range. Core supports IPv6 and this field is always present. A Tunnel device without usable IPv6 is the exceptional platform case. |
| `core_derp_map_urls` | Ordered mirror or hostname-migration sources for one complete canonical Core DERP map. |
| `core_stun_servers` | STUN server endpoints used only for opportunistic direct-path candidate discovery. |

The artifact needs no fixed Ingress UDP endpoint, STUN result, Admin URL,
Admin API token, refresh token, MQTT/WebSocket credential, peer list, or
individual Agent IP/hostname list. Direct UDP is an opportunistic peer-to-peer
upgrade discovered after DERP reachability exists. STUN is an optional
direct-path optimization; it is not required for DERP-only connectivity.

#### Shared Core DERP map contract (agreed)

Ingress and Tunnel use the same Core DERP-map contract as Admin and Agent; do
not create a separate Ingress/Tunnel relay-map configuration. The Core map
sources describe one canonical complete map, not an ordered list of individual
relay servers.

```text
Admin deployment: CORE_DERP_MAP_URLS
→ Admin netclient receives that map contract at startup
→ Admin registration/settings refresh returns core_derp_map_urls to Agents
→ Agent persists and caches the first usable complete map
→ Agent-local /api/v1/derp_map reflection serves Agent netclient and Edge Ingress

Tunnel Connection artifact: core_derp_map_urls
→ Edge Tunnel fetches the same public map sources directly
```

The first usable Core map source wins; maps are never merged. If no Core source
is usable, the client falls back to the Tailscale public map. A successfully
fetched self-hosted-only map does not merge in public Tailscale relays merely
because one of its relay nodes later fails.

Ingress receives the full dynamic Agent behavior: Admin settings refresh can
teach Agent new map-source URLs, and the Agent cache/reflection supplies the
latest usable map. Tunnel has no Admin refresh channel in the initial model;
it can refresh the contents of its known map URLs, but cannot discover an
entirely new URL without reissued/imported connection material.

Therefore a Tunnel artifact containing both a new and old URL supports the
normal migration behavior: it tries the new source first and falls back to the
old source, provided both serve the same complete canonical map. An artifact
that knows only an old URL needs that old source retained or replacement
connection material before the old source is retired.

#### Core STUN server contract (agreed)

Use the term **STUN servers**, not STUN URLs: the configuration values are
network endpoints in `host:port` form, not HTTP URLs. The deployment setting
is `CORE_STUN_SERVERS`; advertised configuration uses `core_stun_servers`.

When no deployment override is supplied, the built-in default is:

```text
stun1.l.google.com:19302
stun2.l.google.com:19302
stun3.l.google.com:19302
stun4.l.google.com:19302
```

`CORE_STUN_SERVERS` strictly replaces this list; it never appends to it. An
operator supplying regional or self-hosted STUN infrastructure should not
silently continue probing third-party public STUN servers. Ingress receives the
effective list through Agent/Admin desired-state refresh; Tunnel receives it
in its imported connection artifact.

Ingress and Tunnel may use the same effective list for predictable operation,
but that is not a correctness requirement. Each side can discover its own
candidate addresses through different STUN servers and exchange those
candidates over DERP. STUN remains a direct-path optimization; DERP-only
connectivity does not require STUN.

#### Configuration reissue and replacement (agreed)

There is no Tunnel refresh credential, background refresh, or permanent
Tunnel → Admin control session in the initial model. When a user needs current
connection material, they manually generate/reissue a new artifact from
Admin, then import it into Edge Tunnel.

An import for an existing `tunnel_connection_id` replaces that local
configuration after it has been accepted successfully. It must not require the
user to delete the working configuration before importing a replacement.
Admin-side peer removal remains the revocation mechanism: a stale imported
artifact cannot carry authorized traffic once Ingress desired state no longer
contains its Tunnel public key.

This makes the configuration transferable by design. Two devices importing the
same configuration are the same WireGuard/API identity: they share the Tunnel
address and authorization, can displace each other's current WireGuard endpoint,
and cannot be distinguished or revoked separately. If separate physical-device
identity becomes a requirement, a device-registration/bootstrap lifecycle must
be added; it cannot be inferred from a copied credential.

Edge Tunnel has no profile abstraction. Its local state is a flat registry of
imported Tunnel Connections, each keyed by its globally unique
`tunnel_connection_id` UUID:

```text
tunnel_connection_id
  → imported connection configuration
  → DERP/path state and display metadata
  → client-local active/inactive selection state
```

The UUID is the local connection identifier, not a server locator or trust
root.
Admin remains authoritative: deleting a TunnelClient or TunnelConnection does
not have to delete its local cached record, but it prevents that stale record
from receiving valid configuration or carrying authorized traffic.

Tunnel does not need a permanent Admin connection for ordinary operation. Once
it has imported valid Tunnel Connection material, its live peer discovery,
direct-path upgrade, and DERP fallback are Tunnel ↔ Ingress behavior. An Admin
refresh is for an explicit user sync, imported replacement configuration, or a
future deliberately chosen refresh policy—not a requirement for the active
data path.

The native Edge Tunnel engine retains normal WireGuard concepts—local private
key, Tunnel IP, selected `Node.ingress_public_key`, `AllowedIPs`, and a direct UDP endpoint
when usable. It is WireGuard-based, but stock WireGuard configuration
compatibility is not a product requirement: Edge Tunnel is a managed Core
client, not a generic enhanced `wg` replacement. Its UUID-keyed connection
state contains the imported connection material and dynamic path information
alongside its WireGuard state.

Edge Ingress does not have separate enrollment, an Ingress API token, or an
independent lifecycle. The Agent's existing Node registration/reregistration
is its lifecycle. The Agent provides its Ingress WireGuard public key to Admin
as part of that lifecycle; Admin stores it as `Node.ingress_public_key`.

```text
Agent Node registration/reregistration
→ Admin authenticates the existing Agent identity
→ Agent provides current `ingress_public_key`
→ Admin stores it as `Node.ingress_public_key`
→ Admin returns current Ingress desired state
```

The Ingress WireGuard private key is generated or durably loaded on the Agent;
only its associated public key reaches Admin as `Node.ingress_public_key` for
peer/session coordination.

A fixed public UDP endpoint is not Ingress identity or registration state.
NAT mappings and public ports can change. Direct-path candidates are dynamic,
per-session reachability information exchanged only after an Edge Tunnel ↔
Ingress session exists; DERP does not require such an endpoint.

### Ingress desired state and realtime transport

Admin's database is authoritative. The desired state for an Ingress is its
complete current set of Edge Tunnel peers and their session configuration, not
an append-only queue of add/remove-peer commands.

```text
Agent registration/reregistration
→ Admin stores the current key as Node.ingress_public_key
→ Admin returns the complete current Ingress snapshot, including an empty peer set
→ Agent durably stores that snapshot in its SQLite database
→ a separate Ingress reconciler converges the live interface to that snapshot

connection change
→ Admin calculates the current complete snapshot from Tunnel Connection rows and deployment configuration
→ existing Admin → Agent HTTP delivery sends that snapshot best-effort
→ Agent stores the latest snapshot in SQLite
→ the same reconciler converges the live interface

→ startup/reregistration obtains the complete snapshot again
→ polling provides recovery when realtime delivery is unavailable
```

This deliberately follows the existing Core resilience pattern: push for
speed, full pull/sync for correctness. A missed peer-removal message must not
leave access active indefinitely.

Delivery and reconciliation are deliberately decoupled by Agent SQLite. The
HTTP/polling path only persists the newest complete desired state; it does not
change the live interface itself. The reconciler reads durable state and
applies it idempotently. Repeated delivery is harmless, rapid changes can
coalesce to the newest snapshot, and a crash after receipt but before
reconciliation recovers from the stored snapshot.

The Ingress snapshot is the inverse of the one-peer Tunnel Connection
artifact: it contains the Ingress's local tunnel configuration and every
currently authorized Tunnel peer. Its agreed conceptual shape is:

```json
{
  "ingress_public_key": "…",
  "ingress_ipv4_address": "10.240.0.1/32",
  "ingress_ipv6_address": "fd20:240::1/128",
  "vpn_dns_suffix": "cluster-1.nm.internal",
  "vpn_ipv4_range": "100.64.0.0/24",
  "vpn_ipv6_range": "fd7a:…/64",
  "core_derp_map_urls": ["https://…/derpmap/default"],
  "core_stun_servers": ["stun1.l.google.com:19302"],
  "peers": [
    {
      "tunnel_connection_id": "uuid",
      "tunnel_public_key": "…",
      "tunnel_ipv4_address": "10.240.0.2/32",
      "tunnel_ipv6_address": "fd20:240::2/128",
      "allowed_ips": ["10.240.0.2/32", "fd20:240::2/128"]
    }
  ]
}
```

Ingress retains its own private key locally. The snapshot never contains a
Tunnel private key, a fixed public UDP endpoint, or STUN-discovered candidates:
those are either private credentials or dynamic Tunnel ↔ Ingress path state.

This is deliberately asymmetric with Tunnel behavior: an Ingress needs
continuous desired-state reconciliation because its permitted Tunnel peers can
change over time. A Tunnel needs no corresponding long-lived coordination
channel merely to keep an already-provisioned connection alive.

Do not add a separate MQTT/EMQX control path merely for Ingress
reconciliation. Core's existing Admin ↔ Agent VPN HTTP path, direct push, and
full-sync/polling recovery are the intended first transport.

### Private naming and cluster-only forwarding (agreed)

Edge Tunnel access is cluster-wide, not a Firezone-style list of arbitrary
resources behind an Ingress. A Tunnel connected through an Ingress may reach
the selected cluster's Netmaker mesh by its VPN hostname; it must not become a
general route to arbitrary LAN addresses or the Internet reachable by that
Ingress.

This needs two independent rules in the imported connection configuration:

```text
VPN DNS suffix
→ select private DNS resolution through the selected Ingress

Netmaker IPv4/IPv6 range
→ select IP-packet routing through the selected Ingress
```

DNS selects an address; packets no longer contain the hostname after that
lookup. A DNS suffix alone cannot route the resulting mesh IP, and a mesh
subnet route alone cannot resolve VPN hostnames. The configuration carries the
cluster's two ranges, not a list of Agent addresses, so Agent joins and leaves
do not require a Tunnel configuration update.

```text
node-a.cluster-1.nm.internal
→ Edge Tunnel split DNS query
→ Ingress DNS endpoint
→ host-local netclient DNS resolver
→ Node A mesh IP
→ Edge Tunnel cluster-range route
→ Ingress
→ host Netmaker interface
→ Node A
```

Ingress forwards DNS queries to the host-local netclient DNS resolver. It
forwards IP traffic only from its attached Tunnel realm to the selected
cluster's Netmaker IPv4/IPv6 ranges through the host's Netmaker interface, and
source-NATs it to its own Netmaker identity. This lets ordinary mesh reply
routing work without teaching every Agent a route back to Tunnel addresses.
It must not forward arbitrary LAN or Internet destinations.

Edge Tunnel installs split DNS only for the selected cluster suffix. Ordinary
device DNS and the default route remain unchanged. Private-name lookup must
fail when the Ingress DNS path is unavailable rather than falling through to
public DNS. The prior stock-WireGuard failure—installing the ingress VPN DNS
address as device-wide DNS, then losing ordinary names when that tunnel was
unreachable—is explicitly avoided.

Activation must fail with a specific error when an advertised cluster IPv4 or
IPv6 range conflicts with an existing local route on the Tunnel device. It
must never silently choose a route. This is the available honest handling for
customer-controlled local ranges.

VPN hostnames are the intended UX, but a user who knows a resolved mesh IP can
technically use it: packet routing happens after DNS and cannot enforce
hostname-only access. This is accepted within the existing cluster-wide trust
boundary.

### Ingress Tunneling questions still to resolve

1. Which netclient/Tailscale-derived packages can be reused or adapted safely for the Go core, versus reimplemented behind a small Edge Tunnel-specific interface?
2. How is the cluster split-DNS resolver exposed through Ingress on each supported Tunnel platform?
3. How are Ingress selection, session expiry, revocation, capacity, and reconnect failover represented?
4. What relay topology, authentication, placement, and failure behavior fit Edge Tunnel?
5. What direct-LAN optimizations, offline behavior, background-VPN constraints, battery limits, MDM constraints, and mobile-store restrictions are honest on each platform?

## Delegated Agent/proxy access — secondary research topic

The desired operation is explicit selection of another Agent's local-network vantage point:

```text
workload or Agent on node-a → node-b proxy → service near node-b
```

Do not expose an Agent's long-lived `proxy_password` in normal node/API reads. The tentative direction to evaluate is an Admin-issued, short-lived scoped proxy ticket bound to caller, target, cluster, expiry, and optionally destination CIDR/host/port/protocol. The target Agent verifies the ticket before allowing the proxy use.

This requires a real product decision before implementation: establish whether the intended caller is another Agent, a workload, an external API client, or all three; then define revocation, key distribution, HTTP CONNECT/SOCKS enforcement, auditing, and proxy-chain behavior. Do not accidentally turn this into implicit network egress or universal cluster-member exit access.

## ACL and policy model — discussion only

The current model remains: a cluster is the trust boundary. Nodes in one cluster are intended to cooperate; strong isolation is achieved by creating another cluster/network. No granular node-to-node ACL feature is committed.

The checked-in Netmaker source has a node-to-node `device-policy` ACL API, but its model is not presently a fit for an open network with selective restrictions:

- Every newly created Netmaker network automatically receives an enabled, per-network `all-nodes` policy: every node may reach every other node on every protocol and port. This is not an environment setting and the network-create API has no default-deny or initial-policy field.
- Custom device policies are positive allows only: a specific node (or `*`) may communicate with another specific node (or `*`) on selected TCP, UDP, ICMP, or all ports/protocols. There are no deny clauses, priorities, or deny-overrides-allow semantics.
- While `all-nodes` remains enabled, custom policies add no restriction. To activate policy enforcement, that built-in policy must be disabled; the network then becomes default-deny and only traffic covered by enabled custom policies passes.
- In the checked-in non-Pro path, enrollment-key groups do not apply node tags, so tag/group-based device policies are not a usable grouping mechanism for Core. The practical selector is an individual Netmaker node ID (or `*`).
- Device policies are bidirectional in this source path. They can restrict a node pair to TCP port `8000`, for example, but do not express a one-way initiation rule.

Therefore, do not implement this feature from the current research. The desired policy experience is open-by-default with explicit restrictive/deny exceptions; Netmaker device policies instead require a deliberate switch to closed-by-default followed by allow-list construction. Revisit only if the product requirement changes, a different enforcement model is chosen, or a demonstrated access-separation requirement cannot honestly be solved by separate clusters, explicit proxy delegation, or application authentication.

## Operational follow-through

These are implementation and qualification tasks, not open product architecture:

- Run the Linux Docker-host qualification plan on native amd64 and arm64: frequent Ubuntu smoke coverage, plus release coverage for Ubuntu 24.04/26.04, Debian 13, Rocky/RHEL-compatible 10, Alpine 3.24, and Raspberry Pi OS Lite.
- Add actionable host preflight diagnostics for resolver, firewall, route, SELinux, storage, init, and hardware constraints.
- Maintain Netmaker/netclient version pinning, canary/upgrade/rollback procedures, compatibility tests, and the fork-patch inventory.
- Test supported multiple-VPN combinations and report route, address, DNS, firewall, and MTU conflicts clearly.
- Benchmark Admin clustering before redesigning it.

## Revisit triggers

- Agent migration to Go is committed for mid-V3; its detailed plan and sequencing will be decided separately.
- Revisit Alpine only for a measured image/storage/startup/operational constraint.
- Revisit bandwidth shaping only for concrete customer demand and Core-owned traffic scope.
- Revisit Netmaker server forking only for a concrete upstream limitation meeting the criteria above.
