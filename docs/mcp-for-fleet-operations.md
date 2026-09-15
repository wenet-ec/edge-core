<!-- docs/mcp-for-fleet-operations.md -->

# MCP for fleet operations

Edge Admin exposes a Streamable HTTP [Model Context
Protocol](https://modelcontextprotocol.io) server at `POST /mcp`. Its
authenticated tools mirror the REST management API, allowing an MCP-compatible
assistant to inspect and operate a fleet through the same control plane used by
human operators and automation.

## What an assistant can do

- inspect Admin health, clusters, nodes, diagnostics, and metrics;
- create a deliberately targeted remote command and read each execution result;
- manage enrollment, aliases, SSH credentials, self-updates, and event
  subscriptions where authorized; and
- work with the Admin HTTP/SOCKS5 proxy when a direct service connection is
  required and VPN connectivity is available.

MCP does not bypass Edge Core's security model. Write operations remain
authenticated, validation still happens at the normal API/domain layers, and
tool metadata marks read-only, destructive, idempotent, and external-IO tools.

## Connect a client

Create a dedicated `MCP_KEY` in the Admin deployment configuration. Do not
share `MASTER_KEY` with an AI client when a scoped MCP key is sufficient.

Use this standard Streamable HTTP configuration shape in a compatible client:

```json
{
  "mcpServers": {
    "edge-core": {
      "url": "https://admin.example.com/mcp",
      "headers": {
        "Authorization": "Bearer <MCP_KEY>"
      }
    }
  }
}
```

Clients discover the live tool list through the protocol. The exact UI for
adding a remote MCP server varies by client; use its Streamable HTTP / remote
MCP connection flow and substitute the URL and key above.

## A safe first workflow

1. Ask the assistant to run `check_admin_health`, then list clusters and nodes.
2. Ask it to inspect one unhealthy node's diagnostics and metrics.
3. If a command is needed, specify the exact node IDs or cluster and request a
   non-destructive diagnostic command first.
4. Review the individual command executions and their exit codes.
5. Subscribe to or inspect lifecycle events for asynchronous confirmation.

Avoid broad imperatives such as “fix every machine” unless the intended target,
command, change window, and rollback plan are explicit. A valid MCP key has
real operational authority; protect and rotate it like an SSH credential.

## Further reference

- [Complete MCP tool catalog](admin-mcp-v0.2.0.md)
- [Operator guide: MCP access](guide.md#4-mcp--ai-assistant-access)
- [REST API overview](openapi.md)
- [Event catalog](admin-asyncapi-v0.2.0.md)
