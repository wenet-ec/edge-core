# Edge Admin MCP — v0.2.0

Tool catalog for every operation the Edge Admin MCP server exposes at `POST /mcp`. Companion to [`guide.md` §4](guide.md#4-mcp--ai-assistant-access) — that section explains how to connect; this page enumerates what's available once you do.

## Why this exists

Unlike OpenAPI (REST) and AsyncAPI (events), the [Model Context Protocol](https://modelcontextprotocol.io) does not yet have a standardised static spec format or off-the-shelf renderer. Discovery happens at runtime via the `tools/list` JSON-RPC method — any connected MCP client (Claude Desktop, Cursor, mcp-inspector) sees the live list. Operators who don't run a client also deserve visibility into what's there, so we maintain this catalog by hand.

For interactive browsing of the live surface, run [`@modelcontextprotocol/inspector`](https://github.com/modelcontextprotocol/inspector) against `/mcp` with your `MCP_KEY`.

## Reading this catalog

- **Required parameters** are listed before optional ones; the parameter name links to the tool's input contract.
- **List tools** all accept `page`, `page_size`, `order_by`, and `order_directions` unless noted otherwise.
- **Annotations** in the tool table use MCP-standard hints:
  - 🔍 `readOnlyHint` — does not mutate state
  - ⚠️ `destructiveHint` — irreversible or fleet-affecting
  - ♻️ `idempotentHint` — safe to retry
  - 🌐 `openWorldHint` — calls external systems (Netmaker, agents, exporters)
- Write tools whose REST counterpart is gated by degraded-mode are also blocked here — see [§ Operations blocked in degraded mode](#operations-blocked-in-degraded-mode) below.

One MCP-only tool (`check_admin_health`) has no REST equivalent; every other tool maps 1:1 to a REST endpoint documented in [`admin-openapi-v0.2.0.json`](admin-openapi-v0.2.0.json).

### Filter value conventions

MCP list tools use typed parameters rather than REST query strings:

- **Wildcard text filters** — single-value string parameter. `*` matches prefix (`prod*`), suffix (`*east`), or contains (`*prod*`). Examples: `cluster_name: "prod*"`, `username: "*admin"`.
- **IN filters** — `<field>_in` array parameter. Passes one or more exact values; any match is returned. Single-element arrays work. Examples: `cluster_name_in: ["prod", "staging"]`, `status_in: ["healthy", "unhealthy"]`, `node_id_in: ["<uuid>"]`. This mirrors the REST `__in` operator (`?cluster_name__in=prod,staging`).
- **Boolean filters** are native JSON booleans: `true` or `false`. MCP Inspector
  renders these as checkbox controls. If sending raw JSON, do not quote boolean
  values; `"true"` / `"false"` are strings and will be rejected by MCP
  validation.
- **Range filters** use `_gte` / `_lte` suffixes: `inserted_at_gte`, `timeout_lte`. Mirrors the REST `__gte` / `__lte` operators.
- REST-only operators (`field__null`, bare comma `field=a,b`) have no MCP equivalent — use the explicit `has_*` / `is_*` booleans and `_in` arrays instead.

---

## 1. Admin info

The local admin instance's identity, its admin-cluster topology, and cross-cluster discovery of other admins.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `get_admin` | Get Admin Info | 🔍 | This admin's metadata: id, name, peer capacity, last recompute time. |
| `get_my_admin_cluster` | Get This Admin's Admin Cluster | 🔍 | This admin's admin-cluster — totals, topology, weak leader. |
| `list_admin_clusters` | List All Admin Clusters | 🔍 🌐 | Every admin cluster Netmaker knows about (incl. zombies). |
| `list_edge_clusters` | List Edge Clusters (Admin View) | 🔍 | Edge clusters grouped by owning admin instance. |
| `list_orphaned_clusters` | List Orphaned Clusters | 🔍 | Clusters with no assigned admin — cannot receive commands. |
| `check_admin_health` | Check Admin Health | 🔍 | **MCP-only.** Runs every subsystem check in parallel: DB, Membership, Metadata, Netmaker API, Netclient, Proxy Servers, Event Broker. Same checks as `/healthz`, flattened for AI consumption. |

All six tools take no parameters.

---

## 2. Clusters

Logical groups that map 1:1 to Netmaker WireGuard networks. One full mesh per cluster.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_clusters` | List Clusters | 🔍 | Filter/sort/paginate. Filters: `name` (wildcard), `name_in` (array), `node_id_in` (array), `ipv4_range`, `node_count_gte/lte`, `node_limit`, `node_limit_gte/lte`, `has_node_limit`, `inserted_at_*`, `updated_at_*`. |
| `get_cluster` | Get Cluster | 🔍 | Required: `cluster_name`. |
| `create_cluster` | Create Cluster | 🌐 | Required: `name` (lowercase alphanumeric + hyphens, ≤24 chars, `default` reserved). Optional: `ipv4_range` (CIDR — auto-assigned if omitted), `node_limit`. |
| `update_cluster` | Update Cluster | ♻️ | Required: `cluster_name`. Optional: `node_limit` (pass `null` to remove the limit). |
| `delete_cluster` | Delete Cluster | ⚠️ 🌐 | Required: `cluster_name`. Deletes the VPN network — all nodes lose connectivity. |

---

## 3. Nodes

Edge machines running the agent. Addressed only by VPN hostname.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_nodes` | List Nodes | 🔍 | Filter/sort/paginate. Filters: `node_id_in` (array), `status_in` (array: `healthy`/`unhealthy`/`unreachable`), `id_type_in` (array: `persistent`/`random`), `cluster_name` (wildcard), `cluster_name_in` (array), `version`, `self_update_enabled`, `last_seen_at_*`, `inserted_at_*`, `updated_at_*`. |
| `get_node` | Get Node | 🔍 | Required: `node_id`. |
| `delete_node` | Delete Node | ⚠️ 🌐 | Required: `node_id`. Removes from VPN mesh — agent must re-enroll. |
| `change_node_cluster` | Move Node to Cluster | ⚠️ 🌐 | Required: `node_id`, `cluster_name`. Best-effort, not transactional — reconciliation worker heals inconsistencies. |

---

## 4. Aliases

Friendly DNS names for nodes. Resolved as `<alias>.<cluster>.<vpn_domain>`.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_aliases` | List Aliases | 🔍 | Filter/sort/paginate. Filters: `name` (wildcard), `node_id_in` (array), `cluster_name` (wildcard), `cluster_name_in` (array), `inserted_at_*`, `updated_at_*`. |
| `get_alias` | Get Alias | 🔍 | Required: `alias_id`. |
| `create_alias` | Create Alias | 🌐 | Required: `node_id`, `name` (lowercase alphanumeric + hyphens, 1–63 chars). |
| `delete_alias` | Delete Alias | ⚠️ 🌐 | Required: `alias_id`. |

---

## 5. Enrollment keys

Tokens agents use to join a cluster's VPN mesh.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_enrollment_keys` | List Enrollment Keys | 🔍 | Filter/sort/paginate. Filters: `cluster_name` (wildcard), `cluster_name_in` (array), `name`, `has_name`, `key`, `uses_remaining`, `uses_remaining_gte/lte`, `is_unlimited`, `is_spent`, `is_expired`, `is_never_used`, `has_expiry`, `expires_at_*`, `last_used_at_*`, `inserted_at_*`, `updated_at_*`. |
| `get_enrollment_key` | Get Enrollment Key | 🔍 | Required: `enrollment_key_id`. |
| `create_enrollment_key` | Create Enrollment Key | | Required: `cluster_name`. Optional: `name` (label), `uses_remaining` (default 1), `expires_at` (ISO8601). |
| `update_enrollment_key` | Update Enrollment Key | ♻️ | Required: `enrollment_key_id`. Optional: `name`, `uses_remaining`, `expires_at`. Pass `null` on any field to clear it (unlimited / no expiry / no label). |
| `delete_enrollment_key` | Delete Enrollment Key | ⚠️ | Required: `enrollment_key_id`. |

---

## 6. Commands

Shell jobs fanned out across the fleet. Creating a command produces one `command_execution` per targeted node.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_commands` | List Commands | 🔍 | Filter/sort/paginate. Filters: `command_text`, `has_timeout`, `timeout_gte/lte`, `has_expires_at`, `expires_at_*`, `inserted_at_*`, `updated_at_*`. |
| `get_command` | Get Command | 🔍 | Required: `command_id`. |
| `create_command` | Create Command | | Required: `command_text` (multi-line shell supported), `targeting` (see below). Optional: `timeout` (ms), `expires_at` (ISO8601, future). |
| `delete_command` | Delete Command | ⚠️ | Required: `command_id`. Only deletes commands where every execution is terminal. |

**Targeting** (required nested object on `create_command`):

- `%{"type" => "all"}` — every node in the fleet
- `%{"type" => "nodes", "node_ids" => [...]}` — explicit list
- `%{"type" => "clusters", "cluster_names" => [...]}` — by cluster

Both `nodes` and `clusters` forms accept optional `node_filters` / `cluster_filters` for AND-refinement.

### Command executions

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_command_executions` | List Command Executions | 🔍 | Filter/sort/paginate. Filters: `command_id_in` (array), `node_id_in` (array), `status_in` (array: `pending`/`sent`/`completed`/`cancelled`/`expired`), `target_all`, `exit_code`, `exit_code_gte/lte`, `output` (wildcard text search), `has_output`, `cluster_name` (wildcard), `cluster_name_in` (array), `has_cluster`, `inserted_at_*`, `updated_at_*`, `sent_at_*`, `completed_at_*`, `cancelled_at_*`. |
| `get_command_execution` | Get Command Execution | 🔍 | Required: `execution_id`. Returns status, output, exit code, timestamps. |
| `cancel_command_execution` | Cancel Command Execution | ⚠️ | Required: `execution_id`. `pending` → cancelled immediately. `sent` → cancellation forwarded to agent (best-effort). Terminal statuses return 409. |
| `delete_command_execution` | Delete Command Execution | ⚠️ | Required: `execution_id`. Only terminal executions can be deleted. |

`completed` is the only terminal *success* status — read `exit_code` to distinguish success (0) from failure (non-zero).

---

## 7. SSH usernames

Centralised SSH credentials. The agent's embedded SSH server (`:40022`) verifies against these via the admin.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_ssh_usernames` | List SSH Usernames | 🔍 | Filter/sort/paginate. Filters: `username` (wildcard), `username_in` (array), `node_id_in` (array), `has_password`, `cluster_name` (wildcard), `cluster_name_in` (array), `key_name` (wildcard), `key_name_in` (array), `inserted_at_*`, `updated_at_*`. |
| `get_ssh_username` | Get SSH Username | 🔍 | Required: `ssh_username_id`. |
| `create_ssh_username` | Create SSH Username | | Required: `node_id`, `username` (3–32 chars, starts with letter or `_`, lowercase + digits + hyphens + underscores). Optional: `password` (12–128 chars, Argon2-hashed at rest), `public_keys` (list of `%{key_name, public_key}`). |
| `delete_ssh_username` | Delete SSH Username | ⚠️ | Required: `ssh_username_id`. Deletes all associated public keys. |

---

## 8. SSH public keys

Authorized keys attached to a username.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_ssh_public_keys` | List SSH Public Keys | 🔍 | Filter/sort/paginate. Filters: `ssh_username_id_in` (array), `node_id_in` (array), `username` (wildcard), `username_in` (array), `key_name` (wildcard), `key_name_in` (array), `public_key`, `cluster_name` (wildcard), `cluster_name_in` (array), `inserted_at_*`, `updated_at_*`. |
| `get_ssh_public_key` | Get SSH Public Key | 🔍 | Required: `ssh_public_key_id`. |
| `create_ssh_public_key` | Create SSH Public Key | | Required: `ssh_username_id`, `public_key` (OpenSSH format: `ssh-ed25519`, `ecdsa-sha2-nistp256/384/521`, `ssh-rsa`), `key_name` (1–255 chars, unique within the username). |
| `delete_ssh_public_key` | Delete SSH Public Key | ⚠️ | Required: `ssh_public_key_id`. |

---

## 9. Self-update requests

Managed agent upgrades across the fleet.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_self_update_requests` | List Self-Update Requests | 🔍 | Filter/sort/paginate. Filters: `status_in` (array: `pending`/`processing`/`completed`), `inserted_at_*`, `updated_at_*`. |
| `get_self_update_request` | Get Self-Update Request | 🔍 | Required: `request_id`. Watch `status` and `summary` (`%{total, triggered, failed}`). |
| `create_self_update_request` | Create Self-Update Request | ⚠️ | Required: `targeting` (same shape as `create_command`). Only healthy nodes with `self_update_enabled=true` are updated. No cancel — durable once triggered. |
| `delete_self_update_request` | Delete Self-Update Request | ⚠️ | Required: `request_id`. Only `completed` requests can be deleted. |

---

## 10. Metrics

Parsed, human-friendly JSON (not raw Prometheus text). For scraping endpoints see [`guide.md` §6](guide.md#6-metrics).

| Tool | Title | Hints | Description |
|---|---|---|---|
| `get_node_metrics` | Get Node Metrics | 🔍 🌐 | Required: `node_id`. Unified host + agent sources. Best-effort: if one source fails, that section is reported unavailable. Always returns ok — verify the node exists first with `get_node` if you need to distinguish "missing" from "not scraping". |
| `get_host_metrics` | Get Host Metrics | 🔍 🌐 | Required: `node_id`. From Node Exporter: CPU, memory, disk, uptime. |
| `get_agent_metrics` | Get Agent Metrics | 🔍 🌐 | Required: `node_id`. From edge_agent PromEx: BEAM, commands, discovery, proxy, SSH, VPN pulls, health check reports, Oban queues. |
| `get_admin_metrics` | Get Admin Metrics | 🔍 | No parameters. 16 sections covering this admin's full operational surface: `application`, `metadata`, `membership`, `discovery`, `nodes`, `quantum`, `vpn`, `commands`, `ssh`, `reconciliation`, `self_updates`, `gateways`, `proxy`, `event_broker`, `webhook`, `oban_queues`. |

---

## 11. Webhooks

User-configured HTTP delivery destinations for events. Webhooks are **immutable** after create — to change a field, delete and recreate.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_webhooks` | List Webhooks | 🔍 | Filter/sort/paginate. Filters: `url`, `event_type` (post-filter: which webhooks fire on this event), `inserted_at_*`, `updated_at_*`. Secret and headers are never returned. |
| `get_webhook` | Get Webhook | 🔍 | Required: `webhook_id`. Secret and headers are never returned. |
| `create_webhook` | Create Webhook | | Required: `url` (absolute http(s), ≤2048 chars, SSRF-checked), `secret` (HMAC-SHA256 key, 32–256 chars), `subscribed_events` (explicit list, 1–20 known event types). Optional: `headers` (≤20 entries, values ≤4096 chars). |
| `delete_webhook` | Delete Webhook | ⚠️ | Required: `webhook_id`. There is no enable/disable toggle — delete to pause delivery. |

## 12. Event catalog

MCP-only tools surfacing the same content as `/asyncdoc`. Useful when picking values for `create_webhook`'s `subscribed_events`.

| Tool | Title | Hints | Description |
|---|---|---|---|
| `list_event_types` | List Event Types | 🔍 | No parameters. Returns `%{event_types: [%{type, description}, ...], count}`. |
| `explain_event_type` | Explain Event Type | 🔍 | Required: `event_type`. Returns `%{type, description, data_example, reference}` — the `data` payload shape inside the CloudEvents envelope. |

---

## Operations blocked in degraded mode

When the admin is in degraded mode (total nodes exceed total edge-capacity across the admin cluster), the following write tools return a degraded-mode error. Reads, alias ops, webhook ops, SSH ops, and commands all run unconditionally.

```
create_cluster              update_cluster              delete_cluster
change_node_cluster         delete_node
create_enrollment_key       update_enrollment_key       delete_enrollment_key
create_self_update_request
```

This mirrors the REST degraded-mode block list — same operations are blocked on both surfaces.
