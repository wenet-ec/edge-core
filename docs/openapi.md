# REST API

The REST API is documented as an OpenAPI 3.x spec. The static spec is kept in this docs site for download and client generation, but the full rendered reference is not embedded here because it is large and keeps growing.

## OpenAPI spec

- Static spec: [`admin-openapi-v0.2.0.json`](admin-openapi-v0.2.0.json)
- Running admin spec: `GET /api/openapi`

The running admin's `/api/openapi` is authoritative for that deployed version. Use the static spec when reading this docs version offline or feeding a known release into client generators.

## Interactive reference

On a running Edge Admin:

- `/swaggerui` — best for trying requests from the browser
- `/redoc` — best for reading the full API reference end-to-end

## Endpoint groups

The management API is organized around these groups:

| Group | What it covers |
|---|---|
| Admin info | Local admin metadata, admin-cluster topology, edge-cluster ownership, orphaned clusters. |
| Clusters | Edge cluster lifecycle, node limits, and WireGuard network backing. |
| Nodes | Registered edge nodes, health status, cluster moves, and node deletion. |
| Aliases | Friendly VPN DNS aliases for nodes. |
| Enrollment keys | Tokens used by agents to join a cluster. |
| Commands | Fleet command creation, execution status, cancellation, and deletion. |
| SSH | Centralized SSH usernames and public keys used by the agent SSH server. |
| Self-updates | Managed agent update requests across selected nodes. |
| Metrics | Parsed admin, node, host, and agent metrics. |
| Webhooks | Event delivery subscriptions and webhook destination management. |
| Event catalog | Event type discovery for webhook subscriptions. |

For workflow-oriented examples, start with the [user guide](guide.md). For AI-assistant access to the same operational surface, see the [MCP tool catalog](admin-mcp-v0.2.0.md).
