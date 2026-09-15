<!-- docs/comparisons.md -->

# Edge Core compared with adjacent tools

Edge Core is a **self-hostable Linux fleet-operations layer**. Its distinctive
combination is private WireGuard connectivity plus remote command execution,
centralized SSH verification, TCP proxying, Prometheus aggregation, events,
and MCP—all for machines that may be behind NAT or firewalls.

These tools overlap at their edges. The practical question is usually not
"which one replaces all the others?" but "which layer is missing from my
stack?"

## Edge Core vs. Tailscale, Headscale, or Netmaker

Choose a mesh VPN when private networking, identity, DNS, ACLs, and exit-node
access are the whole problem. Edge Core needs that network foundation; it uses
Netmaker and WireGuard rather than reimplementing it.

Choose Edge Core when the missing layer is operating the connected machines:
fan-out commands with per-node results, centralized SSH verification, metrics
aggregation, lifecycle events, API automation, and MCP access. It is not a
replacement for the underlying VPN.

## Edge Core vs. Ansible and configuration-management tools

Choose Ansible, Salt, Puppet, or similar tools for declarative desired state,
package/configuration management, and deployment playbooks. They remain useful
on an Edge Core fleet.

Choose Edge Core when reachability is the difficult part: machines sit behind
NAT, move between networks, have changing addresses, or need controlled
on-demand access. Edge Core provides the connectivity and fleet-control path;
run your configuration-management workflow through that path when appropriate.

## Edge Core vs. AWS Systems Manager

AWS Systems Manager is the natural choice for AWS-first estates that want deep
AWS identity, inventory, and service integration. Edge Core is for mixed or
non-AWS environments: on-premises Linux hosts, multiple clouds, appliances,
and edge machines under one self-hosted control plane.

Edge Core does not claim to reproduce every Systems Manager feature. Its focus
is resilient private connectivity and direct operational primitives across
distributed Linux machines.

## Edge Core vs. traditional RMM or MDM

Full RMM and MDM products typically concentrate on endpoint inventory, patch
policy, software catalogs, compliance, remote desktop, helpdesk workflows,
and support across desktop operating systems.

Edge Core is narrower and more infrastructure-oriented: Linux agents, an
isolated WireGuard mesh per cluster, command execution, SSH, proxying,
Prometheus-compatible metrics, and programmable REST/MCP/event interfaces.
Use an RMM/MDM when endpoint-management breadth is the requirement; use Edge
Core when secure network reachability and programmable Linux fleet operations
are central.

## Edge Core vs. a bastion host plus SSH

A bastion gives an operator a path into a network. It does not by itself create
an isolated mesh across hostile networks, manage per-node enrollment, collect
metrics, retain command executions, provide API/MCP management, or preserve an
HTTP-polling control path during a VPN outage.

For a few stable servers, SSH may be simpler. Edge Core becomes useful when the
fleet, network variance, and operational automation make individual SSH paths
hard to manage safely.

## Summary

| If your primary need is… | Start with… |
| --- | --- |
| Private network connectivity | Tailscale/Headscale, Netmaker, or another VPN |
| Declarative configuration and deployments | Ansible or a configuration-management system |
| Desktop/device administration and policy | RMM or MDM |
| AWS-native operational integration | AWS Systems Manager |
| Self-hosted operations for distributed Linux machines behind NAT | Edge Core |

See [When to choose Edge Core](use-cases.md) for concrete use cases and
boundaries.
