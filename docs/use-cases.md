<!-- docs/use-cases.md -->

# When to choose Edge Core

Edge Core is a self-hostable fleet-management platform for **existing Linux
machines that are distributed across networks**. It gives operators and
automation one API for connectivity, commands, controlled access, metrics, and
events without requiring every managed machine to accept public inbound SSH.

## Good fits

### Manage Linux machines behind NAT or strict firewalls

Install an Edge Agent on each machine, enroll it into an isolated WireGuard
cluster, then use the Admin API, MCP server, or proxy endpoints to operate it.
Direct WireGuard is preferred; DERP relay handles difficult NAT paths, and HTTP
polling preserves eventual command delivery when the VPN is unavailable.

This fits branch-office servers, factory equipment, Raspberry Pis, home-lab
machines, customer-site appliances, and cloud VMs spread across providers.

### Run a command across a distributed fleet and retain per-node results

One command request fans out into a command execution for each selected node.
Each execution retains its own delivery state, output, exit code, and timing;
completion can also be observed through CloudEvents webhooks or a broker.

Use this for a controlled diagnostic, a configuration change, or an operational
runbook. Commands are asynchronous jobs, not a synchronous SSH fan-out. See
the [operator guide](guide.md) and [REST API overview](openapi.md).

### Reach an on-site service without exposing it publicly

The Admin exposes HTTP and SOCKS5 forward proxies. It can connect directly to a
VPN node or chain through a particular Agent, allowing an operator to reach a
machine's local LAN or use that machine as an exit point. Agents—not Admins—act
as exit nodes.

This is useful for debugging a local controller, camera, PLC-adjacent service,
or private application through the network location where it actually lives.

### Give an AI assistant a bounded operational interface

The authenticated MCP endpoint exposes the same management operations as REST,
including fleet reads, diagnostics, metrics, commands, and lifecycle actions.
Pair it with a dedicated `MCP_KEY`, explicit command targeting, and lifecycle
events for an observe → decide → act workflow. Start with the [MCP
fleet-operations guide](mcp-for-fleet-operations.md).

## Choose something else when

| Need | Better starting point |
| --- | --- |
| Provision virtual machines, disks, or cloud regions | A cloud provider, Terraform, or a provisioning platform. Edge Core manages machines that already exist. |
| Manage Windows, macOS, mobile devices, patch policy, inventory, or end-user support | An MDM or full RMM product. Edge Core is Linux fleet operations, not endpoint management. |
| Only need a private mesh, identity-aware VPN, ACLs, or exit nodes | Tailscale/Headscale, Netmaker, or another VPN product. Edge Core uses Netmaker as its connectivity layer and adds fleet operations above it. |
| Need desired-state configuration or software deployment pipelines | Ansible, Salt, Puppet, or a CI/CD system. Edge Core can execute and observe those workflows but does not replace their configuration model. |
| Operate thousands of nodes in one flat peer mesh | Split them into edge clusters. WireGuard full meshes have O(n²) peer relationships; Edge Core is designed around small isolated clusters. |

For a more direct comparison with common adjacent tools, see
[Comparisons](comparisons.md).
